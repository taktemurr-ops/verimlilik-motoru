/// Yazma ve çizim uygulamaları: çizim defteri, zihin haritası, metin
/// araçları, pano geçmişi, sunum zamanlayıcı ve teleprompter.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../logic/doc_logic.dart';
import '../logic/text_logic.dart';

// ============================================================ çizim defteri

class Stroke {
  final int color;
  final double width;
  final bool eraser;
  final List<Offset> points;
  Stroke(this.color, this.width, this.eraser, this.points);

  Map<String, Object?> toJson() => {
        'c': color,
        'w': width,
        'e': eraser,
        'p': [for (final p in points) ...[(p.dx * 10).round(), (p.dy * 10).round()]],
      };

  static Stroke fromJson(Map<String, Object?> m) {
    final p = (m['p'] as List? ?? const []).cast<num>();
    return Stroke(
      (m['c'] as num?)?.toInt() ?? 0xFF000000,
      (m['w'] as num?)?.toDouble() ?? 4,
      m['e'] == true,
      [for (var i = 0; i + 1 < p.length; i += 2) Offset(p[i] / 10, p[i + 1] / 10)],
    );
  }
}

const Color kPaper = Color(0xFFFFFDF7);

void paintStrokes(Canvas canvas, Size size, List<Stroke> strokes) {
  canvas.drawRect(Offset.zero & size, Paint()..color = kPaper);
  for (final s in strokes) {
    final paint = Paint()
      ..color = s.eraser ? kPaper : Color(s.color)
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
      continue;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (var i = 1; i < s.points.length; i++) {
      final a = s.points[i - 1], b = s.points[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
    }
    path.lineTo(s.points.last.dx, s.points.last.dy);
    canvas.drawPath(path, paint);
  }
}

class _SketchPainter extends CustomPainter {
  final List<Stroke> strokes;
  final int version;
  _SketchPainter(this.strokes, this.version);

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, size, strokes);

  @override
  bool shouldRepaint(_SketchPainter old) => old.version != version;
}

class SketchTool extends StatefulWidget {
  final ToolContext t;
  const SketchTool(this.t, {super.key});

  @override
  State<SketchTool> createState() => _SketchToolState();
}

class _SketchToolState extends State<SketchTool> {
  static const _inks = [0xFF212121, 0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFDD835, 0xFF8E24AA, 0xFFFB8C00, 0xFF6D4C41];
  List<Map<String, Object?>> _drawings = [];
  String? _cur;
  List<Stroke> _strokes = [];
  final List<Stroke> _redo = [];
  int _version = 0;
  int _ink = 0xFF212121;
  double _width = 4;
  bool _eraser = false;
  Size _size = const Size(1000, 1000);
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _drawings = await t.store.readList('drawings');
    final cur = await t.store.read('cur');
    final d = _drawings.where((x) => x['id'] == cur).firstOrNull ?? _drawings.firstOrNull;
    if (d != null) _open(d);
    if (mounted) setState(() => _loaded = true);
  }

  void _open(Map<String, Object?> d) {
    _cur = d['id'] as String?;
    _strokes = [for (final s in (d['s'] as List? ?? const [])) Stroke.fromJson((s as Map).cast<String, Object?>())];
    _redo.clear();
    _version++;
  }

  Future<void> _save() async {
    if (_strokes.isEmpty && _cur == null) return;
    final data = {'id': _cur ?? newId(), 'updated': DateTime.now().millisecondsSinceEpoch, 's': [for (final s in _strokes) s.toJson()]};
    _cur = data['id'] as String;
    final i = _drawings.indexWhere((x) => x['id'] == _cur);
    if (i >= 0) {
      _drawings[i] = {..._drawings[i], ...data};
    } else {
      _drawings.insert(0, {...data, 'name': '${L(t, 'drawing')} ${_drawings.length + 1}'});
    }
    await t.store.writeList('drawings', _drawings);
    await t.store.write('cur', _cur!);
  }

  void _new() {
    setState(() {
      _cur = null;
      _strokes = [];
      _redo.clear();
      _version++;
    });
  }

  Future<void> _gallery() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(leading: const Icon(Icons.add_rounded), title: Text(L(t, 'new_drawing')), onTap: () => Navigator.pop(c, '+')),
          for (final d in _drawings)
            ListTile(
              leading: const Icon(Icons.brush_rounded),
              title: Text(d['name'] as String? ?? ''),
              subtitle: Text(fmtDateTime(c, DateTime.fromMillisecondsSinceEpoch((d['updated'] as num?)?.toInt() ?? 0))),
              selected: d['id'] == _cur,
              onTap: () => Navigator.pop(c, d['id'] as String),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => Navigator.pop(c, '-${d['id']}'),
              ),
            ),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == '+') {
      _new();
    } else if (pick.startsWith('-')) {
      if (!await confirmDelete(context, t)) return;
      final id = pick.substring(1);
      _drawings.removeWhere((x) => x['id'] == id);
      await t.store.writeList('drawings', _drawings);
      if (id == _cur) _new();
      setState(() {});
    } else {
      setState(() => _open(_drawings.firstWhere((x) => x['id'] == pick)));
      await t.store.write('cur', pick);
    }
  }

  Future<void> _export() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    paintStrokes(canvas, _size, _strokes);
    final img = await rec.endRecording().toImage(_size.width.ceil(), _size.height.ceil());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    await shareBytes(data.buffer.asUint8List(), 'sketch.png', 'image/png');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          IconButton(tooltip: L(t, 'drawings'), onPressed: _gallery, icon: const Icon(Icons.collections_rounded)),
          IconButton(
            tooltip: L(t, 'undo'),
            onPressed: _strokes.isEmpty
                ? null
                : () {
                    setState(() {
                      _redo.add(_strokes.removeLast());
                      _version++;
                    });
                    _save();
                  },
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: L(t, 'redo'),
            onPressed: _redo.isEmpty
                ? null
                : () {
                    setState(() {
                      _strokes.add(_redo.removeLast());
                      _version++;
                    });
                    _save();
                  },
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: L(t, 'eraser'),
            isSelected: _eraser,
            onPressed: () => setState(() => _eraser = !_eraser),
            icon: const Icon(Icons.auto_fix_normal_rounded),
          ),
          IconButton(
            tooltip: L(t, 'clear'),
            onPressed: _strokes.isEmpty
                ? null
                : () async {
                    if (!await confirmDelete(context, t)) return;
                    setState(() {
                      _strokes = [];
                      _redo.clear();
                      _version++;
                    });
                    await _save();
                  },
            icon: const Icon(Icons.layers_clear_rounded),
          ),
          IconButton(tooltip: L(t, 'share'), onPressed: _strokes.isEmpty ? null : _export, icon: const Icon(Icons.ios_share_rounded)),
        ]),
      ),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (final c in _inks)
            GestureDetector(
              onTap: () => setState(() {
                _ink = c;
                _eraser = false;
              }),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: !_eraser && _ink == c ? Colors.white : Colors.white24, width: 3),
                ),
              ),
            ),
          SizedBox(
            width: 180,
            child: Slider(min: 1, max: 40, value: _width, onChanged: (v) => setState(() => _width = v)),
          ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(builder: (context, box) {
              _size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                onPanStart: (d) => setState(() {
                  _strokes.add(Stroke(_ink, _eraser ? _width * 3 : _width, _eraser, [d.localPosition]));
                  _redo.clear();
                  _version++;
                }),
                onPanUpdate: (d) => setState(() {
                  _strokes.last.points.add(d.localPosition);
                  _version++;
                }),
                onPanEnd: (_) => _save(),
                child: CustomPaint(painter: _SketchPainter(_strokes, _version), size: Size.infinite),
              );
            }),
          ),
        ),
      ),
    ]);
  }
}

// ========================================================== zihin haritası

class MindMapTool extends StatefulWidget {
  final ToolContext t;
  const MindMapTool(this.t, {super.key});

  @override
  State<MindMapTool> createState() => _MindMapToolState();
}

class _MindMapToolState extends State<MindMapTool> {
  static const double _nw = 156, _nh = 52, _gx = 196, _gy = 66;
  List<Map<String, Object?>> _maps = [];
  String? _cur;
  MindNode? _root;
  String? _sel;
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _maps = await t.store.readList('maps');
    final cur = await t.store.read('cur');
    final m = _maps.where((x) => x['id'] == cur).firstOrNull ?? _maps.firstOrNull;
    if (m != null) {
      _cur = m['id'] as String;
      _root = MindNode.fromJson((m['root'] as Map).cast<String, Object?>());
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final r = _root;
    if (r == null) return;
    final i = _maps.indexWhere((x) => x['id'] == _cur);
    final data = {'id': _cur, 'root': r.toJson(), 'updated': DateTime.now().millisecondsSinceEpoch};
    if (i >= 0) {
      _maps[i] = data;
    } else {
      _maps.insert(0, data);
    }
    await t.store.writeList('maps', _maps);
    await t.store.write('cur', _cur ?? '');
  }

  Future<void> _newMap() async {
    final n = await askText(context, t, L(t, 'central_idea'));
    if (n == null) return;
    setState(() {
      _cur = newId();
      _root = MindNode(newId(), n, color: 0);
      _sel = _root!.id;
    });
    await _save();
  }

  Future<void> _mapsMenu() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(leading: const Icon(Icons.add_rounded), title: Text(L(t, 'new_map')), onTap: () => Navigator.pop(c, '+')),
          if (_root != null)
            ListTile(leading: const Icon(Icons.ios_share_rounded), title: Text(L(t, 'share')), onTap: () => Navigator.pop(c, 's')),
          for (final m in _maps)
            ListTile(
              leading: const Icon(Icons.account_tree_rounded),
              title: Text(((m['root'] as Map?)?['text'] as String?) ?? ''),
              selected: m['id'] == _cur,
              onTap: () => Navigator.pop(c, m['id'] as String),
              trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => Navigator.pop(c, '-${m['id']}')),
            ),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == '+') {
      await _newMap();
    } else if (pick == 's') {
      await shareText(mindToText(_root!));
    } else if (pick.startsWith('-')) {
      if (!await confirmDelete(context, t)) return;
      final id = pick.substring(1);
      _maps.removeWhere((x) => x['id'] == id);
      await t.store.writeList('maps', _maps);
      setState(() {
        if (id == _cur) {
          final m = _maps.firstOrNull;
          _cur = m?['id'] as String?;
          _root = m == null ? null : MindNode.fromJson((m['root'] as Map).cast<String, Object?>());
        }
      });
    } else {
      final m = _maps.firstWhere((x) => x['id'] == pick);
      setState(() {
        _cur = pick;
        _root = MindNode.fromJson((m['root'] as Map).cast<String, Object?>());
        _sel = null;
      });
      await t.store.write('cur', pick);
    }
  }

  Future<void> _addChild() async {
    final n = _root?.find(_sel ?? '');
    if (n == null) return;
    final text = await askText(context, t, L(t, 'add_branch'));
    if (text == null) return;
    final c = MindNode(newId(), text, color: n == _root ? n.children.length % kPalette.length : n.color);
    setState(() {
      n.children.add(c);
      _sel = c.id;
    });
    await _save();
  }

  Future<void> _rename() async {
    final n = _root?.find(_sel ?? '');
    if (n == null) return;
    final text = await askText(context, t, L(t, 'rename'), initial: n.text);
    if (text == null) return;
    setState(() => n.text = text);
    await _save();
  }

  Future<void> _recolor() async {
    final n = _root?.find(_sel ?? '');
    if (n == null) return;
    setState(() => n.color = (n.color + 1) % kPalette.length);
    await _save();
  }

  Future<void> _delete() async {
    final r = _root;
    final id = _sel;
    if (r == null || id == null || id == r.id) return;
    if (!await confirmDelete(context, t)) return;
    final p = r.parentOf(id);
    setState(() {
      p?.children.removeWhere((c) => c.id == id);
      _sel = p?.id;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final root = _root;
    if (root == null) {
      return ToolList(children: [
        EmptyHint(L(t, 'empty_list'), icon: Icons.account_tree_rounded),
        Center(child: AppButton(label: L(t, 'new_map'), icon: Icons.add_rounded, onPressed: _newMap)),
      ]);
    }
    final pos = layoutMind(root);
    final maxX = pos.values.map((p) => p.x).fold<double>(0, math.max);
    final maxY = pos.values.map((p) => p.y).fold<double>(0, math.max);
    final w = (maxX + 1) * _gx + 80, h = (maxY + 1) * _gy + 80;
    Offset at(String id) => Offset(40 + pos[id]!.x * _gx, 40 + pos[id]!.y * _gy);
    final nodes = <MindNode>[];
    void walk(MindNode n) {
      nodes.add(n);
      n.children.forEach(walk);
    }

    walk(root);
    final sel = _sel == null ? null : root.find(_sel!);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(onPressed: _mapsMenu, icon: const Icon(Icons.menu_rounded)),
          Expanded(child: Text(root.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          Text('${root.count}', style: const TextStyle(color: Colors.white60)),
        ]),
      ),
      Expanded(
        child: InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          minScale: 0.3,
          maxScale: 2.5,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _EdgePainter(root, at, _nw, _nh))),
              for (final n in nodes)
                Positioned(
                  left: at(n.id).dx,
                  top: at(n.id).dy,
                  width: _nw,
                  height: _nh,
                  child: GestureDetector(
                    onTap: () => setState(() => _sel = n.id),
                    onDoubleTap: () {
                      setState(() => _sel = n.id);
                      _rename();
                    },
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: paletteAt(n.color).withValues(alpha: n == root ? 0.95 : 0.75),
                        borderRadius: BorderRadius.circular(n == root ? 26 : 14),
                        border: Border.all(color: n.id == _sel ? Colors.white : Colors.transparent, width: 3),
                      ),
                      child: Text(n.text,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.black87, fontWeight: n == root ? FontWeight.w900 : FontWeight.w600)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      if (sel != null)
        SafeArea(
          top: false,
          child: Wrap(alignment: WrapAlignment.center, children: [
            TextButton.icon(onPressed: _addChild, icon: const Icon(Icons.add_circle_outline_rounded), label: Text(L(t, 'add_branch'))),
            IconButton(tooltip: L(t, 'rename'), onPressed: _rename, icon: const Icon(Icons.edit_rounded)),
            IconButton(tooltip: L(t, 'color'), onPressed: _recolor, icon: const Icon(Icons.palette_rounded)),
            if (sel != root) IconButton(tooltip: L(t, 'delete'), onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
          ]),
        ),
    ]);
  }
}

class _EdgePainter extends CustomPainter {
  final MindNode root;
  final Offset Function(String) at;
  final double nw, nh;
  _EdgePainter(this.root, this.at, this.nw, this.nh);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    void walk(MindNode n) {
      final a = at(n.id) + Offset(nw, nh / 2);
      for (final c in n.children) {
        final b = at(c.id) + Offset(0, nh / 2);
        final mx = (a.dx + b.dx) / 2;
        canvas.drawPath(Path()..moveTo(a.dx, a.dy)..cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy), p);
        walk(c);
      }
    }

    walk(root);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ============================================================ metin araçları

class TextToolsTool extends StatefulWidget {
  final ToolContext t;
  const TextToolsTool(this.t, {super.key});

  @override
  State<TextToolsTool> createState() => _TextToolsToolState();
}

class _TextToolsToolState extends State<TextToolsTool> {
  final _c = TextEditingController();
  final _find = TextEditingController();
  final _rep = TextEditingController();
  String? _undo;
  Timer? _debounce;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.read('text').then((v) {
      if (v != null && mounted) setState(() => _c.text = v);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    t.store.write('text', _c.text);
    _c.dispose();
    _find.dispose();
    _rep.dispose();
    super.dispose();
  }

  void _apply(String Function(String) f) {
    final before = _c.text;
    final after = f(before);
    if (after == before) return;
    setState(() {
      _undo = before;
      _c.text = after;
    });
    t.store.write('text', after);
  }

  @override
  Widget build(BuildContext context) {
    final s = TextStats.of(_c.text);
    final lang = t.lang;
    Widget stat(String k, int v) => Container(
          width: 108,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('$v', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
            Text(L(t, k), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        );
    final ops = <(String, String Function(String))>[
      ('uppercase', (x) => upperFor(x, lang)),
      ('lowercase', (x) => lowerFor(x, lang)),
      ('title_case', (x) => titleCase(x, lang)),
      ('sentence_case', (x) => sentenceCase(x, lang)),
      ('trim_spaces', trimSpaces),
      ('sort_lines', (x) => sortLines(x)),
      ('remove_dupes', removeDuplicateLines),
      ('reverse', reverseText),
      ('slug', slugify),
    ];
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(
          controller: _c,
          label: L(t, 'text'),
          maxLines: 12,
          minLines: 6,
          onChanged: (_) {
            setState(() {});
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 800), () => t.store.write('text', _c.text));
          },
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: L(t, 'undo'), onPressed: _undo == null ? null : () => _apply((_) => _undo!), icon: const Icon(Icons.undo_rounded)),
        IconButton(tooltip: t.tx('copied'), onPressed: () => copyText(context, t, _c.text), icon: const Icon(Icons.copy_rounded)),
        IconButton(
          tooltip: L(t, 'paste_now'),
          onPressed: () async {
            final d = await Clipboard.getData(Clipboard.kTextPlain);
            final v = d?.text;
            if (v != null) _apply((x) => x.isEmpty ? v : '$x\n$v');
          },
          icon: const Icon(Icons.content_paste_rounded),
        ),
        IconButton(tooltip: L(t, 'share'), onPressed: _c.text.isEmpty ? null : () => shareText(_c.text), icon: const Icon(Icons.ios_share_rounded)),
        IconButton(tooltip: L(t, 'clear'), onPressed: () => _apply((_) => ''), icon: const Icon(Icons.clear_all_rounded)),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          stat('chars', s.chars),
          stat('chars_nospace', s.charsNoSpace),
          stat('words', s.words),
          stat('sentences', s.sentences),
          stat('lines', s.lines),
          stat('paragraphs', s.paragraphs),
          stat('read_time', s.readingMinutes),
        ]),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, f) in ops) ActionChip(label: Text(L(t, k)), onPressed: () => _apply(f)),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          AppTextField(controller: _find, label: L(t, 'find')),
          AppTextField(controller: _rep, label: L(t, 'replace_with')),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () {
                final (out, n) = findReplace(_c.text, _find.text, _rep.text);
                _apply((_) => out);
                toast(context, '${L(t, 'matches')}: $n');
              },
              icon: const Icon(Icons.find_replace_rounded),
              label: Text(L(t, 'replace_all')),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ============================================================= pano geçmişi

class ClipboardTool extends StatefulWidget {
  final ToolContext t;
  const ClipboardTool(this.t, {super.key});

  @override
  State<ClipboardTool> createState() => _ClipboardToolState();
}

class _ClipboardToolState extends State<ClipboardTool> {
  List<Map<String, Object?>> _items = [];
  String _q = '';
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('clips').then((l) {
      if (!mounted) return;
      setState(() {
        _items = l;
        _loaded = true;
      });
    });
  }

  Future<void> _save() async {
    // Sabitlenmemişlerden en fazla 200 tutulur.
    var unpinned = 0;
    _items = [
      for (final i in _items)
        if (i['pin'] == true || ++unpinned <= 200) i,
    ];
    await t.store.writeList('clips', _items);
  }

  Future<void> _add(String text) async {
    if (text.trim().isEmpty) return;
    final old = _items.where((i) => i['text'] == text).firstOrNull;
    setState(() {
      _items.remove(old);
      _items.insert(0, {'id': newId(), 'text': text, 'pin': old?['pin'] == true, 'at': DateTime.now().millisecondsSinceEpoch});
    });
    await _save();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final v = d?.text ?? '';
    if (v.trim().isEmpty) {
      toast(context, L(t, 'clip_empty'));
      return;
    }
    HapticFeedback.lightImpact();
    await _add(v);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final q = _q.toLowerCase();
    final vis = _items.where((i) => q.isEmpty || (i['text'] as String? ?? '').toLowerCase().contains(q)).toList()
      ..sort((a, b) => (a['pin'] == true ? 0 : 1).compareTo(b['pin'] == true ? 0 : 1));
    return ToolList(children: [
      AppInfoCard(L(t, 'clip_note'), icon: Icons.privacy_tip_outlined),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: AppButton(label: L(t, 'paste_now'), icon: Icons.content_paste_go_rounded, onPressed: _paste)),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () async {
              final v = await askText(context, t, L(t, 'note'), maxLines: 6);
              if (v != null) await _add(v);
            },
            icon: const Icon(Icons.edit_note_rounded),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      if (vis.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.content_paste_off_rounded),
      for (final i in vis)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            onTap: () => copyText(context, t, i['text'] as String? ?? ''),
            title: Text(i['text'] as String? ?? '', maxLines: 4, overflow: TextOverflow.ellipsis),
            subtitle: Text(fmtDateTime(context, DateTime.fromMillisecondsSinceEpoch((i['at'] as num?)?.toInt() ?? 0)),
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: Icon(i['pin'] == true ? Icons.push_pin_rounded : Icons.push_pin_outlined),
                onPressed: () {
                  setState(() => i['pin'] = i['pin'] != true);
                  _save();
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  setState(() => _items.remove(i));
                  _save();
                },
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ======================================== sunum zamanlayıcı ve teleprompter

class PrompterTool extends StatefulWidget {
  final ToolContext t;
  const PrompterTool(this.t, {super.key});

  @override
  State<PrompterTool> createState() => _PrompterToolState();
}

class _PrompterToolState extends State<PrompterTool> with SingleTickerProviderStateMixin {
  final _script = TextEditingController();
  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_onTick);
  double _speed = 4;
  double _font = 40;
  bool _mirror = false;
  int _target = 5;
  bool _present = false;
  bool _rolling = false;
  Duration _elapsed = Duration.zero;
  Duration _lastTick = Duration.zero;
  Duration _base = Duration.zero;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await t.store.readMap('cfg');
    final s = await t.store.read('script');
    if (!mounted) return;
    setState(() {
      _script.text = s ?? '';
      _speed = (m['speed'] as num?)?.toDouble() ?? 4;
      _font = (m['font'] as num?)?.toDouble() ?? 40;
      _mirror = m['mirror'] == true;
      _target = (m['target'] as num?)?.toInt() ?? 5;
    });
  }

  Future<void> _saveCfg() => t.store.writeMap('cfg', {'speed': _speed, 'font': _font, 'mirror': _mirror, 'target': _target});

  void _onTick(Duration d) {
    final dt = (d - _lastTick).inMicroseconds / 1e6;
    _lastTick = d;
    if (!mounted) return;
    setState(() => _elapsed = _base + d);
    if (_rolling && _scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      final next = math.min<double>(max, _scroll.offset + dt * _speed * 14);
      _scroll.jumpTo(next);
    }
  }

  void _start() {
    t.store.write('script', _script.text);
    setState(() {
      _present = true;
      _rolling = true;
      _elapsed = Duration.zero;
      _base = Duration.zero;
      _lastTick = Duration.zero;
    });
    WakelockPlus.enable();
    _ticker.start();
  }

  void _toggle() {
    setState(() => _rolling = !_rolling);
  }

  void _stop() {
    _ticker.stop();
    WakelockPlus.disable();
    setState(() {
      _present = false;
      _rolling = false;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    WakelockPlus.disable();
    t.store.write('script', _script.text);
    _script.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _present ? _presentView(context) : _editView(context);

  Widget _editView(BuildContext context) {
    final words = TextStats.of(_script.text).words;
    final estimate = Duration(seconds: (words / 130 * 60).round());
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppTextField(controller: _script, label: L(t, 'script'), maxLines: 14, minLines: 8, onChanged: (_) => setState(() {})),
      ),
      AppResult(label: '${L(t, 'words')} · ≈', value: '$words · ${fmtDuration(estimate)}', lang: t.lang),
      AppPanel(
        child: Column(children: [
          Row(children: [
            SizedBox(width: 120, child: Text(L(t, 'speed'))),
            Expanded(
              child: Slider(min: 1, max: 12, divisions: 22, value: _speed, label: _speed.toStringAsFixed(1), onChanged: (v) {
                setState(() => _speed = v);
                _saveCfg();
              }),
            ),
          ]),
          Row(children: [
            SizedBox(width: 120, child: Text(L(t, 'font_size'))),
            Expanded(
              child: Slider(min: 20, max: 96, value: _font, onChanged: (v) {
                setState(() => _font = v);
                _saveCfg();
              }),
            ),
          ]),
          Pick<int>(
            label: '${L(t, 'target')} (${L(t, 'minutes')})',
            values: const [1, 2, 3, 5, 7, 10, 15, 20, 30, 45, 60],
            text: (v) => '$v',
            value: _target,
            onChanged: (v) {
              setState(() => _target = v);
              _saveCfg();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'mirror')),
            value: _mirror,
            onChanged: (v) {
              setState(() => _mirror = v);
              _saveCfg();
            },
          ),
        ]),
      ),
      Center(child: AppButton(label: L(t, 'present'), icon: Icons.slideshow_rounded, onPressed: _start)),
    ]);
  }

  Widget _presentView(BuildContext context) {
    final target = Duration(minutes: _target);
    final left = target - _elapsed;
    final color = left.isNegative ? Colors.redAccent : (left.inSeconds <= 60 ? Colors.amber : Colors.lightGreenAccent);
    Widget text = SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: MediaQuery.sizeOf(context).height * 0.4),
      child: Text(_script.text, style: TextStyle(fontSize: _font, height: 1.35, color: Colors.white, fontWeight: FontWeight.w600)),
    );
    if (_mirror) text = Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: text);
    return Container(
      color: Colors.black,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            IconButton(onPressed: _stop, icon: const Icon(Icons.close_rounded)),
            Expanded(
              child: Text('${L(t, 'elapsed')} ${fmtDuration(_elapsed)}', style: const TextStyle(fontSize: 18, color: Colors.white70)),
            ),
            Text(fmtDuration(left), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: color)),
          ]),
        ),
        LinearProgressIndicator(
          value: target.inSeconds == 0 ? 0 : math.min<double>(1, _elapsed.inMilliseconds / target.inMilliseconds),
          color: color,
          backgroundColor: Colors.white12,
        ),
        Expanded(child: GestureDetector(onTap: _toggle, child: text)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: () => setState(() => _speed = math.max<double>(1, _speed - 0.5)), icon: const Icon(Icons.remove_rounded)),
            Text('${L(t, 'speed')} ${_speed.toStringAsFixed(1)}'),
            IconButton(onPressed: () => setState(() => _speed = math.min<double>(12, _speed + 0.5)), icon: const Icon(Icons.add_rounded)),
            const SizedBox(width: 16),
            IconButton.filled(onPressed: _toggle, icon: Icon(_rolling ? Icons.pause_rounded : Icons.play_arrow_rounded)),
            IconButton(
              onPressed: () {
                if (_scroll.hasClients) _scroll.jumpTo(0);
              },
              icon: const Icon(Icons.vertical_align_top_rounded),
            ),
          ]),
        ),
      ]),
    );
  }
}
