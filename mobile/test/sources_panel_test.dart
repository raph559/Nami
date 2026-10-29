import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/extensions.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/sources.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

final media = Media({
  'id': 1,
  'title': <String, dynamic>{'romaji': 'Frieren'},
  'episodes': 28,
  'format': 'TV',
});

Future<List<Object?>> pumpOpener(WidgetTester tester, {required bool desktop}) async {
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
  await AppSettings.load();
  // No extension installed: the sheet shows its empty state, which is enough here.
  expect(ExtensionStore.instance.enabled, isEmpty);
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = desktop ? const Size(1600, 900) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <Object?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: desktop ? Nami.desktopTheme() : Nami.theme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => results.add(await pickSource(context, media, 4)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('desktop opens a right panel', (tester) async {
    await pumpOpener(tester, desktop: true);
    expect(find.byType(SourcesSheet), findsOneWidget);
    final rect = tester.getRect(find.byKey(SourcesPanel.panelKey));
    expect(rect.left, 1600 - SourcesPanel.width);
    expect(rect.height, 900);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Fermer'), findsOneWidget);
  });

  testWidgets('Escape closes the panel and returns null', (tester) async {
    final results = await pumpOpener(tester, desktop: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SourcesSheet), findsNothing);
    expect(results, [null]);
  });

  testWidgets('a click beside the panel closes it', (tester) async {
    await pumpOpener(tester, desktop: true);
    await tester.tapAt(const Offset(200, 450));
    await tester.pumpAndSettle();
    expect(find.byType(SourcesSheet), findsNothing);
  });

  testWidgets('touch keeps the bottom sheet', (tester) async {
    await pumpOpener(tester, desktop: false);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(SourcesPanel.panelKey), findsNothing);
  });
}
