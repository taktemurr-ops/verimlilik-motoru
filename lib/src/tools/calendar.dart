/// Takvimli uygulamalar: ajanda ve günlük, ders programı, vardiya planlayıcı.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic/plan_logic.dart';

/// Pazartesiyle başlayan ay ızgarası.
class MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime? selected;
  final List<String> weekdays;
  final ValueChanged<DateTime> onTap;
  final ValueChanged<DateTime> onMonth;
  final Widget Function(DateTime day)? marker;
  final Color? Function(DateTime day)? fill;

  const MonthGrid({
    super.key,
    required this.month,
    required this.weekdays,
    required this.onTap,
    required this.onMonth,
    this.selected,
    this.marker,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final cells = lead + days;
    final rows = (cells + 6) ~/ 7;
    final today = dateOnly(DateTime.now());
    final accent = AppLook.of(context).accent;
    return AppPanel(
      child: Column(children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => onMonth(DateTime(month.year, month.month - 1)),
          ),
          Expanded(
            child: Text(MaterialLocalizations.of(context).formatMonthYear(month),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => onMonth(DateTime(month.year, month.month + 1)),
          ),
        ]),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(weekdays.length == 7 ? weekdays[i] : '', textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ),
        ]),
        for (var r = 0; r < rows; r++)
          Row(children: [
            for (var c = 0; c < 7; c++)
              Expanded(
                child: Builder(builder: (_) {
                  final idx = r * 7 + c - lead;
                  if (idx < 0 || idx >= days) return const SizedBox(height: 46);
                  final d = DateTime(month.year, month.month, idx + 1);
                  final sel = selected != null && dateOnly(selected!) == d;
                  final bg = fill?.call(d);
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onTap(d),
                    child: Container(
                      height: 46,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: bg ?? (sel ? accent.withValues(alpha: 0.25) : null),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel ? accent : (d == today ? Colors.white38 : Colors.transparent),
                          width: sel ? 2 : 1,
                        ),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${d.day}', style: TextStyle(fontWeight: d == today ? FontWeight.w900 : FontWeight.w500)),
                        if (marker != null) marker!(d),
                      ]),
                    ),
                  );
                }),
              ),
          ]),
      ]),
    );
  }
}

// ================================================================== ajanda

const List<String> kMoods = ['😞', '🙁', '😐', '🙂', '😄'];

class AgendaTool extends StatefulWidget {
  final ToolContext t;
  const AgendaTool(this.t, {super.key});

  @override
  State<AgendaTool> createState() => _AgendaToolState();
}

class _AgendaToolState extends State<AgendaTool> {
  Map<String, Object?> _days = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _sel = dateOnly(DateTime.now());
  final _journal = TextEditingController();
  Timer? _debounce;
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readMap('days').then((m) {
      if (!mounted) return;
      setState(() {
        _days = m;
        _loaded = true;
      });
      _journal.text = _day(_sel)['journal'] as String? ?? '';
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flush();
    _journal.dispose();
    super.dispose();
  }

  Map<String, Object?> _day(DateTime d) => ((_days[dayKey(d)] as Map?) ?? {}).cast<String, Object?>();

  void _put(DateTime d, Map<String, Object?> v) {
    final empty = (v['journal'] as String? ?? '').trim().isEmpty &&
        (v['events'] as List? ?? const []).isEmpty &&
        v['mood'] == null;
    if (empty) {
      _days.remove(dayKey(d));
    } else {
      _days[dayKey(d)] = v;
    }
  }

  void _flush() {
    if (!_loaded) return;
    final v = _day(_sel);
    v['journal'] = _journal.text;
    _put(_sel, v);
    t.store.writeMap('days', _days);
  }

  void _select(DateTime d) {
    _debounce?.cancel();
    _flush();
    setState(() => _sel = d);
    _journal.text = _day(d)['journal'] as String? ?? '';
  }

  Future<void> _addEvent([int? index]) async {
    final v = _day(_sel);
    final ev = [...(v['events'] as List? ?? const [])].map((e) => (e as Map).cast<String, Object?>()).toList();
    final cur = index == null ? <String, Object?>{} : ev[index];
    final text = await askText(context, t, L(t, 'event'), initial: cur['text'] as String? ?? '');
    if (text == null || !mounted) return;
    TimeOfDay? tm;
    final hm = cur['time'] as String?;
    tm = await showTimePicker(
      context: context,
      initialTime: hm != null && hm.contains(':')
          ? TimeOfDay(hour: int.parse(hm.split(':')[0]), minute: int.parse(hm.split(':')[1]))
          : TimeOfDay.now(),
    );
    final item = {
      'text': text,
      'time': tm == null ? '' : '${tm.hour.toString().padLeft(2, '0')}:${tm.minute.toString().padLeft(2, '0')}',
    };
    if (index == null) {
      ev.add(item);
    } else {
      ev[index] = item;
    }
    ev.sort((a, b) => (a['time'] as String? ?? '').compareTo(b['time'] as String? ?? ''));
    v['events'] = ev;
    v['journal'] = _journal.text;
    setState(() => _put(_sel, v));
    await t.store.writeMap('days', _days);
  }

  Future<void> _removeEvent(int i) async {
    final v = _day(_sel);
    final ev = [...(v['events'] as List? ?? const [])]..removeAt(i);
    v['events'] = ev;
    v['journal'] = _journal.text;
    setState(() => _put(_sel, v));
    await t.store.writeMap('days', _days);
  }

  Future<void> _mood(int? m) async {
    final v = _day(_sel);
    v['mood'] = m;
    v['journal'] = _journal.text;
    setState(() => _put(_sel, v));
    await t.store.writeMap('days', _days);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final v = _day(_sel);
    final ev = (v['events'] as List? ?? const []).map((e) => (e as Map).cast<String, Object?>()).toList();
    final mood = (v['mood'] as num?)?.toInt();
    return ToolList(children: [
      MonthGrid(
        month: _month,
        selected: _sel,
        weekdays: weekdayNames(t),
        onTap: _select,
        onMonth: (m) => setState(() => _month = m),
        marker: (d) {
          final x = _day(d);
          final m = (x['mood'] as num?)?.toInt();
          if (m != null) return Text(kMoods[clampInt(m, 0, 4)], style: const TextStyle(fontSize: 11));
          final has = x.isNotEmpty;
          return Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: has ? Colors.white70 : Colors.transparent, shape: BoxShape.circle),
          );
        },
      ),
      SectionBar(fmtDate(context, _sel), icon: Icons.event_note_rounded, onAdd: () => _addEvent()),
      for (var i = 0; i < ev.length; i++)
        ListTile(
          leading: Text((ev[i]['time'] as String? ?? '').isEmpty ? '•' : ev[i]['time'] as String,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          title: Text(ev[i]['text'] as String? ?? ''),
          onTap: () => _addEvent(i),
          trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => _removeEvent(i)),
        ),
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(L(t, 'mood'), style: const TextStyle(color: Colors.white70)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (var i = 0; i < kMoods.length; i++)
              IconButton(
                onPressed: () => _mood(mood == i ? null : i),
                icon: Opacity(opacity: mood == null || mood == i ? 1 : 0.35, child: Text(kMoods[i], style: const TextStyle(fontSize: 28))),
              ),
          ]),
          AppTextField(
            controller: _journal,
            label: L(t, 'journal'),
            maxLines: 16,
            minLines: 6,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 700), _flush);
            },
          ),
        ]),
      ),
    ]);
  }
}

// =========================================================== ders programı

class TimetableTool extends StatefulWidget {
  final ToolContext t;
  const TimetableTool(this.t, {super.key});

  @override
  State<TimetableTool> createState() => _TimetableToolState();
}

class _TimetableToolState extends State<TimetableTool> {
  int _days = 5;
  int _periods = 7;
  List<String> _times = [];
  Map<String, Object?> _cells = {};
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await t.store.readMap('cfg');
    _days = clampInt((m['days'] as num?)?.toInt() ?? 5, 5, 7);
    _periods = clampInt((m['periods'] as num?)?.toInt() ?? 7, 1, 14);
    _times = (m['times'] as List? ?? const []).cast<String>().toList();
    _cells = await t.store.readMap('cells');
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveCfg() => t.store.writeMap('cfg', {'days': _days, 'periods': _periods, 'times': _times});

  String _time(int p) => p < _times.length ? _times[p] : '';

  Map<String, Object?>? _cell(int d, int p) => (_cells['$d-$p'] as Map?)?.cast<String, Object?>();

  Future<void> _editTime(int p) async {
    final cur = _time(p);
    final tm = await showTimePicker(
      context: context,
      initialTime: cur.contains(':')
          ? TimeOfDay(hour: int.parse(cur.split(':')[0]), minute: int.parse(cur.split(':')[1]))
          : TimeOfDay(hour: 8 + p, minute: 0),
    );
    if (tm == null) return;
    while (_times.length <= p) {
      _times.add('');
    }
    setState(() => _times[p] = '${tm.hour.toString().padLeft(2, '0')}:${tm.minute.toString().padLeft(2, '0')}');
    await _saveCfg();
  }

  Future<void> _editCell(int d, int p) async {
    final cur = _cell(d, p) ?? {};
    final subj = TextEditingController(text: cur['s'] as String? ?? '');
    final room = TextEditingController(text: cur['r'] as String? ?? '');
    var color = (cur['c'] as num?)?.toInt() ?? 0;
    // Daha önce kullanılan dersler (hızlı seçim).
    final known = <String, int>{};
    for (final v in _cells.values) {
      final m = (v as Map).cast<String, Object?>();
      final s = m['s'] as String? ?? '';
      if (s.isNotEmpty) known[s] = (m['c'] as num?)?.toInt() ?? 0;
    }
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
              Text('${weekdayNames(t)[d]} · ${p + 1}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (known.isNotEmpty)
                Wrap(spacing: 6, children: [
                  for (final e in known.entries)
                    ActionChip(
                      label: Text(e.key),
                      backgroundColor: paletteAt(e.value).withValues(alpha: 0.3),
                      onPressed: () => set(() {
                        subj.text = e.key;
                        color = e.value;
                      }),
                    ),
                ]),
              AppTextField(controller: subj, label: L(t, 'lesson'), autofocus: cur.isEmpty && known.isEmpty),
              AppTextField(controller: room, label: L(t, 'room')),
              ColorRow(value: color, onChanged: (v) => set(() => color = v)),
              const SizedBox(height: 12),
              Row(children: [
                if (cur.isNotEmpty)
                  TextButton.icon(onPressed: () => Navigator.pop(c, 'clear'), icon: const Icon(Icons.delete_outline_rounded), label: Text(L(t, 'clear'))),
                const Spacer(),
                FilledButton.icon(onPressed: () => Navigator.pop(c, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
              ]),
            ]),
          ),
        ),
      ),
    );
    final s = subj.text.trim(), r = room.text.trim();
    subj.dispose();
    room.dispose();
    if (res == null) return;
    setState(() {
      if (res == 'clear' || s.isEmpty) {
        _cells.remove('$d-$p');
      } else {
        _cells['$d-$p'] = {'s': s, 'r': r, 'c': color};
      }
    });
    await t.store.writeMap('cells', _cells);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final names = weekdayNames(t);
    final wd = DateTime.now().weekday - 1;
    final todayLessons = wd < _days
        ? [for (var p = 0; p < _periods; p++) if (_cell(wd, p) != null) (p, _cell(wd, p)!)]
        : <(int, Map<String, Object?>)>[];
    const cw = 104.0, ch = 62.0;
    return ToolList(children: [
      AppPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${L(t, 'today')} · ${wd < names.length ? names[wd] : ''}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (todayLessons.isEmpty) const Text('—', style: TextStyle(color: Colors.white60)),
          for (final (p, c) in todayLessons)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                CircleAvatar(radius: 12, backgroundColor: paletteAt((c['c'] as num?)?.toInt() ?? 0), child: Text('${p + 1}', style: const TextStyle(fontSize: 11, color: Colors.black))),
                const SizedBox(width: 8),
                Expanded(child: Text('${c['s']}${(c['r'] as String? ?? '').isEmpty ? '' : ' · ${c['r']}'}')),
                Text(_time(p), style: const TextStyle(color: Colors.white70)),
              ]),
            ),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 56),
            for (var d = 0; d < _days; d++)
              SizedBox(
                width: cw,
                child: Text(d < names.length ? names[d] : '', textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, color: d == wd ? AppLook.of(context).accent : null)),
              ),
          ]),
          for (var p = 0; p < _periods; p++)
            Row(children: [
              InkWell(
                onTap: () => _editTime(p),
                child: SizedBox(
                  width: 56,
                  height: ch,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${p + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(_time(p).isEmpty ? '⏱' : _time(p), style: const TextStyle(fontSize: 11, color: Colors.white60)),
                  ]),
                ),
              ),
              for (var d = 0; d < _days; d++)
                Builder(builder: (_) {
                  final c = _cell(d, p);
                  return InkWell(
                    onTap: () => _editCell(d, p),
                    child: Container(
                      width: cw - 4,
                      height: ch - 4,
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: c == null ? Colors.white.withValues(alpha: 0.04) : paletteAt((c['c'] as num?)?.toInt() ?? 0).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: c == null
                          ? null
                          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(c['s'] as String? ?? '', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              if ((c['r'] as String? ?? '').isNotEmpty)
                                Text(c['r'] as String, maxLines: 1, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                            ]),
                    ),
                  );
                }),
            ]),
        ]),
      ),
      AppPanel(
        child: Column(children: [
          Pick<int>(
            label: L(t, 'days'),
            values: const [5, 6, 7],
            text: (v) => '$v',
            value: _days,
            onChanged: (v) {
              setState(() => _days = v);
              _saveCfg();
            },
          ),
          Pick<int>(
            label: L(t, 'periods'),
            values: [for (var i = 1; i <= 14; i++) i],
            text: (v) => '$v',
            value: _periods,
            onChanged: (v) {
              setState(() => _periods = v);
              _saveCfg();
            },
          ),
        ]),
      ),
    ]);
  }
}

// ============================================================ vardiya

class ShiftTool extends StatefulWidget {
  final ToolContext t;
  const ShiftTool(this.t, {super.key});

  @override
  State<ShiftTool> createState() => _ShiftToolState();
}

class _ShiftToolState extends State<ShiftTool> {
  List<ShiftKind> _kinds = [];
  Map<String, String> _plan = {};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _brush;
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final k = await t.store.readList('kinds');
    if (k.isEmpty) {
      final n = Ls(t, 'shift_defaults');
      String nm(int i) => i < n.length ? n[i] : '${i + 1}';
      _kinds = [
        ShiftKind('d', nm(0), 8 * 60, 16 * 60, 2),
        ShiftKind('e', nm(1), 16 * 60, 0, 3),
        ShiftKind('n', nm(2), 0, 8 * 60, 4),
        ShiftKind('o', nm(3), 0, 0, 7),
      ];
    } else {
      _kinds = k.map(ShiftKind.fromJson).toList();
    }
    final p = await t.store.readMap('plan');
    _plan = p.map((key, v) => MapEntry(key, v as String? ?? ''));
    if (!mounted) return;
    setState(() {
      _brush = _kinds.isEmpty ? null : _kinds.first.id;
      _loaded = true;
    });
  }

  Future<void> _saveKinds() => t.store.writeList('kinds', [for (final k in _kinds) k.toJson()]);
  Future<void> _savePlan() => t.store.writeMap('plan', _plan);

  ShiftKind? _kind(String? id) {
    for (final k in _kinds) {
      if (k.id == id) return k;
    }
    return null;
  }

  String _hm(int m) => '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _tapDay(DateTime d) async {
    final k = dayKey(d);
    setState(() {
      if (_plan[k] == _brush || _brush == null) {
        _plan.remove(k);
      } else {
        _plan[k] = _brush!;
      }
    });
    await _savePlan();
  }

  Future<void> _editKind([ShiftKind? orig]) async {
    final name = TextEditingController(text: orig?.name ?? '');
    var start = orig?.start ?? 9 * 60, end = orig?.end ?? 17 * 60, color = orig?.color ?? _kinds.length % kPalette.length;
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          Future<void> pickTime(bool isStart) async {
            final v = isStart ? start : end;
            final tm = await showTimePicker(context: c, initialTime: TimeOfDay(hour: v ~/ 60 % 24, minute: v % 60));
            if (tm == null) return;
            set(() {
              if (isStart) {
                start = tm.hour * 60 + tm.minute;
              } else {
                end = tm.hour * 60 + tm.minute;
              }
            });
          }

          final mins = ShiftKind('', '', start, end, 0).minutes;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(L(t, 'shift'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  if (orig != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        if (await confirmDelete(c, t) && c.mounted) Navigator.pop(c, 'del');
                      },
                    ),
                ]),
                AppTextField(controller: name, label: L(t, 'name'), autofocus: orig == null),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login_rounded),
                  title: Text(L(t, 'start')),
                  trailing: Text(_hm(start), style: const TextStyle(fontSize: 18)),
                  onTap: () => pickTime(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded),
                  title: Text(L(t, 'stop')),
                  trailing: Text(_hm(end), style: const TextStyle(fontSize: 18)),
                  onTap: () => pickTime(false),
                ),
                Text(mins == 0 ? L(t, 'off_day') : '${L(t, 'hours')}: ${fmtHours(Duration(minutes: mins))}',
                    style: const TextStyle(color: Colors.white70)),
                ColorRow(value: color, onChanged: (v) => set(() => color = v)),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: () => Navigator.pop(c, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
              ]),
            ),
          );
        },
      ),
    );
    final nm = name.text.trim();
    name.dispose();
    if (res == null) return;
    setState(() {
      if (res == 'del' && orig != null) {
        _kinds.removeWhere((k) => k.id == orig.id);
        _plan.removeWhere((_, v) => v == orig.id);
        if (_brush == orig.id) _brush = _kinds.isEmpty ? null : _kinds.first.id;
      } else {
        final k = ShiftKind(orig?.id ?? newId(), nm.isEmpty ? '?' : nm, start, end, color);
        final i = _kinds.indexWhere((x) => x.id == k.id);
        if (i >= 0) {
          _kinds[i] = k;
        } else {
          _kinds.add(k);
        }
        _brush = k.id;
      }
    });
    await _saveKinds();
    await _savePlan();
  }

  Future<void> _rotation() async {
    final pattern = <String>[];
    var from = dateOnly(DateTime.now());
    var days = 90;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(L(t, 'rotation'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in _kinds)
                ActionChip(
                  avatar: CircleAvatar(backgroundColor: paletteAt(k.color)),
                  label: Text(k.name),
                  onPressed: () => set(() => pattern.add(k.id)),
                ),
              ActionChip(label: Text('— ${L(t, 'off_day')}'), onPressed: () => set(() => pattern.add(''))),
            ]),
            const SizedBox(height: 8),
            AppPanel(
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final (i, id) in pattern.indexed)
                  Chip(
                    label: Text('${i + 1}. ${_kind(id)?.name ?? '—'}'),
                    onDeleted: () => set(() => pattern.removeAt(i)),
                  ),
              ]),
            ),
            DateRow(label: L(t, 'start_date'), value: from, clearable: false, onChanged: (d) => set(() => from = d ?? from)),
            Pick<int>(
              label: L(t, 'days'),
              values: const [28, 30, 60, 90, 180, 365],
              text: (v) => '$v',
              value: days,
              onChanged: (v) => set(() => days = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: pattern.isEmpty ? null : () => Navigator.pop(c, true),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: Text(L(t, 'apply_rotation')),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    final m = applyRotation(pattern, from, days);
    setState(() {
      m.forEach((k, v) {
        if (v.isEmpty) {
          _plan.remove(k);
        } else {
          _plan[k] = v;
        }
      });
    });
    await _savePlan();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final total = monthMinutes(_plan, _kinds, _month.year, _month.month);
    final counts = <String, int>{};
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    for (var d = 1; d <= days; d++) {
      final id = _plan[dayKey(DateTime(_month.year, _month.month, d))];
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return ToolList(children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final k in _kinds)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: () => _editKind(k),
                child: ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: paletteAt(k.color)),
                  label: Text(k.minutes == 0 ? k.name : '${k.name} ${_hm(k.start)}–${_hm(k.end)}'),
                  selected: _brush == k.id,
                  onSelected: (_) => setState(() => _brush = k.id),
                ),
              ),
            ),
          IconButton(onPressed: () => _editKind(), icon: const Icon(Icons.add_rounded)),
          if (_kind(_brush) != null)
            IconButton(onPressed: () => _editKind(_kind(_brush)), icon: const Icon(Icons.edit_rounded)),
        ]),
      ),
      MonthGrid(
        month: _month,
        weekdays: weekdayNames(t),
        onTap: _tapDay,
        onMonth: (m) => setState(() => _month = m),
        fill: (d) {
          final k = _kind(_plan[dayKey(d)]);
          return k == null ? null : paletteAt(k.color).withValues(alpha: 0.45);
        },
        marker: (d) {
          final k = _kind(_plan[dayKey(d)]);
          if (k == null) return const SizedBox.shrink();
          final n = k.name;
          return Text(n.substring(0, math.min<int>(n.length, 3)), style: const TextStyle(fontSize: 10));
        },
      ),
      AppResult(label: L(t, 'month_hours'), value: fmtHours(Duration(minutes: total)), lang: t.lang, big: true),
      AppPanel(
        child: Column(children: [
          for (final k in _kinds)
            if ((counts[k.id] ?? 0) > 0)
              Row(children: [
                CircleAvatar(radius: 7, backgroundColor: paletteAt(k.color)),
                const SizedBox(width: 8),
                Expanded(child: Text(k.name)),
                Text('${counts[k.id]} × ${fmtHours(Duration(minutes: k.minutes))}'),
              ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _kinds.isEmpty ? null : _rotation, icon: const Icon(Icons.autorenew_rounded), label: Text(L(t, 'rotation'))),
        ]),
      ),
    ]);
  }
}
