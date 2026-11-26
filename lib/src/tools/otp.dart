/// Doğrulama kodları (2FA, RFC 6238 TOTP / RFC 4226 HOTP). Tamamen
/// çevrimdışı; bulut yok. Hesaplar cihazda AES-256-GCM ile şifreli durur;
/// şifreleme anahtarı cihazın güvenli deposundadır (Android Keystore /
/// iOS Keychain, yalnız bu cihaz). İçe aktarma: QR (otpauth:// ve toplu
/// aktarım), elle giriş, şifreli yedek. Dışa aktarma yalnızca parolayla
/// şifrelenmiş yedek dosyasıdır (Argon2id + AES-256-GCM).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic/otp_logic.dart';
import '../logic/vault_logic.dart';
import '../secure_window.dart';

const String _kKeyName = 'otp_data_key_v1';
const String _kAad = 'otp1';

/// Cihaz anahtarıyla şifreli hesap deposu.
class OtpStore {
  final AppStore store;
  final FlutterSecureStorage secure;
  OtpStore(this.store, this.secure);

  static final AesGcm _aes = AesGcm.with256bits();

  Future<List<int>?> _key({bool create = false}) async {
    final s = await secure.read(key: _kKeyName);
    if (s != null) return base64Decode(s);
    if (!create) return null;
    final k = randomBytes(32);
    await secure.write(key: _kKeyName, value: base64Encode(k));
    return k;
  }

  /// Hesaplar; şifreli veri var ama anahtar yoksa [StateError].
  Future<List<OtpAccount>> load() async {
    final raw = await store.read('box');
    if (raw == null || raw.isEmpty) return [];
    final key = await _key();
    if (key == null) throw StateError('key');
    final env = (jsonDecode(raw) as Map).cast<String, Object?>();
    final box = SecretBox(
      base64Decode(env['ct'] as String),
      nonce: base64Decode(env['nonce'] as String),
      mac: Mac(base64Decode(env['mac'] as String)),
    );
    final clear = await _aes.decrypt(box, secretKey: SecretKey(key), aad: utf8.encode(_kAad));
    return decodeAccounts(clear);
  }

  Future<void> save(List<OtpAccount> list) async {
    final key = await _key(create: true);
    final box = await _aes.encrypt(encodeAccounts(list),
        secretKey: SecretKey(key!), nonce: _aes.newNonce(), aad: utf8.encode(_kAad));
    await store.write(
        'box',
        jsonEncode({
          'fmt': _kAad,
          'nonce': base64Encode(box.nonce),
          'ct': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }));
  }

  /// Her şeyi siler (anahtar dahil).
  Future<void> wipe() async {
    await store.remove('box');
    try {
      await secure.delete(key: _kKeyName);
    } catch (_) {}
  }
}

class OtpTool extends StatefulWidget {
  final ToolContext t;
  const OtpTool(this.t, {super.key});

  @override
  State<OtpTool> createState() => _OtpToolState();
}

class _OtpToolState extends State<OtpTool> with WidgetsBindingObserver {
  // Anahtar yalnız bu cihazda, cihaz kilidi açıkken okunur; yedeğe taşınmaz.
  static const _secure = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );
  late final OtpStore _box = OtpStore(t.store, _secure);
  final _auth = LocalAuthentication();
  List<OtpAccount> _list = [];
  bool _loading = true;
  bool _keyLost = false;
  bool _locked = false;
  bool _lockOn = false;
  bool _busy = false;
  String _q = '';
  Timer? _tick;
  Timer? _clip;

  ToolContext get t => widget.t;

  int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(secureWindow(true));
    unawaited(_load());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_locked) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(secureWindow(false));
    _tick?.cancel();
    _clip?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) && _lockOn && mounted) {
      setState(() => _locked = true);
    }
  }

  Future<void> _load() async {
    if (kIsWeb) {
      setState(() => _loading = false);
      return;
    }
    _lockOn = await t.store.readBool('lock');
    try {
      final l = await _box.load();
      if (!mounted) return;
      setState(() {
        _list = l;
        _loading = false;
        _locked = _lockOn;
      });
      if (_lockOn) unawaited(_unlock());
    } on StateError {
      if (mounted) {
        setState(() {
          _keyLost = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _keyLost = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _unlock() async {
    try {
      final ok = await _auth.authenticate(localizedReason: L(t, 'otp_unlock_reason'));
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      if (mounted) toast(context, t.tx('not_available'));
    }
  }

  Future<void> _setLock(bool on) async {
    if (on) {
      try {
        final ok = await _auth.authenticate(localizedReason: L(t, 'otp_unlock_reason'));
        if (!ok) return;
      } catch (_) {
        if (mounted) toast(context, t.tx('not_available'));
        return;
      }
    }
    await t.store.writeBool('lock', on);
    if (mounted) setState(() => _lockOn = on);
  }

  Future<void> _persist() async {
    try {
      await _box.save(_list);
    } catch (_) {
      if (mounted) toast(context, L(t, 'otp_save_failed'));
    }
  }

  int _addAll(List<OtpAccount> incoming) {
    var n = 0;
    for (final a in incoming) {
      if (!a.valid || _list.any((x) => x.sameAs(a))) continue;
      _list.add(a);
      n++;
    }
    return n;
  }

  Future<void> _scan() async {
    if (!await rationaleOnce(context, t, 'camera', Icons.qr_code_scanner_rounded)) return;
    if (!mounted) return;
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _OtpScanSheet(),
    );
    if (v == null || !mounted) return;
    final found = v.toLowerCase().startsWith('otpauth-migration')
        ? parseMigration(v, newId: newId)
        : [if (parseOtpauth(v, id: newId()) case final a?) a];
    if (found.isEmpty) {
      toast(context, L(t, 'otp_bad_qr'));
      return;
    }
    final n = _addAll(found);
    setState(() {});
    await _persist();
    if (mounted) toast(context, '${L(t, 'otp_added')}: $n');
  }

  Future<void> _manual() async {
    final issuer = TextEditingController();
    final label = TextEditingController();
    final secret = TextEditingController();
    var algo = OtpAlgo.sha1;
    var digits = 6;
    var period = 30;
    var hotpMode = false;
    String? err;
    final r = await showDialog<OtpAccount>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(L(t, 'otp_manual')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppTextField(controller: issuer, label: L(t, 'otp_issuer')),
              AppTextField(controller: label, label: L(t, 'otp_account')),
              AppTextField(controller: secret, label: L(t, 'otp_secret')),
              if (err != null) Text(err!, style: const TextStyle(color: Colors.orangeAccent)),
              ExpansionTile(
                title: Text(L(t, 'otp_advanced')),
                children: [
                  Choice<OtpAlgo>(
                    values: OtpAlgo.values,
                    labels: const ['SHA-1', 'SHA-256', 'SHA-512'],
                    selected: algo,
                    onChanged: (v) => set(() => algo = v),
                  ),
                  Choice<int>(values: const [6, 8], labels: const ['6', '8'], selected: digits, onChanged: (v) => set(() => digits = v)),
                  Choice<int>(values: const [30, 60], labels: const ['30 s', '60 s'], selected: period, onChanged: (v) => set(() => period = v)),
                  SwitchListTile(
                    title: Text(L(t, 'otp_counter_based')),
                    value: hotpMode,
                    onChanged: (v) => set(() => hotpMode = v),
                  ),
                ],
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.core('cancel'))),
            FilledButton(
              onPressed: () {
                final a = OtpAccount(
                  id: newId(),
                  issuer: issuer.text.trim(),
                  label: label.text.trim(),
                  secret: secret.text.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase(),
                  algo: algo,
                  digits: digits,
                  period: period,
                  hotpMode: hotpMode,
                );
                if (!a.valid || (a.issuer.isEmpty && a.label.isEmpty)) {
                  set(() => err = L(t, 'otp_bad_secret'));
                  return;
                }
                Navigator.pop(ctx, a);
              },
              child: Text(t.core('ok')),
            ),
          ],
        ),
      ),
    );
    issuer.dispose();
    label.dispose();
    secret.dispose();
    if (r == null || !mounted) return;
    final n = _addAll([r]);
    setState(() {});
    await _persist();
    if (mounted && n == 0) toast(context, L(t, 'otp_exists'));
  }

  Future<String?> _askPassword(String title, {bool confirm = false}) async {
    final a = TextEditingController(), b = TextEditingController();
    String? err;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          icon: const Icon(Icons.lock_rounded),
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: a, obscureText: true, decoration: InputDecoration(labelText: L(t, 'otp_backup_pw'))),
            if (confirm)
              TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: L(t, 'otp_backup_pw2'))),
            if (err != null) Text(err!, style: const TextStyle(color: Colors.orangeAccent)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.core('cancel'))),
            FilledButton(
              onPressed: () {
                if (confirm && a.text.length < 8) return set(() => err = L(t, 'vault_min'));
                if (confirm && a.text != b.text) return set(() => err = L(t, 'vault_mismatch'));
                if (a.text.isEmpty) return;
                Navigator.pop(ctx, a.text);
              },
              child: Text(t.core('ok')),
            ),
          ],
        ),
      ),
    );
    a.dispose();
    b.dispose();
    return r;
  }

  Future<void> _export() async {
    if (_list.isEmpty) return;
    final pw = await _askPassword(L(t, 'otp_export'), confirm: true);
    if (pw == null || !mounted) return;
    setState(() => _busy = true);
    final env = await sealWithPassword(pw, encodeAccounts(_list));
    if (!mounted) return;
    setState(() => _busy = false);
    final d = DateTime.now();
    final name = 'dogrulama_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.2fa';
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({...env, 'kind': '2fa'})));
    String? path;
    try {
      path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
    } catch (_) {
      path = null;
    }
    if (path == null) await shareBytes(bytes, name, 'application/octet-stream');
    if (mounted && path != null) toast(context, '✓ $name');
  }

  Future<void> _import() async {
    try {
      final r = await FilePicker.platform.pickFiles(withData: true);
      final bytes = r?.files.single.bytes;
      if (bytes == null || !mounted) return;
      final env = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
      final pw = await _askPassword(L(t, 'otp_import'));
      if (pw == null || !mounted) return;
      setState(() => _busy = true);
      final clear = await openWithPassword(pw, env);
      final incoming = [for (final a in decodeAccounts(clear)) OtpAccount.fromJson({...a.toJson(), 'id': newId()})];
      final n = _addAll(incoming);
      if (_keyLost) {
        await _box.wipe();
        _keyLost = false;
      }
      await _persist();
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, '${L(t, 'otp_added')}: $n');
    } on VaultAuthError {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, L(t, 'vault_wrong'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, L(t, 'vault_bad_file'));
      }
    }
  }

  void _copy(OtpAccount a) {
    Clipboard.setData(ClipboardData(text: a.code(_now)));
    toast(context, t.tx('copied'));
    _clip?.cancel();
    _clip = Timer(const Duration(seconds: 45), () => Clipboard.setData(const ClipboardData(text: '')));
  }

  Future<void> _edit(OtpAccount a) async {
    final issuer = TextEditingController(text: a.issuer);
    final label = TextEditingController(text: a.label);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L(t, 'otp_edit')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppTextField(controller: issuer, label: L(t, 'otp_issuer')),
          AppTextField(controller: label, label: L(t, 'otp_account')),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Text(t.core('delete'), style: const TextStyle(color: Colors.redAccent)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.core('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(t.core('ok'))),
        ],
      ),
    );
    final ni = issuer.text.trim(), nl = label.text.trim();
    issuer.dispose();
    label.dispose();
    if (!mounted || r == null) return;
    if (r == 'delete') {
      if (!await _confirmDelete(a)) return;
      setState(() => _list.removeWhere((x) => x.id == a.id));
    } else {
      setState(() {
        final i = _list.indexWhere((x) => x.id == a.id);
        if (i >= 0) _list[i] = a.copyWith(issuer: ni, label: nl);
      });
    }
    await _persist();
  }

  Future<bool> _confirmDelete(OtpAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 40),
        title: Text('${a.issuer} ${a.label}'.trim()),
        content: Text(L(t, 'otp_delete_warn')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.core('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.core('delete'))),
        ],
      ),
    );
    return ok == true;
  }

  Widget _tile(OtpAccount a) {
    final s = AppLook.of(context);
    final code = a.code(_now);
    final left = a.remaining(_now);
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: InkWell(
        onTap: () => _copy(a),
        onLongPress: () => _edit(a),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: s.accent.withValues(alpha: 0.25),
            child: Text((a.issuer.isNotEmpty ? a.issuer : (a.label.isNotEmpty ? a.label : '?')).characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.issuer.isEmpty ? a.label : a.issuer,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (a.issuer.isNotEmpty && a.label.isNotEmpty)
                Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(groupCode(code),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2, color: s.number)),
              ),
            ]),
          ),
          if (a.hotpMode)
            IconButton(
              tooltip: L(t, 'otp_next'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () async {
                setState(() {
                  final i = _list.indexWhere((x) => x.id == a.id);
                  if (i >= 0) _list[i] = a.copyWith(counter: a.counter + 1);
                });
                await _persist();
              },
            )
          else
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: left / a.period,
                  strokeWidth: 4,
                  color: left <= 5 ? Colors.redAccent : s.accent,
                  backgroundColor: Colors.white12,
                ),
                Text('$left', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return ToolList(children: [notAvailable(t), AppInfoCard(L(t, 'otp_web'), icon: Icons.phonelink_lock_rounded)]);
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_locked) {
      return SecureCurtain(
        child: ToolList(children: [
          const SizedBox(height: 40),
          const Icon(Icons.lock_rounded, size: 72),
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppButton(label: L(t, 'otp_unlock'), icon: Icons.fingerprint_rounded, onPressed: _unlock),
          ),
        ]),
      );
    }
    final shown = _q.isEmpty
        ? _list
        : _list.where((a) => '${a.issuer} ${a.label}'.toLowerCase().contains(_q.toLowerCase())).toList();
    return SecureCurtain(
      child: Stack(children: [
        ToolList(children: [
          if (_keyLost) AppInfoCard(L(t, 'otp_key_lost'), icon: Icons.key_off_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: AppButton(label: L(t, 'otp_scan'), icon: Icons.qr_code_scanner_rounded, onPressed: _keyLost ? null : _scan)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: L(t, 'otp_manual'),
                onPressed: _keyLost ? null : _manual,
                icon: const Icon(Icons.keyboard_rounded),
              ),
            ]),
          ),
          if (_list.length > 6)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          if (_list.isEmpty && !_keyLost) AppInfoCard(L(t, 'otp_empty'), icon: Icons.verified_user_rounded),
          for (final a in shown) _tile(a),
          if (_list.isNotEmpty) AppInfoCard(L(t, 'otp_tap_hint'), icon: Icons.touch_app_rounded),
          AppHeading(L(t, 'otp_backup'), icon: Icons.save_rounded),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: AppButton(label: L(t, 'otp_export'), icon: Icons.upload_file_rounded, onPressed: _list.isEmpty ? null : _export)),
              const SizedBox(width: 8),
              Expanded(child: AppButton(label: L(t, 'otp_import'), icon: Icons.download_rounded, onPressed: _import)),
            ]),
          ),
          SwitchListTile(
            title: Text(L(t, 'otp_lock')),
            value: _lockOn,
            onChanged: _setLock,
          ),
          AppInfoCard(L(t, 'otp_local'), icon: Icons.cloud_off_rounded),
          AppInfoCard(L(t, 'otp_clock'), icon: Icons.schedule_rounded),
        ]),
        if (_busy)
          const Positioned.fill(child: ColoredBox(color: Colors.black45, child: Center(child: CircularProgressIndicator()))),
      ]),
    );
  }
}

class _OtpScanSheet extends StatefulWidget {
  const _OtpScanSheet();

  @override
  State<_OtpScanSheet> createState() => _OtpScanSheetState();
}

class _OtpScanSheetState extends State<_OtpScanSheet> {
  final MobileScannerController _c = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: MobileScanner(
            controller: _c,
            onDetect: (cap) {
              if (_done || cap.barcodes.isEmpty) return;
              final v = cap.barcodes.first.rawValue;
              if (v == null || !v.toLowerCase().startsWith('otpauth')) return;
              _done = true;
              Navigator.pop(context, v);
            },
          ),
        ),
      );
}
