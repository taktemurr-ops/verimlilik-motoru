/// Doğrulama kodları (2FA) mantığı: RFC 4226 HOTP ve RFC 6238 TOTP,
/// Base32 (RFC 4648), otpauth:// bağlantıları ve "otpauth-migration"
/// (başka bir doğrulayıcının toplu aktarım QR'ı) çözümü. Ağ kullanılmaz.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const String _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Base32 çözer (boşluk, tire ve "=" yok sayılır; küçük harf kabul edilir).
/// Geçersiz karakterde null.
Uint8List? base32Decode(String s) {
  final clean = s.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');
  if (clean.isEmpty) return null;
  final out = <int>[];
  var buf = 0, bits = 0;
  for (final ch in clean.split('')) {
    final v = _b32.indexOf(ch);
    if (v < 0) return null;
    buf = (buf << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buf >> bits) & 0xFF);
    }
    buf &= (1 << bits) - 1;
  }
  return Uint8List.fromList(out);
}

String base32Encode(List<int> data) {
  final sb = StringBuffer();
  var buf = 0, bits = 0;
  for (final b in data) {
    buf = (buf << 8) | (b & 0xFF);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sb.write(_b32[(buf >> bits) & 31]);
    }
    buf &= (1 << bits) - 1;
  }
  if (bits > 0) sb.write(_b32[(buf << (5 - bits)) & 31]);
  return sb.toString();
}

enum OtpAlgo { sha1, sha256, sha512 }

Hash _hash(OtpAlgo a) => switch (a) {
      OtpAlgo.sha1 => sha1,
      OtpAlgo.sha256 => sha256,
      OtpAlgo.sha512 => sha512,
    };

/// RFC 4226 HOTP.
String hotp(List<int> key, int counter, {int digits = 6, OtpAlgo algo = OtpAlgo.sha1}) {
  final msg = Uint8List(8);
  var c = counter;
  for (var i = 7; i >= 0; i--) {
    msg[i] = c & 0xFF;
    c = c >> 8;
  }
  final h = Hmac(_hash(algo), key).convert(msg).bytes;
  final o = h[h.length - 1] & 0x0F;
  final bin = ((h[o] & 0x7F) << 24) | ((h[o + 1] & 0xFF) << 16) | ((h[o + 2] & 0xFF) << 8) | (h[o + 3] & 0xFF);
  var mod = 1;
  for (var i = 0; i < digits; i++) {
    mod *= 10;
  }
  return (bin % mod).toString().padLeft(digits, '0');
}

/// RFC 6238 TOTP; [unixSeconds] saniye cinsinden zaman.
String totp(List<int> key, int unixSeconds, {int period = 30, int digits = 6, OtpAlgo algo = OtpAlgo.sha1}) =>
    hotp(key, unixSeconds ~/ period, digits: digits, algo: algo);

/// Bir doğrulama hesabı. [secret] Base32 metindir.
class OtpAccount {
  final String id;
  final String issuer;
  final String label;
  final String secret;
  final OtpAlgo algo;
  final int digits;
  final int period;
  final bool hotpMode;
  final int counter;

  const OtpAccount({
    required this.id,
    required this.issuer,
    required this.label,
    required this.secret,
    this.algo = OtpAlgo.sha1,
    this.digits = 6,
    this.period = 30,
    this.hotpMode = false,
    this.counter = 0,
  });

  OtpAccount copyWith({String? issuer, String? label, int? counter}) => OtpAccount(
        id: id,
        issuer: issuer ?? this.issuer,
        label: label ?? this.label,
        secret: secret,
        algo: algo,
        digits: digits,
        period: period,
        hotpMode: hotpMode,
        counter: counter ?? this.counter,
      );

  /// Gizli anahtar geçerli mi (en az 1 bayt, Base32)?
  bool get valid => (base32Decode(secret)?.isNotEmpty ?? false) && (digits == 6 || digits == 7 || digits == 8) && period > 0;

  /// Şu anki kod (TOTP) ya da sayaçtaki kod (HOTP).
  String code(int unixSeconds) {
    final k = base32Decode(secret) ?? Uint8List(0);
    return hotpMode ? hotp(k, counter, digits: digits, algo: algo) : totp(k, unixSeconds, period: period, digits: digits, algo: algo);
  }

  /// Bu periyotta kalan saniye.
  int remaining(int unixSeconds) => period - unixSeconds % period;

  /// Aynı hesap mı (aynı gizli anahtar ve ad)?
  bool sameAs(OtpAccount o) =>
      base32Encode(base32Decode(secret) ?? const []) == base32Encode(base32Decode(o.secret) ?? const []) &&
      label == o.label &&
      issuer == o.issuer;

  Map<String, Object?> toJson() => {
        'id': id,
        'issuer': issuer,
        'label': label,
        'secret': secret,
        'algo': algo.name,
        'digits': digits,
        'period': period,
        'hotp': hotpMode,
        'counter': counter,
      };

  static OtpAccount fromJson(Map<String, Object?> j) => OtpAccount(
        id: j['id'] as String? ?? '',
        issuer: j['issuer'] as String? ?? '',
        label: j['label'] as String? ?? '',
        secret: j['secret'] as String? ?? '',
        algo: OtpAlgo.values.firstWhere((a) => a.name == j['algo'], orElse: () => OtpAlgo.sha1),
        digits: (j['digits'] as num?)?.toInt() ?? 6,
        period: (j['period'] as num?)?.toInt() ?? 30,
        hotpMode: j['hotp'] == true,
        counter: (j['counter'] as num?)?.toInt() ?? 0,
      );
}

/// Kodu okunur gruplara böler: "123 456", "1234 5678".
String groupCode(String c) {
  if (c.length < 6) return c;
  final h = c.length ~/ 2;
  return '${c.substring(0, h)} ${c.substring(h)}';
}

/// otpauth://totp/Issuer:hesap?secret=...&issuer=...&algorithm=SHA1&digits=6&period=30
OtpAccount? parseOtpauth(String uri, {required String id}) {
  final u = Uri.tryParse(uri.trim());
  if (u == null || u.scheme.toLowerCase() != 'otpauth') return null;
  final type = u.host.toLowerCase();
  if (type != 'totp' && type != 'hotp') return null;
  final q = u.queryParameters;
  final secret = (q['secret'] ?? '').replaceAll(' ', '').toUpperCase();
  if (base32Decode(secret) == null) return null;
  var path = u.path.startsWith('/') ? u.path.substring(1) : u.path;
  path = Uri.decodeComponent(path);
  var issuer = q['issuer'] ?? '';
  var label = path;
  final colon = path.indexOf(':');
  if (colon >= 0) {
    if (issuer.isEmpty) issuer = path.substring(0, colon).trim();
    label = path.substring(colon + 1).trim();
  }
  final algo = switch ((q['algorithm'] ?? 'SHA1').toUpperCase()) {
    'SHA256' => OtpAlgo.sha256,
    'SHA512' => OtpAlgo.sha512,
    _ => OtpAlgo.sha1,
  };
  final a = OtpAccount(
    id: id,
    issuer: issuer,
    label: label,
    secret: secret,
    algo: algo,
    digits: int.tryParse(q['digits'] ?? '') ?? 6,
    period: int.tryParse(q['period'] ?? '') ?? 30,
    hotpMode: type == 'hotp',
    counter: int.tryParse(q['counter'] ?? '') ?? 0,
  );
  return a.valid ? a : null;
}

// ----------------------------------------------------- toplu aktarım QR'ı

class _Pb {
  final Uint8List b;
  int i = 0;
  _Pb(this.b);
  bool get done => i >= b.length;

  int varint() {
    var shift = 0, v = 0;
    while (i < b.length) {
      final x = b[i++];
      v |= (x & 0x7F) << shift;
      if (x & 0x80 == 0) return v;
      shift += 7;
      if (shift > 63) throw const FormatException('varint');
    }
    throw const FormatException('varint');
  }

  Uint8List bytes() {
    final n = varint();
    if (n < 0 || i + n > b.length) throw const FormatException('len');
    final out = Uint8List.sublistView(b, i, i + n);
    i += n;
    return out;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        i += 8;
      case 2:
        bytes();
      case 5:
        i += 4;
      default:
        throw const FormatException('wire');
    }
  }
}

/// "otpauth-migration://offline?data=..." (protobuf) içindeki hesaplar.
/// Desteklenmeyen (MD5) ya da bozuk kayıtlar atlanır.
List<OtpAccount> parseMigration(String uri, {required String Function() newId}) {
  final u = Uri.tryParse(uri.trim());
  if (u == null || u.scheme.toLowerCase() != 'otpauth-migration') return const [];
  final data = u.queryParameters['data'];
  if (data == null) return const [];
  Uint8List raw;
  try {
    raw = base64Decode(base64.normalize(data.replaceAll(' ', '+')));
  } catch (_) {
    return const [];
  }
  final out = <OtpAccount>[];
  try {
    final top = _Pb(raw);
    while (!top.done) {
      final tag = top.varint();
      if (tag >> 3 == 1 && tag & 7 == 2) {
        final p = _Pb(top.bytes());
        Uint8List? secret;
        var name = '', issuer = '';
        var algo = 1, digits = 1, type = 2, counter = 0;
        while (!p.done) {
          final t = p.varint();
          final f = t >> 3, w = t & 7;
          if (f == 1 && w == 2) {
            secret = p.bytes();
          } else if (f == 2 && w == 2) {
            name = utf8.decode(p.bytes(), allowMalformed: true);
          } else if (f == 3 && w == 2) {
            issuer = utf8.decode(p.bytes(), allowMalformed: true);
          } else if (f == 4 && w == 0) {
            algo = p.varint();
          } else if (f == 5 && w == 0) {
            digits = p.varint();
          } else if (f == 6 && w == 0) {
            type = p.varint();
          } else if (f == 7 && w == 0) {
            counter = p.varint();
          } else {
            p.skip(w);
          }
        }
        if (secret == null || secret.isEmpty || algo == 4) continue;
        var label = name;
        final colon = name.indexOf(':');
        if (colon >= 0) {
          if (issuer.isEmpty) issuer = name.substring(0, colon).trim();
          label = name.substring(colon + 1).trim();
        }
        out.add(OtpAccount(
          id: newId(),
          issuer: issuer,
          label: label,
          secret: base32Encode(secret),
          algo: algo == 2 ? OtpAlgo.sha256 : (algo == 3 ? OtpAlgo.sha512 : OtpAlgo.sha1),
          digits: digits == 2 ? 8 : 6,
          hotpMode: type == 1,
          counter: counter,
        ));
      } else {
        top.skip(tag & 7);
      }
    }
  } on FormatException {
    return out;
  } on RangeError {
    return out;
  }
  return out;
}

/// Hesap listesini yedek/kasa için JSON baytlarına çevirir.
List<int> encodeAccounts(List<OtpAccount> list) =>
    utf8.encode(jsonEncode({'v': 1, 'accounts': [for (final a in list) a.toJson()]}));

List<OtpAccount> decodeAccounts(List<int> bytes) {
  final j = jsonDecode(utf8.decode(bytes));
  if (j is! Map) return const [];
  return [
    for (final e in (j['accounts'] as List? ?? const []))
      if (e is Map) OtpAccount.fromJson(e.cast<String, Object?>()),
  ].where((a) => a.valid).toList();
}
