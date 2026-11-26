/// Şifre kasası: çevrimdışı, AES-256-GCM ile şifreli; anahtar ana şifreden
/// Argon2id ile türetilir. İsteğe bağlı biyometrik açma (anahtar cihazın
/// güvenli deposunda, Keystore/Keychain). Bulut yok; dışa aktarma da
/// şifrelidir.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic/vault_logic.dart';

typedef Js = Map<String, Object?>;

enum _Stage { loading, setup, locked, open }

class VaultTool extends StatefulWidget {
  final ToolContext t;
  const VaultTool(this.t, {super.key});

  @override
  State<VaultTool> createState() => _VaultToolState();
}

class _VaultToolState extends State<VaultTool> with WidgetsBindingObserver {
  static const _bioKey = 'vault_key_v1';
  static const _idle = Duration(minutes: 5);
  final _secure = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  _Stage _stage = _Stage.loading;
  Js? _env;
  List<int>? _key;
  List<Js> _items = [];
  bool _busy = false;
  String? _error;
  int _fails = 0;
  bool _bioAvailable = false;
  bool _bioOn = false;
  String _q = '';
  Timer? _idleTimer;
  Timer? _clipTimer;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _show = false;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _clipTimer?.cancel();
    _pw.dispose();
    _pw2.dispose();
    _key = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _lock();
  }

  Future<void> _load() async {
    final raw = await t.store.read('vault');
    _bioOn = await t.store.readBool('bio');
    if (!kIsWeb) {
      try {
        _bioAvailable = await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
      } catch (_) {
        _bioAvailable = false;
      }
    }
    Js? env;
    if (raw != null && raw.isNotEmpty) {
      try {
        env = (jsonDecode(raw) as Map).cast<String, Object?>();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _env = env;
      _stage = env == null ? _Stage.setup : _Stage.locked;
    });
    if (env != null && _bioOn && _bioAvailable) unawaited(_unlockBio());
  }

  void _touch() {
    _idleTimer?.cancel();
    if (_stage == _Stage.open) _idleTimer = Timer(_idle, _lock);
  }

  void _lock() {
    if (_stage != _Stage.open) return;
    _idleTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _key = null;
      _items = [];
      _q = '';
      _stage = _Stage.locked;
    });
  }

  Future<void> _persist() async {
    final key = _key;
    final env = _env;
    if (key == null || env == null) return;
    final clear = utf8.encode(jsonEncode({'items': _items}));
    final next = await sealVault(key, clear, (env['kdf'] as Map).cast<String, Object?>());
    _env = next;
    await t.store.write('vault', jsonEncode(next));
  }

  // ----------------------------------------------------------- kurulum/açma

  Future<void> _create() async {
    final a = _pw.text, b = _pw2.text;
    if (a.length < 8) return setState(() => _error = L(t, 'vault_min'));
    if (a != b) return setState(() => _error = L(t, 'vault_mismatch'));
    setState(() {
      _busy = true;
      _error = null;
    });
    const p = KdfParams();
    final salt = randomBytes(16);
    final key = await deriveVaultKey(a, salt, p);
    final env = await sealVault(key, utf8.encode(jsonEncode({'items': <Js>[]})), p.toJson(salt));
    await t.store.write('vault', jsonEncode(env));
    _pw.clear();
    _pw2.clear();
    if (!mounted) return;
    setState(() {
      _env = env;
      _key = key;
      _items = [];
      _busy = false;
      _stage = _Stage.open;
    });
    _touch();
  }

  Future<bool> _openWith(List<int> key) async {
    try {
      final clear = await openVault(key, _env!);
      final j = (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
      final items = [for (final e in (j['items'] as List? ?? const [])) (e as Map).cast<String, Object?>()];
      if (!mounted) return true;
      setState(() {
        _key = key;
        _items = items;
        _stage = _Stage.open;
        _fails = 0;
        _error = null;
      });
      _touch();
      return true;
    } on VaultAuthError {
      return false;
    }
  }

  Future<void> _unlock() async {
    final pw = _pw.text;
    if (pw.isEmpty || _env == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Art arda yanlış denemelerde artan bekleme.
    if (_fails >= 3) await Future<void>.delayed(Duration(seconds: (_fails - 2) * 2));
    final (salt, p) = vaultKdf(_env!);
    final key = await deriveVaultKey(pw, salt, p);
    final ok = await _openWith(key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _fails++;
        _error = L(t, 'vault_wrong');
      } else {
        _pw.clear();
      }
    });
  }

  Future<void> _unlockBio() async {
    try {
      final ok = await _auth.authenticate(localizedReason: L(t, 'vault_bio_reason'), biometricOnly: true);
      if (!ok) return;
      final s = await _secure.read(key: _bioKey);
      if (s == null) return;
      final good = await _openWith(base64Decode(s));
      if (!good) {
        await _secure.delete(key: _bioKey);
        await t.store.writeBool('bio', false);
        _bioOn = false;
      }
    } catch (_) {}
  }

  Future<void> _setBio(bool on) async {
    if (!on) {
      try {
        await _secure.delete(key: _bioKey);
      } catch (_) {}
      await t.store.writeBool('bio', false);
      setState(() => _bioOn = false);
      return;
    }
    try {
      final ok = await _auth.authenticate(localizedReason: L(t, 'vault_bio_reason'), biometricOnly: true);
      if (!ok || _key == null) return;
      await _secure.write(key: _bioKey, value: base64Encode(_key!));
      await t.store.writeBool('bio', true);
      if (mounted) setState(() => _bioOn = true);
    } catch (_) {
      if (mounted) toast(context, t.tx('not_available'));
    }
  }

  // ------------------------------------------------------------ kayıtlar

  void _copySecret(String v) {
    Clipboard.setData(ClipboardData(text: v));
    toast(context, L(t, 'vault_copied'));
    _clipTimer?.cancel();
    _clipTimer = Timer(const Duration(seconds: 30), () => Clipboard.setData(const ClipboardData(text: '')));
    _touch();
  }

  Future<void> _edit([Js? orig]) async {
    _touch();
    final r = Map<String, Object?>.from(orig ?? {});
    final title = TextEditingController(text: r['title'] as String? ?? '');
    final user = TextEditingController(text: r['user'] as String? ?? '');
    final pass = TextEditingController(text: r['pass'] as String? ?? '');
    final url = TextEditingController(text: r['url'] as String? ?? '');
    final note = TextEditingController(text: r['note'] as String? ?? '');
    var len = 20.0;
    var sym = true;
    var hide = orig != null;
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(L(t, 'vault_entry'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (orig != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (await confirmDelete(c, t) && c.mounted) Navigator.pop(c, 'del');
                    },
                  ),
              ]),
              AppTextField(controller: title, label: L(t, 'title'), autofocus: orig == null),
              AppTextField(controller: user, label: L(t, 'vault_user')),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextField(
                  controller: pass,
                  obscureText: hide,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => set(() {}),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 17),
                  decoration: InputDecoration(
                    labelText: L(t, 'vault_password'),
                    suffixIcon: IconButton(
                      icon: Icon(hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                      onPressed: () => set(() => hide = !hide),
                    ),
                  ),
                ),
              ),
              _Strength(t, pass.text),
              Row(children: [
                Text('${len.round()}'),
                Expanded(child: Slider(min: 8, max: 64, divisions: 56, value: len, onChanged: (v) => set(() => len = v))),
                FilterChip(label: const Text('#\$%'), selected: sym, onSelected: (v) => set(() => sym = v)),
              ]),
              OutlinedButton.icon(
                icon: const Icon(Icons.autorenew_rounded),
                label: Text(L(t, 'vault_generate')),
                onPressed: () => set(() {
                  pass.text = generatePassword(length: len.round(), symbols: sym);
                  hide = false;
                }),
              ),
              AppTextField(controller: url, label: L(t, 'website'), keyboard: TextInputType.url),
              AppTextField(controller: note, label: L(t, 'note'), maxLines: 4),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(c, 'ok'),
                icon: const Icon(Icons.check_rounded),
                label: Text(L(t, 'save')),
              ),
            ]),
          ),
        ),
      ),
    );
    final vals = [title.text.trim(), user.text.trim(), pass.text, url.text.trim(), note.text.trim()];
    for (final c in [title, user, pass, url, note]) {
      c.dispose();
    }
    if (res == null || !mounted || _stage != _Stage.open) return;
    if (res == 'del') {
      setState(() => _items.removeWhere((x) => x['id'] == orig?['id']));
    } else {
      r['title'] = vals[0].isEmpty ? (vals[3].isEmpty ? L(t, 'vault_entry') : vals[3]) : vals[0];
      r['user'] = vals[1];
      r['pass'] = vals[2];
      r['url'] = vals[3];
      r['note'] = vals[4];
      r['upd'] = DateTime.now().millisecondsSinceEpoch;
      if (orig == null) {
        r['id'] = newId();
        setState(() => _items.add(r));
      } else {
        final i = _items.indexWhere((x) => x['id'] == orig['id']);
        setState(() => _items[i] = r);
      }
    }
    await _persist();
    _touch();
  }

  // ----------------------------------------------------- dışa/içe aktarma

  Future<String?> _askPassword(String title, {bool confirm = false}) async {
    final a = TextEditingController(), b = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, obscureText: true, autofocus: true, decoration: InputDecoration(labelText: L(t, 'vault_password'))),
          if (confirm)
            TextField(controller: b, obscureText: true, decoration: InputDecoration(labelText: L(t, 'vault_repeat'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(L(t, 'cancel'))),
          FilledButton(
            onPressed: () {
              if (a.text.length < 8) return toast(c, L(t, 'vault_min'));
              if (confirm && a.text != b.text) return toast(c, L(t, 'vault_mismatch'));
              Navigator.pop(c, a.text);
            },
            child: Text(t.core('ok')),
          ),
        ],
      ),
    );
    a.dispose();
    b.dispose();
    return v;
  }

  Future<void> _export() async {
    final pw = await _askPassword(L(t, 'vault_export_pw'), confirm: true);
    if (pw == null || !mounted) return;
    setState(() => _busy = true);
    final env = await sealWithPassword(pw, utf8.encode(jsonEncode({'items': _items})));
    if (!mounted) return;
    setState(() => _busy = false);
    final d = DateTime.now();
    final name = 'kasa_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.kasa';
    await shareBytes(Uint8List.fromList(utf8.encode(jsonEncode(env))), name, 'application/octet-stream');
    _touch();
  }

  Future<void> _import() async {
    try {
      final r = await FilePicker.platform.pickFiles(withData: true);
      final bytes = r?.files.single.bytes;
      if (bytes == null || !mounted) return;
      final env = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
      final pw = await _askPassword(L(t, 'vault_import_pw'));
      if (pw == null || !mounted) return;
      setState(() => _busy = true);
      final clear = await openWithPassword(pw, env);
      final j = (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
      final incoming = [for (final e in (j['items'] as List? ?? const [])) (e as Map).cast<String, Object?>()];
      var added = 0;
      for (final e in incoming) {
        final i = _items.indexWhere((x) => x['id'] == e['id']);
        if (i < 0) {
          _items.add(e);
          added++;
        } else if (((e['upd'] as num?) ?? 0) > ((_items[i]['upd'] as num?) ?? 0)) {
          _items[i] = e;
          added++;
        }
      }
      await _persist();
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, '${L(t, 'vault_imported')}: $added');
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
    _touch();
  }

  Future<void> _changeMaster() async {
    final pw = await _askPassword(L(t, 'vault_change'), confirm: true);
    if (pw == null || !mounted) return;
    setState(() => _busy = true);
    const p = KdfParams();
    final salt = randomBytes(16);
    final key = await deriveVaultKey(pw, salt, p);
    _key = key;
    _env = {...?_env, 'kdf': p.toJson(salt)};
    await _persist();
    if (_bioOn) {
      try {
        await _secure.write(key: _bioKey, value: base64Encode(key));
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _busy = false);
      toast(context, L(t, 'vault_changed'));
    }
  }

  // ------------------------------------------------------------------ ekran

  Widget _pwField(TextEditingController c, String label, {VoidCallback? submit}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: c,
          obscureText: !_show,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: submit == null ? null : (_) => submit(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: IconButton(
              icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
      );

  List<Widget> _setupView() => [
        AppInfoCard(L(t, 'vault_intro'), icon: Icons.shield_rounded),
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _pwField(_pw, L(t, 'vault_master')),
            _Strength(t, _pw.text),
            _pwField(_pw2, L(t, 'vault_repeat'), submit: _create),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            AppButton(label: L(t, 'vault_create'), icon: Icons.lock_rounded, onPressed: _busy ? null : _create),
          ]),
        ),
        AppInfoCard(L(t, 'vault_forget'), icon: Icons.warning_amber_rounded),
      ];

  List<Widget> _lockedView() => [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Icon(Icons.lock_rounded, size: 72, color: Colors.white70),
        ),
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _pwField(_pw, L(t, 'vault_master'), submit: _unlock),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            AppButton(label: L(t, 'vault_unlock'), icon: Icons.lock_open_rounded, onPressed: _busy ? null : _unlock),
            if (_bioOn && _bioAvailable)
              OutlinedButton.icon(
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(L(t, 'vault_bio')),
                onPressed: _busy ? null : _unlockBio,
              ),
          ]),
        ),
      ];

  List<Widget> _openView() {
    final q = _q.toLowerCase();
    final list = _items
        .where((e) => q.isEmpty || '${e['title']} ${e['user']} ${e['url']}'.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => '${a['title']}'.toLowerCase().compareTo('${b['title']}'.toLowerCase()));
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: L(t, 'find'),
          ),
          onChanged: (v) => setState(() {
            _q = v;
            _touch();
          }),
        ),
      ),
      SectionBar('${L(t, 'vault_entries')} · ${_items.length}', icon: Icons.key_rounded, onAdd: () => _edit(), actions: [
        IconButton(tooltip: L(t, 'vault_lock'), icon: const Icon(Icons.lock_outline_rounded), onPressed: _lock),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'export':
                _export();
              case 'import':
                _import();
              case 'change':
                _changeMaster();
              case 'bio':
                _setBio(!_bioOn);
            }
          },
          itemBuilder: (c) => [
            PopupMenuItem(value: 'export', child: Text(L(t, 'vault_export'))),
            PopupMenuItem(value: 'import', child: Text(L(t, 'vault_import'))),
            PopupMenuItem(value: 'change', child: Text(L(t, 'vault_change'))),
            if (_bioAvailable)
              CheckedPopupMenuItem(value: 'bio', checked: _bioOn, child: Text(L(t, 'vault_bio'))),
          ],
        ),
      ]),
      if (_items.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.key_off_rounded),
      for (final e in list)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            onTap: () => _edit(e),
            leading: CircleAvatar(
              child: Text(('${e['title']}'.isEmpty ? '?' : '${e['title']}'.characters.first).toUpperCase()),
            ),
            title: Text('${e['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${e['user'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if ('${e['user'] ?? ''}'.isNotEmpty)
                IconButton(
                  tooltip: L(t, 'vault_user'),
                  icon: const Icon(Icons.person_outline_rounded),
                  onPressed: () => _copySecret('${e['user']}'),
                ),
              IconButton(
                tooltip: L(t, 'vault_password'),
                icon: const Icon(Icons.key_rounded),
                onPressed: () => _copySecret('${e['pass'] ?? ''}'),
              ),
            ]),
          ),
        ),
      AppInfoCard(L(t, 'vault_local'), icon: Icons.cloud_off_rounded),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_stage) {
      _Stage.loading => <Widget>[],
      _Stage.setup => _setupView(),
      _Stage.locked => _lockedView(),
      _Stage.open => _openView(),
    };
    return Listener(
      onPointerDown: (_) => _touch(),
      child: Stack(children: [
        if (_stage == _Stage.loading) const Center(child: CircularProgressIndicator()) else ToolList(children: body),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(color: Colors.black45, child: Center(child: CircularProgressIndicator())),
          ),
      ]),
    );
  }
}

/// Şifre gücü çubuğu.
class _Strength extends StatelessWidget {
  final ToolContext t;
  final String pw;
  const _Strength(this.t, this.pw);

  @override
  Widget build(BuildContext context) {
    if (pw.isEmpty) return const SizedBox.shrink();
    final s = passwordScore(pw);
    const colors = [Colors.redAccent, Colors.orangeAccent, Colors.amber, Colors.lightGreen, Colors.greenAccent];
    final names = Ls(t, 'vault_strength');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: (s + 1) / 5, color: colors[s], minHeight: 6),
          ),
        ),
        const SizedBox(width: 10),
        Text(s < names.length ? names[s] : '$s', style: TextStyle(color: colors[s])),
      ]),
    );
  }
}
