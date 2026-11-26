/// Kayıt listesi motoru: not defteri, yapılacaklar, okuma ve izleme
/// listeleri, ödev, fatura/fiş ve envanter aynı sağlam listeyi kullanır.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

/// Alan türü.
enum FK { text, longText, number, money, date, choice, rating, check, color }

/// Bir alanın tanımı. [label] ve [choices] etiket anahtarlarıdır.
class FieldSpec {
  final String key;
  final String label;
  final FK kind;
  final String? choices;
  const FieldSpec(this.key, this.label, this.kind, {this.choices});
}

/// Bir listenin tanımı.
class RecordSpec {
  final List<FieldSpec> fields;
  final String titleKey;
  final List<String> subtitleKeys;
  final String? doneKey;
  final String? dateKey;
  final bool dateIsDue;
  final String? sumKey;
  final String? filterKey;
  final bool monthFilter;
  final bool pinnable;
  final String? colorKey;
  final String? incKey;
  final String? codeKey;
  final String itemLabel;
  final IconData icon;
  final String? info;

  const RecordSpec({
    required this.fields,
    required this.titleKey,
    required this.itemLabel,
    required this.icon,
    this.subtitleKeys = const [],
    this.doneKey,
    this.dateKey,
    this.dateIsDue = false,
    this.sumKey,
    this.filterKey,
    this.monthFilter = false,
    this.pinnable = false,
    this.colorKey,
    this.incKey,
    this.codeKey,
    this.info,
  });

  FieldSpec field(String k) => fields.firstWhere((f) => f.key == k);
}

typedef Rec = Map<String, Object?>;

/// Kayıtların sıralanması: sabitlenenler, sonra (varsa) yapılmamışlar,
/// sonra vade tarihi ya da son değişiklik.
List<Rec> sortRecords(List<Rec> items, RecordSpec s) {
  int pinOf(Rec r) => r['pin'] == true ? 0 : 1;
  int doneOf(Rec r) => s.doneKey != null && r[s.doneKey] == true ? 1 : 0;
  final l = [...items];
  l.sort((a, b) {
    var c = pinOf(a).compareTo(pinOf(b));
    if (c != 0) return c;
    c = doneOf(a).compareTo(doneOf(b));
    if (c != 0) return c;
    final dk = s.dateKey;
    if (dk != null) {
      final da = a[dk] as String? ?? '', db = b[dk] as String? ?? '';
      if (s.dateIsDue) {
        if (da.isEmpty != db.isEmpty) return da.isEmpty ? 1 : -1;
        c = da.compareTo(db);
      } else {
        c = db.compareTo(da);
      }
      if (c != 0) return c;
    }
    return ((b['updated'] as num?) ?? 0).compareTo((a['updated'] as num?) ?? 0);
  });
  return l;
}

/// Basit metin araması (bütün metin alanlarında, büyük/küçük harf duyarsız).
bool matchesQuery(Rec r, RecordSpec s, String q) {
  if (q.trim().isEmpty) return true;
  final needle = q.toLowerCase();
  for (final f in s.fields) {
    if (f.kind == FK.text || f.kind == FK.longText) {
      if ((r[f.key] as String? ?? '').toLowerCase().contains(needle)) return true;
    }
  }
  return false;
}

/// Toplam (para/sayı alanı).
double sumOf(Iterable<Rec> items, String key) =>
    items.fold<double>(0, (a, r) => a + ((r[key] as num?)?.toDouble() ?? 0));

class RecordsTool extends StatefulWidget {
  final ToolContext t;
  final RecordSpec spec;
  const RecordsTool(this.t, this.spec, {super.key});

  @override
  State<RecordsTool> createState() => _RecordsToolState();
}

class _RecordsToolState extends State<RecordsTool> {
  List<Rec> _items = [];
  bool _loaded = false;
  String _q = '';
  int _filter = -1;
  bool _showDone = true;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  ToolContext get t => widget.t;
  RecordSpec get s => widget.spec;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await t.store.readList('items');
    final sd = await t.store.readBool('show_done', true);
    if (!mounted) return;
    setState(() {
      _items = l;
      _showDone = sd;
      _loaded = true;
    });
  }

  Future<void> _save() => t.store.writeList('items', _items);

  List<Rec> get _visible {
    var l = _items.where((r) => matchesQuery(r, s, _q));
    final fk = s.filterKey;
    if (fk != null && _filter >= 0) l = l.where((r) => (r[fk] as num?)?.toInt() == _filter);
    final dk = s.doneKey;
    if (dk != null && !_showDone) l = l.where((r) => r[dk] != true);
    final mk = s.dateKey;
    if (s.monthFilter && mk != null) {
      final prefix = dayKey(_month).substring(0, 7);
      l = l.where((r) => (r[mk] as String? ?? '').startsWith(prefix));
    }
    return sortRecords(l.toList(), s);
  }

  String _fmtNum(double v) => formatNumber(v, digits: 2);

  String _display(Rec r, FieldSpec f) {
    final v = r[f.key];
    switch (f.kind) {
      case FK.text:
      case FK.longText:
        return (v as String? ?? '').trim();
      case FK.number:
        return v == null ? '' : '${L(t, f.label)}: ${_fmtNum((v as num).toDouble())}';
      case FK.money:
        return v == null ? '' : _fmtNum((v as num).toDouble());
      case FK.date:
        final d = DateTime.tryParse(v as String? ?? '');
        return d == null ? '' : fmtDate(context, d);
      case FK.choice:
        final i = (v as num?)?.toInt();
        final opts = Ls(t, f.choices!);
        return i == null || i < 0 || i >= opts.length ? '' : opts[i];
      case FK.rating:
        final n = (v as num?)?.toInt() ?? 0;
        return n == 0 ? '' : '★' * n;
      case FK.check:
      case FK.color:
        return '';
    }
  }

  Future<void> _edit([Rec? orig]) async {
    final r = Map<String, Object?>.from(orig ?? {});
    if (orig == null) {
      for (final f in s.fields) {
        if (f.kind == FK.date && !s.dateIsDue && f.key == s.dateKey) r[f.key] = dayKey(DateTime.now());
        if (f.kind == FK.choice && f.key == s.filterKey && _filter >= 0) r[f.key] = _filter;
      }
      final ck = s.codeKey;
      if (ck != null) r[ck] = 'INV-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    }
    final res = await showModalBottomSheet<Rec>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => _RecordForm(t: t, spec: s, initial: r, isNew: orig == null),
    );
    if (res == null || !mounted) return;
    if (res['_delete'] == true) {
      setState(() => _items.removeWhere((x) => x['id'] == orig?['id']));
    } else {
      res['updated'] = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        if (orig == null) {
          res['id'] = newId();
          _items.add(res);
        } else {
          final i = _items.indexWhere((x) => x['id'] == orig['id']);
          if (i >= 0) _items[i] = res;
        }
      });
    }
    await _save();
  }

  Future<void> _toggleDone(Rec r) async {
    final dk = s.doneKey!;
    setState(() {
      r[dk] = r[dk] != true;
      r['updated'] = DateTime.now().millisecondsSinceEpoch;
    });
    await _save();
  }

  Future<void> _inc(Rec r) async {
    final k = s.incKey!;
    setState(() {
      r[k] = ((r[k] as num?)?.toInt() ?? 0) + 1;
      r['updated'] = DateTime.now().millisecondsSinceEpoch;
    });
    await _save();
  }

  Future<void> _exportCsv() async {
    if (!await extraGate(context, t, 'csv')) return;
    final rows = <List<String>>[
      [for (final f in s.fields) if (f.kind != FK.color) L(t, f.label)],
      for (final r in sortRecords(_items, s))
        [
          for (final f in s.fields)
            if (f.kind != FK.color)
              switch (f.kind) {
                FK.check => r[f.key] == true ? '✓' : '',
                FK.number || FK.money => (r[f.key] as num?)?.toString() ?? '',
                FK.rating => (r[f.key] as num?)?.toString() ?? '',
                FK.choice => (() {
                    final i = (r[f.key] as num?)?.toInt();
                    final o = Ls(t, f.choices!);
                    return i == null || i < 0 || i >= o.length ? '' : o[i];
                  })(),
                _ => r[f.key]?.toString() ?? '',
              },
        ],
    ];
    await shareBytes(Uint8List.fromList(utf8.encode('﻿${toCsv(rows)}')), '${safeName(t.toolId)}.csv', 'text/csv');
  }

  Future<void> _labelsPdf() async {
    final ck = s.codeKey!;
    final theme = await pdfTheme();
    final items = sortRecords(_items, s);
    if (items.isEmpty) return;
    final doc = pw.Document(theme: theme);
    const perPage = 24;
    for (var p = 0; p < items.length; p += perPage) {
      final chunk = items.sublist(p, math.min<int>(p + perPage, items.length));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (c) => pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in chunk)
            pw.Container(
              width: 128,
              height: 112,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey600)),
              child: pw.Column(children: [
                pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: r[ck] as String? ?? '', width: 64, height: 64),
                pw.SizedBox(height: 4),
                pw.Text(r[s.titleKey] as String? ?? '', maxLines: 1, style: const pw.TextStyle(fontSize: 9)),
                pw.Text(r[ck] as String? ?? '', style: const pw.TextStyle(fontSize: 7)),
              ]),
            ),
        ]),
      ));
    }
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: 'labels.pdf');
  }

  Future<void> _scanFind() async {
    final ck = s.codeKey!;
    if (!await rationaleOnce(context, t, 'camera', Icons.qr_code_scanner_rounded)) return;
    if (!mounted) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => const _ScanSheet(),
    );
    if (code == null || !mounted) return;
    final i = _items.indexWhere((r) => r[ck] == code);
    if (i < 0) {
      toast(context, L(t, 'not_found'));
      return;
    }
    await _edit(_items[i]);
  }

  void _showQr(Rec r) {
    final code = r[s.codeKey!] as String? ?? '';
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(r[s.titleKey] as String? ?? ''),
        content: SizedBox(
          width: 240,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: code, size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            SelectableText(code),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(L(t, 'close')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final vis = _visible;
    final fk = s.filterKey;
    final sk = s.sumKey;
    return Stack(children: [
      ToolList(children: [
        if (s.info != null) AppInfoCard(L(t, s.info!), icon: Icons.info_outline_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t.tx('search'),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        if (s.monthFilter)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            ),
            Text(MaterialLocalizations.of(context).formatMonthYear(_month), style: const TextStyle(fontSize: 17)),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ]),
        if (fk != null)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(t.tx('all')), selected: _filter < 0, onSelected: (_) => setState(() => _filter = -1)),
              ),
              for (final (i, o) in Ls(t, s.field(fk).choices!).indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$o (${_items.where((r) => (r[fk] as num?)?.toInt() == i).length})'),
                    selected: _filter == i,
                    onSelected: (_) => setState(() => _filter = i),
                  ),
                ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (s.doneKey != null)
              FilterChip(
                label: Text(L(t, 'show_done')),
                selected: _showDone,
                onSelected: (v) {
                  setState(() => _showDone = v);
                  t.store.writeBool('show_done', v);
                },
              ),
            if (s.codeKey != null) ...[
              // Barkod tarayıcı (mobile_scanner) Windows ve Linux'ta yok.
              if (_scanSupported)
                IconButton(tooltip: L(t, 'find_scan'), icon: const Icon(Icons.qr_code_scanner_rounded), onPressed: _scanFind),
              IconButton(tooltip: L(t, 'labels_pdf'), icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _labelsPdf),
            ],
            IconButton(tooltip: L(t, 'export_csv'), icon: const Icon(Icons.ios_share_rounded), onPressed: _items.isEmpty ? null : _exportCsv),
          ]),
        ),
        if (sk != null)
          AppResult(label: '${L(t, 'total')} (${vis.length})', value: _fmtNum(sumOf(vis, sk)), lang: t.lang, big: true),
        if (vis.isEmpty) EmptyHint(L(t, 'empty_list'), icon: s.icon),
        for (final r in vis) _tile(r),
      ]),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () => _edit(),
          icon: const Icon(Icons.add_rounded),
          label: Text(L(t, s.itemLabel)),
        ),
      ),
    ]);
  }

  Widget _tile(Rec r) {
    final dk = s.doneKey;
    final done = dk != null && r[dk] == true;
    final ck = s.colorKey;
    final color = ck != null ? paletteAt((r[ck] as num?)?.toInt() ?? 0) : null;
    final title = (r[s.titleKey] as String? ?? '').trim();
    final subs = <String>[
      for (final k in s.subtitleKeys)
        if (_display(r, s.field(k)).isNotEmpty) _display(r, s.field(k)),
    ];
    var overdue = false;
    final dkey = s.dateKey;
    if (s.dateIsDue && dkey != null && !done) {
      final d = DateTime.tryParse(r[dkey] as String? ?? '');
      overdue = d != null && d.isBefore(dateOnly(DateTime.now()));
    }
    final sk = s.sumKey;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: color?.withValues(alpha: 0.22),
      child: ListTile(
        onTap: () => _edit(r),
        leading: dk != null
            ? Checkbox(value: done, onChanged: (_) => _toggleDone(r))
            : (r['pin'] == true ? const Icon(Icons.push_pin_rounded) : Icon(s.icon, color: color)),
        title: Text(
          title.isEmpty ? '…' : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            decoration: done ? TextDecoration.lineThrough : null,
            color: done ? Colors.white54 : null,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: subs.isEmpty
            ? null
            : Text(subs.join(' · '),
                maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: overdue ? Colors.redAccent : Colors.white70)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (sk != null && r[sk] != null)
            Text(_fmtNum((r[sk] as num).toDouble()), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (s.incKey != null)
            IconButton(tooltip: '+1', icon: const Icon(Icons.exposure_plus_1_rounded), onPressed: () => _inc(r)),
          if (s.codeKey != null) IconButton(icon: const Icon(Icons.qr_code_2_rounded), onPressed: () => _showQr(r)),
        ]),
      ),
    );
  }
}

/// Kayıt formu (alt sayfa).
class _RecordForm extends StatefulWidget {
  final ToolContext t;
  final RecordSpec spec;
  final Rec initial;
  final bool isNew;
  const _RecordForm({required this.t, required this.spec, required this.initial, required this.isNew});

  @override
  State<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<_RecordForm> {
  late final Rec r = Map<String, Object?>.from(widget.initial);
  final Map<String, TextEditingController> _c = {};

  ToolContext get t => widget.t;
  RecordSpec get s => widget.spec;

  @override
  void initState() {
    super.initState();
    for (final f in s.fields) {
      if (f.kind == FK.text || f.kind == FK.longText) {
        _c[f.key] = TextEditingController(text: r[f.key] as String? ?? '');
      } else if (f.kind == FK.number || f.kind == FK.money) {
        final v = r[f.key] as num?;
        _c[f.key] = TextEditingController(text: v == null ? '' : formatNumber(v.toDouble(), digits: 2));
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    for (final f in s.fields) {
      final c = _c[f.key];
      if (c == null) continue;
      if (f.kind == FK.number || f.kind == FK.money) {
        r[f.key] = parseNumber(c.text);
      } else {
        r[f.key] = c.text.trim();
      }
    }
    Navigator.pop(context, r);
  }

  Widget _field(FieldSpec f) {
    switch (f.kind) {
      case FK.text:
        return AppTextField(controller: _c[f.key]!, label: L(t, f.label), autofocus: widget.isNew && f.key == s.titleKey);
      case FK.longText:
        return AppTextField(controller: _c[f.key]!, label: L(t, f.label), maxLines: 14, minLines: 4);
      case FK.number:
      case FK.money:
        return AppNumberField(controller: _c[f.key]!, label: L(t, f.label));
      case FK.date:
        return DateRow(
          label: L(t, f.label),
          value: DateTime.tryParse(r[f.key] as String? ?? ''),
          onChanged: (d) => setState(() => r[f.key] = d == null ? null : dayKey(d)),
        );
      case FK.choice:
        final opts = Ls(t, f.choices!);
        final cur = math.max<int>(0, math.min<int>((r[f.key] as num?)?.toInt() ?? 0, opts.length - 1));
        return Pick<int>(
          label: L(t, f.label),
          values: [for (var i = 0; i < opts.length; i++) i],
          text: (i) => opts[i],
          value: cur,
          onChanged: (v) => setState(() => r[f.key] = v),
        );
      case FK.rating:
        final n = (r[f.key] as num?)?.toInt() ?? 0;
        return Row(children: [
          Text(L(t, f.label)),
          const Spacer(),
          for (var i = 1; i <= 5; i++)
            IconButton(
              icon: Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber),
              onPressed: () => setState(() => r[f.key] = i == n ? 0 : i),
            ),
        ]);
      case FK.check:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(L(t, f.label)),
          value: r[f.key] == true,
          onChanged: (v) => setState(() => r[f.key] = v),
        );
      case FK.color:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L(t, f.label)),
          ColorRow(value: (r[f.key] as num?)?.toInt() ?? 0, onChanged: (v) => setState(() => r[f.key] = v)),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Seçimli alanlar için varsayılanı yaz (kaydedildiğinde boş kalmasın).
    for (final f in s.fields) {
      if (f.kind == FK.choice && r[f.key] == null) r[f.key] = 0;
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(L(t, s.itemLabel), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            if (s.pinnable)
              IconButton(
                tooltip: L(t, 'pin'),
                icon: Icon(r['pin'] == true ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                onPressed: () => setState(() => r['pin'] = r['pin'] != true),
              ),
            if (!widget.isNew)
              IconButton(
                tooltip: L(t, 'delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (await confirmDelete(context, t) && context.mounted) Navigator.pop(context, {'_delete': true});
                },
              ),
          ]),
          for (final f in s.fields) _field(f),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _done, icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
        ]),
      ),
    );
  }
}

/// QR/barkod okuyup değeri döndüren alt sayfa.
class _ScanSheet extends StatefulWidget {
  const _ScanSheet();

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
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
              if (v == null) return;
              _done = true;
              Navigator.pop(context, v);
            },
          ),
        ),
      );
}

/// Kamerayla barkod/QR okuma bu platformda var mı (mobile_scanner: Android,
/// iOS, macOS, web)?
bool get _scanSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;
