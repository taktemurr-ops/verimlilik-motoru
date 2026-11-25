/// Proje zaman çizelgesi (Gantt): projeler, işler, süreler, bitiş-başlangıç
/// bağımlılıkları (otomatik kaydırma), kilometre taşları, ilerleme, kritik
/// yol ve bugün çizgisi. CSV olarak paylaşılabilir. Veriler yalnızca cihazda.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic/goal_logic.dart';

typedef Js = Map<String, Object?>;

List<Js> _maps(Object? v) => [for (final e in (v as List? ?? const [])) (e as Map).cast<String, Object?>()];
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

GTask _task(Js m) => GTask(
      id: m['id'] as String,
      name: m['name'] as String? ?? '',
      start: _day(DateTime.fromMillisecondsSinceEpoch((m['start'] as num?)?.toInt() ?? 0)),
      days: (m['days'] as num?)?.toInt() ?? 1,
      deps: [for (final d in (m['deps'] as List? ?? const [])) '$d'],
      progress: (m['progress'] as num?)?.toInt() ?? 0,
    );

class GanttTool extends StatefulWidget {
  final ToolContext t;
  const GanttTool(this.t, {super.key});

  @override
  State<GanttTool> createState() => _GanttToolState();
}

class _GanttToolState extends State<GanttTool> {
  static const double _rowH = 38, _headH = 34, _nameW = 132;
  List<Js> _projects = [];
  String? _cur;
  bool _loaded = false;
  int _zoom = 0;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _projects = await t.store.readList('projects');
    if (_projects.isEmpty) _projects = [{'id': newId(), 'name': L(t, 'project'), 'tasks': <Js>[]}];
    final cur = await t.store.read('cur');
    _zoom = await t.store.readInt('zoom', 0);
    if (!mounted) return;
    setState(() {
      _cur = _projects.any((p) => p['id'] == cur) ? cur : _projects.first['id'] as String;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await t.store.writeList('projects', _projects);
    await t.store.write('cur', _cur ?? '');
  }

  Js get _proj => _projects.firstWhere((p) => p['id'] == _cur, orElse: () => _projects.first);
  List<Js> get _tasks => _maps(_proj['tasks']);

  /// Bağımlılıklara göre kaydırıp saklar; döngü varsa false.
  bool _apply(List<Js> tasks) {
    final gt = [for (final m in tasks) _task(m)];
    if (topoOrder(gt) == null) return false;
    final s = scheduleTasks(gt);
    for (var i = 0; i < tasks.length; i++) {
      tasks[i] = {...tasks[i], 'start': s[i].start.millisecondsSinceEpoch};
    }
    _proj['tasks'] = tasks;
    return true;
  }

  Future<void> _projectMenu(String v) async {
    switch (v) {
      case 'new':
        final n = await askText(context, t, L(t, 'project'));
        if (n == null) return;
        final p = {'id': newId(), 'name': n, 'tasks': <Js>[]};
        setState(() {
          _projects.add(p);
          _cur = p['id'] as String;
        });
      case 'rename':
        final n = await askText(context, t, L(t, 'rename'), initial: '${_proj['name']}');
        if (n == null) return;
        setState(() => _proj['name'] = n);
      case 'delete':
        if (!await confirmDelete(context, t)) return;
        setState(() {
          _projects.removeWhere((p) => p['id'] == _cur);
          if (_projects.isEmpty) _projects = [{'id': newId(), 'name': L(t, 'project'), 'tasks': <Js>[]}];
          _cur = _projects.first['id'] as String;
        });
      case 'csv':
        final tasks = [for (final m in _tasks) _task(m)];
        final names = {for (final x in tasks) x.id: x.name};
        final crit = criticalPath(tasks);
        String iso(DateTime d) => dayKey(d);
        await shareText(toCsv([
          [L(t, 'task'), L(t, 'start_date'), L(t, 'finish'), L(t, 'duration'), L(t, 'progress'), L(t, 'depends_on'), L(t, 'critical')],
          for (final x in tasks)
            [
              x.name,
              iso(x.start),
              iso(x.end),
              '${x.days}',
              '${x.progress}%',
              x.deps.map((d) => names[d] ?? '').join('; '),
              crit.contains(x.id) ? '✓' : '',
            ],
        ]), subject: '${_proj['name']}');
        return;
    }
    await _save();
  }

  Future<void> _edit([Js? orig]) async {
    final tasks = _tasks;
    final m = Map<String, Object?>.from(orig ??
        {
          'start': (tasks.isEmpty
                  ? _day(DateTime.now())
                  : tasks.map(_task).map((x) => x.end).reduce((a, b) => a.isAfter(b) ? a : b))
              .millisecondsSinceEpoch,
          'days': 5,
          'deps': tasks.isEmpty ? <String>[] : [tasks.last['id'] as String],
          'progress': 0,
          'color': tasks.length,
        });
    final name = TextEditingController(text: m['name'] as String? ?? '');
    final days = TextEditingController(text: '${(m['days'] as num?)?.toInt() ?? 1}');
    final deps = <String>{for (final d in (m['deps'] as List? ?? const [])) '$d'};
    final others = [for (final x in tasks) if (x['id'] != m['id']) x];
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
                Expanded(child: Text(L(t, 'task'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (orig != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (await confirmDelete(c, t) && c.mounted) Navigator.pop(c, 'del');
                    },
                  ),
              ]),
              AppTextField(controller: name, label: L(t, 'name'), autofocus: orig == null),
              DateRow(
                label: L(t, 'start_date'),
                value: DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
                clearable: false,
                onChanged: (d) => set(() => m['start'] = _day(d ?? DateTime.now()).millisecondsSinceEpoch),
              ),
              AppNumberField(controller: days, label: '${L(t, 'duration')} (${L(t, 'days')})', decimal: false),
              Text(L(t, 'milestone_hint'), style: const TextStyle(color: Colors.white60, fontSize: 13)),
              Row(children: [
                Text(L(t, 'progress')),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 100,
                    divisions: 20,
                    value: ((m['progress'] as num?) ?? 0).toDouble(),
                    onChanged: (v) => set(() => m['progress'] = v.round()),
                  ),
                ),
                Text('${m['progress']}%'),
              ]),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(L(t, 'depends_on'), style: const TextStyle(fontWeight: FontWeight.w700)),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final o in others)
                    FilterChip(
                      label: Text('${o['name']}'),
                      selected: deps.contains(o['id']),
                      onSelected: (v) => set(() => v ? deps.add(o['id'] as String) : deps.remove(o['id'])),
                    ),
                ]),
              ],
              ColorRow(value: (m['color'] as num?)?.toInt() ?? 0, onChanged: (i) => set(() => m['color'] = i)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => Navigator.pop(c, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
            ]),
          ),
        ),
      ),
    );
    final nm = name.text.trim();
    final dd = int.tryParse(days.text.trim()) ?? (parseNumber(days.text)?.round() ?? 1);
    name.dispose();
    days.dispose();
    if (res == null || !mounted) return;
    final next = [...tasks];
    if (res == 'del') {
      next.removeWhere((x) => x['id'] == orig?['id']);
      for (var i = 0; i < next.length; i++) {
        next[i] = {...next[i], 'deps': [for (final d in (next[i]['deps'] as List? ?? const [])) if (d != orig?['id']) d]};
      }
    } else {
      m['name'] = nm.isEmpty ? L(t, 'task') : nm;
      m['days'] = math.max(0, math.min(dd, 3650));
      m['deps'] = deps.toList();
      if (orig == null) {
        m['id'] = newId();
        next.add(m);
      } else {
        next[next.indexWhere((x) => x['id'] == orig['id'])] = m;
      }
    }
    if (!_apply(next)) {
      toast(context, L(t, 'dep_cycle'));
      return;
    }
    setState(() {});
    await _save();
  }

  Future<void> _move(int i, int dir) async {
    final next = [..._tasks];
    final j = i + dir;
    if (j < 0 || j >= next.length) return;
    final x = next[i];
    next[i] = next[j];
    next[j] = x;
    setState(() => _proj['tasks'] = next);
    await _save();
  }

  double get _dayW => const [36.0, 14.0, 5.0][clampInt(_zoom, 0, 2)];

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final maps = _tasks;
    final tasks = [for (final m in maps) _task(m)];
    final crit = criticalPath(tasks);
    final (ps, pe, pp) = projectSpan(tasks);
    final colors = [for (final m in maps) paletteAt((m['color'] as num?)?.toInt() ?? 0)];
    final zooms = Ls(t, 'zoom_opts');
    final origin = _day(ps).subtract(const Duration(days: 2));
    final span = math.max(14, _day(pe).difference(origin).inDays + 10);
    final chartW = span * _dayW;
    return ToolList(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: Pick<String>(
              label: L(t, 'project'),
              values: [for (final p in _projects) p['id'] as String],
              text: (id) => '${_projects.firstWhere((p) => p['id'] == id)['name']}',
              value: _cur!,
              onChanged: (v) async {
                setState(() => _cur = v);
                await _save();
              },
            ),
          ),
          PopupMenuButton<String>(
            onSelected: _projectMenu,
            itemBuilder: (c) => [
              PopupMenuItem(value: 'new', child: Text('+ ${L(t, 'project')}')),
              PopupMenuItem(value: 'rename', child: Text(L(t, 'rename'))),
              PopupMenuItem(value: 'csv', child: Text(L(t, 'export_csv'))),
              PopupMenuItem(value: 'delete', child: Text(L(t, 'delete'))),
            ],
          ),
        ]),
      ),
      if (tasks.isNotEmpty)
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'start_date'), value: fmtDate(context, ps), lang: t.lang),
            AppResult(label: L(t, 'finish'), value: fmtDate(context, pe), lang: t.lang),
            AppResult(label: L(t, 'duration'), value: '${_day(pe).difference(_day(ps)).inDays} ${L(t, 'days')}', lang: t.lang),
            AppResult(label: L(t, 'progress'), value: '${(pp * 100).round()}%', lang: t.lang, big: true),
          ]),
        ),
      SectionBar('${L(t, 'task')} · ${tasks.length}', icon: Icons.view_timeline_rounded, onAdd: () => _edit()),
      if (tasks.isEmpty)
        EmptyHint(L(t, 'gantt_empty'), icon: Icons.view_timeline_outlined)
      else ...[
        Choice<int>(
          values: const [0, 1, 2],
          labels: [for (var i = 0; i < 3; i++) i < zooms.length ? zooms[i] : '$i'],
          selected: clampInt(_zoom, 0, 2),
          onChanged: (v) {
            setState(() => _zoom = v);
            t.store.write('zoom', '$v');
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: _nameW,
              child: Column(children: [
                const SizedBox(height: _headH),
                for (var i = 0; i < tasks.length; i++)
                  SizedBox(
                    height: _rowH,
                    child: InkWell(
                      onTap: () => _edit(maps[i]),
                      onLongPress: () => _move(i, i == 0 ? 1 : -1),
                      child: Row(children: [
                        if (crit.contains(tasks[i].id))
                          const Icon(Icons.priority_high_rounded, size: 14, color: Colors.redAccent),
                        Expanded(
                          child: Text(tasks[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: tasks[i].days == 0 ? FontWeight.w900 : FontWeight.w600)),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  onTapUp: (d) {
                    final row = ((d.localPosition.dy - _headH) / _rowH).floor();
                    if (row >= 0 && row < maps.length) _edit(maps[row]);
                  },
                  child: CustomPaint(
                    size: Size(chartW, _headH + tasks.length * _rowH),
                    painter: _GanttPainter(
                      tasks: tasks,
                      colors: colors,
                      critical: crit,
                      origin: origin,
                      days: span,
                      dayW: _dayW,
                      rowH: _rowH,
                      headH: _headH,
                      zoom: clampInt(_zoom, 0, 2),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(spacing: 14, runSpacing: 6, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 10, decoration: BoxDecoration(border: Border.all(color: Colors.redAccent, width: 2))),
              const SizedBox(width: 6),
              Text(L(t, 'critical'), style: const TextStyle(fontSize: 13)),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Transform.rotate(angle: math.pi / 4, child: Container(width: 9, height: 9, color: Colors.amber)),
              const SizedBox(width: 6),
              Text(L(t, 'milestone'), style: const TextStyle(fontSize: 13)),
            ]),
          ]),
        ),
      ],
    ]);
  }
}

class _GanttPainter extends CustomPainter {
  final List<GTask> tasks;
  final List<Color> colors;
  final Set<String> critical;
  final DateTime origin;
  final int days;
  final double dayW, rowH, headH;
  final int zoom;
  _GanttPainter({
    required this.tasks,
    required this.colors,
    required this.critical,
    required this.origin,
    required this.days,
    required this.dayW,
    required this.rowH,
    required this.headH,
    required this.zoom,
  });

  double _x(DateTime d) => _day(d).difference(origin).inDays * dayW;

  void _text(Canvas c, String s, Offset o, {double size = 11, Color color = Colors.white70}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = Colors.white10;
    final strong = Paint()..color = Colors.white24;
    // Başlık: günler / haftalar / aylar.
    for (var i = 0; i <= days; i++) {
      final d = DateTime(origin.year, origin.month, origin.day + i);
      final x = i * dayW;
      final weekend = d.weekday >= 6;
      if (zoom == 0 && weekend) {
        canvas.drawRect(Rect.fromLTWH(x, headH, dayW, size.height - headH), Paint()..color = Colors.white.withValues(alpha: 0.03));
      }
      final mark = switch (zoom) { 0 => true, 1 => d.weekday == 1, _ => d.day == 1 };
      if (mark) {
        canvas.drawLine(Offset(x, headH - 6), Offset(x, size.height), d.day == 1 ? strong : grid);
        final label = switch (zoom) { 0 => '${d.day}', 1 => '${d.day}.${d.month}', _ => '${d.month}/${d.year % 100}' };
        _text(canvas, label, Offset(x + 2, 4));
      }
      if (zoom == 0 && d.day == 1) _text(canvas, '${d.month}/${d.year}', Offset(x + 2, 18), size: 10, color: Colors.white54);
    }
    for (var r = 0; r <= tasks.length; r++) {
      final y = headH + r * rowH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Bağımlılık okları.
    final idx = {for (var i = 0; i < tasks.length; i++) tasks[i].id: i};
    final arrow = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < tasks.length; i++) {
      for (final d in tasks[i].deps) {
        final j = idx[d];
        if (j == null) continue;
        final from = Offset(_x(tasks[j].end), headH + j * rowH + rowH / 2);
        final to = Offset(_x(tasks[i].start), headH + i * rowH + rowH / 2);
        final midX = math.max(from.dx + 6, to.dx - 6);
        final path = Path()
          ..moveTo(from.dx, from.dy)
          ..lineTo(midX, from.dy)
          ..lineTo(midX, to.dy)
          ..lineTo(to.dx, to.dy);
        canvas.drawPath(path, arrow);
        canvas.drawPath(
          Path()
            ..moveTo(to.dx, to.dy)
            ..lineTo(to.dx - 5, to.dy - 4)
            ..lineTo(to.dx - 5, to.dy + 4)
            ..close(),
          Paint()..color = Colors.white54,
        );
      }
    }
    // Çubuklar.
    for (var i = 0; i < tasks.length; i++) {
      final tk = tasks[i];
      final y = headH + i * rowH;
      final x0 = _x(tk.start);
      final crit = critical.contains(tk.id);
      if (tk.days == 0) {
        final c = Offset(x0, y + rowH / 2);
        final p = Path()
          ..moveTo(c.dx, c.dy - 9)
          ..lineTo(c.dx + 9, c.dy)
          ..lineTo(c.dx, c.dy + 9)
          ..lineTo(c.dx - 9, c.dy)
          ..close();
        canvas.drawPath(p, Paint()..color = Colors.amber);
        if (crit) {
          canvas.drawPath(p, Paint()
            ..color = Colors.redAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
        }
        continue;
      }
      final w = math.max(tk.days * dayW, 3.0);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x0, y + 8, w, rowH - 16), const Radius.circular(5));
      canvas.drawRRect(rect, Paint()..color = colors[i].withValues(alpha: 0.45));
      if (tk.progress > 0) {
        canvas.save();
        canvas.clipRRect(rect);
        canvas.drawRect(Rect.fromLTWH(x0, y + 8, w * tk.progress / 100, rowH - 16), Paint()..color = colors[i]);
        canvas.restore();
      }
      if (crit) {
        canvas.drawRRect(rect, Paint()
          ..color = Colors.redAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
      if (w > 34) _text(canvas, '${tk.progress}%', Offset(x0 + 4, y + rowH / 2 - 7), color: Colors.black87);
    }
    // Bugün çizgisi.
    final today = _x(DateTime.now()) + dayW / 2;
    if (today >= 0 && today <= size.width) {
      canvas.drawLine(
        Offset(today, 0),
        Offset(today, size.height),
        Paint()
          ..color = Colors.lightBlueAccent
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_GanttPainter old) => true;
}
