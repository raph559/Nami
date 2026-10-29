import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/main.dart';
import 'package:nami/platform.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/desktop_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

const pages = [Text('page home'), Text('page search'), Text('page list'), Text('page settings')];

Future<void> pumpRoot(WidgetTester tester, {required bool desktop, Size size = const Size(1600, 900)}) async {
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: Nami.theme(),
      home: const RootScreen(pages: pages),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  testWidgets('desktop shows a slim rail with a tooltip per page', (tester) async {
    await pumpRoot(tester, desktop: true);
    expect(find.byType(DesktopShell), findsOneWidget);
    for (final label in ['Accueil', 'Recherche', 'Ma liste', 'Réglages']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(find.byType(VerticalDivider), findsNothing);
    // Labels live in tooltips only: no text under the icons.
    expect(find.text('Recherche'), findsNothing);
    expect(tester.getSize(find.byKey(DesktopShell.railKey)).width, 60);
  });

  testWidgets('clicking a rail icon shows its page', (tester) async {
    await pumpRoot(tester, desktop: true);
    await tester.tap(find.byTooltip('Recherche'));
    await tester.pump();
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1);
  });

  testWidgets('the selected rail item says so to screen readers', (tester) async {
    await pumpRoot(tester, desktop: true);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byTooltip('Accueil')),
      matchesSemantics(
        isSelected: true,
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        tooltip: 'Accueil',
      ),
    );
    handle.dispose();
  });

  testWidgets('pages get the rail width as left padding', (tester) async {
    await pumpRoot(tester, desktop: true);
    final ctx = tester.element(find.text('page home'));
    expect(MediaQuery.paddingOf(ctx).left, 60);
  });

  testWidgets('touch keeps the bottom bar', (tester) async {
    await pumpRoot(tester, desktop: false, size: const Size(390, 844));
    expect(find.byType(DesktopShell), findsNothing);
  });

  testWidgets('phone bar labels only the selected tab', (tester) async {
    await pumpRoot(tester, desktop: false, size: const Size(390, 844));
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Recherche'), findsNothing);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Recherche'), findsOneWidget);
    handle.dispose();
  });
}
