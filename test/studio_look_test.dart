// Araç ekranlarının kendi parçaları onaylı tasarımda (StudioLook / studio_ui).
import 'package:verimlilik_motoru/verimlilik_motoru.dart';
import 'package:verimlilik_motoru/src/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/app/approved_hub.dart' show ApprovedLook;
import 'package:studio_core/app/services/ads.dart';
import 'package:studio_core/app/services/purchases.dart';
import 'package:studio_core/app/studio_ui.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:studio_core/core/save_store.dart';

final look = verHubStyle.look;

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

ToolContext ctxOf(String id) {
  final s = AppServices(hubId: 'm', backend: MemoryBackend(), ads: NoAdsService(), purchases: NoPurchaseService());
  return ToolContext(toolId: id, lang: 'tr', store: s.storeFor(id), services: s);
}

Widget host(Widget child) => StudioLookScope(
      look: look,
      child: MaterialApp(
        theme: buildStudioTheme(look),
        home: AppLook(style: verHubStyle, child: Scaffold(body: child)),
      ),
    );

void main() {
  test('koyu palette yazılar okunur', () {
    for (final bg in [look.sheet, look.base, look.background.first]) {
      expect(contrast(Colors.white, bg), greaterThanOrEqualTo(4.5));
    }
    expect(contrast(look.onAccent, look.accent), greaterThanOrEqualTo(4.5));
    final theme = buildStudioTheme(look);
    expect(contrast(theme.colorScheme.onSurface, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
    expect(theme.dialogTheme.backgroundColor, look.sheet);
  });

  testWidgets('seçenekler hap çip: seçili olan vurgu renginde, okunur', (tester) async {
    var sel = 0;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (c, set) => Choice<int>(
        values: const [0, 1, 2],
        labels: const ['Bir', 'İki', 'Üç'],
        selected: sel,
        onChanged: (v) => set(() => sel = v),
      ),
    )));
    expect(find.byType(StudioPill), findsNWidgets(3));
    await tester.tap(find.text('İki'));
    await tester.pump();
    expect(sel, 1);
    expect(tester.widget<StudioPill>(find.widgetWithText(StudioPill, 'İki')).selected, isTrue);
    final txt = tester.widget<Text>(find.text('İki'));
    expect(txt.style?.color, look.onAccent);
  });

  testWidgets('açılır liste ve metin alanı studio temasıyla açılır', (tester) async {
    var v = 'a';
    await tester.pumpWidget(host(Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Pick<String>(label: 'Liste', values: const ['a', 'b'], text: (x) => x.toUpperCase(), value: v, onChanged: (x) => v = x),
        AppTextField(controller: TextEditingController(text: 'yazı'), label: 'Metin'),
      ]),
    )));
    final field = tester.widget<InputDecorator>(find.byType(InputDecorator).last);
    expect(Theme.of(tester.element(find.byType(InputDecorator).last)).inputDecorationTheme.filled, isTrue);
    expect(field.decoration.labelText, 'Metin');
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();
    expect(v, 'b');
  });

  testWidgets('araç ekranı studio temasıyla açılır', (tester) async {
    final id = 'uyg-hedef-takibi';
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final t = ctxOf(id);
    await tester.pumpWidget(host(Builder(builder: (c) => verTool(id).builder(c, t))));
    await tester.pump(const Duration(milliseconds: 300));
    final pills = find.byType(StudioPill);
    if (pills.evaluate().length > 1) {
      await tester.tap(pills.at(1), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('silme onayı: studio diyaloğu, kırmızı simge', (tester) async {
    final t = ctxOf('uyg-hedef-takibi');
    await tester.pumpWidget(host(Builder(builder: (c) => TextButton(onPressed: () => confirmDelete(c, t), child: const Text('aç')))));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_rounded), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(AlertDialog))).dialogTheme.backgroundColor, look.sheet);
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
