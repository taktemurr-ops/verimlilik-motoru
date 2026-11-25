import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:studio_core/app/services/ads.dart';
import 'package:studio_core/app/services/purchases.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:studio_core/core/save_store.dart';
import 'package:verimlilik_motoru/verimlilik_motoru.dart';

void main() {
  test('29 uygulama, 33 dilde ad ve açıklama, benzersiz kimlik', () {
    expect(verTools.length, 29);
    expect(verTools.map((t) => t.id).toSet().length, 29);
    for (final t in verTools) {
      expect(t.title.length, 33, reason: t.id);
      expect(t.tagline.length, 33, reason: t.id);
      expect(t.id.startsWith('uyg-'), isTrue);
      expect(verCategories.any((c) => c.id == t.category), isTrue, reason: t.id);
    }
    expect(verHubTitle.length, 33);
    for (final f in verFeatured) {
      expect(verTools.any((t) => t.id == f), isTrue, reason: f);
    }
    // Para ile ilgili uygulamalar finans uyarısı taşır.
    expect(verTool('uyg-fatura-fis-takip').disclaimer, AppDisclaimer.finance);
    expect(verTool('uyg-fatura-ve-teklif-hazirlayici').disclaimer, AppDisclaimer.finance);
  });

  group('metin araçları', () {
    test('sayaç', () {
      final s = TextStats.of('Merhaba dünya. Nasılsın?\n\nİyiyim!');
      expect(s.words, 4);
      expect(s.sentences, 3);
      expect(s.lines, 4);
      expect(s.paragraphs, 2);
      expect(s.chars, 'Merhaba dünya. Nasılsın?\n\nİyiyim!'.runes.length);
      expect(TextStats.of('').words, 0);
      expect(TextStats.of(List.filled(450, 'kelime').join(' ')).readingMinutes, 3);
    });
    test('Türkçe büyük/küçük harf', () {
      expect(upperFor('istanbul ılık', 'tr'), 'İSTANBUL ILIK');
      expect(lowerFor('IŞIK İZİ', 'tr'), 'ışık izi');
      expect(upperFor('istanbul', 'en'), 'ISTANBUL');
      expect(titleCase('merhaba DÜNYA', 'tr'), 'Merhaba Dünya');
      expect(sentenceCase('MERHABA. NASILSIN?', 'en'), 'Merhaba. Nasilsin?');
    });
    test('dönüştürücüler', () {
      expect(slugify('Çok Güzel Şeyler İçin!'), 'cok-guzel-seyler-icin');
      expect(sortLines('b\nA\nc'), 'A\nb\nc');
      expect(removeDuplicateLines('a\nb\na'), 'a\nb');
      expect(reverseText('abc'), 'cba');
      expect(trimSpaces('  a   b \n\n\n\n c '), 'a b\n\nc');
      final (out, n) = findReplace('Kedi kedi KEDİ', 'kedi', 'köpek');
      expect(n, 2);
      expect(out, 'köpek köpek KEDİ');
    });
  });

  group('planlama', () {
    test('alışkanlık serisi', () {
      final today = DateTime(2026, 11, 25);
      expect(currentStreak({'2026-11-25', '2026-11-24', '2026-11-23'}, today), 3);
      expect(currentStreak({'2026-11-24', '2026-11-23'}, today), 2);
      expect(currentStreak({'2026-11-22'}, today), 0);
      expect(bestStreak({'2026-01-01', '2026-01-02', '2026-01-03', '2026-02-01'}), 3);
      expect(bestStreak({}), 0);
      // Ay ve yıl geçişleri.
      expect(currentStreak({'2027-01-01', '2026-12-31'}, DateTime(2027, 1, 1)), 2);
    });
    test('tekrarlayan hatırlatıcı', () {
      final start = DateTime(2026, 1, 31, 9, 0);
      expect(addRepeat(start, 3, 1), DateTime(2026, 2, 28, 9, 0));
      expect(addRepeat(start, 2, 1), DateTime(2026, 2, 7, 9, 0));
      final n = nextOccurrences(start, 1, DateTime(2026, 3, 1, 10, 0), 3);
      expect(n, [DateTime(2026, 3, 2, 9), DateTime(2026, 3, 3, 9), DateTime(2026, 3, 4, 9)]);
      expect(nextOccurrences(start, 0, DateTime(2026, 2, 1), 5), isEmpty);
      expect(nextOccurrences(start, 0, DateTime(2026, 1, 1), 5), [start]);
    });
    test('vardiya saatleri ve döngü', () {
      const kinds = [
        ShiftKind('d', 'Gündüz', 8 * 60, 16 * 60, 0),
        ShiftKind('n', 'Gece', 22 * 60, 6 * 60, 1),
        ShiftKind('o', 'İzin', 0, 0, 2),
      ];
      expect(kinds[1].minutes, 8 * 60);
      expect(kinds[2].minutes, 0);
      final plan = applyRotation(['d', 'd', 'n', 'o'], DateTime(2026, 2, 1), 28);
      expect(plan['2026-02-01'], 'd');
      expect(plan['2026-02-03'], 'n');
      expect(plan['2026-02-05'], 'd');
      // 28 gün: 7 döngü × (8+8+8) saat.
      expect(monthMinutes(plan, kinds, 2026, 2), 7 * 24 * 60);
    });
    test('zaman takibi toplamları', () {
      final a = DateTime(2026, 11, 25, 23, 0).millisecondsSinceEpoch;
      final b = DateTime(2026, 11, 26, 1, 0).millisecondsSinceEpoch;
      final m = totalsByProject([TimeEntry('X', a, b)], DateTime(2026, 11, 25), DateTime(2026, 11, 26));
      expect(m['X'], const Duration(hours: 1));
      expect(weekStart(DateTime(2026, 11, 26)), DateTime(2026, 11, 23));
    });
    test('pomodoro evreleri', () {
      expect(nextPhase(PomoPhase.focus, 1, 4), PomoPhase.shortBreak);
      expect(nextPhase(PomoPhase.focus, 4, 4), PomoPhase.longBreak);
      expect(nextPhase(PomoPhase.longBreak, 4, 4), PomoPhase.focus);
    });
  });

  group('belgeler', () {
    test('fatura toplamları kuruş hassasiyetinde', () {
      final items = [const LineItem('A', 3, 19.99, 20), const LineItem('B', 1, 100, 10)];
      final t = invoiceTotals(items);
      expect(t.subtotal, 15997);
      expect(t.vat, 1199 + 1000);
      expect(t.total, 15997 + 2199);
      final d = invoiceTotals(items, discountPct: 10);
      expect(d.discount, 1600);
      expect(d.total, 15997 - 1600 + (5997 * 0.9 * 0.2).round() + (10000 * 0.9 * 0.1).round());
      expect(centsText(123456), '1234.56');
      expect(centsText(-5), '-0.05');
    });
    test('kartvizit ayrıştırma ve vCard', () {
      final c = parseCardText('ACME Teknoloji Ltd. Şti.\nAyşe Yılmaz\nSatış Müdürü\n+90 532 123 45 67\nayse@acme.com.tr\nwww.acme.com.tr\nAtatürk Cd. No:5 İstanbul');
      expect(c.name, 'Ayşe Yılmaz');
      expect(c.email, 'ayse@acme.com.tr');
      expect(c.phone, '+90 532 123 45 67');
      expect(c.web, 'www.acme.com.tr');
      expect(c.company, 'ACME Teknoloji Ltd. Şti.');
      expect(c.title, 'Satış Müdürü');
      expect(c.address, contains('No:5'));
      final v = c.toVCard();
      expect(v, startsWith('BEGIN:VCARD'));
      expect(v, contains('FN:Ayşe Yılmaz'));
      expect(v, contains('N:Yılmaz;Ayşe;;;'));
      expect(v, contains('TEL;TYPE=CELL:+90 532 123 45 67'));
      expect(v, endsWith('END:VCARD'));
      expect(ContactCard(name: 'a;b').toVCard(), contains('FN:a\;b'));
    });
    test('zihin haritası yerleşimi', () {
      final root = MindNode('r', 'Kök', children: [
        MindNode('a', 'A', children: [MindNode('a1', 'A1'), MindNode('a2', 'A2')]),
        MindNode('b', 'B'),
      ]);
      final p = layoutMind(root);
      expect(p['a1']!.y, 0);
      expect(p['a2']!.y, 1);
      expect(p['a']!.y, 0.5);
      expect(p['b']!.y, 2);
      expect(p['r']!.y, 1.25);
      expect(p['a1']!.x, 2);
      expect(root.count, 5);
      expect(root.parentOf('a2')!.id, 'a');
      final back = MindNode.fromJson(root.toJson());
      expect(back.find('a2')!.text, 'A2');
      expect(mindToText(root), 'Kök\n  - A\n    - A1\n    - A2\n  - B\n');
    });
    test('sayfa düzleştirme', () {
      final src = img.Image(width: 200, height: 100);
      img.fill(src, color: img.ColorRgb8(255, 255, 255));
      final bytes = Uint8List.fromList(img.encodeJpg(src));
      final out = rectifyPage(RectifyJob(bytes, const [10, 10, 190, 10, 190, 90, 10, 90], turns: 1));
      expect(out, isNotNull);
      final d = img.decodeImage(out!)!;
      expect(d.width, 80);
      expect(d.height, 180);
    });
  });

  group('kayıt listeleri', () {
    test('sıralama: sabit, yapılmamış, vade', () {
      final items = <Map<String, Object?>>[
        {'id': '1', 'task': 'geç', 'due': '2026-12-01', 'done': false},
        {'id': '2', 'task': 'erken', 'due': '2026-11-01', 'done': false},
        {'id': '3', 'task': 'bitti', 'due': '2026-10-01', 'done': true},
        {'id': '4', 'task': 'tarihsiz', 'done': false},
        {'id': '5', 'task': 'sabit', 'done': false, 'pin': true},
      ];
      expect(sortRecords(items, kTodoSpec).map((r) => r['id']).toList(), ['5', '2', '1', '4', '3']);
      expect(matchesQuery(items[0], kTodoSpec, 'GE'), isTrue);
      expect(matchesQuery(items[0], kTodoSpec, 'xyz'), isFalse);
      expect(sumOf([{'amount': 2.5}, {'amount': 3}, {}], 'amount'), 5.5);
    });
    test('liste etiketleri 33 dilde', () {
      for (final s in [kNotesSpec, kTodoSpec, kHomeworkSpec, kReadingSpec, kWatchSpec, kReceiptSpec, kInventorySpec]) {
        expect(s.fields.any((f) => f.key == s.titleKey), isTrue);
      }
    });
  });

  // Eklentisiz açılabilen ekranlar (kamera, mikrofon, ML eklentileri test
  // ortamında yoktur; onlar cihazda denenir).
  for (final id in [
    'uyg-not-defteri', 'uyg-yapilacaklar-listesi', 'uyg-aliskanlik-takibi', 'uyg-pomodoro',
    'uyg-kontrol-ve-alisveris-listesi', 'uyg-hatirlatici', 'uyg-cizim-defteri', 'uyg-zihin-haritasi',
    'uyg-metin-araclari', 'uyg-ajanda-ve-gunluk', 'uyg-fatura-fis-takip', 'uyg-kanban-panosu',
    'uyg-zaman-takibi', 'uyg-fatura-ve-teklif-hazirlayici', 'uyg-okuma-listesi',
    'uyg-film-ve-dizi-izleme-listesi', 'uyg-ders-programi', 'uyg-odev-takibi', 'uyg-vardiya-planlayici',
    'uyg-sunum-zamanlayici-ve-teleprompter', 'uyg-pano-gecmisi', 'uyg-etiket-ve-envanter',
  ]) {
    testWidgets('ekran açılır: $id', (tester) async {
      final s = AppServices(hubId: 'm', backend: MemoryBackend(), ads: NoAdsService(), purchases: NoPurchaseService());
      final tool = verTool(id);
      final ctx = ToolContext(toolId: id, lang: 'tr', store: s.storeFor(id), services: s);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AppLook(style: verHubStyle, child: Scaffold(body: Builder(builder: (c) => tool.builder(c, ctx)))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
