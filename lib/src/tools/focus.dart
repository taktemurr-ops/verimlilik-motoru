/// Odak kilidi ve ekran süresi. Her platformda odak sayacı ve istatistik;
/// Android'de ayrıca odak süresince seçilen uygulamalar açılınca üstte
/// "odaklan" ekranı (Kullanım erişimi + üstte gösterme izni) ve bugünkü
/// ekran süresi. iOS'ta uygulama engelleme Apple'ın özel izinli Screen
/// Time arayüzünü gerektirdiğinden yalnızca sayaç çalışır.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';

import '../common.dart';
import '../platform/focus.dart';
import '../platform/notify.dart';

/// Odak istatistiği: bugün ve son 7 gün (dakika), tamamlanan oturum ve
/// art arda odaklanılan gün sayısı.
class FocusStats {
  final int todayMin;
  final int weekMin;
  final int done;
  final int streak;
  const FocusStats(this.todayMin, this.weekMin, this.done, this.streak);
}

FocusStats focusStats(List<Map<String, Object?>> sessions, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  var todayMin = 0, weekMin = 0, done = 0;
  final days = <int>{};
  for (final s in sessions) {
    final at = DateTime.fromMillisecondsSinceEpoch((s['at'] as num?)?.toInt() ?? 0);
    final min = (s['min'] as num?)?.toInt() ?? 0;
    final d = DateTime(at.year, at.month, at.day);
    final ago = today.difference(d).inDays;
    if (ago == 0) todayMin += min;
    if (ago >= 0 && ago < 7) weekMin += min;
    if (s['done'] == true) {
      done++;
      days.add(ago);
    }
  }
  var streak = 0;
  // Bugün henüz oturum yoksa dünden başlayarak sayılır.
  var k = days.contains(0) ? 0 : 1;
  while (days.contains(k)) {
    streak++;
    k++;
  }
  return FocusStats(todayMin, weekMin, done, streak);
}

class FocusTool extends StatefulWidget {
  final ToolContext t;
  const FocusTool(this.t, {super.key});

  @override
  State<FocusTool> createState() => _FocusToolState();
}

class _FocusToolState extends State<FocusTool> with WidgetsBindingObserver {
  int _minutes = 25;
  int _endsAt = 0;
  int _startedAt = 0;
  int _leaves = 0;
  FocusStatus _st = const FocusStatus();
  List<FocusApp> _apps = [];
  List<FocusApp> _usage = [];
  final Set<String> _blocked = {};
  List<Map<String, Object?>> _sessions = [];
  Timer? _tick;
  bool _showApps = false;

  ToolContext get t => widget.t;
  bool get _android => FocusNative.supported;
  int get _now => DateTime.now().millisecondsSinceEpoch;
  bool get _running => _endsAt > _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _running && !_android) {
      // iOS/web: oturum sırasında uygulamadan çıkışlar sayılır.
      _leaves++;
      unawaited(t.store.write('leaves', '$_leaves'));
    }
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _load() async {
    final m = await t.store.readMap('prefs');
    final sessions = await t.store.readList('sessions');
    final ends = await t.store.readInt('endsAt');
    final started = await t.store.readInt('startedAt');
    final leaves = await t.store.readInt('leaves');
    if (!mounted) return;
    setState(() {
      _minutes = (m['min'] as num?)?.toInt() ?? 25;
      _blocked
        ..clear()
        ..addAll([for (final x in (m['apps'] as List? ?? const [])) '$x']);
      _sessions = sessions;
      _endsAt = ends;
      _startedAt = started;
      _leaves = leaves;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (!_android) return;
    final st = await FocusNative.status();
    final usage = st.usage ? await FocusNative.usageToday() : const <FocusApp>[];
    if (!mounted) return;
    setState(() {
      _st = st;
      _usage = usage;
      if (st.running && st.endsAt > _now) _endsAt = st.endsAt;
    });
  }

  Future<void> _savePrefs() => t.store.writeMap('prefs', {'min': _minutes, 'apps': _blocked.toList()});

  void _onTick() {
    if (!mounted) return;
    if (_endsAt != 0 && !_running) {
      unawaited(_finish(true));
      return;
    }
    if (_running) setState(() {});
  }

  Future<void> _start() async {
    final now = _now;
    final ends = now + _minutes * 60000;
    if (_android && _blocked.isNotEmpty) {
      if (!_st.usage || !_st.overlay) {
        toast(context, L(t, 'focus_need_perm'));
        return;
      }
      await Notify.requestPermission();
      final ok = await FocusNative.start(packages: _blocked.toList(), endsAt: ends, texts: {
        'title': L(t, 'focus_on'),
        'body': L(t, 'focus_until'),
        'blockTitle': L(t, 'focus_block_title'),
        'blockBody': L(t, 'focus_block_body'),
        'homeLabel': L(t, 'focus_home'),
        'doneTitle': L(t, 'focus_complete'),
      });
      if (!ok && mounted) toast(context, t.tx('not_available'));
    }
    await t.store.write('endsAt', '$ends');
    await t.store.write('startedAt', '$now');
    await t.store.write('leaves', '0');
    if (!mounted) return;
    setState(() {
      _endsAt = ends;
      _startedAt = now;
      _leaves = 0;
    });
  }

  Future<void> _finish(bool completed) async {
    final started = _startedAt;
    final mins = started == 0 ? 0 : ((math.min(_now, _endsAt) - started) / 60000).round();
    await FocusNative.stop();
    if (started != 0 && mins > 0) {
      _sessions.add({'at': started, 'min': mins, 'done': completed, 'leaves': _leaves});
      if (_sessions.length > 400) _sessions.removeRange(0, _sessions.length - 400);
      await t.store.writeList('sessions', _sessions);
    }
    await t.store.write('endsAt', '0');
    await t.store.write('startedAt', '0');
    if (!mounted) return;
    setState(() {
      _endsAt = 0;
      _startedAt = 0;
    });
    if (completed) toast(context, '${L(t, 'focus_complete')} · $mins ${L(t, 'minutes')}');
    // Oturum sonu doğal bir mola: reklam (varsa, 3 dk aralıkla) burada.
    await t.services.naturalBreak();
  }

  Future<void> _pickApps() async {
    final apps = _apps.isNotEmpty ? _apps : await FocusNative.apps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _showApps = !_showApps;
    });
  }

  String _mmss(int ms) {
    final s = (ms / 1000).ceil().clamp(0, 1 << 30);
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final stats = focusStats(_sessions, DateTime.now());
    final running = _running;
    final total = math.max(1, _endsAt - _startedAt);
    final left = math.max(0, _endsAt - _now);
    return ToolList(children: [
      AppPanel(
        child: Column(children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: running ? left / total : 1,
                  strokeWidth: 10,
                  color: s.accent,
                  backgroundColor: Colors.white12,
                ),
              ),
              Text(running ? _mmss(left) : '$_minutes:00',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: s.number)),
            ]),
          ),
          const SizedBox(height: 12),
          if (!running)
            AppButton(label: L(t, 'focus_start'), icon: Icons.self_improvement_rounded, onPressed: _start)
          else
            GestureDetector(
              onLongPress: () => _finish(false),
              child: OutlinedButton.icon(
                onPressed: () => toast(context, L(t, 'focus_hold')),
                icon: const Icon(Icons.stop_rounded),
                label: Text(L(t, 'focus_end_early')),
              ),
            ),
          if (running && !_android && _leaves > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${L(t, 'focus_leaves')}: $_leaves', style: const TextStyle(color: Colors.orangeAccent)),
            ),
        ]),
      ),
      if (!running)
        Choice<int>(
          values: const [15, 25, 45, 60, 90, 120],
          labels: [for (final m in const [15, 25, 45, 60, 90, 120]) '$m ${L(t, 'minutes')}'],
          selected: _minutes,
          onChanged: (v) {
            setState(() => _minutes = v);
            unawaited(_savePrefs());
          },
        ),
      AppPanel(
        child: Column(children: [
          AppResult(label: L(t, 'focus_today'), value: '${stats.todayMin} ${L(t, 'minutes')}', lang: t.lang),
          AppResult(label: L(t, 'focus_week'), value: '${stats.weekMin} ${L(t, 'minutes')}', lang: t.lang),
          AppResult(label: L(t, 'focus_sessions'), value: '${stats.done}', lang: t.lang),
          AppResult(label: L(t, 'focus_streak'), value: '${stats.streak} ${L(t, 'days')}', lang: t.lang),
        ]),
      ),
      if (_android) ...[
        AppHeading(L(t, 'focus_block'), icon: Icons.block_rounded),
        if (!_st.usage)
          ListTile(
            leading: const Icon(Icons.query_stats_rounded),
            title: Text(L(t, 'focus_perm_usage')),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: FocusNative.openUsage,
          ),
        if (!_st.overlay)
          ListTile(
            leading: const Icon(Icons.layers_rounded),
            title: Text(L(t, 'focus_perm_overlay')),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: FocusNative.openOverlay,
          ),
        ListTile(
          leading: const Icon(Icons.apps_rounded),
          title: Text('${L(t, 'focus_apps')} (${_blocked.length})'),
          trailing: Icon(_showApps ? Icons.expand_less_rounded : Icons.expand_more_rounded),
          onTap: running ? null : _pickApps,
        ),
        if (_showApps && !running)
          for (final a in _apps)
            CheckboxListTile(
              dense: true,
              title: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              value: _blocked.contains(a.pkg),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _blocked.add(a.pkg);
                  } else {
                    _blocked.remove(a.pkg);
                  }
                });
                unawaited(_savePrefs());
              },
            ),
        AppInfoCard(L(t, 'focus_android_note'), icon: Icons.privacy_tip_rounded),
        if (_st.usage) ...[
          AppHeading(L(t, 'focus_screen_time'), icon: Icons.hourglass_bottom_rounded),
          if (_usage.isEmpty) AppInfoCard(L(t, 'focus_no_usage')),
          for (final a in _usage.take(12))
            ListTile(
              dense: true,
              title: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(fmtDuration(Duration(milliseconds: a.ms))),
            ),
        ],
      ] else
        AppInfoCard(kIsWeb ? L(t, 'focus_web_note') : L(t, 'focus_ios_note'), icon: Icons.info_outline_rounded),
    ]);
  }
}
