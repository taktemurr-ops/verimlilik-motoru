/// Hedef (OKR) ve proje zaman çizelgesi (Gantt) uygulamalarının saf mantığı.
library;

import 'dart:math' as math;

// ================================================================= OKR

/// Anahtar sonucun ilerlemesi (0–1): başlangıçtan hedefe doğru (azalan
/// hedefler de desteklenir).
double krProgress(num start, num target, num current) {
  if (target == start) return current == target ? 1.0 : 0.0;
  return ((current - start) / (target - start)).clamp(0.0, 1.0).toDouble();
}

/// Hedefin ilerlemesi: anahtar sonuçların ağırlıklı ortalaması.
double objectiveProgress(List<(double progress, double weight)> krs) {
  var sum = 0.0, w = 0.0;
  for (final (p, wt) in krs) {
    sum += p * wt;
    w += wt;
  }
  return w <= 0 ? 0.0 : sum / w;
}

/// Zaman içinde beklenen ilerleme (0–1).
double expectedProgress(DateTime start, DateTime due, DateTime now) {
  final total = due.difference(start).inMinutes;
  if (total <= 0) return now.isBefore(due) ? 0.0 : 1.0;
  return (now.difference(start).inMinutes / total).clamp(0.0, 1.0);
}

/// 0 yolunda, 1 risk altında, 2 geride, 3 tamamlandı.
int goalStatus(double progress, double expected) {
  if (progress >= 1) return 3;
  if (progress + 0.1 >= expected) return 0;
  if (progress + 0.25 >= expected) return 1;
  return 2;
}

/// Tarihin çeyrek etiketi: "2026 Q4".
String quarterOf(DateTime d) => '${d.year} Q${(d.month - 1) ~/ 3 + 1}';

/// Çeyreğin ilk ve son günü.
(DateTime, DateTime) quarterRange(DateTime d) {
  final q = (d.month - 1) ~/ 3;
  return (DateTime(d.year, q * 3 + 1, 1), DateTime(d.year, q * 3 + 4, 0));
}

// =============================================================== Gantt

/// Zaman çizelgesindeki bir iş.
class GTask {
  final String id;
  final String name;

  /// Başlangıç (gün, proje başından itibaren değil; mutlak tarih).
  final DateTime start;

  /// Süre (gün); 0 kilometre taşıdır.
  final int days;
  final List<String> deps;
  final int progress;
  const GTask({required this.id, required this.name, required this.start, required this.days, this.deps = const [], this.progress = 0});

  DateTime get end => DateTime(start.year, start.month, start.day + days);

  GTask copyWith({DateTime? start}) =>
      GTask(id: id, name: name, start: start ?? this.start, days: days, deps: deps, progress: progress);
}

/// Bağımlılık sırası (topolojik); döngü varsa null.
List<String>? topoOrder(List<GTask> tasks) {
  final byId = {for (final t in tasks) t.id: t};
  final state = <String, int>{};
  final out = <String>[];
  bool visit(String id) {
    final s = state[id] ?? 0;
    if (s == 1) return false;
    if (s == 2) return true;
    state[id] = 1;
    for (final d in byId[id]?.deps ?? const <String>[]) {
      if (byId.containsKey(d) && !visit(d)) return false;
    }
    state[id] = 2;
    out.add(id);
    return true;
  }

  for (final t in tasks) {
    if (!visit(t.id)) return null;
  }
  return out;
}

/// Bitiş-başlangıç bağımlılıklarına göre işleri ileri kaydırır: bir iş,
/// bağlı olduğu işlerin hepsi bitmeden başlamaz. Döngü varsa değişmez.
List<GTask> scheduleTasks(List<GTask> tasks) {
  final order = topoOrder(tasks);
  if (order == null) return tasks;
  final byId = {for (final t in tasks) t.id: t};
  for (final id in order) {
    final t = byId[id]!;
    var s = t.start;
    for (final d in t.deps) {
      final dt = byId[d];
      if (dt != null && dt.end.isAfter(s)) s = dt.end;
    }
    if (s != t.start) byId[id] = t.copyWith(start: s);
  }
  return [for (final t in tasks) byId[t.id]!];
}

/// Kritik yol: geç başlangıçla erken başlangıcı aynı olan (bolluğu sıfır)
/// işler. Proje bitişini geciktirmeden kaydırılamazlar.
Set<String> criticalPath(List<GTask> tasks) {
  if (tasks.isEmpty) return {};
  final order = topoOrder(tasks);
  if (order == null) return {};
  final byId = {for (final t in tasks) t.id: t};
  final succ = <String, List<String>>{for (final t in tasks) t.id: []};
  for (final t in tasks) {
    for (final d in t.deps) {
      succ[d]?.add(t.id);
    }
  }
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final origin = tasks.map((t) => day(t.start)).reduce((a, b) => a.isBefore(b) ? a : b);
  int off(DateTime d) => day(d).difference(origin).inDays;
  final es = {for (final t in tasks) t.id: off(t.start)};
  final ef = {for (final t in tasks) t.id: off(t.start) + t.days};
  final finish = ef.values.reduce(math.max);
  final lf = <String, int>{};
  final ls = <String, int>{};
  for (final id in order.reversed) {
    final s = succ[id]!;
    lf[id] = s.isEmpty ? finish : s.map((x) => ls[x]!).reduce(math.min);
    ls[id] = lf[id]! - byId[id]!.days;
  }
  return {for (final t in tasks) if (ls[t.id] == es[t.id]) t.id};
}

/// Projenin başlangıç, bitiş ve ağırlıklı (süreye göre) ilerlemesi.
(DateTime, DateTime, double) projectSpan(List<GTask> tasks) {
  if (tasks.isEmpty) {
    final n = DateTime.now();
    return (n, n, 0.0);
  }
  var s = tasks.first.start, e = tasks.first.end;
  var w = 0.0, p = 0.0;
  for (final t in tasks) {
    if (t.start.isBefore(s)) s = t.start;
    if (t.end.isAfter(e)) e = t.end;
    final wt = math.max(1, t.days).toDouble();
    w += wt;
    p += wt * t.progress / 100;
  }
  return (s, e, w == 0 ? 0.0 : p / w);
}
