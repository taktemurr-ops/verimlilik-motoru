/// Belge uygulamaları: belge tarayıcı, PDF görüntüleyici, fatura ve teklif.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:studio_core/app/studio_ui.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic/doc_logic.dart';
import '../platform/disk.dart';

// ============================================================ belge tarayıcı

/// Düzeltme işi: köşeler görüntü pikseli olarak (sol üst, sağ üst, sağ alt,
/// sol alt). [bw]: siyah-beyaz belge görünümü. [turns]: 90° dönüş sayısı.
class RectifyJob {
  final Uint8List bytes;
  final List<double> corners;
  final bool bw;
  final int turns;
  const RectifyJob(this.bytes, this.corners, {this.bw = false, this.turns = 0});
}

/// Fotoğraftaki sayfayı dört köşeye göre düzleştirir ve JPEG döndürür.
/// Ana iş parçacığını yormamak için `compute` ile çağrılır.
Uint8List? rectifyPage(RectifyJob job) {
  final src0 = img.decodeImage(job.bytes);
  if (src0 == null) return null;
  final src = img.bakeOrientation(src0);
  final c = job.corners;
  double dist(int a, int b) => math.sqrt(math.pow(c[a * 2] - c[b * 2], 2) + math.pow(c[a * 2 + 1] - c[b * 2 + 1], 2));
  var w = math.max<double>(dist(0, 1), dist(3, 2)).round();
  var h = math.max<double>(dist(0, 3), dist(1, 2)).round();
  final scale = math.min<double>(1, 2200 / math.max<int>(1, math.max<int>(w, h)));
  w = math.max<int>(8, (w * scale).round());
  h = math.max<int>(8, (h * scale).round());
  var out = img.copyRectify(
    src,
    topLeft: img.Point(c[0], c[1]),
    topRight: img.Point(c[2], c[3]),
    bottomRight: img.Point(c[4], c[5]),
    bottomLeft: img.Point(c[6], c[7]),
    interpolation: img.Interpolation.linear,
    toImage: img.Image(width: w, height: h),
  );
  for (var i = 0; i < job.turns % 4; i++) {
    out = img.copyRotate(out, angle: 90);
  }
  if (job.bw) {
    out = img.grayscale(out);
    out = img.adjustColor(out, contrast: 1.5, brightness: 1.08);
  }
  return img.encodeJpg(out, quality: 85);
}

/// Görüntünün boyutu (köşe başlangıcı için).
List<int>? imageSize(Uint8List bytes) {
  final d = img.decodeImage(bytes);
  if (d == null) return null;
  final o = img.bakeOrientation(d);
  return [o.width, o.height];
}

class ScannerTool extends StatefulWidget {
  final ToolContext t;
  const ScannerTool(this.t, {super.key});

  @override
  State<ScannerTool> createState() => _ScannerToolState();
}

class _ScannerToolState extends State<ScannerTool> {
  final List<Uint8List> _pages = [];
  List<Map<String, Object?>> _saved = [];
  bool _busy = false;
  bool _bw = true;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('pdfs').then((l) async {
      final ok = <Map<String, Object?>>[];
      for (final r in l) {
        if (await Disk.exists(r['path'] as String? ?? '')) ok.add(r);
      }
      if (mounted) setState(() => _saved = ok);
    });
  }

  Future<void> _add(ImageSource src) async {
    if (src == ImageSource.camera && !kIsWeb) {
      if (!await rationaleOnce(context, t, 'camera', Icons.document_scanner_rounded)) return;
    }
    XFile? x;
    try {
      x = await ImagePicker().pickImage(source: src, maxWidth: 3000, maxHeight: 3000, imageQuality: 92);
    } catch (_) {
      if (mounted) showPermissionDenied(context, t.lang);
      return;
    }
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    setState(() => _busy = true);
    final size = await compute(imageSize, bytes);
    if (!mounted) return;
    setState(() => _busy = false);
    if (size == null) return;
    final res = await Navigator.of(context).push<RectifyJob>(MaterialPageRoute(
      builder: (_) => _CropPage(t: t, bytes: bytes, width: size[0], height: size[1], bw: _bw),
    ));
    if (res == null || !mounted) return;
    setState(() {
      _busy = true;
      _bw = res.bw;
    });
    final page = await compute(rectifyPage, res);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (page != null) _pages.add(page);
    });
  }

  Future<Uint8List> _pdf() async {
    final doc = pw.Document();
    for (final p in _pages) {
      final im = pw.MemoryImage(p);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12),
        build: (c) => pw.Center(child: pw.Image(im, fit: pw.BoxFit.contain)),
      ));
    }
    return doc.save();
  }

  Future<void> _makePdf() async {
    if (_pages.isEmpty) return;
    setState(() => _busy = true);
    final bytes = await _pdf();
    final name = 'scan_${dayKey(DateTime.now())}_${DateTime.now().millisecondsSinceEpoch % 100000}.pdf';
    final path = await Disk.write('scans', name, bytes);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (path != null) {
        _saved.insert(0, {'name': name, 'path': path, 'pages': _pages.length, 'at': DateTime.now().millisecondsSinceEpoch});
      }
      _pages.clear();
    });
    await t.store.writeList('pdfs', _saved);
    await Printing.sharePdf(bytes: bytes, filename: name);
  }

  @override
  Widget build(BuildContext context) {
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
            AppButton(label: L(t, 'take_photo'), icon: Icons.photo_camera_rounded, onPressed: _busy ? null : () => _add(ImageSource.camera)),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _add(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded),
              label: Text(L(t, 'gallery')),
            ),
          ]),
          if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
        ]),
      ),
      if (_pages.isNotEmpty) ...[
        SectionBar('${L(t, 'pages')}: ${_pages.length}', icon: Icons.description_rounded),
        SizedBox(
          height: 180,
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onReorder: (a, b) => setState(() {
              if (b > a) b--;
              _pages.insert(b, _pages.removeAt(a));
            }),
            children: [
              for (var i = 0; i < _pages.length; i++)
                Padding(
                  key: ObjectKey(_pages[i]),
                  padding: const EdgeInsets.all(4),
                  child: Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_pages[i], height: 170, fit: BoxFit.contain)),
                    PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _pages.removeAt(i)),
                        icon: const Icon(Icons.close_rounded, size: 16),
                      ),
                    ),
                    PositionedDirectional(
                      bottom: 4,
                      start: 4,
                      child: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        Center(child: AppButton(label: L(t, 'make_pdf'), icon: Icons.picture_as_pdf_rounded, onPressed: _busy ? null : _makePdf)),
      ],
      if (_pages.isEmpty && _saved.isEmpty) EmptyHint(L(t, 'crop_hint'), icon: Icons.document_scanner_rounded),
      if (_saved.isNotEmpty) SectionBar(L(t, 'saved_files'), icon: Icons.folder_rounded),
      for (final s in _saved)
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_rounded),
          title: Text(s['name'] as String? ?? ''),
          subtitle: Text('${L(t, 'pages')}: ${s['pages']}'),
          onTap: () async {
            final b = await Disk.read(s['path'] as String);
            if (b != null) await Printing.sharePdf(bytes: b, filename: s['name'] as String? ?? 'scan.pdf');
          },
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              if (!await confirmDelete(context, t)) return;
              await Disk.delete(s['path'] as String);
              setState(() => _saved.remove(s));
              await t.store.writeList('pdfs', _saved);
            },
          ),
        ),
    ]);
  }
}

/// Dört köşeyi sürükleyerek sayfa kenarlarını seçme ekranı.
class _CropPage extends StatefulWidget {
  final ToolContext t;
  final Uint8List bytes;
  final int width, height;
  final bool bw;
  const _CropPage({required this.t, required this.bytes, required this.width, required this.height, required this.bw});

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> {
  late List<Offset> _c;
  late bool _bw = widget.bw;
  int _turns = 0;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    final w = widget.width.toDouble(), h = widget.height.toDouble();
    _c = [Offset(w * .05, h * .05), Offset(w * .95, h * .05), Offset(w * .95, h * .95), Offset(w * .05, h * .95)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(L(t, 'crop_hint'), style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(tooltip: L(t, 'rotate'), onPressed: () => setState(() => _turns = (_turns + 1) % 4), icon: const Icon(Icons.rotate_right_rounded)),
          IconButton(
            tooltip: L(t, 'bw'),
            isSelected: _bw,
            onPressed: () => setState(() => _bw = !_bw),
            icon: const Icon(Icons.contrast_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(
          context,
          RectifyJob(widget.bytes, [for (final o in _c) ...[o.dx, o.dy]], bw: _bw, turns: _turns),
        ),
        icon: const Icon(Icons.check_rounded),
        label: Text(L(t, 'save')),
      ),
      body: LayoutBuilder(builder: (context, box) {
        final iw = widget.width.toDouble(), ih = widget.height.toDouble();
        final s = math.min<double>((box.maxWidth - 32) / iw, (box.maxHeight - 96) / ih);
        final dw = iw * s, dh = ih * s;
        final ox = (box.maxWidth - dw) / 2, oy = 16.0;
        Offset toScreen(Offset p) => Offset(ox + p.dx * s, oy + p.dy * s);
        return Stack(children: [
          Positioned(left: ox, top: oy, width: dw, height: dh, child: Image.memory(widget.bytes, fit: BoxFit.fill)),
          Positioned.fill(child: CustomPaint(painter: _QuadPainter([for (final p in _c) toScreen(p)]))),
          for (var i = 0; i < 4; i++)
            Positioned(
              left: toScreen(_c[i]).dx - 22,
              top: toScreen(_c[i]).dy - 22,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  final n = _c[i] + d.delta / s;
                  _c[i] = Offset(n.dx.clamp(0, iw).toDouble(), n.dy.clamp(0, ih).toDouble());
                }),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.tealAccent.withValues(alpha: 0.35),
                    border: Border.all(color: Colors.tealAccent, width: 3),
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> p;
  _QuadPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(p, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.tealAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}

// ============================================================ PDF görüntüleyici

class PdfViewerTool extends StatefulWidget {
  final ToolContext t;
  const PdfViewerTool(this.t, {super.key});

  @override
  State<PdfViewerTool> createState() => _PdfViewerToolState();
}

class _PdfViewerToolState extends State<PdfViewerTool> {
  Uint8List? _bytes;
  String _name = '';
  final List<Uint8List> _pages = [];
  bool _loading = false;
  bool _error = false;
  StreamSubscription<PdfRaster>? _sub;
  final _scroll = ScrollController();
  List<Map<String, Object?>> _recent = [];
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('recent').then((l) async {
      final ok = <Map<String, Object?>>[];
      for (final r in l) {
        if (await Disk.exists(r['path'] as String? ?? '')) ok.add(r);
      }
      if (mounted) setState(() => _recent = ok);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
    } catch (_) {
      return;
    }
    final f = r?.files.single;
    final b = f?.bytes;
    if (f == null || b == null) return;
    await _open(b, f.name);
    // Son açılanlar: uygulama klasörüne bir kopya (web'de yok).
    final path = await Disk.write('pdf', '${safeName(f.name.replaceAll('.pdf', ''))}.pdf', b);
    if (path != null) {
      _recent.removeWhere((x) => x['path'] == path);
      _recent.insert(0, {'name': f.name, 'path': path, 'at': DateTime.now().millisecondsSinceEpoch});
      if (_recent.length > 10) {
        for (final old in _recent.sublist(10)) {
          await Disk.delete(old['path'] as String);
        }
        _recent = _recent.sublist(0, 10);
      }
      await t.store.writeList('recent', _recent);
      if (mounted) setState(() {});
    }
  }

  Future<void> _open(Uint8List b, String name) async {
    await _sub?.cancel();
    setState(() {
      _bytes = b;
      _name = name;
      _pages.clear();
      _loading = true;
      _error = false;
    });
    try {
      _sub = Printing.raster(b, dpi: 110).listen(
        (r) async {
          final png = await r.toPng();
          if (mounted) setState(() => _pages.add(png));
        },
        onError: (Object _) {
          if (!mounted) return;
          setState(() {
            _error = true;
            _loading = false;
          });
        },
        onDone: () {
          if (mounted) setState(() => _loading = false);
        },
      );
    } catch (_) {
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      return ToolList(children: [
        const SizedBox(height: 24),
        Center(child: AppButton(label: L(t, 'open_file'), icon: Icons.file_open_rounded, onPressed: _pick)),
        if (_recent.isNotEmpty) SectionBar(L(t, 'recent_files'), icon: Icons.history_rounded),
        for (final r in _recent)
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_rounded),
            title: Text(r['name'] as String? ?? ''),
            subtitle: Text(fmtDateTime(context, DateTime.fromMillisecondsSinceEpoch((r['at'] as num?)?.toInt() ?? 0))),
            onTap: () async {
              final bytes = await Disk.read(r['path'] as String);
              if (bytes != null) await _open(bytes, r['name'] as String? ?? '');
            },
          ),
      ]);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(
            onPressed: () {
              _sub?.cancel();
              setState(() => _bytes = null);
            },
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(child: Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('${_pages.length}${_loading ? '…' : ''} ${L(t, 'pages')}', style: const TextStyle(color: Colors.white70)),
          IconButton(tooltip: L(t, 'share'), onPressed: () => Printing.sharePdf(bytes: b, filename: _name), icon: const Icon(Icons.ios_share_rounded)),
          IconButton(tooltip: L(t, 'print'), onPressed: () => Printing.layoutPdf(onLayout: (_) async => b, name: _name), icon: const Icon(Icons.print_rounded)),
          IconButton(onPressed: _pick, icon: const Icon(Icons.file_open_rounded)),
        ]),
      ),
      if (_error) AppInfoCard(L(t, 'pdf_error'), icon: Icons.error_outline_rounded),
      Expanded(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(8),
            itemCount: _pages.length + (_loading ? 1 : 0),
            itemBuilder: (c, i) => i >= _pages.length
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: [
                      Container(color: Colors.white, child: Image.memory(_pages[i], fit: BoxFit.contain)),
                      Text('${i + 1}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ]),
                  ),
          ),
        ),
      ),
    ]);
  }
}

// ======================================================= fatura ve teklif

String defaultCurrency(String lang) => switch (lang) {
      'tr' => 'TRY',
      'de' || 'fr' || 'es' || 'it' || 'nl' || 'fi' || 'el' || 'pt' => 'EUR',
      'ja' => 'JPY',
      'ru' => 'RUB',
      'uk' => 'UAH',
      'pl' => 'PLN',
      'cs' => 'CZK',
      'ro' => 'RON',
      'hu' => 'HUF',
      'sv' => 'SEK',
      'da' => 'DKK',
      'nb' => 'NOK',
      'ko' => 'KRW',
      'zh' => 'CNY',
      'hi' => 'INR',
      'bn' => 'BDT',
      'id' => 'IDR',
      'ms' => 'MYR',
      'th' => 'THB',
      'vi' => 'VND',
      'fil' => 'PHP',
      'he' => 'ILS',
      'ar' => 'SAR',
      'fa' => 'IRR',
      'ur' => 'PKR',
      _ => 'USD',
    };

/// Fatura/teklif PDF'i.
Future<Uint8List> invoicePdf(ToolContext t, Map<String, Object?> d, String business, String currency) async {
  final theme = await pdfTheme();
  final items = [for (final m in (d['items'] as List? ?? const [])) LineItem.fromJson((m as Map).cast<String, Object?>())];
  final disc = (d['disc'] as num?)?.toDouble() ?? 0;
  final tot = invoiceTotals(items, discountPct: disc);
  final isQuote = (d['type'] as num?)?.toInt() == 1;
  String money(int c) => '${centsText(c)} $currency';
  final doc = pw.Document(theme: theme);
  pw.Widget cell(String s, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: pw.Text(s, textAlign: align, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : null)),
      );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (c) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Text(business, style: const pw.TextStyle(fontSize: 10))),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(L(t, isQuote ? 'quote' : 'invoice').toUpperCase(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text('${L(t, 'doc_no')}: ${d['no'] ?? ''}'),
          pw.Text('${L(t, 'date')}: ${d['date'] ?? ''}'),
          if ((d['due'] as String? ?? '').isNotEmpty) pw.Text('${L(t, 'due')}: ${d['due']}'),
        ]),
      ]),
      pw.SizedBox(height: 20),
      pw.Text(L(t, 'client'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.Text(d['client'] as String? ?? ''),
      pw.SizedBox(height: 16),
      pw.Table(
        border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey600),
        columnWidths: const {
          0: pw.FlexColumnWidth(5),
          1: pw.FlexColumnWidth(1.2),
          2: pw.FlexColumnWidth(2),
          3: pw.FlexColumnWidth(1.2),
          4: pw.FlexColumnWidth(2.2),
        },
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            cell(L(t, 'description'), bold: true),
            cell(L(t, 'qty'), bold: true, align: pw.TextAlign.right),
            cell(L(t, 'unit_price'), bold: true, align: pw.TextAlign.right),
            cell(L(t, 'vat'), bold: true, align: pw.TextAlign.right),
            cell(L(t, 'total'), bold: true, align: pw.TextAlign.right),
          ]),
          for (final i in items)
            pw.TableRow(children: [
              cell(i.text),
              cell(formatNumber(i.qty, digits: 3), align: pw.TextAlign.right),
              cell(formatNumber(i.price, digits: 2), align: pw.TextAlign.right),
              cell('%${formatNumber(i.vat, digits: 2)}', align: pw.TextAlign.right),
              cell(centsText(i.netCents), align: pw.TextAlign.right),
            ]),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 240,
          child: pw.Column(children: [
            for (final (k, v, bold) in [
              (L(t, 'subtotal'), tot.subtotal, false),
              if (tot.discount != 0) ('${L(t, 'discount')} %${formatNumber(disc, digits: 2)}', -tot.discount, false),
              (L(t, 'vat_total'), tot.vat, false),
              (L(t, 'grand_total'), tot.total, true),
            ])
              pw.Row(children: [
                pw.Expanded(child: pw.Text(k, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null))),
                pw.Text(money(v), style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null, fontSize: bold ? 13 : 10)),
              ]),
          ]),
        ),
      ),
      if ((d['notes'] as String? ?? '').isNotEmpty) ...[
        pw.SizedBox(height: 20),
        pw.Text(d['notes'] as String),
      ],
    ],
  ));
  return doc.save();
}

class InvoiceTool extends StatefulWidget {
  final ToolContext t;
  const InvoiceTool(this.t, {super.key});

  @override
  State<InvoiceTool> createState() => _InvoiceToolState();
}

class _InvoiceToolState extends State<InvoiceTool> {
  List<Map<String, Object?>> _docs = [];
  String _business = '';
  String _currency = 'USD';
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _docs = await t.store.readList('docs');
    _business = await t.store.read('business') ?? '';
    _currency = await t.store.read('currency') ?? defaultCurrency(t.lang);
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _settings() async {
    final b = TextEditingController(text: _business);
    final c = TextEditingController(text: _currency);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppTextField(controller: b, label: L(t, 'your_business'), maxLines: 6, minLines: 3),
            AppTextField(controller: c, label: L(t, 'currency')),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(L(t, 'save'))),
          ]),
        ),
      ),
    );
    if (ok == true) {
      _business = b.text.trim();
      _currency = c.text.trim().isEmpty ? defaultCurrency(t.lang) : c.text.trim();
      await t.store.write('business', _business);
      await t.store.write('currency', _currency);
      if (mounted) setState(() {});
    }
    b.dispose();
    c.dispose();
  }

  String _nextNo(int type) {
    final y = DateTime.now().year;
    final prefix = '${type == 1 ? 'Q' : 'INV'}-$y-';
    var n = 0;
    for (final d in _docs) {
      final no = d['no'] as String? ?? '';
      if (no.startsWith(prefix)) n = math.max<int>(n, int.tryParse(no.substring(prefix.length)) ?? 0);
    }
    return '$prefix${(n + 1).toString().padLeft(3, '0')}';
  }

  Future<void> _edit([Map<String, Object?>? orig]) async {
    final d = Map<String, Object?>.from(orig ??
        {'type': 0, 'no': _nextNo(0), 'date': dayKey(DateTime.now()), 'items': <Object?>[], 'disc': 0, 'client': '', 'notes': ''});
    final res = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _InvoiceEditor(t: t, d: d, currency: _currency, nextNo: _nextNo)));
    if (res == null || !mounted) return;
    setState(() {
      if (res == 'del') {
        _docs.removeWhere((x) => x['id'] == orig?['id']);
      } else if (orig == null) {
        d['id'] = newId();
        _docs.insert(0, d);
      } else {
        final i = _docs.indexWhere((x) => x['id'] == orig['id']);
        if (i >= 0) _docs[i] = d;
      }
    });
    await t.store.writeList('docs', _docs);
    if (res == 'pdf') await _share(d);
  }

  Future<void> _share(Map<String, Object?> d) async {
    final bytes = await invoicePdf(t, d, _business, _currency);
    await Printing.sharePdf(bytes: bytes, filename: '${safeName(d['no'] as String? ?? 'invoice')}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Stack(children: [
      ToolList(children: [
        AppInfoCard(L(t, 'not_efatura'), icon: Icons.gavel_rounded),
        ListTile(
          leading: const Icon(Icons.store_rounded),
          title: Text(L(t, 'your_business')),
          subtitle: Text(_business.isEmpty ? '—' : _business.split('\n').first),
          trailing: Text(_currency, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: _settings,
        ),
        if (_docs.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.receipt_long_rounded),
        for (final d in _docs)
          Builder(builder: (_) {
            final items = [for (final m in (d['items'] as List? ?? const [])) LineItem.fromJson((m as Map).cast<String, Object?>())];
            final tot = invoiceTotals(items, discountPct: (d['disc'] as num?)?.toDouble() ?? 0);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                onTap: () => _edit(d),
                leading: Icon((d['type'] as num?)?.toInt() == 1 ? Icons.request_quote_rounded : Icons.receipt_long_rounded),
                title: Text('${d['no']} · ${(d['client'] as String? ?? '').split('\n').first}'),
                subtitle: Text(d['date'] as String? ?? ''),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${centsText(tot.total)} $_currency', style: const TextStyle(fontWeight: FontWeight.w800)),
                  IconButton(onPressed: () => _share(d), icon: const Icon(Icons.picture_as_pdf_rounded)),
                ]),
              ),
            );
          }),
      ]),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () => _edit(),
          icon: const Icon(Icons.add_rounded),
          label: Text(L(t, 'invoice')),
        ),
      ),
    ]);
  }
}

class _InvoiceEditor extends StatefulWidget {
  final ToolContext t;
  final Map<String, Object?> d;
  final String currency;
  final String Function(int type) nextNo;
  const _InvoiceEditor({required this.t, required this.d, required this.currency, required this.nextNo});

  @override
  State<_InvoiceEditor> createState() => _InvoiceEditorState();
}

class _InvoiceEditorState extends State<_InvoiceEditor> {
  late final _no = TextEditingController(text: widget.d['no'] as String? ?? '');
  late final _client = TextEditingController(text: widget.d['client'] as String? ?? '');
  late final _notes = TextEditingController(text: widget.d['notes'] as String? ?? '');
  late final _disc = TextEditingController(text: formatNumber((widget.d['disc'] as num?)?.toDouble() ?? 0, digits: 2));
  late List<LineItem> _items =
      [for (final m in (widget.d['items'] as List? ?? const [])) LineItem.fromJson((m as Map).cast<String, Object?>())];
  ToolContext get t => widget.t;
  Map<String, Object?> get d => widget.d;

  @override
  void dispose() {
    _no.dispose();
    _client.dispose();
    _notes.dispose();
    _disc.dispose();
    super.dispose();
  }

  void _commit() {
    d['no'] = _no.text.trim();
    d['client'] = _client.text.trim();
    d['notes'] = _notes.text.trim();
    d['disc'] = parseNumber(_disc.text) ?? 0;
    d['items'] = [for (final i in _items) i.toJson()];
  }

  Future<void> _item([int? index]) async {
    final cur = index == null ? null : _items[index];
    final text = TextEditingController(text: cur?.text ?? '');
    final qty = TextEditingController(text: formatNumber(cur?.qty ?? 1, digits: 3));
    final price = TextEditingController(text: cur == null ? '' : formatNumber(cur.price, digits: 2));
    final vat = TextEditingController(text: formatNumber(cur?.vat ?? (t.lang == 'tr' ? 20 : 0), digits: 2));
    final ok = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppTextField(controller: text, label: L(t, 'description'), autofocus: cur == null),
            Row(children: [
              Expanded(child: AppNumberField(controller: qty, label: L(t, 'qty'))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: AppNumberField(controller: price, label: L(t, 'unit_price'), suffix: widget.currency)),
            ]),
            AppNumberField(controller: vat, label: L(t, 'vat'), suffix: '%'),
            const SizedBox(height: 12),
            Row(children: [
              if (cur != null) TextButton(onPressed: () => Navigator.pop(c, 'del'), child: Text(L(t, 'delete'))),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(c, 'ok'), child: Text(L(t, 'save'))),
            ]),
          ]),
        ),
      ),
    );
    final li = LineItem(text.text.trim(), parseNumber(qty.text) ?? 1, parseNumber(price.text) ?? 0, parseNumber(vat.text) ?? 0);
    for (final c in [text, qty, price, vat]) {
      c.dispose();
    }
    if (ok == null) return;
    setState(() {
      if (ok == 'del' && index != null) {
        _items.removeAt(index);
      } else if (ok == 'ok' && li.text.isNotEmpty) {
        if (index == null) {
          _items = [..._items, li];
        } else {
          _items[index] = li;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _commit();
    final tot = invoiceTotals(_items, discountPct: (d['disc'] as num?)?.toDouble() ?? 0);
    final type = (d['type'] as num?)?.toInt() ?? 0;
    return Scaffold(
      backgroundColor: StudioLook.of(context).base,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: StudioTitle(L(t, type == 1 ? 'quote' : 'invoice'), icon: Icons.receipt_long_rounded),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              if (await confirmDelete(context, t) && context.mounted) Navigator.pop(context, 'del');
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onPressed: () {
              _commit();
              Navigator.pop(context, 'pdf');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _commit();
          Navigator.pop(context, 'ok');
        },
        icon: const Icon(Icons.check_rounded),
        label: Text(L(t, 'save')),
      ),
      body: StudioBackdrop(child: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Choice<int>(
          values: const [0, 1],
          labels: [L(t, 'invoice'), L(t, 'quote')],
          selected: type,
          onChanged: (v) => setState(() {
            d['type'] = v;
            _no.text = widget.nextNo(v);
          }),
        ),
        AppTextField(controller: _no, label: L(t, 'doc_no')),
        DateRow(
          label: L(t, 'date'),
          value: DateTime.tryParse(d['date'] as String? ?? ''),
          clearable: false,
          onChanged: (v) => setState(() => d['date'] = v == null ? d['date'] : dayKey(v)),
        ),
        DateRow(
          label: L(t, 'due'),
          value: DateTime.tryParse(d['due'] as String? ?? ''),
          onChanged: (v) => setState(() => d['due'] = v == null ? '' : dayKey(v)),
        ),
        AppTextField(controller: _client, label: L(t, 'client'), maxLines: 5, minLines: 2),
        SectionBar(L(t, 'items'), icon: Icons.list_alt_rounded, onAdd: () => _item()),
        for (var i = 0; i < _items.length; i++)
          ListTile(
            onTap: () => _item(i),
            title: Text(_items[i].text),
            subtitle: Text('${formatNumber(_items[i].qty, digits: 3)} × ${formatNumber(_items[i].price, digits: 2)} · %${formatNumber(_items[i].vat, digits: 2)}'),
            trailing: Text(centsText(_items[i].netCents), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        AppNumberField(controller: _disc, label: L(t, 'discount'), suffix: '%', onChanged: (_) => setState(() {})),
        AppResult(label: L(t, 'subtotal'), value: '${centsText(tot.subtotal - tot.discount)} ${widget.currency}', lang: t.lang),
        AppResult(label: L(t, 'vat_total'), value: '${centsText(tot.vat)} ${widget.currency}', lang: t.lang),
        AppResult(label: L(t, 'grand_total'), value: '${centsText(tot.total)} ${widget.currency}', lang: t.lang, big: true),
        AppTextField(controller: _notes, label: L(t, 'note'), maxLines: 4),
      ]))),
    );
  }
}
