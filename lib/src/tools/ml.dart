/// Cihaz üstü yapay zekâ uygulamaları (Google ML Kit): kartvizit tarayıcı,
/// görselden metin ve çevrimdışı çeviri. Görüntü ve metin cihazdan çıkmaz.
/// Web'de ML Kit yoktur: kartvizit elle girilir, diğerleri bilgi gösterir.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic/doc_logic.dart';

/// Kamera ya da galeriden görüntü seçip metni tanır.
Future<String?> pickAndRecognize(BuildContext context, ToolContext t, ImageSource src, TextRecognitionScript script) async {
  if (src == ImageSource.camera && !await rationaleOnce(context, t, 'camera', Icons.photo_camera_rounded)) return null;
  XFile? x;
  try {
    x = await ImagePicker().pickImage(source: src, maxWidth: 2600, maxHeight: 2600, imageQuality: 92);
  } catch (_) {
    if (context.mounted) showPermissionDenied(context, t.lang);
    return null;
  }
  if (x == null) return null;
  final r = TextRecognizer(script: script);
  try {
    final res = await r.processImage(InputImage.fromFilePath(x.path));
    return res.text;
  } catch (_) {
    return null;
  } finally {
    await r.close();
  }
}

// ======================================================== kartvizit tarayıcı

class CardScanTool extends StatefulWidget {
  final ToolContext t;
  const CardScanTool(this.t, {super.key});

  @override
  State<CardScanTool> createState() => _CardScanToolState();
}

class _CardScanToolState extends State<CardScanTool> {
  List<Map<String, Object?>> _cards = [];
  bool _busy = false;
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('cards').then((l) {
      if (!mounted) return;
      setState(() {
        _cards = l;
        _loaded = true;
      });
    });
  }

  Future<void> _scan(ImageSource src) async {
    setState(() => _busy = true);
    final text = await pickAndRecognize(context, t, src, TextRecognitionScript.latin);
    if (!mounted) return;
    setState(() => _busy = false);
    if (text == null) return;
    if (text.trim().isEmpty) {
      toast(context, L(t, 'no_text'));
      return;
    }
    await _edit(card: parseCardText(text));
  }

  Future<void> _edit({ContactCard? card, Map<String, Object?>? orig}) async {
    final c = card ?? (orig == null ? ContactCard() : ContactCard.fromJson(orig));
    final keys = ['name', 'company', 'title', 'phone', 'email', 'web', 'address'];
    final labels = ['full_name', 'company', 'job_title', 'phone', 'email', 'website', 'address'];
    final json = c.toJson();
    final ctrls = [for (final k in keys) TextEditingController(text: json[k] as String? ?? '')];
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(L(t, 'business_card'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              if (orig != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    if (await confirmDelete(ctx, t) && ctx.mounted) Navigator.pop(ctx, 'del');
                  },
                ),
            ]),
            for (var i = 0; i < keys.length; i++)
              AppTextField(
                controller: ctrls[i],
                label: L(t, labels[i]),
                maxLines: keys[i] == 'address' ? 3 : 1,
                keyboard: switch (keys[i]) {
                  'phone' => TextInputType.phone,
                  'email' => TextInputType.emailAddress,
                  'web' => TextInputType.url,
                  _ => null,
                },
              ),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'vcf'), icon: const Icon(Icons.contact_page_rounded), label: Text(L(t, 'vcard'))),
              const Spacer(),
              FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
            ]),
          ]),
        ),
      ),
    );
    final data = {for (var i = 0; i < keys.length; i++) keys[i]: ctrls[i].text.trim()};
    for (final x in ctrls) {
      x.dispose();
    }
    if (res == null || !mounted) return;
    if (res == 'del') {
      setState(() => _cards.removeWhere((x) => x['id'] == orig?['id']));
    } else {
      final m = <String, Object?>{...data, 'id': orig?['id'] ?? newId(), 'at': DateTime.now().millisecondsSinceEpoch};
      setState(() {
        final i = _cards.indexWhere((x) => x['id'] == m['id']);
        if (i >= 0) {
          _cards[i] = m;
        } else {
          _cards.insert(0, m);
        }
      });
      if (res == 'vcf') await _shareVcf(m);
    }
    await t.store.writeList('cards', _cards);
  }

  Future<void> _shareVcf(Map<String, Object?> m) async {
    final c = ContactCard.fromJson(m);
    final name = safeName(c.name.isEmpty ? 'contact' : c.name);
    await shareBytes(Uint8List.fromList(utf8.encode(c.toVCard())), '$name.vcf', 'text/vcard');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Stack(children: [
      ToolList(children: [
        if (kIsWeb)
          AppInfoCard(L(t, 'manual_entry_web'), icon: Icons.keyboard_rounded)
        else
          AppPanel(
            child: Column(children: [
              Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                AppButton(label: L(t, 'scan_card'), icon: Icons.photo_camera_rounded, onPressed: _busy ? null : () => _scan(ImageSource.camera)),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _scan(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(L(t, 'gallery')),
                ),
              ]),
              if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
              const SizedBox(height: 6),
              Text(L(t, 'ml_on_device'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ]),
          ),
        if (_cards.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.contact_mail_rounded),
        for (final m in _cards)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              onTap: () => _edit(orig: m),
              leading: const Icon(Icons.badge_rounded),
              title: Text((m['name'] as String? ?? '').isEmpty ? '…' : m['name'] as String),
              subtitle: Text([m['company'], m['phone'], m['email']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(onPressed: () => _shareVcf(m), icon: const Icon(Icons.ios_share_rounded)),
            ),
          ),
      ]),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton(heroTag: null, onPressed: () => _edit(), child: const Icon(Icons.edit_rounded)),
      ),
    ]);
  }
}

// ========================================================== görselden metin

class OcrTool extends StatefulWidget {
  final ToolContext t;
  const OcrTool(this.t, {super.key});

  @override
  State<OcrTool> createState() => _OcrToolState();
}

class _OcrToolState extends State<OcrTool> {
  static const _scripts = [
    TextRecognitionScript.latin,
    TextRecognitionScript.chinese,
    TextRecognitionScript.japanese,
    TextRecognitionScript.korean,
    TextRecognitionScript.devanagiri,
  ];
  static const _names = ['Latin', '中文', '日本語', '한국어', 'देवनागरी'];
  int _script = 0;
  final _text = TextEditingController();
  List<String> _history = [];
  bool _busy = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _script = switch (t.lang) { 'zh' => 1, 'ja' => 2, 'ko' => 3, 'hi' => 4, _ => 0 };
    t.store.readStrings('history').then((h) {
      if (mounted) setState(() => _history = h);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(ImageSource src) async {
    setState(() => _busy = true);
    final r = await pickAndRecognize(context, t, src, _scripts[_script]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) return;
    if (r.trim().isEmpty) {
      toast(context, L(t, 'no_text'));
      return;
    }
    setState(() {
      _text.text = r;
      _history.remove(r);
      _history.insert(0, r);
      if (_history.length > 20) _history = _history.sublist(0, 20);
    });
    await t.store.writeStrings('history', _history);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return ToolList(children: [notAvailable(t)]);
    return ToolList(children: [
      Choice<int>(
        values: const [0, 1, 2, 3, 4],
        labels: _names,
        selected: _script,
        onChanged: (v) => setState(() => _script = v),
      ),
      AppInfoCard(L(t, 'ocr_unsupported'), icon: Icons.translate_rounded),
      AppPanel(
        child: Column(children: [
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
            AppButton(label: L(t, 'take_photo'), icon: Icons.photo_camera_rounded, onPressed: _busy ? null : () => _run(ImageSource.camera)),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded),
              label: Text(L(t, 'gallery')),
            ),
          ]),
          if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          const SizedBox(height: 6),
          Text(L(t, 'ml_on_device'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(controller: _text, label: L(t, 'text'), maxLines: 16, minLines: 6),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: () => copyText(context, t, _text.text), icon: const Icon(Icons.copy_rounded)),
        IconButton(onPressed: () => shareText(_text.text), icon: const Icon(Icons.ios_share_rounded)),
      ]),
      if (_history.isNotEmpty) SectionBar(L(t, 'history'), icon: Icons.history_rounded),
      for (final h in _history)
        ListTile(
          title: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => setState(() => _text.text = h),
          trailing: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              setState(() => _history.remove(h));
              t.store.writeStrings('history', _history);
            },
          ),
        ),
    ]);
  }
}

// ========================================================= çevrimdışı çeviri

/// ML Kit dil kodlarının yerel adları (bilinmeyenlerde kod gösterilir).
const Map<String, String> kLangNames = {
  'af': 'Afrikaans', 'ar': 'العربية', 'be': 'Беларуская', 'bg': 'Български', 'bn': 'বাংলা', 'ca': 'Català',
  'cs': 'Čeština', 'cy': 'Cymraeg', 'da': 'Dansk', 'de': 'Deutsch', 'el': 'Ελληνικά', 'en': 'English',
  'eo': 'Esperanto', 'es': 'Español', 'et': 'Eesti', 'fa': 'فارسی', 'fi': 'Suomi', 'fr': 'Français',
  'ga': 'Gaeilge', 'gl': 'Galego', 'gu': 'ગુજરાતી', 'he': 'עברית', 'hi': 'हिन्दी', 'hr': 'Hrvatski',
  'ht': 'Kreyòl ayisyen', 'hu': 'Magyar', 'id': 'Bahasa Indonesia', 'is': 'Íslenska', 'it': 'Italiano',
  'ja': '日本語', 'ka': 'ქართული', 'kn': 'ಕನ್ನಡ', 'ko': '한국어', 'lt': 'Lietuvių', 'lv': 'Latviešu',
  'mk': 'Македонски', 'mr': 'मराठी', 'ms': 'Bahasa Melayu', 'mt': 'Malti', 'nl': 'Nederlands', 'no': 'Norsk',
  'pl': 'Polski', 'pt': 'Português', 'ro': 'Română', 'ru': 'Русский', 'sk': 'Slovenčina', 'sl': 'Slovenščina',
  'sq': 'Shqip', 'sv': 'Svenska', 'sw': 'Kiswahili', 'ta': 'தமிழ்', 'te': 'తెలుగు', 'th': 'ไทย',
  'tl': 'Filipino', 'tr': 'Türkçe', 'uk': 'Українська', 'ur': 'اردو', 'vi': 'Tiếng Việt', 'zh': '中文',
};

String langName(TranslateLanguage l) => kLangNames[l.bcpCode] ?? l.bcpCode;

class TranslateTool extends StatefulWidget {
  final ToolContext t;
  const TranslateTool(this.t, {super.key});

  @override
  State<TranslateTool> createState() => _TranslateToolState();
}

class _TranslateToolState extends State<TranslateTool> {
  final _mgr = OnDeviceTranslatorModelManager();
  late final List<TranslateLanguage> _langs = [...TranslateLanguage.values]..sort((a, b) => langName(a).compareTo(langName(b)));
  TranslateLanguage? _from, _to;
  final _in = TextEditingController();
  String _out = '';
  bool _busy = false;
  final Set<String> _have = {};
  ToolContext get t => widget.t;

  TranslateLanguage? _byCode(String? c) {
    for (final l in TranslateLanguage.values) {
      if (l.bcpCode == c) return l;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _load();
  }

  Future<void> _load() async {
    final mine = t.lang == 'nb' ? 'no' : (t.lang == 'fil' ? 'tl' : t.lang);
    _from = _byCode(await t.store.read('from')) ?? _byCode(mine == 'en' ? 'tr' : 'en');
    _to = _byCode(await t.store.read('to')) ?? _byCode(mine == 'en' ? 'es' : mine) ?? _byCode('en');
    await _refresh();
  }

  Future<void> _refresh() async {
    final have = <String>{};
    for (final l in TranslateLanguage.values) {
      try {
        if (await _mgr.isModelDownloaded(l.bcpCode)) have.add(l.bcpCode);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _have
        ..clear()
        ..addAll(have);
    });
  }

  Future<bool> _ensure(TranslateLanguage l) async {
    if (_have.contains(l.bcpCode)) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.download_rounded),
        title: Text(langName(l)),
        content: Text(L(t, 'model_size')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L(t, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L(t, 'download_model'))),
        ],
      ),
    );
    if (ok != true) return false;
    setState(() => _busy = true);
    try {
      final done = await _mgr.downloadModel(l.bcpCode, isWifiRequired: false);
      if (done) _have.add(l.bcpCode);
      return done;
    } catch (_) {
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _translate() async {
    final f = _from, to = _to;
    final text = _in.text.trim();
    if (f == null || to == null || text.isEmpty) return;
    if (!await _ensure(f) || !mounted || !await _ensure(to) || !mounted) {
      if (mounted) toast(context, L(t, 'model_missing'));
      return;
    }
    setState(() => _busy = true);
    final tr = OnDeviceTranslator(sourceLanguage: f, targetLanguage: to);
    try {
      final r = await tr.translateText(text);
      if (mounted) setState(() => _out = r);
    } catch (_) {
      if (mounted) toast(context, L(t, 'model_missing'));
    } finally {
      await tr.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _models() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(L(t, 'download_model'), style: const TextStyle(fontWeight: FontWeight.w800))),
            for (final l in _langs.where((l) => _have.contains(l.bcpCode)))
              ListTile(
                leading: const Icon(Icons.offline_pin_rounded),
                title: Text(langName(l)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    try {
                      await _mgr.deleteModel(l.bcpCode);
                    } catch (_) {}
                    _have.remove(l.bcpCode);
                    set(() {});
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Widget _langPick(TranslateLanguage? v, ValueChanged<TranslateLanguage> on, String label) => Pick<TranslateLanguage>(
        label: label,
        values: _langs,
        text: (l) => '${langName(l)}${_have.contains(l.bcpCode) ? '  ✓' : ''}',
        value: v ?? _langs.first,
        onChanged: on,
      );

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return ToolList(children: [notAvailable(t)]);
    return ToolList(children: [
      AppInfoCard(L(t, 'draft_note'), icon: Icons.info_outline_rounded),
      AppPanel(
        child: Column(children: [
          Row(children: [
            Expanded(child: _langPick(_from, (l) {
              setState(() => _from = l);
              t.store.write('from', l.bcpCode);
            }, L(t, 'from'))),
            IconButton(
              onPressed: () => setState(() {
                final a = _from;
                _from = _to;
                _to = a;
                if (_out.isNotEmpty) {
                  _in.text = _out;
                  _out = '';
                }
              }),
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
            Expanded(child: _langPick(_to, (l) {
              setState(() => _to = l);
              t.store.write('to', l.bcpCode);
            }, L(t, 'to'))),
          ]),
          AppTextField(controller: _in, label: L(t, 'text'), maxLines: 8, minLines: 3),
          Row(children: [
            IconButton(tooltip: L(t, 'download_model'), onPressed: _models, icon: const Icon(Icons.download_for_offline_rounded)),
            const Spacer(),
            FilledButton.icon(onPressed: _busy ? null : _translate, icon: const Icon(Icons.translate_rounded), label: Text(L(t, 'translate'))),
          ]),
          if (_busy) const LinearProgressIndicator(),
        ]),
      ),
      if (_out.isNotEmpty)
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(_out, style: const TextStyle(fontSize: 18)),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(onPressed: () => copyText(context, t, _out), icon: const Icon(Icons.copy_rounded)),
              IconButton(onPressed: () => shareText(_out), icon: const Icon(Icons.ios_share_rounded)),
            ]),
          ]),
        ),
    ]);
  }
}
