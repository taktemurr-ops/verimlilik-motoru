/// PDF imzala ve doldur: PDF sayfaları cihazda görüntüye çevrilir, üzerine
/// metin, onay işareti, tarih, elle çizilmiş imza ve paraf yerleştirilir;
/// sonuç yeni bir PDF olarak kaydedilir (sayfalar düzleştirilir). Dosya
/// cihazdan çıkmaz. Çizilen imza "nitelikli elektronik imza" değildir.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';

/// İşaret türleri.
enum SignKind { text, check, cross, date, sign, initials }

/// Bir çizgi: 0–1 aralığında (x, y) noktaları.
typedef Stroke = List<Offset>;

/// Sayfadaki bir işaret. Konum (x, y) ve boyut sayfa GENİŞLİĞİNE oranlıdır
/// (y de genişliğe bölünür; böylece en/boy oranı korunur).
class SignMark {
  final SignKind kind;
  final int page;
  double x, y;

  /// Genişlik (imza/paraf) ya da yazı yüksekliği (metin/işaret) – sayfa
  /// genişliğine oran.
  double size;
  String text;
  SignMark(this.kind, this.page, this.x, this.y, {this.size = 0.03, this.text = ''});
}

/// İmza çizgilerini JSON'a çevirir (kalıcı saklama).
String strokesToJson(List<Stroke> s) => jsonEncode([
      for (final st in s) [for (final p in st) [double.parse(p.dx.toStringAsFixed(4)), double.parse(p.dy.toStringAsFixed(4))]],
    ]);

List<Stroke> strokesFromJson(String? s) {
  if (s == null || s.isEmpty) return [];
  try {
    return [
      for (final st in jsonDecode(s) as List)
        [for (final p in st as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
    ];
  } catch (_) {
    return [];
  }
}

/// İmza kutusunun en/boy oranı (genişlik / yükseklik).
const double kSignAspect = 3.0;

/// Sayfa görüntüleri ve işaretlerden düzleştirilmiş PDF üretir.
/// [pages]: (PNG, piksel genişlik, piksel yükseklik), [dpi]: görüntü çözünürlüğü.
Future<Uint8List> buildSignedPdf({
  required List<(Uint8List, int, int)> pages,
  required double dpi,
  required List<SignMark> marks,
  required List<Stroke> signature,
  required List<Stroke> initials,
  pw.ThemeData? theme,
}) async {
  final doc = pw.Document(theme: theme);
  for (var i = 0; i < pages.length; i++) {
    final (png, wpx, hpx) = pages[i];
    final w = wpx * 72 / dpi, h = hpx * 72 / dpi;
    final img = pw.MemoryImage(png);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(w, h, marginAll: 0),
      build: (_) => pw.Stack(children: [
        pw.Positioned(left: 0, top: 0, child: pw.SizedBox(width: w, height: h, child: pw.Image(img, fit: pw.BoxFit.fill))),
        for (final m in marks.where((m) => m.page == i))
          pw.Positioned(left: m.x * w, top: m.y * w, child: _pdfMark(m, w, signature, initials)),
      ]),
    ));
  }
  return doc.save();
}

pw.Widget _pdfMark(SignMark m, double pageW, List<Stroke> signature, List<Stroke> initials) {
  final ink = PdfColor.fromInt(0xFF1A237E);
  switch (m.kind) {
    case SignKind.text:
    case SignKind.date:
      return pw.Text(m.text, style: pw.TextStyle(fontSize: m.size * pageW, color: PdfColors.black));
    case SignKind.check:
    case SignKind.cross:
      return pw.Text(m.kind == SignKind.check ? '✓' : '✗', style: pw.TextStyle(fontSize: m.size * pageW * 1.3, color: ink));
    case SignKind.sign:
    case SignKind.initials:
      final strokes = m.kind == SignKind.sign ? signature : initials;
      final bw = m.size * pageW, bh = bw / kSignAspect;
      return pw.SizedBox(
        width: bw,
        height: bh,
        child: pw.CustomPaint(
          size: PdfPoint(bw, bh),
          painter: (PdfGraphics g, PdfPoint size) {
            g
              ..setStrokeColor(ink)
              ..setLineWidth(math.max(0.8, bw / 120))
              ..setLineCap(PdfLineCap.round)
              ..setLineJoin(PdfLineJoin.round);
            for (final st in strokes) {
              if (st.isEmpty) continue;
              // PDF çizim düzleminde y yukarı doğrudur.
              g.moveTo(st.first.dx * size.x, size.y - st.first.dy * size.y);
              for (final p in st.skip(1)) {
                g.lineTo(p.dx * size.x, size.y - p.dy * size.y);
              }
              if (st.length == 1) g.lineTo(st.first.dx * size.x + 0.5, size.y - st.first.dy * size.y);
              g.strokePath();
            }
          },
        ),
      );
  }
}

// ------------------------------------------------------------------- araç

class PdfSignTool extends StatefulWidget {
  final ToolContext t;
  const PdfSignTool(this.t, {super.key});

  @override
  State<PdfSignTool> createState() => _PdfSignToolState();
}

class _PdfSignToolState extends State<PdfSignTool> {
  static const double _dpi = 144;
  static const int _maxPages = 40;
  String? _name;
  final List<(Uint8List, int, int)> _pages = [];
  final List<SignMark> _marks = [];
  StreamSubscription<PdfRaster>? _sub;
  bool _loading = false;
  bool _error = false;
  SignKind _tool = SignKind.text;
  SignMark? _sel;
  List<Stroke> _signature = [];
  List<Stroke> _initials = [];

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      final s = await t.store.read('signature');
      final i = await t.store.read('initials');
      if (!mounted) return;
      setState(() {
        _signature = strokesFromJson(s);
        _initials = strokesFromJson(i);
      });
    }());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _pick() async {
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
    } catch (_) {
      if (mounted) toast(context, t.tx('not_available'));
      return;
    }
    final f = r?.files.single;
    final b = f?.bytes;
    if (f == null || b == null || !mounted) return;
    await _sub?.cancel();
    setState(() {
      _name = f.name;
      _pages.clear();
      _marks.clear();
      _sel = null;
      _loading = true;
      _error = false;
    });
    try {
      _sub = Printing.raster(b, dpi: _dpi).listen(
        (r) async {
          if (_pages.length >= _maxPages) return;
          final png = await r.toPng();
          if (mounted) setState(() => _pages.add((png, r.width, r.height)));
        },
        onError: (Object _) {
          if (mounted) {
            setState(() {
              _error = true;
              _loading = false;
            });
          }
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

  String _today() => MaterialLocalizations.of(context).formatShortDate(DateTime.now());

  Future<void> _place(int page, Offset frac) async {
    switch (_tool) {
      case SignKind.text:
        final s = await askText(context, t, L(t, 'pdfs_text'));
        if (s == null || s.trim().isEmpty) return;
        _add(SignMark(SignKind.text, page, frac.dx, frac.dy, text: s.trim(), size: 0.022));
      case SignKind.date:
        _add(SignMark(SignKind.date, page, frac.dx, frac.dy, text: _today(), size: 0.022));
      case SignKind.check:
      case SignKind.cross:
        _add(SignMark(_tool, page, frac.dx, frac.dy, size: 0.03));
      case SignKind.sign:
      case SignKind.initials:
        final sign = _tool == SignKind.sign;
        if ((sign ? _signature : _initials).isEmpty) {
          final ok = await _draw(sign);
          if (!ok) return;
        }
        _add(SignMark(_tool, page, frac.dx, frac.dy, size: sign ? 0.3 : 0.12));
    }
  }

  void _add(SignMark m) {
    if (!mounted) return;
    setState(() {
      _marks.add(m);
      _sel = m;
    });
  }

  Future<bool> _draw(bool sign) async {
    final r = await showDialog<List<Stroke>>(
      context: context,
      builder: (_) => _SignPadDialog(t: t, title: sign ? L(t, 'pdfs_sign') : L(t, 'pdfs_initials')),
    );
    if (r == null || r.isEmpty) return false;
    await t.store.write(sign ? 'signature' : 'initials', strokesToJson(r));
    if (mounted) {
      setState(() {
        if (sign) {
          _signature = r;
        } else {
          _initials = r;
        }
      });
    }
    return true;
  }

  Future<void> _export() async {
    if (_pages.isEmpty) return;
    setState(() => _loading = true);
    try {
      final bytes = await buildSignedPdf(
        pages: _pages,
        dpi: _dpi,
        marks: _marks,
        signature: _signature,
        initials: _initials,
        theme: await pdfTheme(),
      );
      final base = (_name ?? 'belge').replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final name = '${safeName(base)}_imzali.pdf';
      String? path;
      try {
        path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
      } catch (_) {
        path = null;
      }
      if (path == null) await Printing.sharePdf(bytes: bytes, filename: name);
      if (mounted && path != null) toast(context, '✓ $name');
    } catch (_) {
      if (mounted) toast(context, t.tx('not_available'));
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _markView(SignMark m, double pw) {
    final selected = identical(m, _sel);
    Widget child;
    switch (m.kind) {
      case SignKind.text:
      case SignKind.date:
        child = Text(m.text, style: TextStyle(fontSize: m.size * pw, color: Colors.black, height: 1.1));
      case SignKind.check:
      case SignKind.cross:
        child = Text(m.kind == SignKind.check ? '✓' : '✗',
            style: TextStyle(fontSize: m.size * pw * 1.3, color: const Color(0xFF1A237E), height: 1.0));
      case SignKind.sign:
      case SignKind.initials:
        final bw = m.size * pw;
        child = SizedBox(
          width: bw,
          height: bw / kSignAspect,
          child: CustomPaint(painter: _StrokePainter(m.kind == SignKind.sign ? _signature : _initials, const Color(0xFF1A237E))),
        );
    }
    return GestureDetector(
      onTap: () => setState(() => _sel = m),
      onPanStart: (_) => setState(() => _sel = m),
      onPanUpdate: (d) => setState(() {
        m.x = (m.x + d.delta.dx / pw).clamp(0.0, 0.98);
        m.y = (m.y + d.delta.dy / pw).clamp(0.0, 10.0);
      }),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: selected ? Colors.orangeAccent : Colors.transparent, width: 1.5)),
        child: child,
      ),
    );
  }

  Widget _pageView(int i) {
    final (png, wpx, hpx) = _pages[i];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: LayoutBuilder(builder: (context, c) {
        final pw = c.maxWidth;
        final ph = pw * hpx / wpx;
        return GestureDetector(
          onTapUp: (d) => _place(i, Offset(d.localPosition.dx / pw, d.localPosition.dy / pw)),
          child: SizedBox(
            width: pw,
            height: ph,
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              Positioned.fill(child: Image.memory(png, fit: BoxFit.fill, gaplessPlayback: true)),
              for (final m in _marks.where((m) => m.page == i))
                Positioned(left: m.x * pw, top: m.y * pw, child: _markView(m, pw)),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_name == null) {
      return ToolList(children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppButton(label: L(t, 'open_file'), icon: Icons.file_open_rounded, onPressed: _pick),
        ),
        AppInfoCard(L(t, 'pdfs_intro'), icon: Icons.draw_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _draw(true), icon: const Icon(Icons.gesture_rounded), label: Text(L(t, 'pdfs_sign')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _draw(false), icon: const Icon(Icons.short_text_rounded), label: Text(L(t, 'pdfs_initials')))),
          ]),
        ),
        AppInfoCard(L(t, 'pdfs_legal'), icon: Icons.gavel_rounded),
      ]);
    }
    final names = Ls(t, 'pdfs_tools');
    final sel = _sel;
    return Column(children: [
      SizedBox(
        height: 64,
        child: Choice<SignKind>(
          values: SignKind.values,
          labels: [for (var i = 0; i < SignKind.values.length; i++) i < names.length ? names[i].trim() : SignKind.values[i].name],
          selected: _tool,
          onChanged: (v) => setState(() => _tool = v),
        ),
      ),
      if (sel != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            const Icon(Icons.format_size_rounded, size: 20),
            Expanded(
              child: Slider(
                min: sel.kind == SignKind.sign || sel.kind == SignKind.initials ? 0.06 : 0.01,
                max: sel.kind == SignKind.sign || sel.kind == SignKind.initials ? 0.6 : 0.08,
                value: sel.size.clamp(sel.kind == SignKind.sign || sel.kind == SignKind.initials ? 0.06 : 0.01,
                    sel.kind == SignKind.sign || sel.kind == SignKind.initials ? 0.6 : 0.08),
                onChanged: (v) => setState(() => sel.size = v),
              ),
            ),
            if (sel.kind == SignKind.text)
              IconButton(
                tooltip: L(t, 'pdfs_text'),
                icon: const Icon(Icons.edit_rounded),
                onPressed: () async {
                  final s = await askText(context, t, L(t, 'pdfs_text'), initial: sel.text);
                  if (s != null && mounted) setState(() => sel.text = s);
                },
              ),
            IconButton(
              tooltip: t.core('delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => setState(() {
                _marks.remove(sel);
                _sel = null;
              }),
            ),
            IconButton(
              tooltip: t.core('ok'),
              icon: const Icon(Icons.check_rounded),
              onPressed: () => setState(() => _sel = null),
            ),
          ]),
        ),
      Expanded(
        child: _error
            ? ToolList(children: [AppInfoCard(L(t, 'pdfs_error'), icon: Icons.error_outline_rounded)])
            : ListView.builder(
                itemCount: _pages.length + 1,
                itemBuilder: (_, i) => i < _pages.length
                    ? _pageView(i)
                    : Column(children: [
                        if (_loading) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                        AppInfoCard(L(t, 'pdfs_hint'), icon: Icons.touch_app_rounded),
                        AppInfoCard(L(t, 'pdfs_legal'), icon: Icons.gavel_rounded),
                        const SizedBox(height: 80),
                      ]),
              ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(children: [
            Expanded(child: AppButton(label: L(t, 'pdfs_save'), icon: Icons.save_alt_rounded, onPressed: _loading || _pages.isEmpty ? null : _export)),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: L(t, 'open_file'),
              onPressed: _pick,
              icon: const Icon(Icons.file_open_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _StrokePainter extends CustomPainter {
  final List<Stroke> strokes;
  final Color color;
  _StrokePainter(this.strokes, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = math.max(1.5, size.width / 120)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final st in strokes) {
      if (st.isEmpty) continue;
      final path = Path()..moveTo(st.first.dx * size.width, st.first.dy * size.height);
      for (final q in st.skip(1)) {
        path.lineTo(q.dx * size.width, q.dy * size.height);
      }
      if (st.length == 1) path.lineTo(st.first.dx * size.width + 0.5, st.first.dy * size.height);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

/// İmza ya da paraf çizme penceresi.
class _SignPadDialog extends StatefulWidget {
  final ToolContext t;
  final String title;
  const _SignPadDialog({required this.t, required this.title});

  @override
  State<_SignPadDialog> createState() => _SignPadDialogState();
}

class _SignPadDialogState extends State<_SignPadDialog> {
  final List<Stroke> _strokes = [];

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: AspectRatio(
          aspectRatio: kSignAspect,
          child: LayoutBuilder(builder: (context, c) {
            Offset norm(Offset o) => Offset((o.dx / c.maxWidth).clamp(0.0, 1.0), (o.dy / c.maxHeight).clamp(0.0, 1.0));
            return GestureDetector(
              onPanStart: (d) => setState(() => _strokes.add([norm(d.localPosition)])),
              onPanUpdate: (d) => setState(() => _strokes.last.add(norm(d.localPosition))),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: CustomPaint(painter: _StrokePainter(_strokes, const Color(0xFF1A237E)), size: Size.infinite),
              ),
            );
          }),
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(_strokes.clear), child: Text(L(t, 'pdfs_clear'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.core('cancel'))),
        FilledButton(onPressed: _strokes.isEmpty ? null : () => Navigator.pop(context, _strokes), child: Text(t.core('ok'))),
      ],
    );
  }
}
