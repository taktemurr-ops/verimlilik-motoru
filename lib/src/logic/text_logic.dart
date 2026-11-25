/// Metin araçlarının saf mantığı (sayaç ve dönüştürücüler).
library;

/// Metin istatistikleri.
class TextStats {
  final int chars;
  final int charsNoSpace;
  final int words;
  final int sentences;
  final int lines;
  final int paragraphs;

  const TextStats({
    required this.chars,
    required this.charsNoSpace,
    required this.words,
    required this.sentences,
    required this.lines,
    required this.paragraphs,
  });

  /// Dakikada ~200 kelime okuma hızıyla yaklaşık okuma süresi (dakika, en az 1).
  int get readingMinutes => words == 0 ? 0 : ((words + 199) ~/ 200);

  static final _space = RegExp(r'\s');
  static final _word = RegExp(r'[^\s]+');
  static final _sentence = RegExp(r'[^.!?。！？؟।]+[.!?。！？؟।]+|[^.!?。！？؟।]+$');

  factory TextStats.of(String s) {
    final runes = s.runes.length;
    final noSpace = s.runes.where((r) => !_space.hasMatch(String.fromCharCode(r))).length;
    final trimmed = s.trim();
    final words = trimmed.isEmpty ? 0 : _word.allMatches(trimmed).length;
    final sentences = trimmed.isEmpty ? 0 : _sentence.allMatches(trimmed).where((m) => m.group(0)!.trim().isNotEmpty).length;
    final lines = s.isEmpty ? 0 : s.split('\n').length;
    final paragraphs = trimmed.isEmpty ? 0 : trimmed.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).length;
    return TextStats(
      chars: runes,
      charsNoSpace: noSpace,
      words: words,
      sentences: sentences,
      lines: lines,
      paragraphs: paragraphs,
    );
  }
}

/// Dile duyarlı büyük harf (Türkçe ve Azerice i/İ, ı/I).
String upperFor(String s, String lang) {
  if (lang == 'tr') s = s.replaceAll('i', 'İ').replaceAll('ı', 'I');
  return s.toUpperCase();
}

/// Dile duyarlı küçük harf.
String lowerFor(String s, String lang) {
  if (lang == 'tr') s = s.replaceAll('I', 'ı').replaceAll('İ', 'i');
  return s.toLowerCase();
}

/// Her kelimenin ilk harfi büyük.
String titleCase(String s, String lang) => s.splitMapJoin(
      RegExp(r'[^\s\-]+'),
      onMatch: (m) {
        final w = m.group(0)!;
        if (w.isEmpty) return w;
        final first = String.fromCharCode(w.runes.first);
        final rest = w.substring(first.length);
        return upperFor(first, lang) + lowerFor(rest, lang);
      },
      onNonMatch: (n) => n,
    );

/// Cümle düzeni: her cümlenin ilk harfi büyük, gerisi küçük.
String sentenceCase(String s, String lang) {
  final low = lowerFor(s, lang);
  final b = StringBuffer();
  var start = true;
  for (final r in low.runes) {
    final ch = String.fromCharCode(r);
    if (start && ch.trim().isNotEmpty) {
      b.write(upperFor(ch, lang));
      start = false;
    } else {
      b.write(ch);
    }
    if ('.!?\n。！？؟'.contains(ch)) start = true;
  }
  return b.toString();
}

/// Fazla boşlukları temizler (satır sonlarını korur).
String trimSpaces(String s) =>
    s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim()).join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

/// Satırları alfabetik sıralar.
String sortLines(String s, {bool descending = false}) {
  final l = s.split('\n')..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return (descending ? l.reversed : l).join('\n');
}

/// Metni ters çevirir (karakter bazında).
String reverseText(String s) => String.fromCharCodes(s.runes.toList().reversed);

/// Tekrarlanan satırları kaldırır (ilkini tutar).
String removeDuplicateLines(String s) {
  final seen = <String>{};
  return s.split('\n').where((l) => seen.add(l)).join('\n');
}

const _fold = {
  'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u',
  'á': 'a', 'à': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o', 'ú': 'u',
  'ù': 'u', 'ñ': 'n', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe', 'ł': 'l', 'ś': 's', 'ź': 'z', 'ż': 'z',
  'ń': 'n', 'ć': 'c', 'ę': 'e', 'ą': 'a', 'č': 'c', 'ř': 'r', 'š': 's', 'ž': 'z', 'ý': 'y',
  'ů': 'u', 'ě': 'e', 'ď': 'd', 'ť': 't', 'ň': 'n', 'ő': 'o', 'ű': 'u', 'ă': 'a', 'ș': 's',
  'ț': 't', 'đ': 'd',
};

/// URL için kısa ad: "Merhaba Dünya!" → "merhaba-dunya".
String slugify(String s) {
  final low = lowerFor(s, 'tr');
  final b = StringBuffer();
  for (final r in low.runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Bul ve değiştir. Dönüş: (yeni metin, eşleşme sayısı).
(String, int) findReplace(String s, String find, String replace, {bool caseSensitive = false}) {
  if (find.isEmpty) return (s, 0);
  final re = RegExp(RegExp.escape(find), caseSensitive: caseSensitive);
  final n = re.allMatches(s).length;
  return (s.replaceAll(re, replace), n);
}
