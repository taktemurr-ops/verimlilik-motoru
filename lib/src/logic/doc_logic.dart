/// Belge araçlarının saf mantığı: fatura toplamları, kartvizit (vCard)
/// ve zihin haritası ağacı.
library;

import 'dart:math' as math;

// ------------------------------------------------------------------ fatura

/// Fatura/teklif kalemi. Tutarlar kuruş (en küçük birim) olarak hesaplanır.
class LineItem {
  final String text;
  final double qty;
  final double price;
  final double vat;
  const LineItem(this.text, this.qty, this.price, this.vat);

  /// KDV hariç satır tutarı (kuruş).
  int get netCents => (qty * price * 100).round();

  /// Satır KDV'si (kuruş).
  int get vatCents => (netCents * vat / 100).round();

  Map<String, Object?> toJson() => {'text': text, 'qty': qty, 'price': price, 'vat': vat};

  static LineItem fromJson(Map<String, Object?> m) => LineItem(
        m['text'] as String? ?? '',
        (m['qty'] as num?)?.toDouble() ?? 1,
        (m['price'] as num?)?.toDouble() ?? 0,
        (m['vat'] as num?)?.toDouble() ?? 0,
      );
}

/// Ara toplam, KDV ve genel toplam (kuruş). İskonto yüzde olarak ara
/// toplama uygulanır ve KDV iskontolu tutar üzerinden hesaplanır.
({int subtotal, int discount, int vat, int total}) invoiceTotals(List<LineItem> items, {double discountPct = 0}) {
  final sub = items.fold<int>(0, (a, l) => a + l.netCents);
  final f = 1 - discountPct.clamp(0, 100) / 100;
  final disc = sub - (sub * f).round();
  final vat = items.fold<int>(0, (a, l) => a + (l.netCents * f * l.vat / 100).round());
  return (subtotal: sub, discount: disc, vat: vat, total: sub - disc + vat);
}

/// Kuruşu iki ondalıklı metne çevirir: 123456 → "1234.56".
String centsText(int c) {
  final neg = c < 0;
  final a = c.abs();
  final s = '${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  return neg ? '-$s' : s;
}

// --------------------------------------------------------------- kartvizit

/// Kartvizit alanları.
class ContactCard {
  String name;
  String company;
  String title;
  String phone;
  String email;
  String web;
  String address;

  ContactCard({
    this.name = '',
    this.company = '',
    this.title = '',
    this.phone = '',
    this.email = '',
    this.web = '',
    this.address = '',
  });

  Map<String, Object?> toJson() => {
        'name': name, 'company': company, 'title': title, 'phone': phone,
        'email': email, 'web': web, 'address': address,
      };

  static ContactCard fromJson(Map<String, Object?> m) => ContactCard(
        name: m['name'] as String? ?? '',
        company: m['company'] as String? ?? '',
        title: m['title'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        web: m['web'] as String? ?? '',
        address: m['address'] as String? ?? '',
      );

  String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\\;').replaceAll('\n', '\\n');

  /// vCard 3.0 metni (rehber izni gerekmez; kullanıcı paylaşır).
  String toVCard() {
    final parts = name.trim().split(RegExp(r'\s+'));
    final last = parts.length > 1 ? parts.last : '';
    final first = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : name.trim();
    final b = StringBuffer()
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0')
      ..writeln('N:${_esc(last)};${_esc(first)};;;')
      ..writeln('FN:${_esc(name.trim())}');
    if (company.isNotEmpty) b.writeln('ORG:${_esc(company)}');
    if (title.isNotEmpty) b.writeln('TITLE:${_esc(title)}');
    for (final p in phone.split(RegExp(r'[,;\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      b.writeln('TEL;TYPE=CELL:${_esc(p)}');
    }
    if (email.isNotEmpty) b.writeln('EMAIL;TYPE=INTERNET:${_esc(email)}');
    if (web.isNotEmpty) b.writeln('URL:${_esc(web)}');
    if (address.isNotEmpty) b.writeln('ADR;TYPE=WORK:;;${_esc(address)};;;;');
    b.write('END:VCARD');
    return b.toString();
  }
}

final _email = RegExp(r'[\w.+\-]+@[\w\-]+(\.[\w\-]+)+');
final _url = RegExp(r'((https?://)|(www\.))[^\s,;]+|\b[\w\-]+\.(com|net|org|io|co|dev|app|info|biz|de|fr|es|it|nl|tr|uk|eu|ru|jp|cn|in|br)(\.[a-z]{2})?\b', caseSensitive: false);
final _phone = RegExp(r'(\+?\d[\d\s().\-/]{6,}\d)');
final _titleWords = RegExp(
    r'\b(manager|director|engineer|ceo|cto|cfo|founder|owner|sales|consultant|designer|developer|specialist|'
    r'müdür|mudur|uzman|mühendis|muhendis|sahibi|kurucu|danışman|direktör|genel|koordinatör|'
    r'geschäftsführer|leiter|ingenieur|gerente|director|ingeniero|directeur|ingénieur|responsable)\b',
    caseSensitive: false);
final _companyWords = RegExp(
    r'\b(ltd|ltd\.|şti|sti|a\.ş|aş|inc|llc|gmbh|ag|s\.a|sa|srl|bv|corp|co\.|company|holding|group|grup|limited)\b',
    caseSensitive: false);

/// OCR metninden kartvizit alanlarını tahmin eder. Kullanıcı her zaman
/// düzeltebilir; bu yalnızca bir başlangıçtır.
ContactCard parseCardText(String text) {
  final c = ContactCard();
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final used = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final em = _email.firstMatch(l);
    if (em != null && c.email.isEmpty) {
      c.email = em.group(0)!;
      used.add(i);
      continue;
    }
    final ph = _phone.allMatches(l).map((m) => m.group(0)!.trim()).where((p) => p.replaceAll(RegExp(r'\D'), '').length >= 7);
    if (ph.isNotEmpty) {
      c.phone = [if (c.phone.isNotEmpty) c.phone, ...ph].join(', ');
      used.add(i);
      continue;
    }
    final u = _url.firstMatch(l);
    if (u != null && c.web.isEmpty && !l.contains('@')) {
      c.web = u.group(0)!;
      used.add(i);
      continue;
    }
  }
  for (var i = 0; i < lines.length; i++) {
    if (used.contains(i)) continue;
    final l = lines[i];
    if (c.company.isEmpty && _companyWords.hasMatch(l)) {
      c.company = l;
      used.add(i);
    } else if (c.title.isEmpty && _titleWords.hasMatch(l)) {
      c.title = l;
      used.add(i);
    }
  }
  // Ad: rakam içermeyen, 2-4 kelimelik ilk kullanılmamış satır.
  for (var i = 0; i < lines.length; i++) {
    if (used.contains(i)) continue;
    final l = lines[i];
    final words = l.split(RegExp(r'\s+'));
    if (!RegExp(r'\d').hasMatch(l) && words.length >= 2 && words.length <= 4) {
      c.name = l;
      used.add(i);
      break;
    }
  }
  // Adres: rakam içeren, kalan en uzun satır.
  final rest = [for (var i = 0; i < lines.length; i++) if (!used.contains(i) && RegExp(r'\d').hasMatch(lines[i])) lines[i]];
  if (rest.isNotEmpty) {
    rest.sort((a, b) => b.length.compareTo(a.length));
    c.address = rest.first;
  }
  if (c.company.isEmpty) {
    final left = [for (var i = 0; i < lines.length; i++) if (!used.contains(i) && lines[i] != c.address) lines[i]];
    if (left.isNotEmpty) c.company = left.first;
  }
  return c;
}

// ---------------------------------------------------------- zihin haritası

/// Zihin haritası düğümü.
class MindNode {
  final String id;
  String text;
  int color;
  final List<MindNode> children;
  MindNode(this.id, this.text, {this.color = 0, List<MindNode>? children}) : children = children ?? [];

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'color': color, 'c': [for (final c in children) c.toJson()]};

  static MindNode fromJson(Map<String, Object?> m) => MindNode(
        m['id'] as String? ?? '',
        m['text'] as String? ?? '',
        color: (m['color'] as num?)?.toInt() ?? 0,
        children: [for (final c in (m['c'] as List? ?? const [])) MindNode.fromJson((c as Map).cast<String, Object?>())],
      );

  MindNode? find(String id) {
    if (this.id == id) return this;
    for (final c in children) {
      final f = c.find(id);
      if (f != null) return f;
    }
    return null;
  }

  MindNode? parentOf(String id) {
    for (final c in children) {
      if (c.id == id) return this;
      final f = c.parentOf(id);
      if (f != null) return f;
    }
    return null;
  }

  int get count => 1 + children.fold<int>(0, (a, c) => a + c.count);
}

/// Yatay ağaç yerleşimi: derinlik → x, yaprak sırası → y. Her düğüm
/// çocuklarının ortasına hizalanır. Dönüş: kimlik → (sütun, satır).
Map<String, ({double x, double y})> layoutMind(MindNode root) {
  final out = <String, ({double x, double y})>{};
  var next = 0.0;
  double place(MindNode n, int depth) {
    if (n.children.isEmpty) {
      final y = next;
      next += 1;
      out[n.id] = (x: depth.toDouble(), y: y);
      return y;
    }
    final ys = [for (final c in n.children) place(c, depth + 1)];
    final y = (ys.reduce(math.min) + ys.reduce(math.max)) / 2;
    out[n.id] = (x: depth.toDouble(), y: y);
    return y;
  }

  place(root, 0);
  return out;
}

/// Ağacı girintili düz metne çevirir (paylaşmak için).
String mindToText(MindNode n, [int depth = 0]) {
  final b = StringBuffer('${'  ' * depth}${depth == 0 ? '' : '- '}${n.text}\n');
  for (final c in n.children) {
    b.write(mindToText(c, depth + 1));
  }
  return b.toString();
}
