/// Planlama uygulamaları: alışkanlık, pomodoro, hatırlatıcı, zaman takibi.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../logic/plan_logic.dart';
import '../platform/notify.dart';

/// Bildirim izni: önce açıklama, sonra sistem isteği.
Future<bool> askNotify(BuildContext context, ToolContext t) async {
  if (!Notify.supported) return false;
  if (!await rationaleOnce(context, t, 'notify', Icons.notifications_active_rounded)) return false;
  final ok = await Notify.requestPermission();
  if (!ok && context.mounted) showPermissionDenied(context, t.lang);
  return ok;
}

// ============================================================== alışkanlık

class HabitTool extends StatefulWidget {
  final ToolContext t;
  const HabitTool(this.t, {super.key});

  @override
  State<HabitTool> createState() => _HabitToolState();
}

class _HabitToolState extends State<HabitTool> {
  List<Map<String, Object?>> _h = [];
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('habits').then((l) {
      if (!mounted) return;
      setState(() {
        _h = l;
        _loaded = true;
      });
    });
  }

  Set<String> _days(Map<String, Object?> h) => {...(h['days'] as List? ?? const []).cast<String>()};

  Future<void> _save() => t.store.writeList('habits', _h);

  Future<void> _toggle(Map<String, Object?> h, DateTime d) async {
    final s = _days(h);
    final k = dayKey(d);
    if (!s.remove(k)) {
      s.add(k);
      HapticFeedback.lightImpact();
    }
    setState(() => h['days'] = s.toList()..sort());
    await _save();
  }

  Future<void> _add() async {
    final n = await askText(context, t, L(t, 'habit'));
    if (n == null) return;
    setState(() => _h.add({'id': newId(), 'name': n, 'color': _h.length % kPalette.length, 'days': <String>[]}));
    await _save();
  }

  Future<void> _menu(Map<String, Object?> h) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_rounded), title: Text(L(t, 'rename')), onTap: () => Navigator.pop(c, 'r')),
          ListTile(leading: const Icon(Icons.palette_rounded), title: Text(L(t, 'color')), onTap: () => Navigator.pop(c, 'c')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded), title: Text(L(t, 'delete')), onTap: () => Navigator.pop(c, 'd')),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    if (a == 'r') {
      final n = await askText(context, t, L(t, 'rename'), initial: h['name'] as String? ?? '');
      if (n != null) setState(() => h['name'] = n);
    } else if (a == 'c') {
      setState(() => h['color'] = (((h['color'] as num?)?.toInt() ?? 0) + 1) % kPalette.length);
    } else if (a == 'd') {
      if (await confirmDelete(context, t)) setState(() => _h.remove(h));
    }
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final today = dateOnly(DateTime.now());
    final names = weekdayNames(t);
    final doneToday = _h.where((h) => _days(h).contains(dayKey(today))).length;
    return Stack(children: [
      ToolList(children: [
        if (_h.isNotEmpty)
          AppResult(label: L(t, 'today'), value: '$doneToday / ${_h.length}', lang: t.lang, big: true),
        if (_h.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.repeat_rounded),
        for (final h in _h) _card(h, today, names),
      ]),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: null,
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: Text(L(t, 'habit')),
        ),
      ),
    ]);
  }

  Widget _card(Map<String, Object?> h, DateTime today, List<String> names) {
    final days = _days(h);
    final color = paletteAt((h['color'] as num?)?.toInt() ?? 0);
    final streak = currentStreak(days, today);
    final best = bestStreak(days);
    final doneNow = days.contains(dayKey(today));
    return AppPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onLongPress: () => _menu(h),
              onTap: () => _menu(h),
              child: Text(h['name'] as String? ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: doneNow ? color : Colors.white12),
            icon: Icon(doneNow ? Icons.check_rounded : Icons.circle_outlined, color: doneNow ? Colors.black : Colors.white),
            onPressed: () => _toggle(h, today),
          ),
        ]),
        Text('🔥 ${L(t, 'streak')}: $streak · ${L(t, 'best_streak')}: $best', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 6; i >= 0; i--)
            Builder(builder: (_) {
              final d = DateTime(today.year, today.month, today.day - i);
              final on = days.contains(dayKey(d));
              return InkWell(
                onTap: () => _toggle(h, d),
                borderRadius: BorderRadius.circular(20),
                child: Column(children: [
                  Text(names.length == 7 ? names[d.weekday - 1] : '${d.weekday}',
                      style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  const SizedBox(height: 4),
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: on ? color : Colors.white10,
                    child: Text('${d.day}', style: TextStyle(fontSize: 12, color: on ? Colors.black : Colors.white70)),
                  ),
                ]),
              );
            }),
        ]),
      ]),
    );
  }
}

// ================================================================ pomodoro

class PomodoroTool extends StatefulWidget {
  final ToolContext t;
  const PomodoroTool(this.t, {super.key});

  @override
  State<PomodoroTool> createState() => _PomodoroToolState();
}

class _PomodoroToolState extends State<PomodoroTool> {
  static const _nid = 7101;
  int _focus = 25, _short = 5, _long = 15, _every = 4;
  PomoPhase _phase = PomoPhase.focus;
  int? _endAt;
  int _left = 25 * 60;
  int _doneToday = 0;
  int _cycle = 0;
  bool _awake = false;
  Timer? _tick;
  bool _loaded = false;

  ToolContext get t => widget.t;

  int _len(PomoPhase p) => 60 * switch (p) { PomoPhase.focus => _focus, PomoPhase.shortBreak => _short, PomoPhase.longBreak => _long };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await t.store.readMap('state');
    _focus = (m['focus'] as num?)?.toInt() ?? 25;
    _short = (m['short'] as num?)?.toInt() ?? 5;
    _long = (m['long'] as num?)?.toInt() ?? 15;
    _every = (m['every'] as num?)?.toInt() ?? 4;
    _phase = PomoPhase.values[math.max<int>(0, math.min<int>((m['phase'] as num?)?.toInt() ?? 0, 2))];
    _cycle = (m['cycle'] as num?)?.toInt() ?? 0;
    _endAt = (m['endAt'] as num?)?.toInt();
    _left = (m['left'] as num?)?.toInt() ?? _len(_phase);
    _doneToday = await t.store.readInt('done.${dayKey(DateTime.now())}');
    if (!mounted) return;
    setState(() => _loaded = true);
    if (_endAt != null) _run();
  }

  Future<void> _persist() => t.store.writeMap('state', {
        'focus': _focus, 'short': _short, 'long': _long, 'every': _every,
        'phase': _phase.index, 'cycle': _cycle, 'endAt': _endAt, 'left': _left,
      });

  void _run() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _update());
    _update();
  }

  void _update() {
    final e = _endAt;
    if (e == null) return;
    final left = ((e - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    if (left <= 0) {
      _finish();
    } else if (mounted) {
      setState(() => _left = left);
    }
  }

  Future<void> _finish() async {
    _tick?.cancel();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    if (_phase == PomoPhase.focus) {
      _doneToday++;
      _cycle++;
      await t.store.write('done.${dayKey(DateTime.now())}', '$_doneToday');
    }
    final next = nextPhase(_phase, _cycle, _every);
    if (!mounted) return;
    setState(() {
      _phase = next;
      _endAt = null;
      _left = _len(next);
    });
    await _persist();
  }

  Future<void> _start() async {
    if (Notify.supported && !await t.store.readBool('asked_notify')) {
      await t.store.writeBool('asked_notify', true);
      if (mounted) await askNotify(context, t);
    }
    final end = DateTime.now().add(Duration(seconds: _left));
    setState(() => _endAt = end.millisecondsSinceEpoch);
    final title = L(t, _phaseKey(_phase));
    await Notify.schedule(_nid, title, L(t, _phase == PomoPhase.focus ? 'focus_done' : 'break_done'), end);
    await _persist();
    if (_awake) unawaited(WakelockPlus.enable());
    _run();
  }

  Future<void> _pause() async {
    _tick?.cancel();
    setState(() => _endAt = null);
    await Notify.cancel(_nid);
    await _persist();
  }

  Future<void> _reset() async {
    _tick?.cancel();
    await Notify.cancel(_nid);
    setState(() {
      _endAt = null;
      _left = _len(_phase);
    });
    await _persist();
  }

  Future<void> _skip() async {
    await Notify.cancel(_nid);
    final next = nextPhase(_phase, _phase == PomoPhase.focus ? _cycle + 1 : _cycle, _every);
    if (_phase == PomoPhase.focus) _cycle++;
    _tick?.cancel();
    setState(() {
      _phase = next;
      _endAt = null;
      _left = _len(next);
    });
    await _persist();
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_awake) unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final running = _endAt != null;
    final total = _len(_phase);
    final look = AppLook.of(context);
    final color = _phase == PomoPhase.focus ? look.accent : Colors.lightGreenAccent;
    List<int> opts(int a, int b, int step) => [for (var i = a; i <= b; i += step) i];
    return ToolList(children: [
      Choice<PomoPhase>(
        values: PomoPhase.values,
        labels: [L(t, 'focus'), L(t, 'short_break'), L(t, 'long_break')],
        selected: _phase,
        onChanged: running
            ? (_) {}
            : (p) {
                setState(() {
                  _phase = p;
                  _left = _len(p);
                });
                _persist();
              },
      ),
      const SizedBox(height: 12),
      Center(
        child: SizedBox(
          width: 260,
          height: 260,
          child: Stack(fit: StackFit.expand, children: [
            CircularProgressIndicator(
              value: total == 0 ? 0 : 1 - _left / total,
              strokeWidth: 12,
              color: color,
              backgroundColor: Colors.white12,
            ),
            Center(
              child: Text(fmtDuration(Duration(seconds: _left)),
                  style: TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: look.number)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: L(t, 'reset'), iconSize: 32, onPressed: _reset, icon: const Icon(Icons.replay_rounded)),
        const SizedBox(width: 16),
        FloatingActionButton.large(
          heroTag: null,
          onPressed: running ? _pause : _start,
          child: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 48),
        ),
        const SizedBox(width: 16),
        IconButton(tooltip: '⏭', iconSize: 32, onPressed: _skip, icon: const Icon(Icons.skip_next_rounded)),
      ]),
      AppResult(label: L(t, 'sessions_today'), value: '$_doneToday', lang: t.lang),
      AppPanel(
        child: Column(children: [
          for (final (label, value, list, set) in [
            (L(t, 'focus'), _focus, opts(5, 90, 5), (int v) => _focus = v),
            (L(t, 'short_break'), _short, opts(1, 30, 1), (int v) => _short = v),
            (L(t, 'long_break'), _long, opts(5, 60, 5), (int v) => _long = v),
            (L(t, 'long_every'), _every, opts(2, 8, 1), (int v) => _every = v),
          ])
            Pick<int>(
              label: label,
              values: list.contains(value) ? list : [...list, value],
              text: (v) => '$v',
              value: value,
              onChanged: (v) {
                if (running) return;
                setState(() {
                  set(v);
                  _left = _len(_phase);
                });
                _persist();
              },
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(L(t, 'keep_awake')),
            value: _awake,
            onChanged: (v) {
              setState(() => _awake = v);
              if (v && running) {
                WakelockPlus.enable();
              } else if (!v) {
                WakelockPlus.disable();
              }
            },
          ),
        ]),
      ),
    ]);
  }
}

/// Evrenin etiket anahtarı.
String _phaseKey(PomoPhase p) => switch (p) {
      PomoPhase.focus => 'focus',
      PomoPhase.shortBreak => 'short_break',
      PomoPhase.longBreak => 'long_break',
    };

// ============================================================= hatırlatıcı

class ReminderTool extends StatefulWidget {
  final ToolContext t;
  const ReminderTool(this.t, {super.key});

  @override
  State<ReminderTool> createState() => _ReminderToolState();
}

class _ReminderToolState extends State<ReminderTool> {
  static const _per = 12;
  List<Map<String, Object?>> _r = [];
  bool _loaded = false;
  Timer? _tick;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await t.store.readList('items');
    if (!mounted) return;
    setState(() {
      _r = l;
      _loaded = true;
    });
    // Tekrarlayanların sonraki zamanlarını tazele.
    for (final r in _r) {
      await _schedule(r);
    }
  }

  Future<void> _save() => t.store.writeList('items', _r);

  DateTime _at(Map<String, Object?> r) => DateTime.fromMillisecondsSinceEpoch((r['at'] as num?)?.toInt() ?? 0);
  int _rep(Map<String, Object?> r) => (r['repeat'] as num?)?.toInt() ?? 0;
  int _nid(Map<String, Object?> r) => (r['nid'] as num?)?.toInt() ?? 0;

  DateTime? _next(Map<String, Object?> r) {
    final n = nextOccurrences(_at(r), _rep(r), DateTime.now(), 1);
    return n.isEmpty ? null : n.first;
  }

  Future<void> _cancel(Map<String, Object?> r) async {
    for (var i = 0; i < _per; i++) {
      await Notify.cancel(_nid(r) * _per + i);
    }
  }

  Future<void> _schedule(Map<String, Object?> r) async {
    await _cancel(r);
    if (r['on'] == false) return;
    final times = nextOccurrences(_at(r), _rep(r), DateTime.now(), _per);
    for (var i = 0; i < times.length; i++) {
      await Notify.schedule(_nid(r) * _per + i, r['title'] as String? ?? '', r['note'] as String? ?? '', times[i]);
    }
  }

  Future<void> _edit([Map<String, Object?>? orig]) async {
    final r = Map<String, Object?>.from(orig ??
        {
          'title': '',
          'at': DateTime.now().add(const Duration(hours: 1)).copyWith(second: 0, millisecond: 0, microsecond: 0).millisecondsSinceEpoch,
          'repeat': 0,
          'on': true,
        });
    final title = TextEditingController(text: r['title'] as String? ?? '');
    final note = TextEditingController(text: r['note'] as String? ?? '');
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
                Expanded(child: Text(L(t, 'reminder'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (orig != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (await confirmDelete(c, t) && c.mounted) Navigator.pop(c, 'del');
                    },
                  ),
              ]),
              AppTextField(controller: title, label: L(t, 'title'), autofocus: orig == null),
              AppTextField(controller: note, label: L(t, 'note'), maxLines: 4),
              DateRow(
                label: L(t, 'at_time'),
                value: _at(r),
                withTime: true,
                clearable: false,
                onChanged: (d) => set(() => r['at'] = d?.millisecondsSinceEpoch ?? r['at']),
              ),
              Pick<int>(
                label: L(t, 'repeat'),
                values: const [0, 1, 2, 3],
                text: (i) => Ls(t, 'repeat_opts')[i],
                value: _rep(r),
                onChanged: (v) => set(() => r['repeat'] = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => Navigator.pop(c, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
            ]),
          ),
        ),
      ),
    );
    final tt = title.text.trim(), nt = note.text.trim();
    title.dispose();
    note.dispose();
    if (res == null || !mounted) return;
    if (res == 'del') {
      await _cancel(r);
      setState(() => _r.removeWhere((x) => x['id'] == orig?['id']));
      await _save();
      return;
    }
    r['title'] = tt.isEmpty ? L(t, 'reminder') : tt;
    r['note'] = nt;
    r['on'] = true;
    if (orig == null) {
      r['id'] = newId();
      final used = _r.map(_nid).toSet();
      var n = 1;
      while (used.contains(n)) {
        n++;
      }
      r['nid'] = n;
      setState(() => _r.add(r));
    } else {
      final i = _r.indexWhere((x) => x['id'] == orig['id']);
      setState(() => _r[i] = r);
    }
    await _save();
    if (mounted && Notify.supported && !await t.store.readBool('asked_notify')) {
      await t.store.writeBool('asked_notify', true);
      if (mounted) await askNotify(context, t);
    }
    await _schedule(r);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final sorted = [..._r]..sort((a, b) {
        final na = _next(a), nb = _next(b);
        if ((na == null) != (nb == null)) return na == null ? 1 : -1;
        if (na == null || nb == null) return 0;
        return na.compareTo(nb);
      });
    final now = DateTime.now();
    return Stack(children: [
      ToolList(children: [
        if (!Notify.supported) AppInfoCard(L(t, 'web_remind'), icon: Icons.notifications_off_rounded),
        if (_r.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.notifications_none_rounded),
        for (final r in sorted)
          Builder(builder: (_) {
            final n = _next(r);
            final active = r['on'] != false && n != null;
            final dueNow = !Notify.supported && n == null && _at(r).isBefore(now) && _rep(r) == 0;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                onTap: () => _edit(r),
                leading: Icon(active ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                    color: dueNow ? Colors.amber : null),
                title: Text(r['title'] as String? ?? '', style: TextStyle(color: active ? null : Colors.white54)),
                subtitle: Text([
                  fmtDateTime(context, n ?? _at(r)),
                  if (_rep(r) > 0) Ls(t, 'repeat_opts')[_rep(r)],
                ].join(' · ')),
                trailing: Switch(
                  value: r['on'] != false,
                  onChanged: (v) async {
                    setState(() => r['on'] = v);
                    await _save();
                    await _schedule(r);
                  },
                ),
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
          icon: const Icon(Icons.add_alert_rounded),
          label: Text(L(t, 'reminder')),
        ),
      ),
    ]);
  }
}

// ============================================================ zaman takibi

class TimeTrackTool extends StatefulWidget {
  final ToolContext t;
  const TimeTrackTool(this.t, {super.key});

  @override
  State<TimeTrackTool> createState() => _TimeTrackToolState();
}

class _TimeTrackToolState extends State<TimeTrackTool> {
  List<String> _projects = [];
  List<Map<String, Object?>> _entries = [];
  String? _runP;
  int? _runS;
  String? _sel;
  Timer? _tick;
  bool _loaded = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_runS != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _projects = await t.store.readStrings('projects');
    _entries = await t.store.readList('entries');
    final run = await t.store.readMap('running');
    _runP = run['p'] as String?;
    _runS = (run['s'] as num?)?.toInt();
    if (!mounted) return;
    setState(() {
      _sel = _runP ?? (_projects.isEmpty ? null : _projects.first);
      _loaded = true;
    });
  }

  List<TimeEntry> get _list => [
        for (final e in _entries)
          TimeEntry(e['p'] as String? ?? '', (e['s'] as num?)?.toInt() ?? 0, (e['e'] as num?)?.toInt() ?? 0),
        if (_runP != null && _runS != null) TimeEntry(_runP!, _runS!, DateTime.now().millisecondsSinceEpoch),
      ];

  Future<void> _addProject() async {
    final n = await askText(context, t, L(t, 'project'));
    if (n == null || _projects.contains(n)) return;
    setState(() {
      _projects.add(n);
      _sel = n;
    });
    await t.store.writeStrings('projects', _projects);
  }

  Future<void> _toggle() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_runS != null) {
      _entries.insert(0, {'p': _runP, 's': _runS, 'e': now});
      setState(() {
        _runP = null;
        _runS = null;
      });
      await t.store.writeList('entries', _entries);
      await t.store.writeMap('running', {});
    } else {
      if (_sel == null) {
        await _addProject();
        if (_sel == null) return;
      }
      setState(() {
        _runP = _sel;
        _runS = now;
      });
      await t.store.writeMap('running', {'p': _runP, 's': _runS});
    }
  }

  Future<void> _csv() async {
    if (!await extraGate(context, t, 'csv')) return;
    final rows = <List<String>>[
      [L(t, 'project'), L(t, 'start'), L(t, 'stop'), L(t, 'minutes')],
      for (final e in _list)
        [
          e.project,
          DateTime.fromMillisecondsSinceEpoch(e.start).toIso8601String(),
          DateTime.fromMillisecondsSinceEpoch(e.end).toIso8601String(),
          '${e.duration.inMinutes}',
        ],
    ];
    await shareBytes(Uint8List.fromList(utf8.encode('﻿${toCsv(rows)}')), 'time.csv', 'text/csv');
  }

  Widget _totals(String label, DateTime from, DateTime to) {
    final m = totalsByProject(_list, from, to);
    final sum = m.values.fold<Duration>(Duration.zero, (a, b) => a + b);
    return AppPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          Text(fmtHours(sum), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        for (final e in (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(child: Text(e.key)),
              SizedBox(
                width: 90,
                child: LinearProgressIndicator(
                  value: sum.inSeconds == 0 ? 0 : e.value.inSeconds / sum.inSeconds,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(width: 8),
              Text(fmtHours(e.value)),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final now = DateTime.now();
    final running = _runS != null;
    final elapsed = running ? Duration(milliseconds: now.millisecondsSinceEpoch - _runS!) : Duration.zero;
    final today = dateOnly(now);
    final ws = weekStart(now);
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          Row(children: [
            Expanded(
              child: _projects.isEmpty
                  ? Text(L(t, 'project'), style: const TextStyle(color: Colors.white60))
                  : Pick<String>(
                      label: L(t, 'project'),
                      values: _projects,
                      text: (s) => s,
                      value: _sel ?? _projects.first,
                      onChanged: (v) {
                        if (!running) setState(() => _sel = v);
                      },
                    ),
            ),
            IconButton(onPressed: _addProject, icon: const Icon(Icons.add_rounded)),
          ]),
          Text(fmtDuration(elapsed), style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: AppLook.of(context).number)),
          if (running) Text('${L(t, 'running')}: $_runP', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _toggle,
            icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(L(t, running ? 'stop' : 'start')),
          ),
        ]),
      ),
      _totals(L(t, 'today'), today, today.add(const Duration(days: 1))),
      _totals(L(t, 'this_week'), ws, ws.add(const Duration(days: 7))),
      SectionBar(L(t, 'entries'), icon: Icons.list_alt_rounded, actions: [
        IconButton(onPressed: _entries.isEmpty ? null : _csv, icon: const Icon(Icons.ios_share_rounded)),
      ]),
      if (_entries.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.timer_outlined),
      for (final e in _entries.take(math.min<int>(_entries.length, 60)))
        Builder(builder: (_) {
          final s = DateTime.fromMillisecondsSinceEpoch((e['s'] as num?)?.toInt() ?? 0);
          final en = DateTime.fromMillisecondsSinceEpoch((e['e'] as num?)?.toInt() ?? 0);
          return ListTile(
            title: Text(e['p'] as String? ?? ''),
            subtitle: Text('${fmtDate(context, s)} · ${fmtTime(context, s)}–${fmtTime(context, en)}'),
            trailing: Text(fmtHours(en.difference(s)), style: const TextStyle(fontWeight: FontWeight.w700)),
            onLongPress: () async {
              if (await confirmDelete(context, t)) {
                setState(() => _entries.remove(e));
                await t.store.writeList('entries', _entries);
              }
            },
          );
        }),
    ]);
  }
}
