/// Şifre kasasının saf mantığı: anahtar türetme (Argon2id), AES-256-GCM
/// ile mühürleme/açma, şifre üretici ve güç tahmini. İnternet yok, bulut
/// yok; kasa cihazda yalnızca şifreli hâlde durur.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Şifreli kasa / dışa aktarma biçimi.
const String kVaultFormat = 'kasa1';

/// Varsayılan Argon2id ayarları (OWASP önerisi: 19 MiB, 2 tur, 1 iş parçacığı).
class KdfParams {
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  const KdfParams({this.memoryKiB = 19456, this.iterations = 2, this.parallelism = 1});

  Map<String, Object?> toJson(List<int> salt) =>
      {'alg': 'argon2id', 'm': memoryKiB, 't': iterations, 'p': parallelism, 'salt': base64Encode(salt)};

  static KdfParams fromJson(Map<String, Object?> j) => KdfParams(
        memoryKiB: (j['m'] as num?)?.toInt() ?? 19456,
        iterations: (j['t'] as num?)?.toInt() ?? 2,
        parallelism: (j['p'] as num?)?.toInt() ?? 1,
      );

  /// Dosyadan gelen ayarlar makul aralıkta mı: değiştirilmiş bir dosyadaki
  /// cihazı kilitleyecek kadar büyük ayarla (bellek/süre tüketme) açma denenmez.
  bool get sane =>
      memoryKiB >= 8 && memoryKiB <= 262144 && iterations >= 1 && iterations <= 10 && parallelism >= 1 && parallelism <= 8;
}

/// Yanlış ana şifre ya da bozulmuş dosya.
class VaultAuthError implements Exception {
  const VaultAuthError();
  @override
  String toString() => 'VaultAuthError';
}

List<int> randomBytes(int n) {
  final r = math.Random.secure();
  return List<int>.generate(n, (_) => r.nextInt(256));
}

Future<List<int>> _derive(List<Object> a) async {
  final alg = Argon2id(
    parallelism: a[3] as int,
    memory: a[2] as int,
    iterations: a[4] as int,
    hashLength: 32,
  );
  final k = await alg.deriveKeyFromPassword(password: a[0] as String, nonce: a[1] as List<int>);
  return k.extractBytes();
}

/// Ana şifreden 256 bit anahtar (Argon2id). Mobilde ayrı iş parçacığında.
Future<List<int>> deriveVaultKey(String password, List<int> salt, KdfParams p) =>
    compute(_derive, <Object>[password, salt, p.memoryKiB, p.parallelism, p.iterations]);

final AesGcm _aes = AesGcm.with256bits();

/// [clear] baytlarını [key] ile şifreler; KDF bilgisiyle birlikte zarf döner.
Future<Map<String, Object?>> sealVault(List<int> key, List<int> clear, Map<String, Object?> kdf) async {
  final box = await _aes.encrypt(clear, secretKey: SecretKey(key), nonce: _aes.newNonce(), aad: utf8.encode(kVaultFormat));
  return {
    'fmt': kVaultFormat,
    'kdf': kdf,
    'nonce': base64Encode(box.nonce),
    'ct': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  };
}

/// Zarfı açar; anahtar yanlışsa [VaultAuthError].
Future<List<int>> openVault(List<int> key, Map<String, Object?> env) async {
  if (env['fmt'] != kVaultFormat) throw const VaultAuthError();
  try {
    final box = SecretBox(
      base64Decode(env['ct'] as String),
      nonce: base64Decode(env['nonce'] as String),
      mac: Mac(base64Decode(env['mac'] as String)),
    );
    return await _aes.decrypt(box, secretKey: SecretKey(key), aad: utf8.encode(kVaultFormat));
  } on SecretBoxAuthenticationError {
    throw const VaultAuthError();
  } on FormatException {
    throw const VaultAuthError();
  } on TypeError {
    throw const VaultAuthError();
  }
}

/// Zarftaki tuz ve KDF ayarları.
(List<int>, KdfParams) vaultKdf(Map<String, Object?> env) {
  final k = (env['kdf'] as Map?)?.cast<String, Object?>() ?? const {};
  final salt = base64Decode(k['salt'] as String? ?? '');
  final p = KdfParams.fromJson(k);
  if (k['alg'] != null && k['alg'] != 'argon2id') throw const VaultAuthError();
  if (salt.length < 16 || !p.sane) throw const VaultAuthError();
  return (salt, p);
}

/// Şifreyle doğrudan şifreleme (dışa aktarma): yeni tuz, Argon2id, AES-GCM.
Future<Map<String, Object?>> sealWithPassword(String password, List<int> clear,
    {KdfParams params = const KdfParams()}) async {
  final salt = randomBytes(16);
  final key = await deriveVaultKey(password, salt, params);
  return sealVault(key, clear, params.toJson(salt));
}

Future<List<int>> openWithPassword(String password, Map<String, Object?> env) async {
  final (salt, p) = vaultKdf(env);
  final key = await deriveVaultKey(password, salt, p);
  return openVault(key, env);
}

// ------------------------------------------------------------ şifre üretici

const String _lower = 'abcdefghijkmnopqrstuvwxyz';
const String _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const String _digits = '23456789';
const String _symbols = '!@#\$%^&*()-_=+[]{};:,.?/';

/// Rastgele şifre (karışıklık yaratan l/I/O/0/1 çıkarılır); seçilen her
/// gruptan en az bir karakter içerir.
String generatePassword({int length = 20, bool upper = true, bool digits = true, bool symbols = true, math.Random? rng}) {
  final r = rng ?? math.Random.secure();
  final groups = [_lower, if (upper) _upper, if (digits) _digits, if (symbols) _symbols];
  final n = math.max(length, groups.length);
  final all = groups.join();
  final out = [for (final g in groups) g[r.nextInt(g.length)]];
  while (out.length < n) {
    out.add(all[r.nextInt(all.length)]);
  }
  for (var i = out.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final x = out[i];
    out[i] = out[j];
    out[j] = x;
  }
  return out.join();
}

/// Yaklaşık entropi (bit): karakter havuzu × uzunluk; tekrar ve sıralı
/// desenler için ceza uygulanır.
double passwordBits(String p) {
  if (p.isEmpty) return 0;
  var pool = 0;
  if (p.contains(RegExp(r'[a-z]'))) pool += 26;
  if (p.contains(RegExp(r'[A-Z]'))) pool += 26;
  if (p.contains(RegExp(r'[0-9]'))) pool += 10;
  if (p.contains(RegExp(r'[^a-zA-Z0-9]'))) pool += 33;
  final unique = p.runes.toSet().length;
  var effLen = math.min(p.runes.length, unique * 2).toDouble();
  var seq = 0;
  final cu = p.codeUnits;
  for (var i = 2; i < cu.length; i++) {
    if (cu[i] - cu[i - 1] == cu[i - 1] - cu[i - 2] && (cu[i] - cu[i - 1]).abs() <= 1) seq++;
  }
  effLen = math.max(1, effLen - seq);
  return effLen * math.log(math.max(pool, 2)) / math.ln2;
}

/// 0 çok zayıf … 4 çok güçlü.
int passwordScore(String p) {
  final b = passwordBits(p);
  if (b < 28) return 0;
  if (b < 40) return 1;
  if (b < 60) return 2;
  if (b < 90) return 3;
  return 4;
}
