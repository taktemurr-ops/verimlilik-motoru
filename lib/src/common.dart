/// Verimlilik uygulamalarının ortak yardımcıları: çeviri, liste düzeni,
/// diyaloglar, paylaşma, PDF yazı tipi ve ödüllü ekstra kapısı.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:studio_core/apps/apps.dart';

import 'tx.dart';

/// Uygulama etiketi (33 dil).
String L(ToolContext t, String key) => t.t(kVerL[key] ?? [key]);

/// Virgülle ayrılmış etiket listesi.
List<String> Ls(ToolContext t, String key) => L(t, key).split(',');

/// Uygulamanın gövdesi: kaydırılabilir sütun.
class ToolList extends StatelessWidget {
  final List<Widget> children;
  const ToolList({super.key, required this.children});

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(top: 8, bottom: 96), children: children);
}

/// "Bu cihazda yok" bilgisi.
Widget notAvailable(ToolContext t) =>
    AppInfoCard(t.tx(kIsWeb ? 'web_unavailable' : 'not_available'), icon: Icons.devices_other_rounded);

/// Boş liste bilgisi.
class EmptyHint extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyHint(this.text, {super.key, this.icon = Icons.inbox_rounded});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(icon, size: 56, color: Colors.white38),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 16)),
        ]),
      );
}

/// Seçenek düğmeleri (SegmentedButton) için kısa yol.
class Choice<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  const Choice({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (var i = 0; i < values.length; i++) ButtonSegment<T>(value: values[i], label: Text(labels[i])),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}

/// Açılır liste.
class Pick<T> extends StatelessWidget {
  final String label;
  final List<T> values;
  final String Function(T) text;
  final T value;
  final ValueChanged<T> onChanged;
  const Pick({
    super.key,
    required this.label,
    required this.values,
    required this.text,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        items: [for (final v in values) DropdownMenuItem<T>(value: v, child: Text(text(v), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Düz metin alanı.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboard;
  final bool autofocus;
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.minLines = 1,
    this.onChanged,
    this.keyboard,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: math.min<int>(minLines, maxLines),
        onChanged: onChanged,
        autofocus: autofocus,
        keyboardType: keyboard ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
        style: const TextStyle(color: Colors.white, fontSize: 17),
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: maxLines > 1,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

/// Tarih seçme satırı.
class DateRow extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool withTime;
  final bool clearable;
  const DateRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.withTime = false,
    this.clearable = true,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(withTime ? Icons.schedule_rounded : Icons.event_rounded),
      title: Text(label),
      subtitle: Text(v == null ? '—' : (withTime ? fmtDateTime(context, v) : fmtDate(context, v))),
      trailing: clearable && v != null
          ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => onChanged(null))
          : null,
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: v ?? now,
          firstDate: DateTime(1900),
          lastDate: DateTime(2300),
        );
        if (d == null) return;
        if (!withTime) {
          onChanged(DateTime(d.year, d.month, d.day));
          return;
        }
        if (!context.mounted) return;
        final tm = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(v ?? now.add(const Duration(hours: 1))),
        );
        if (tm == null) return;
        onChanged(DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
      },
    );
  }
}

// ----------------------------------------------------------- biçimlendirme

String fmtDate(BuildContext context, DateTime d) => MaterialLocalizations.of(context).formatMediumDate(d);

String fmtTime(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(d), alwaysUse24HourFormat: true);

String fmtDateTime(BuildContext context, DateTime d) => '${fmtDate(context, d)} · ${fmtTime(context, d)}';

/// Süre: 1:05:09 ya da 05:09.
String fmtDuration(Duration d) {
  final neg = d.isNegative;
  final s = d.inSeconds.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  final body = h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  return neg ? '-$body' : body;
}

/// Saat ve dakika: 7 h 05 min → "7:05".
String fmtHours(Duration d) {
  final m = d.inMinutes;
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// ISO gün anahtarı: 2026-11-25.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Pazartesi=0 … Pazar=6 hafta günü adları (kısa).
List<String> weekdayNames(ToolContext t) => Ls(t, 'weekdays');

/// Tamsayıyı aralığa sıkıştırır.
int clampInt(int v, int lo, int hi) => math.max<int>(lo, math.min<int>(v, hi));

/// Benzersiz kimlik.
String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 20).toRadixString(36)}';

/// Küçük renk paleti (etiket renkleri).
const List<Color> kPalette = [
  Color(0xFF90CAF9),
  Color(0xFFA5D6A7),
  Color(0xFFFFE082),
  Color(0xFFFFAB91),
  Color(0xFFCE93D8),
  Color(0xFF80CBC4),
  Color(0xFFF48FB1),
  Color(0xFFB0BEC5),
];

Color paletteAt(int i) => kPalette[i.abs() % kPalette.length];

/// Renk seçici satırı.
class ColorRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const ColorRow({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < kPalette.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kPalette[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: i == value ? Colors.white : Colors.transparent, width: 3),
                ),
              ),
            ),
        ]),
      );
}

// --------------------------------------------------------------- diyaloglar

/// Silme onayı.
Future<bool> confirmDelete(BuildContext context, ToolContext t) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(L(t, 'confirm_delete')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L(t, 'cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(L(t, 'delete'))),
      ],
    ),
  );
  return ok ?? false;
}

/// Tek satırlık metin sorar.
Future<String?> askText(BuildContext context, ToolContext t, String title, {String initial = '', int maxLines = 1}) async {
  final c = TextEditingController(text: initial);
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: maxLines,
        minLines: 1,
        onSubmitted: maxLines == 1 ? (s) => Navigator.pop(ctx, s) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L(t, 'cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(L(t, 'save'))),
      ],
    ),
  );
  c.dispose();
  final s = v?.trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// İzin açıklaması bir kez gösterildi mi?
Future<bool> rationaleOnce(BuildContext context, ToolContext t, String perm, IconData icon) async {
  if (await t.store.readBool('perm.$perm')) return true;
  if (!context.mounted) return false;
  final ok = await explainPermission(context, lang: t.lang, icon: icon, reason: L(t, 'perm_$perm'));
  if (ok) await t.store.writeBool('perm.$perm', true);
  return ok;
}

/// İsteğe bağlı ekstra: reklamsız/premium kullanıcıya açık; diğerlerine
/// ödüllü reklamla bugünlük açılır. Asıl iş hiçbir zaman kilitlenmez.
Future<bool> extraGate(BuildContext context, ToolContext t, String feature) async {
  if (t.services.adFree || await t.unlockedToday(feature)) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.card_giftcard_rounded),
      content: Text(t.tx('unlock_ad')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L(t, 'cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Icon(Icons.play_arrow_rounded)),
      ],
    ),
  );
  if (go != true) return false;
  return t.unlockForToday(feature);
}

// --------------------------------------------------------------- paylaşma

void copyText(BuildContext context, ToolContext t, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.tx('copied'))));
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

Future<void> shareText(String text, {String? subject}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  } catch (_) {}
}

Future<void> shareBytes(Uint8List bytes, String name, String mime) async {
  try {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mime, name: name)],
      fileNameOverrides: [name],
    ));
  } catch (_) {}
}

Future<void> sharePath(String path, String mime) async {
  try {
    await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: mime)]));
  } catch (_) {}
}

/// Dosya adı için güvenli metin.
String safeName(String s) {
  final v = s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  return v.isEmpty ? 'file' : (v.length > 40 ? v.substring(0, 40) : v);
}

// ---------------------------------------------------------------- PDF

pw.ThemeData? _pdfTheme;

/// Türkçe, Kiril, Yunanca ve İbranice karakterleri çizebilen gömülü yazı
/// tipi (DejaVu Sans, özgür lisans). İnternet gerekmez.
Future<pw.ThemeData> pdfTheme() async {
  final cached = _pdfTheme;
  if (cached != null) return cached;
  try {
    final r = await rootBundle.load('packages/verimlilik_motoru/assets/fonts/DejaVuSans.ttf');
    final b = await rootBundle.load('packages/verimlilik_motoru/assets/fonts/DejaVuSans-Bold.ttf');
    return _pdfTheme = pw.ThemeData.withFont(base: pw.Font.ttf(r), bold: pw.Font.ttf(b));
  } catch (_) {
    return _pdfTheme = pw.ThemeData.base();
  }
}

/// Satır başına bir ayırıcı ile CSV (Excel uyumlu, ; ayırıcı yerine virgül
/// ve tırnaklama).
String toCsv(List<List<String>> rows) {
  String cell(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) return '"${v.replaceAll('"', '""')}"';
    return v;
  }

  return rows.map((r) => r.map(cell).join(',')).join('\n');
}

/// Bölüm başlığı + ekleme düğmesi.
class SectionBar extends StatelessWidget {
  final String title;
  final IconData? icon;
  final VoidCallback? onAdd;
  final List<Widget> actions;
  const SectionBar(this.title, {super.key, this.icon, this.onAdd, this.actions = const []});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(children: [
          Expanded(child: AppHeading(title, icon: icon)),
          ...actions,
          if (onAdd != null) IconButton.filledTonal(onPressed: onAdd, icon: const Icon(Icons.add_rounded)),
        ]),
      );
}
