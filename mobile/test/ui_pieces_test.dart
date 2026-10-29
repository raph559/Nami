import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/tabs.dart';
import 'package:nami/ui/tags.dart';
import 'package:shared_preferences/shared_preferences.dart';

const labels = ['En cours', 'À voir', 'Terminé', 'Revisionnage', 'En pause', 'Abandonné'];

Widget host(Widget child, {double width = 1000, double textScale = 1}) => MaterialApp(
  theme: Nami.theme(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

Color? textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color ??
    DefaultTextStyle.of(tester.element(find.text(text))).style.color;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  testWidgets('selected tab text is readable', (tester) async {
    await tester.pumpWidget(host(UnderlineTabs(labels: labels, selected: 0, onSelect: (_) {})));
    expect(textColor(tester, 'En cours'), Nami.text);
    // Nothing light is painted behind the selected label (the old chip filled it with off-white).
    expect(find.descendant(of: find.byType(UnderlineTabs), matching: find.byType(ChoiceChip)), findsNothing);
    expect(Nami.contrast(Nami.text, Nami.ground), greaterThan(4.5));
    expect(textColor(tester, 'À voir'), Nami.textSecondary);
  });

  testWidgets('the selected tab has a bar under it, apart from the text', (tester) async {
    await tester.pumpWidget(host(UnderlineTabs(labels: labels, selected: 1, onSelect: (_) {})));
    final bar = tester.getRect(find.byKey(UnderlineTabs.barKey));
    final text = tester.getRect(find.text('À voir'));
    expect(bar.height, 2);
    expect(bar.top - text.bottom, greaterThanOrEqualTo(8));
    expect(bar.left, closeTo(text.left, 0.5));
  });

  testWidgets('tabs report taps', (tester) async {
    int? picked;
    await tester.pumpWidget(host(UnderlineTabs(labels: labels, selected: 0, onSelect: (i) => picked = i)));
    await tester.tap(find.text('Terminé'));
    expect(picked, 2);
  });

  testWidgets('counts follow their label', (tester) async {
    await tester.pumpWidget(
      host(UnderlineTabs(labels: labels, counts: const [10, 37, null, 1, 10, 15], selected: 0, onSelect: (_) {})),
    );
    expect(find.text('37'), findsOneWidget);
    expect(textColor(tester, '37'), Nami.textMuted);
  });

  testWidgets('tabs at 200 % text', (tester) async {
    await tester.pumpWidget(
      host(UnderlineTabs(labels: labels, selected: 0, onSelect: (_) {}), width: 390, textScale: 2),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Abandonné'), findsOneWidget);
  });

  testWidgets('FlatTag selected colors', (tester) async {
    await tester.pumpWidget(
      host(
        Row(
          children: [
            FlatTag('Fantasy', selected: true, onTap: () {}),
            const FlatTag('Romance'),
          ],
        ),
      ),
    );
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.widgetWithText(FlatTag, 'Fantasy'), matching: find.byType(DecoratedBox)).first,
    );
    expect((box.decoration as BoxDecoration).color, Nami.text);
    expect(textColor(tester, 'Fantasy'), Nami.ground);
    expect(textColor(tester, 'Romance'), Nami.textSecondary);
  });

  testWidgets('a FlatTag without onTap is not a button', (tester) async {
    await tester.pumpWidget(host(const FlatTag('84 %')));
    expect(find.descendant(of: find.byType(FlatTag), matching: find.byType(InkWell)), findsNothing);
  });

  test('desktop buttons are 34 px high', () {
    final theme = Nami.desktopTheme();
    final size = theme.filledButtonTheme.style!.minimumSize!.resolve({});
    expect(size!.height, 34);
    expect(theme.outlinedButtonTheme.style!.minimumSize!.resolve({})!.height, 34);
  });
}
