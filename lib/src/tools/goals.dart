/// Hedef ve OKR takibi: hedefler, ölçülebilir anahtar sonuçlar, ilerleme
/// girişleri (geçmişiyle), zamana göre durum (yolunda / risk / geride) ve
/// dönem (çeyrek) süzgeci. Veriler yalnızca cihazda.
library;

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../logic/goal_logic.dart';

typedef Js = Map<String, Object?>;

List<Js> _maps(Object? v) => [for (final e in (v as List? ?? const [])) (e as Map).cast<String, Object?>()];
double _d(Object? v, [double f = 0]) => (v as num?)?.toDouble() ?? f;
String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

class GoalsTool extends StatefulWidget {
  final ToolContext t;
  const GoalsTool(this.t, {super.key});

  @override
  State<GoalsTool> createState() => _GoalsToolState();
}

class _GoalsToolState extends State<GoalsTool> {
  List<Js> _goals = [];
  bool _loaded = false;
  String _period = '';
  bool _showDone = false;
  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await t.store.readList('goals');
    if (!mounted) return;
    setState(() {
      _goals = g;
      _loaded = true;
    });
  }

  Future<void> _save() => t.store.writeList('goals', _goals);

  DateTime _start(Js g) => DateTime.fromMillisecondsSinceEpoch((g['start'] as num?)?.toInt() ?? 0);
  DateTime _due(Js g) => DateTime.fromMillisecondsSinceEpoch((g['due'] as num?)?.toInt() ?? 0);

  double _kr(Js k) => (k['kind'] == 'done')
      ? (k['cur'] == 1 ? 1.0 : 0.0)
      : krProgress(_d(k['start']), _d(k['target'], 1), _d(k['cur']));

  double _progress(Js g) => objectiveProgress([for (final k in _maps(g['krs'])) (_kr(k), _d(k['w'], 1))]);

  int _status(Js g) => goalStatus(_progress(g), expectedProgress(_start(g), _due(g), DateTime.now()));

  static const _statusColors = [Colors.greenAccent, Colors.amber, Colors.redAccent, Colors.lightBlueAccent];

  Future<void> _editGoal([Js? orig]) async {
    final now = DateTime.now();
    final (qs, qe) = quarterRange(now);
    final g = Map<String, Object?>.from(orig ??
        {
          'start': qs.millisecondsSinceEpoch,
          'due': qe.millisecondsSinceEpoch,
          'color': _goals.length,
          'krs': <Js>[],
        });
    final title = TextEditingController(text: g['title'] as String? ?? '');
    final why = TextEditingController(text: g['why'] as String? ?? '');
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
                Expanded(child: Text(L(t, 'objective'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (orig != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (await confirmDelete(c, t) && c.mounted) Navigator.pop(c, 'del');
                    },
                  ),
              ]),
              AppTextField(controller: title, label: L(t, 'title'), autofocus: orig == null),
              AppTextField(controller: why, label: L(t, 'description'), maxLines: 3),
              DateRow(
                label: L(t, 'start_date'),
                value: _start(g),
                clearable: false,
                onChanged: (d) => set(() => g['start'] = (d ?? _start(g)).millisecondsSinceEpoch),
              ),
              DateRow(
                label: L(t, 'due'),
                value: _due(g),
                clearable: false,
                onChanged: (d) => set(() => g['due'] = (d ?? _due(g)).millisecondsSinceEpoch),
              ),
              Wrap(spacing: 8, children: [
                for (final off in [0, 1])
                  ActionChip(
                    label: Text(quarterOf(DateTime(now.year, now.month + off * 3, 1))),
                    onPressed: () => set(() {
                      final (a, b) = quarterRange(DateTime(now.year, now.month + off * 3, 1));
                      g['start'] = a.millisecondsSinceEpoch;
                      g['due'] = b.millisecondsSinceEpoch;
                    }),
                  ),
                ActionChip(
                  label: Text('${now.year}'),
                  onPressed: () => set(() {
                    g['start'] = DateTime(now.year, 1, 1).millisecondsSinceEpoch;
                    g['due'] = DateTime(now.year, 12, 31).millisecondsSinceEpoch;
                  }),
                ),
              ]),
              ColorRow(value: (g['color'] as num?)?.toInt() ?? 0, onChanged: (i) => set(() => g['color'] = i)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => Navigator.pop(c, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
            ]),
          ),
        ),
      ),
    );
    final tt = title.text.trim(), wt = why.text.trim();
    title.dispose();
    why.dispose();
    if (res == null || !mounted) return;
    if (res == 'del') {
      setState(() => _goals.removeWhere((x) => x['id'] == orig?['id']));
    } else {
      g['title'] = tt.isEmpty ? L(t, 'objective') : tt;
      g['why'] = wt;
      if (_due(g).isBefore(_start(g))) g['due'] = g['start'];
      if (orig == null) {
        g['id'] = newId();
        setState(() => _goals.add(g));
        await _save();
        if (mounted) await _editKr(g);
        return;
      }
      final i = _goals.indexWhere((x) => x['id'] == orig['id']);
      setState(() => _goals[i] = g);
    }
    await _save();
  }

  Future<void> _editKr(Js g, [Js? orig]) async {
    final k = Map<String, Object?>.from(orig ?? {'kind': 'num', 'start': 0, 'target': 100, 'cur': 0, 'w': 1});
    final title = TextEditingController(text: k['title'] as String? ?? '');
    final start = TextEditingController(text: _n(_d(k['start'])));
    final target = TextEditingController(text: _n(_d(k['target'], 100)));
    final unit = TextEditingController(text: k['unit'] as String? ?? '');
    final kinds = Ls(t, 'kr_kinds');
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
                Expanded(child: Text(L(t, 'key_result'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                if (orig != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () async {
                      if (await confirmDelete(c, t) && c.mounted) Navigator.pop(c, 'del');
                    },
                  ),
              ]),
              AppTextField(controller: title, label: L(t, 'title'), autofocus: orig == null),
              Choice<String>(
                values: const ['num', 'pct', 'done'],
                labels: [for (var i = 0; i < 3; i++) i < kinds.length ? kinds[i] : '$i'],
                selected: k['kind'] as String? ?? 'num',
                onChanged: (v) => set(() {
                  k['kind'] = v;
                  if (v == 'pct') {
                    start.text = '0';
                    target.text = '100';
                    unit.text = '%';
                  }
                }),
              ),
              if (k['kind'] != 'done') ...[
                Row(children: [
                  Expanded(child: AppNumberField(controller: start, label: L(t, 'kr_start'), signed: true)),
                  const SizedBox(width: 10),
                  Expanded(child: AppNumberField(controller: target, label: L(t, 'kr_target'), signed: true)),
                ]),
                AppTextField(controller: unit, label: L(t, 'unit')),
              ],
              Row(children: [
                Text(L(t, 'weight')),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 5,
                    divisions: 4,
                    value: _d(k['w'], 1).clamp(1, 5).toDouble(),
                    label: _n(_d(k['w'], 1)),
                    onChanged: (v) => set(() => k['w'] = v),
                  ),
                ),
                Text('×${_n(_d(k['w'], 1))}'),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => Navigator.pop(c, 'ok'), icon: const Icon(Icons.check_rounded), label: Text(L(t, 'save'))),
            ]),
          ),
        ),
      ),
    );
    final vals = (title.text.trim(), parseNumber(start.text), parseNumber(target.text), unit.text.trim());
    for (final c in [title, start, target, unit]) {
      c.dispose();
    }
    if (res == null || !mounted) return;
    final krs = _maps(g['krs']);
    if (res == 'del') {
      krs.removeWhere((x) => x['id'] == orig?['id']);
    } else {
      k['title'] = vals.$1.isEmpty ? L(t, 'key_result') : vals.$1;
      if (k['kind'] == 'done') {
        k['start'] = 0;
        k['target'] = 1;
        k['cur'] = (k['cur'] == 1) ? 1 : 0;
      } else {
        k['start'] = vals.$2 ?? 0;
        k['target'] = vals.$3 ?? 100;
        k['unit'] = vals.$4;
        if (orig == null) k['cur'] = k['start'];
      }
      if (orig == null) {
        k['id'] = newId();
        krs.add(k);
      } else {
        final i = krs.indexWhere((x) => x['id'] == orig['id']);
        if (i >= 0) krs[i] = k;
      }
    }
    setState(() => g['krs'] = krs);
    await _save();
  }

  Future<void> _checkIn(Js g, Js k) async {
    if (k['kind'] == 'done') {
      _setCur(g, k, k['cur'] == 1 ? 0 : 1, '');
      return;
    }
    final v = TextEditingController(text: _n(_d(k['cur'])));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${k['title']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          AppNumberField(controller: v, label: L(t, 'kr_current'), suffix: '${k['unit'] ?? ''}', signed: true),
          AppTextField(controller: note, label: L(t, 'note')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L(t, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L(t, 'save'))),
        ],
      ),
    );
    final nv = parseNumber(v.text), nt = note.text.trim();
    v.dispose();
    note.dispose();
    if (ok == true && nv != null) _setCur(g, k, nv, nt);
  }

  void _setCur(Js g, Js k, num value, String note) {
    final krs = _maps(g['krs']);
    final i = krs.indexWhere((x) => x['id'] == k['id']);
    if (i < 0) return;
    final hist = _maps(k['hist'])..add({'at': DateTime.now().millisecondsSinceEpoch, 'v': value, if (note.isNotEmpty) 'n': note});
    krs[i] = {...k, 'cur': value, 'hist': hist.length > 200 ? hist.sublist(hist.length - 200) : hist};
    setState(() => g['krs'] = krs);
    _save();
  }

  Future<void> _history(Js k) async {
    final h = _maps(k['hist']).reversed.toList();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (c) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('${k['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (h.isEmpty) EmptyHint(L(t, 'empty_list'), icon: Icons.history_rounded),
        for (final e in h)
          ListTile(
            dense: true,
            leading: const Icon(Icons.flag_circle_outlined),
            title: Text('${_n(_d(e['v']))} ${k['unit'] ?? ''}'),
            subtitle: Text([
              fmtDateTime(c, DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt())),
              if (e['n'] != null) '${e['n']}',
            ].join(' · ')),
          ),
      ]),
    );
  }

  Widget _goalCard(Js g) {
    final p = _progress(g);
    final st = _status(g);
    final names = Ls(t, 'goal_status');
    final color = paletteAt((g['color'] as num?)?.toInt() ?? 0);
    final left = _due(g).difference(DateTime.now()).inDays;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 6, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => _editGoal(g),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${g['title']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(
                    '${quarterOf(_start(g))} · ${fmtDate(context, _due(g))}'
                    '${left >= 0 && p < 1 ? ' · $left ${L(t, 'days')}' : ''}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ]),
              ),
            ),
            Chip(
              label: Text(st < names.length ? names[st] : '', style: const TextStyle(fontSize: 12)),
              side: BorderSide(color: _statusColors[st]),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: p, minHeight: 10, color: color),
              ),
            ),
            const SizedBox(width: 10),
            Text('${(p * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
          if ('${g['why'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${g['why']}', style: const TextStyle(color: Colors.white70)),
            ),
          for (final k in _maps(g['krs']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              onTap: () => _editKr(g, k),
              onLongPress: () => _history(k),
              leading: k['kind'] == 'done'
                  ? Checkbox(value: k['cur'] == 1, onChanged: (_) => _checkIn(g, k))
                  : SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(value: _kr(k), strokeWidth: 5, color: color),
                    ),
              title: Text('${k['title']}'),
              subtitle: k['kind'] == 'done'
                  ? null
                  : Text('${_n(_d(k['cur']))} / ${_n(_d(k['target'], 1))} ${k['unit'] ?? ''}'),
              trailing: k['kind'] == 'done'
                  ? null
                  : IconButton(
                      tooltip: L(t, 'check_in'),
                      icon: const Icon(Icons.add_task_rounded),
                      onPressed: () => _checkIn(g, k),
                    ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _editKr(g),
              icon: const Icon(Icons.add_rounded),
              label: Text(L(t, 'key_result')),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final periods = <String>{for (final g in _goals) quarterOf(_start(g))}.toList()..sort();
    final list = _goals
        .where((g) => _period.isEmpty || quarterOf(_start(g)) == _period)
        .where((g) => _showDone || _progress(g) < 1)
        .toList()
      ..sort((a, b) => _due(a).compareTo(_due(b)));
    final all = _goals.where((g) => _period.isEmpty || quarterOf(_start(g)) == _period).toList();
    final avg = all.isEmpty ? 0.0 : all.map(_progress).reduce((a, b) => a + b) / all.length;
    final counts = List.filled(4, 0);
    for (final g in all) {
      counts[_status(g)]++;
    }
    final names = Ls(t, 'goal_status');
    return ToolList(children: [
      if (periods.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            ChoiceChip(label: Text(t.tx('all')), selected: _period.isEmpty, onSelected: (_) => setState(() => _period = '')),
            for (final p in periods)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: ChoiceChip(label: Text(p), selected: _period == p, onSelected: (_) => setState(() => _period = p)),
              ),
          ]),
        ),
      if (all.isNotEmpty)
        AppPanel(
          child: Column(children: [
            AppResult(label: L(t, 'avg_progress'), value: '${(avg * 100).round()}%', lang: t.lang, big: true),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (var i = 0; i < 4; i++)
                if (counts[i] > 0)
                  Chip(
                    avatar: CircleAvatar(backgroundColor: _statusColors[i], radius: 6),
                    label: Text('${i < names.length ? names[i] : i}: ${counts[i]}'),
                  ),
            ]),
          ]),
        ),
      SectionBar(L(t, 'objectives'), icon: Icons.flag_rounded, onAdd: () => _editGoal(), actions: [
        IconButton(
          tooltip: L(t, 'show_done'),
          icon: Icon(_showDone ? Icons.visibility_rounded : Icons.visibility_off_rounded),
          onPressed: () => setState(() => _showDone = !_showDone),
        ),
      ]),
      if (list.isEmpty) EmptyHint(L(t, 'goal_empty'), icon: Icons.flag_outlined),
      for (final g in list) _goalCard(g),
    ]);
  }
}
