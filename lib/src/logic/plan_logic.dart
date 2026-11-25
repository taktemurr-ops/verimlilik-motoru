/// Planlama araçlarının saf mantığı: seri, tekrar, vardiya, süre, pomodoro.
library;

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

// -------------------------------------------------------------- alışkanlık

/// Güncel seri: bugün yapıldıysa bugünden, yapılmadıysa dünden geriye
/// kesintisiz gün sayısı.
int currentStreak(Set<String> done, DateTime today) {
  var d = _day(today);
  if (!done.contains(_key(d))) d = DateTime(d.year, d.month, d.day - 1);
  var n = 0;
  while (done.contains(_key(d))) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// En uzun seri.
int bestStreak(Set<String> done) {
  if (done.isEmpty) return 0;
  final days = done.map(DateTime.parse).map(_day).toList()..sort();
  var best = 1, run = 1;
  for (var i = 1; i < days.length; i++) {
    final prev = days[i - 1];
    final expect = DateTime(prev.year, prev.month, prev.day + 1);
    if (days[i] == expect) {
      run++;
      if (run > best) best = run;
    } else if (days[i] != prev) {
      run = 1;
    }
  }
  return best;
}

// ------------------------------------------------------------- hatırlatıcı

/// Tekrar: 0 bir kez, 1 her gün, 2 her hafta, 3 her ay.
DateTime addRepeat(DateTime d, int repeat, int n) {
  switch (repeat) {
    case 1:
      return DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
    case 2:
      return DateTime(d.year, d.month, d.day + 7 * n, d.hour, d.minute);
    case 3:
      final m = d.month - 1 + n;
      final y = d.year + m ~/ 12;
      final mm = m % 12 + 1;
      final last = DateTime(y, mm + 1, 0).day;
      return DateTime(y, mm, d.day > last ? last : d.day, d.hour, d.minute);
    default:
      return d;
  }
}

/// [from] anından sonraki en fazla [count] zaman.
List<DateTime> nextOccurrences(DateTime start, int repeat, DateTime from, int count) {
  final out = <DateTime>[];
  if (repeat == 0) {
    if (start.isAfter(from)) out.add(start);
    return out;
  }
  var i = 0;
  // Uzun süre önce başlamış günlük tekrarlarda hızlı atla.
  if (repeat == 1 && start.isBefore(from)) {
    i = from.difference(start).inDays - 1;
    if (i < 0) i = 0;
  }
  while (out.length < count && i < 100000) {
    final d = addRepeat(start, repeat, i);
    if (d.isAfter(from)) out.add(d);
    i++;
  }
  return out;
}

// ----------------------------------------------------------------- vardiya

/// Vardiya türü: başlangıç ve bitiş günün dakikası; bitiş başlangıçtan
/// küçükse ertesi güne taşar (gece vardiyası). Eşitse izin günüdür.
class ShiftKind {
  final String id;
  final String name;
  final int start;
  final int end;
  final int color;
  const ShiftKind(this.id, this.name, this.start, this.end, this.color);

  int get minutes {
    if (start == end) return 0;
    return end > start ? end - start : 24 * 60 - start + end;
  }

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'start': start, 'end': end, 'color': color};

  static ShiftKind fromJson(Map<String, Object?> m) => ShiftKind(
        m['id'] as String? ?? '',
        m['name'] as String? ?? '',
        (m['start'] as num?)?.toInt() ?? 0,
        (m['end'] as num?)?.toInt() ?? 0,
        (m['color'] as num?)?.toInt() ?? 0,
      );
}

/// Ayın toplam çalışma dakikası. [plan]: gün anahtarı → vardiya kimliği.
int monthMinutes(Map<String, String> plan, List<ShiftKind> kinds, int year, int month) {
  final byId = {for (final k in kinds) k.id: k};
  var total = 0;
  final days = DateTime(year, month + 1, 0).day;
  for (var d = 1; d <= days; d++) {
    final k = byId[plan[_key(DateTime(year, month, d))]];
    if (k != null) total += k.minutes;
  }
  return total;
}

/// Döngüyü [from] gününden başlayarak [days] gün boyunca uygular.
/// Döngüdeki boş metin o günü boş bırakır.
Map<String, String> applyRotation(List<String> pattern, DateTime from, int days) {
  final out = <String, String>{};
  if (pattern.isEmpty) return out;
  final f = _day(from);
  for (var i = 0; i < days; i++) {
    out[_key(DateTime(f.year, f.month, f.day + i))] = pattern[i % pattern.length];
  }
  return out;
}

// ------------------------------------------------------------- zaman takibi

/// Bir zaman kaydı (epoch ms).
class TimeEntry {
  final String project;
  final int start;
  final int end;
  const TimeEntry(this.project, this.start, this.end);
  Duration get duration => Duration(milliseconds: end - start);
}

/// [from, to) aralığına düşen süre, projeye göre. Aralığı aşan kayıtlar
/// kırpılır.
Map<String, Duration> totalsByProject(List<TimeEntry> entries, DateTime from, DateTime to) {
  final a = from.millisecondsSinceEpoch, b = to.millisecondsSinceEpoch;
  final out = <String, Duration>{};
  for (final e in entries) {
    final s = e.start < a ? a : e.start;
    final en = e.end > b ? b : e.end;
    if (en <= s) continue;
    out[e.project] = (out[e.project] ?? Duration.zero) + Duration(milliseconds: en - s);
  }
  return out;
}

/// Haftanın (pazartesi) başlangıcı.
DateTime weekStart(DateTime d) {
  final x = _day(d);
  return DateTime(x.year, x.month, x.day - (x.weekday - 1));
}

// ---------------------------------------------------------------- pomodoro

/// Pomodoro evreleri.
enum PomoPhase { focus, shortBreak, longBreak }

/// Bir evre bitince sıradaki evre. [focusDone]: bu evreyle birlikte
/// tamamlanan odak sayısı.
PomoPhase nextPhase(PomoPhase p, int focusDone, int longEvery) {
  if (p != PomoPhase.focus) return PomoPhase.focus;
  if (longEvery > 0 && focusDone > 0 && focusDone % longEvery == 0) return PomoPhase.longBreak;
  return PomoPhase.shortBreak;
}
