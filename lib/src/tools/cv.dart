/// Özgeçmiş (CV) oluşturucu: özgün 4 şablon, 33 dilde bölüm başlıkları
/// (CV dili arayüz dilinden bağımsız), PDF dışa aktarma (seçilebilir metin;
/// ATS uyumlu). Veriler yalnızca cihazda saklanır.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:studio_core/core/strings.dart';

import '../common.dart';
import '../tx.dart';

typedef Js = Map<String, Object?>;

/// kVerL listelerinin dil sırası.
const List<String> kCvLangs = [
  'tr', 'en', 'de', 'es', 'fr', 'ar', 'fa', 'he', 'ur', 'ru', 'uk', 'pl', 'cs', 'ro', 'hu', 'el', 'it', 'pt', 'nl',
  'sv', 'da', 'nb', 'fi', 'ja', 'ko', 'zh', 'hi', 'bn', 'id', 'ms', 'th', 'vi', 'fil',
];

const List<String> kCvTemplates = ['classic', 'modern', 'minimal', 'compact'];
const List<int> kCvColors = [0xFF1E3A5F, 0xFF00695C, 0xFF6A1B9A, 0xFFB71C1C, 0xFF37474F, 0xFFE65100];

/// CV dilinde bölüm başlıkları: profil, deneyim, eğitim, beceriler, diller,
/// sertifikalar, projeler, referanslar, iletişim, halen.
List<String> cvHeads(String lang) {
  final all = kVerL['cv_heads'];
  var i = kCvLangs.indexOf(lang == 'no' ? 'nb' : lang);
  if (i < 0) i = 1;
  final l = (all == null || i >= all.length ? 'Profile,Experience,Education,Skills,Languages,Certificates,Projects,References,Contact,Present' : all[i])
      .split(',')
      .map((s) => s.trim())
      .toList();
  while (l.length < 10) {
    l.add('');
  }
  return l;
}

bool cvRtl(String lang) => const {'ar', 'fa', 'he', 'ur'}.contains(lang);

Js newCv(String lang) => {
      'id': newId(),
      'lang': lang,
      'tpl': 'modern',
      'color': kCvColors.first,
      'p': <String, Object?>{},
      'summary': '',
      'exp': <Object?>[],
      'edu': <Object?>[],
      'skills': <Object?>[],
      'langs': <Object?>[],
      'certs': <Object?>[],
      'projects': <Object?>[],
      'refs': '',
    };

String _s(Object? v) => v is String ? v : '';
List<Js> _l(Object? v) => [for (final e in (v is List ? v : const [])) if (e is Map) e.cast<String, Object?>()];

/// "2019 – 2023" ya da "2021 – Halen".
String cvRange(Js e, String present) {
  final from = _s(e['from']), to = e['cur'] == true ? present : _s(e['to']);
  if (from.isEmpty && to.isEmpty) return '';
  if (from.isEmpty) return to;
  if (to.isEmpty) return from;
  return '$from – $to';
}

/// Metinde DejaVu Sans'ın çizemediği yazı sistemleri var mı (CJK, Hint,
/// Tay, Bengal)? Varsa uygun Noto yazı tipi gerekir.
Set<String> cvScripts(String text) {
  final out = <String>{};
  for (final r in text.runes) {
    if (r >= 0x3040 && r <= 0x30FF) out.add('ja');
    if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF)) out.add('zh');
    if (r >= 0xAC00 && r <= 0xD7AF || r >= 0x1100 && r <= 0x11FF) out.add('ko');
    if (r >= 0x0900 && r <= 0x097F) out.add('hi');
    if (r >= 0x0980 && r <= 0x09FF) out.add('bn');
    if (r >= 0x0E00 && r <= 0x0E7F) out.add('th');
  }
  return out;
}

/// CV'nin bütün metni (yazı tipi seçimi ve testler için).
String cvAllText(Js cv) {
  final heads = cvHeads(_s(cv['lang']));
  return [jsonEncode(cv['p']), cv['summary'], jsonEncode(cv['exp']), jsonEncode(cv['edu']), jsonEncode(cv['skills']),
    jsonEncode(cv['langs']), jsonEncode(cv['certs']), jsonEncode(cv['projects']), cv['refs'], heads.join(' ')].join(' ');
}

/// CV'yi PDF'e çevirir. [extraFonts]: CJK/Hint/Tay yazı tipleri.
Future<Uint8List> buildCvPdf(Js cv, {pw.ThemeData? theme, Uint8List? photo}) async {
  final lang = _s(cv['lang']);
  final heads = cvHeads(lang);
  final dir = cvRtl(lang) ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final accent = PdfColor.fromInt((cv['color'] as num?)?.toInt() ?? kCvColors.first);
  final tpl = _s(cv['tpl']).isEmpty ? 'modern' : _s(cv['tpl']);
  final p = (cv['p'] as Map?)?.cast<String, Object?>() ?? const {};
  final compact = tpl == 'compact';
  final base = compact ? 9.5 : 10.5;
  final doc = pw.Document(theme: theme);
  final img = photo == null ? null : pw.MemoryImage(photo);

  pw.Widget head(String s, {PdfColor? color}) => pw.Padding(
        padding: pw.EdgeInsets.only(top: compact ? 8 : 12, bottom: 4),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(tpl == 'minimal' ? s : s.toUpperCase(),
              style: pw.TextStyle(fontSize: base + 1.5, fontWeight: pw.FontWeight.bold, color: color ?? accent, letterSpacing: tpl == 'minimal' ? 0 : 0.8)),
          if (tpl != 'minimal') pw.Container(height: 1.2, width: 40, color: color ?? accent, margin: const pw.EdgeInsets.only(top: 2)),
        ]),
      );

  pw.Widget para(String s, {double? size, PdfColor? color}) =>
      pw.Text(s, style: pw.TextStyle(fontSize: size ?? base, color: color ?? PdfColors.grey900, lineSpacing: 1.5));

  pw.Widget entry(String title, String sub, String range, String desc) => pw.Padding(
        padding: pw.EdgeInsets.only(bottom: compact ? 5 : 8),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: pw.Text(title, style: pw.TextStyle(fontSize: base + 0.5, fontWeight: pw.FontWeight.bold))),
            if (range.isNotEmpty) pw.Text(range, style: pw.TextStyle(fontSize: base - 1, color: PdfColors.grey700)),
          ]),
          if (sub.isNotEmpty) pw.Text(sub, style: pw.TextStyle(fontSize: base, color: accent)),
          if (desc.isNotEmpty) pw.SizedBox(height: 2),
          for (final line in desc.split('\n').where((x) => x.trim().isNotEmpty))
            pw.Bullet(
              text: line.trim().replaceFirst(RegExp(r'^[-•*]\s*'), ''),
              style: pw.TextStyle(fontSize: base - 0.5, lineSpacing: 1.3),
              bulletSize: 2.5,
              bulletColor: accent,
            ),
        ]),
      );

  final contact = [
    for (final k in const ['email', 'phone', 'city', 'web', 'linkedin'])
      if (_s(p[k]).isNotEmpty) _s(p[k]),
  ];
  final exp = _l(cv['exp']), edu = _l(cv['edu']), certs = _l(cv['certs']), projects = _l(cv['projects']);
  final skills = [for (final s in (cv['skills'] as List? ?? const [])) '$s'].where((s) => s.trim().isNotEmpty).toList();
  final langs = _l(cv['langs']);

  List<pw.Widget> mainCol() => [
        if (_s(cv['summary']).isNotEmpty) ...[head(heads[0]), para(_s(cv['summary']))],
        if (exp.isNotEmpty) ...[
          head(heads[1]),
          for (final e in exp) entry(_s(e['role']), _s(e['org']), cvRange(e, heads[9]), _s(e['desc'])),
        ],
        if (edu.isNotEmpty) ...[
          head(heads[2]),
          for (final e in edu) entry(_s(e['degree']), _s(e['school']), cvRange(e, heads[9]), _s(e['desc'])),
        ],
        if (projects.isNotEmpty) ...[
          head(heads[6]),
          for (final e in projects) entry(_s(e['name']), '', '', _s(e['desc'])),
        ],
      ];

  List<pw.Widget> sideCol({PdfColor? color, PdfColor? text}) => [
        if (contact.isNotEmpty) ...[
          head(heads[8], color: color),
          for (final c in contact) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 2), child: para(c, size: base - 0.5, color: text)),
        ],
        if (skills.isNotEmpty) ...[
          head(heads[3], color: color),
          pw.Wrap(spacing: 4, runSpacing: 4, children: [
            for (final s in skills)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: color ?? accent, width: 0.6),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Text(s, style: pw.TextStyle(fontSize: base - 1, color: text ?? PdfColors.grey900)),
              ),
          ]),
        ],
        if (langs.isNotEmpty) ...[
          head(heads[4], color: color),
          for (final l in langs)
            para('${_s(l['name'])}${_s(l['level']).isEmpty ? '' : ' · ${_s(l['level'])}'}', size: base - 0.5, color: text),
        ],
        if (certs.isNotEmpty) ...[
          head(heads[5], color: color),
          for (final c in certs)
            para('${_s(c['name'])}${_s(c['year']).isEmpty ? '' : ' (${_s(c['year'])})'}', size: base - 0.5, color: text),
        ],
        if (_s(cv['refs']).isNotEmpty) ...[head(heads[7], color: color), para(_s(cv['refs']), size: base - 0.5, color: text)],
      ];

  pw.Widget nameBlock({PdfColor? color, PdfColor? sub, bool center = false}) => pw.Column(
        crossAxisAlignment: center ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_s(p['name']), style: pw.TextStyle(fontSize: compact ? 20 : 24, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.grey900)),
          if (_s(p['title']).isNotEmpty) pw.Text(_s(p['title']), style: pw.TextStyle(fontSize: base + 2, color: sub ?? accent)),
        ],
      );

  pw.Widget photoBox(double size) => img == null
      ? pw.SizedBox()
      : pw.Container(
          width: size,
          height: size,
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.ClipOval(child: pw.Image(img, fit: pw.BoxFit.cover)),
        );

  if (tpl == 'modern') {
    // Solda renkli kenar sütunu, sağda ana içerik.
    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        textDirection: dir,
        buildBackground: (ctx) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Row(children: [pw.Container(width: 190, color: accent), pw.Expanded(child: pw.Container())]),
        ),
      ),
      build: (ctx) => [
        pw.Partitions(children: [
          pw.Partition(
            width: 190,
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(18, 28, 14, 18),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                photoBox(96),
                ...sideCol(color: PdfColors.white, text: PdfColors.white),
              ]),
            ),
          ),
          pw.Partition(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(22, 28, 26, 18),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [nameBlock(), ...mainCol()]),
            ),
          ),
        ]),
      ],
    ));
  } else {
    final center = tpl == 'classic';
    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(compact ? 28 : 40),
        textDirection: dir,
      ),
      build: (ctx) => [
        if (center)
          pw.Center(child: pw.Column(children: [photoBox(80), nameBlock(center: true)]))
        else
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: nameBlock()),
            if (img != null) photoBox(70),
          ]),
        if (contact.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: center
                ? pw.Center(child: para(contact.join('  ·  '), size: base - 0.5))
                : para(contact.join('  ·  '), size: base - 0.5),
          ),
        if (tpl != 'minimal') pw.Divider(color: accent, thickness: 1.2),
        ...mainCol(),
        ...sideCol().skip(contact.isNotEmpty ? 1 + contact.length : 0),
      ],
    ));
  }
  return doc.save();
}

// ------------------------------------------------------------------- araç

class CvTool extends StatefulWidget {
  final ToolContext t;
  const CvTool(this.t, {super.key});

  @override
  State<CvTool> createState() => _CvToolState();
}

class _CvToolState extends State<CvTool> {
  List<Js> _cvs = [];
  Js? _cv;
  bool _preview = false;
  Timer? _saveT;
  final Map<String, Uint8List> _photos = {};

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      final l = await t.store.readList('cvs');
      if (!mounted) return;
      setState(() => _cvs = l);
    }());
  }

  @override
  void dispose() {
    _saveT?.cancel();
    unawaited(t.store.writeList('cvs', _cvs));
    super.dispose();
  }

  void _changed() {
    _saveT?.cancel();
    _saveT = Timer(const Duration(milliseconds: 600), () => t.store.writeList('cvs', _cvs));
  }

  Js get _p => ((_cv!['p'] as Map?) ?? (_cv!['p'] = <String, Object?>{})).cast<String, Object?>();

  Uint8List? _photo(Js cv) {
    final id = _s(cv['id']);
    final c = _photos[id];
    if (c != null) return c;
    final b64 = _s(cv['photo']);
    if (b64.isEmpty) return null;
    try {
      return _photos[id] = base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<pw.ThemeData> _theme(Js cv) async {
    final base = await pdfTheme();
    final scripts = cvScripts(cvAllText(cv));
    if (scripts.isEmpty) return base;
    final fallback = <pw.Font>[];
    try {
      for (final s in scripts) {
        fallback.add(await switch (s) {
          'ja' => PdfGoogleFonts.notoSansJPRegular(),
          'ko' => PdfGoogleFonts.notoSansKRRegular(),
          'zh' => PdfGoogleFonts.notoSansSCRegular(),
          'hi' => PdfGoogleFonts.notoSansDevanagariRegular(),
          'bn' => PdfGoogleFonts.notoSansBengaliRegular(),
          _ => PdfGoogleFonts.notoSansThaiRegular(),
        });
      }
    } catch (_) {
      if (mounted) toast(context, L(t, 'cv_font_note'));
    }
    return base.copyWith(
      defaultTextStyle: base.defaultTextStyle.copyWith(fontFallback: fallback),
    );
  }

  Future<Uint8List> _build(Js cv) async => buildCvPdf(cv, theme: await _theme(cv), photo: _photo(cv));

  Future<void> _editList(String key, List<(String, String, bool)> fields, [int? index]) async {
    final list = (_cv![key] as List?) ?? (_cv![key] = <Object?>[]) as List;
    final orig = index == null ? <String, Object?>{} : Map<String, Object?>.from(list[index] as Map);
    final ctl = {for (final f in fields) f.$1: TextEditingController(text: _s(orig[f.$1]))};
    var cur = orig['cur'] == true;
    final hasDates = fields.any((f) => f.$1 == 'from');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final f in fields)
                if (!(f.$1 == 'to' && cur))
                  AppTextField(controller: ctl[f.$1]!, label: f.$2, maxLines: f.$3 ? 5 : 1, minLines: f.$3 ? 3 : 1),
              if (hasDates)
                CheckboxListTile(
                  value: cur,
                  title: Text(cvHeads(_s(_cv!['lang']))[9]),
                  onChanged: (v) => set(() => cur = v == true),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.core('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.core('ok'))),
          ],
        ),
      ),
    );
    final item = <String, Object?>{for (final e in ctl.entries) e.key: e.value.text.trim(), if (hasDates) 'cur': cur};
    for (final c in ctl.values) {
      c.dispose();
    }
    if (ok != true || !mounted) return;
    setState(() {
      if (index == null) {
        list.add(item);
      } else {
        list[index] = item;
      }
    });
    _changed();
  }

  Widget _listSection(String key, String title, IconData icon, List<(String, String, bool)> fields, String Function(Js) line) {
    final list = _l(_cv![key]);
    return ExpansionTile(
      leading: Icon(icon),
      title: Text('$title (${list.length})'),
      children: [
        for (var i = 0; i < list.length; i++)
          ListTile(
            title: Text(line(list[i]), maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _editList(key, fields, i),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (i > 0)
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: () {
                    final l = _cv![key] as List;
                    setState(() => l.insert(i - 1, l.removeAt(i)));
                    _changed();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  setState(() => (_cv![key] as List).removeAt(i));
                  _changed();
                },
              ),
            ]),
          ),
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: Text(L(t, 'cv_add')),
          onTap: () => _editList(key, fields),
        ),
      ],
    );
  }

  Widget _field(Js m, String key, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextFormField(
          key: ValueKey('${_s(_cv?['id'])}.$key'),
          initialValue: _s(m[key]),
          maxLines: lines,
          minLines: 1,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) {
            m[key] = v;
            _changed();
          },
        ),
      );

  Widget _editor() {
    final cv = _cv!;
    final f = Ls(t, 'cv_fields'); // ad, unvan, e-posta, telefon, şehir, web, LinkedIn, özet
    String fl(int i) => i < f.length ? f[i].trim() : '';
    final heads = cvHeads(_s(cv['lang']));
    final skills = [for (final s in (cv['skills'] as List? ?? const [])) '$s'];
    final photo = _photo(cv);
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              unawaited(t.store.writeList('cvs', _cvs));
              setState(() => _cv = null);
            },
          ),
          Expanded(child: Text(_s(_p['name']).isEmpty ? L(t, 'cv_new') : _s(_p['name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          FilledButton.icon(onPressed: () => setState(() => _preview = true), icon: const Icon(Icons.picture_as_pdf_rounded), label: Text(L(t, 'cv_preview'))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Pick<String>(
          label: L(t, 'cv_lang'),
          values: kCvLangs,
          text: (l) => '${Strings.languageNames[l] ?? l} ($l)',
          value: kCvLangs.contains(_s(cv['lang'])) ? _s(cv['lang']) : 'en',
          onChanged: (v) {
            setState(() => cv['lang'] = v);
            _changed();
          },
        ),
      ),
      Choice<String>(
        values: kCvTemplates,
        labels: [for (var i = 0; i < 4; i++) Ls(t, 'cv_templates').elementAtOrNull(i)?.trim() ?? kCvTemplates[i]],
        selected: _s(cv['tpl']).isEmpty ? 'modern' : _s(cv['tpl']),
        onChanged: (v) {
          setState(() => cv['tpl'] = v);
          _changed();
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Wrap(spacing: 10, children: [
          for (final c in kCvColors)
            GestureDetector(
              onTap: () {
                setState(() => cv['color'] = c);
                _changed();
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Color(c),
                child: (cv['color'] as num?)?.toInt() == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
              ),
            ),
        ]),
      ),
      ListTile(
        leading: photo == null
            ? const CircleAvatar(child: Icon(Icons.add_a_photo_rounded))
            : CircleAvatar(backgroundImage: MemoryImage(photo)),
        title: Text(L(t, 'cv_photo')),
        trailing: photo == null
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  setState(() {
                    cv.remove('photo');
                    _photos.remove(_s(cv['id']));
                  });
                  _changed();
                },
              ),
        onTap: () async {
          try {
            final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 85);
            if (x == null) return;
            final b = await x.readAsBytes();
            if (!mounted) return;
            setState(() {
              cv['photo'] = base64Encode(b);
              _photos[_s(cv['id'])] = b;
            });
            _changed();
          } catch (_) {
            if (mounted) toast(context, t.tx('not_available'));
          }
        },
      ),
      AppHeading(heads[8], icon: Icons.badge_rounded),
      _field(_p, 'name', fl(0)),
      _field(_p, 'title', fl(1)),
      _field(_p, 'email', fl(2)),
      _field(_p, 'phone', fl(3)),
      _field(_p, 'city', fl(4)),
      _field(_p, 'web', fl(5)),
      _field(_p, 'linkedin', fl(6)),
      AppHeading(heads[0], icon: Icons.person_rounded),
      _field(cv, 'summary', fl(7), lines: 5),
      _listSection('exp', heads[1], Icons.work_rounded, [
        ('role', Ls(t, 'cv_exp_fields').elementAtOrNull(0)?.trim() ?? '', false),
        ('org', Ls(t, 'cv_exp_fields').elementAtOrNull(1)?.trim() ?? '', false),
        ('from', Ls(t, 'cv_exp_fields').elementAtOrNull(2)?.trim() ?? '', false),
        ('to', Ls(t, 'cv_exp_fields').elementAtOrNull(3)?.trim() ?? '', false),
        ('desc', Ls(t, 'cv_exp_fields').elementAtOrNull(4)?.trim() ?? '', true),
      ], (e) => '${_s(e['role'])} · ${_s(e['org'])}  ${cvRange(e, heads[9])}'),
      _listSection('edu', heads[2], Icons.school_rounded, [
        ('degree', Ls(t, 'cv_edu_fields').elementAtOrNull(0)?.trim() ?? '', false),
        ('school', Ls(t, 'cv_edu_fields').elementAtOrNull(1)?.trim() ?? '', false),
        ('from', Ls(t, 'cv_exp_fields').elementAtOrNull(2)?.trim() ?? '', false),
        ('to', Ls(t, 'cv_exp_fields').elementAtOrNull(3)?.trim() ?? '', false),
        ('desc', Ls(t, 'cv_exp_fields').elementAtOrNull(4)?.trim() ?? '', true),
      ], (e) => '${_s(e['degree'])} · ${_s(e['school'])}  ${cvRange(e, heads[9])}'),
      ExpansionTile(
        leading: const Icon(Icons.psychology_rounded),
        title: Text('${heads[3]} (${skills.length})'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (var i = 0; i < skills.length; i++)
                InputChip(
                  label: Text(skills[i]),
                  onDeleted: () {
                    setState(() => (cv['skills'] as List).removeAt(i));
                    _changed();
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: Text(L(t, 'cv_add')),
                onPressed: () async {
                  final s = await askText(context, t, heads[3]);
                  if (s == null || s.trim().isEmpty || !mounted) return;
                  setState(() {
                    final l = (cv['skills'] as List?) ?? (cv['skills'] = <Object?>[]) as List;
                    for (final x in s.split(',')) {
                      if (x.trim().isNotEmpty) l.add(x.trim());
                    }
                  });
                  _changed();
                },
              ),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ),
      _listSection('langs', heads[4], Icons.translate_rounded, [
        ('name', Ls(t, 'cv_lang_fields').elementAtOrNull(0)?.trim() ?? '', false),
        ('level', Ls(t, 'cv_lang_fields').elementAtOrNull(1)?.trim() ?? '', false),
      ], (e) => '${_s(e['name'])} · ${_s(e['level'])}'),
      _listSection('certs', heads[5], Icons.workspace_premium_rounded, [
        ('name', fl(0), false),
        ('year', Ls(t, 'cv_exp_fields').elementAtOrNull(2)?.trim() ?? '', false),
      ], (e) => '${_s(e['name'])} ${_s(e['year'])}'),
      _listSection('projects', heads[6], Icons.rocket_launch_rounded, [
        ('name', fl(0), false),
        ('desc', Ls(t, 'cv_exp_fields').elementAtOrNull(4)?.trim() ?? '', true),
      ], (e) => _s(e['name'])),
      AppHeading(heads[7], icon: Icons.contacts_rounded),
      _field(cv, 'refs', heads[7], lines: 3),
      AppInfoCard(L(t, 'cv_tip'), icon: Icons.tips_and_updates_rounded),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cv = _cv;
    if (cv != null && _preview) {
      final name = '${safeName(_s(_p['name']).isEmpty ? 'cv' : _s(_p['name']))}_CV.pdf';
      return Column(children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _preview = false),
            icon: const Icon(Icons.edit_rounded),
            label: Text(L(t, 'cv_edit')),
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: (_) => _build(cv),
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: name,
          ),
        ),
      ]);
    }
    if (cv != null) return _editor();
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppButton(
          label: L(t, 'cv_new'),
          icon: Icons.note_add_rounded,
          onPressed: () {
            final c = newCv(t.lang);
            setState(() {
              _cvs.insert(0, c);
              _cv = c;
            });
            _changed();
          },
        ),
      ),
      for (final c in _cvs)
        ListTile(
          leading: const Icon(Icons.description_rounded),
          title: Text(_s(((c['p'] as Map?) ?? const {})['name']).isEmpty ? L(t, 'cv_new') : _s((c['p'] as Map)['name'])),
          subtitle: Text('${Strings.languageNames[_s(c['lang'])] ?? _s(c['lang'])} · ${_s(c['tpl'])}'),
          onTap: () => setState(() {
            _cv = c;
            _preview = false;
          }),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'copy') {
                final d = (jsonDecode(jsonEncode(c)) as Map).cast<String, Object?>()..['id'] = newId();
                setState(() => _cvs.insert(0, d));
                _changed();
              } else if (v == 'del' && await confirmDelete(context, t)) {
                setState(() => _cvs.remove(c));
                _changed();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: Text(L(t, 'cv_copy'))),
              PopupMenuItem(value: 'del', child: Text(t.core('delete'))),
            ],
          ),
        ),
      if (_cvs.isEmpty) AppInfoCard(L(t, 'cv_intro'), icon: Icons.description_rounded),
      AppInfoCard(L(t, 'cv_local'), icon: Icons.lock_rounded),
    ]);
  }
}
