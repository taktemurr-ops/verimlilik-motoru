import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:verimlilik_motoru/verimlilik_motoru.dart';

List<int> _ascii(String s) => ascii.encode(s);

/// Paketin gömülü yazı tipi (DejaVu Sans): Türkçe, Arapça, ✓ işaretleri.
pw.ThemeData _theme() {
  pw.Font f(String n) => pw.Font.ttf(ByteData.sublistView(File('assets/fonts/$n').readAsBytesSync()));
  return pw.ThemeData.withFont(base: f('DejaVuSans.ttf'), bold: f('DejaVuSans-Bold.ttf'));
}

/// Protobuf alanı (uzunluklu) – test için toplu aktarım verisi üretir.
List<int> _ld(int field, List<int> data) => [(field << 3) | 2, ..._varint(data.length), ...data];
List<int> _vi(int field, int v) => [(field << 3), ..._varint(v)];
List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

void main() {
  group('TOTP / HOTP (RFC 6238 / 4226)', () {
    final k1 = _ascii('12345678901234567890');
    final k256 = _ascii('12345678901234567890123456789012');
    final k512 = _ascii('1234567890123456789012345678901234567890123456789012345678901234');

    test('RFC 4226 HOTP test vektörleri', () {
      const want = ['755224', '287082', '359152', '969429', '338314', '254676', '287922', '162583', '399871', '520489'];
      for (var i = 0; i < want.length; i++) {
        expect(hotp(k1, i), want[i], reason: 'sayaç $i');
      }
    });

    test('RFC 6238 TOTP test vektörleri (8 hane)', () {
      final cases = <(int, String, String, String)>[
        (59, '94287082', '46119246', '90693936'),
        (1111111109, '07081804', '68084774', '25091201'),
        (1111111111, '14050471', '67062674', '99943326'),
        (1234567890, '89005924', '91819424', '93441116'),
        (2000000000, '69279037', '90698825', '38618901'),
        (20000000000, '65353130', '77737706', '47863826'),
      ];
      for (final c in cases) {
        expect(totp(k1, c.$1, digits: 8), c.$2, reason: 'SHA1 ${c.$1}');
        expect(totp(k256, c.$1, digits: 8, algo: OtpAlgo.sha256), c.$3, reason: 'SHA256 ${c.$1}');
        expect(totp(k512, c.$1, digits: 8, algo: OtpAlgo.sha512), c.$4, reason: 'SHA512 ${c.$1}');
      }
    });

    test('Base32', () {
      expect(base32Encode(_ascii('foobar')), 'MZXW6YTBOI');
      expect(utf8.decode(base32Decode('mzxw 6ytb-oi======')!), 'foobar');
      expect(base32Decode('MZXW1'), isNull);
      expect(base32Encode(base32Decode('JBSWY3DPEHPK3PXP')!), 'JBSWY3DPEHPK3PXP');
    });

    test('otpauth:// ayrıştırma', () {
      final a = parseOtpauth('otpauth://totp/Ornek%20Sirket:ali@ornek.com?secret=JBSWY3DPEHPK3PXP&issuer=Ornek%20Sirket&digits=8&period=60&algorithm=SHA256', id: '1')!;
      expect(a.issuer, 'Ornek Sirket');
      expect(a.label, 'ali@ornek.com');
      expect(a.digits, 8);
      expect(a.period, 60);
      expect(a.algo, OtpAlgo.sha256);
      expect(a.code(59).length, 8);
      expect(a.remaining(59), 1);
      final h = parseOtpauth('otpauth://hotp/x?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&counter=1', id: '2')!;
      expect(h.hotpMode, isTrue);
      expect(h.code(0), '287082');
      expect(parseOtpauth('otpauth://totp/x?secret=!!!', id: '3'), isNull);
      expect(parseOtpauth('https://example.com', id: '4'), isNull);
    });

    test('toplu aktarım (otpauth-migration) çözülür', () {
      final p1 = [
        ..._ld(1, _ascii('12345678901234567890')),
        ..._ld(2, utf8.encode('Örnek:ayşe@ornek.com')),
        ..._vi(4, 1),
        ..._vi(5, 1),
        ..._vi(6, 2),
      ];
      final p2 = [..._ld(1, [1, 2, 3, 4, 5]), ..._ld(2, utf8.encode('kod')), ..._ld(3, utf8.encode('Servis')), ..._vi(4, 4)];
      final payload = [..._ld(1, p1), ..._ld(1, p2), ..._vi(2, 1)];
      final uri = 'otpauth-migration://offline?data=${Uri.encodeQueryComponent(base64Encode(payload))}';
      var n = 0;
      final l = parseMigration(uri, newId: () => '${n++}');
      expect(l.length, 1); // MD5 kaydı atlanır
      expect(l.single.issuer, 'Örnek');
      expect(l.single.label, 'ayşe@ornek.com');
      expect(l.single.code(59), totp(_ascii('12345678901234567890'), 59));
      expect(parseMigration('otpauth-migration://offline?data=@@@', newId: () => 'x'), isEmpty);
    });

    test('hesap listesi JSON gidiş-dönüş', () {
      final a = OtpAccount(id: '1', issuer: 'A', label: 'b', secret: 'JBSWY3DPEHPK3PXP', digits: 6);
      final l = decodeAccounts(encodeAccounts([a, a.copyWith(counter: 3)]));
      expect(l.length, 2);
      expect(l[1].counter, 3);
      expect(l[0].sameAs(a), isTrue);
      expect(groupCode('123456'), '123 456');
      expect(groupCode('12345678'), '1234 5678');
    });
  });

  group('odak istatistiği', () {
    test('bugün, hafta ve seri', () {
      final now = DateTime(2026, 11, 26, 15);
      int at(int daysAgo) => DateTime(2026, 11, 26 - daysAgo, 10).millisecondsSinceEpoch;
      final s = focusStats([
        {'at': at(0), 'min': 25, 'done': true},
        {'at': at(1), 'min': 50, 'done': true},
        {'at': at(2), 'min': 25, 'done': true},
        {'at': at(4), 'min': 25, 'done': true},
        {'at': at(9), 'min': 90, 'done': true},
        {'at': at(0), 'min': 10, 'done': false},
      ], now);
      expect(s.todayMin, 35);
      expect(s.weekMin, 135);
      expect(s.done, 5);
      expect(s.streak, 3);
      expect(focusStats([{'at': at(1), 'min': 25, 'done': true}], now).streak, 1);
    });
  });

  group('özgeçmiş', () {
    test('33 dilde 10 başlık, aralık metni, yazı sistemi', () {
      for (final l in kCvLangs) {
        final h = cvHeads(l);
        expect(h.length, 10, reason: l);
        expect(h.every((x) => x.isNotEmpty), isTrue, reason: l);
      }
      expect(cvRange({'from': '2020', 'cur': true}, 'Halen'), '2020 – Halen');
      expect(cvRange({'from': '2018', 'to': '2020'}, 'x'), '2018 – 2020');
      expect(cvScripts('Ayşe Yılmaz Привет שלום مرحبا'), isEmpty);
      expect(cvScripts('東京 서울 ไทย हिन्दी বাংলা'), containsAll(['zh', 'ko', 'th', 'hi', 'bn']));
    });

    test('her şablon PDF üretir', () async {
      for (final tpl in kCvTemplates) {
        final cv = newCv('tr')
          ..['tpl'] = tpl
          ..['p'] = {'name': 'Ayşe Yılmaz', 'title': 'Yazılım Geliştirici', 'email': 'ayse@ornek.com', 'city': 'İzmir'}
          ..['summary'] = 'Mobil uygulamalarda 6 yıl deneyim.'
          ..['exp'] = [
            {'role': 'Kıdemli Geliştirici', 'org': 'Örnek A.Ş.', 'from': '2021', 'cur': true, 'desc': 'Uygulamayı yeniden yazdı\n- Çökmeleri %70 azalttı'},
          ]
          ..['edu'] = [{'degree': 'Bilgisayar Mühendisliği', 'school': 'Ege Üniversitesi', 'from': '2013', 'to': '2017'}]
          ..['skills'] = ['Flutter', 'Dart', 'Kotlin']
          ..['langs'] = [{'name': 'İngilizce', 'level': 'C1'}];
        final b = await buildCvPdf(cv, theme: _theme());
        expect(ascii.decode(b.sublist(0, 4)), '%PDF', reason: tpl);
      }
      final ar = await buildCvPdf(newCv('ar')..['p'] = {'name': 'سارة'}, theme: _theme());
      expect(ar.length, greaterThan(500));
    });
  });

  group('PDF imza', () {
    test('imza çizgileri JSON gidiş-dönüş', () {
      final s = [
        [const Offset(0.1, 0.2), const Offset(0.5, 0.6)],
        [const Offset(0.7, 0.7)],
      ];
      final back = strokesFromJson(strokesToJson(s));
      expect(back.length, 2);
      expect(back[0][1].dx, closeTo(0.5, 1e-6));
      expect(strokesFromJson('bozuk'), isEmpty);
    });

    test('işaretli sayfadan PDF üretilir', () async {
      final png = img.encodePng(img.Image(width: 8, height: 12));
      final b = await buildSignedPdf(
        pages: [(Uint8List.fromList(png), 1240, 1754)],
        dpi: 150,
        marks: [
          SignMark(SignKind.text, 0, 0.1, 0.1, text: 'Ad Soyad'),
          SignMark(SignKind.check, 0, 0.2, 0.3),
          SignMark(SignKind.sign, 0, 0.5, 1.2, size: 0.3),
        ],
        signature: [
          [const Offset(0, 0.5), const Offset(0.5, 0.2), const Offset(1, 0.8)],
        ],
        initials: const [],
        theme: _theme(),
      );
      expect(ascii.decode(b.sublist(0, 4)), '%PDF');
    });
  });
}
