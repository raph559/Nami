import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/main.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/search.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/tags.dart';
import 'package:shared_preferences/shared_preferences.dart';

final calls = <(String, List<String>)>[];

Future<List<Media>> fakeSearch(String text, {List<String> genres = const []}) async {
  calls.add((text, genres));
  return [
    Media({
      'id': 1,
      'title': <String, dynamic>{'romaji': 'Result'},
    }),
  ];
}

Future<void> pumpRoot(WidgetTester tester, {bool desktop = true}) async {
  calls.clear();
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
  await AppSettings.load();
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = desktop ? const Size(1600, 900) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: desktop ? Nami.desktopTheme() : Nami.theme(),
      home: const RootScreen(
        pages: [
          Text('home'),
          SearchScreen(search: fakeSearch),
          Text('list'),
          Text('settings'),
        ],
      ),
    ),
  );
  await tester.pump();
}

EditableText field(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText, skipOffstage: false));

Future<void> goToSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Recherche'));
  await tester.pump();
}

void main() {
  testWidgets('two genres are sent together', (tester) async {
    await pumpRoot(tester);
    await goToSearch(tester);
    await tester.tap(find.widgetWithText(FlatTag, 'Fantastique'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FlatTag, 'Romance'));
    await tester.pump();
    expect(calls.last.$2, ['Fantasy', 'Romance']);
    await tester.tap(find.widgetWithText(FlatTag, 'Fantastique'));
    await tester.pump();
    expect(calls.last.$2, ['Romance']);
  });

  testWidgets('the heading counts the results', (tester) async {
    await pumpRoot(tester);
    await goToSearch(tester);
    await tester.enterText(find.byType(TextField), 'frieren');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Résultats · 1 anime'), findsOneWidget);
  });

  testWidgets('Ctrl+K focuses search from Home', (tester) async {
    await pumpRoot(tester);
    expect(field(tester).focusNode.hasFocus, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(field(tester).focusNode.hasFocus, isTrue);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
  });

  testWidgets('slash focuses search too', (tester) async {
    await pumpRoot(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(field(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('Escape clears the query', (tester) async {
    await pumpRoot(tester);
    await goToSearch(tester);
    await tester.enterText(find.byType(TextField), 'frieren');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(field(tester).controller.text, '');
  });

  testWidgets('touch has no keyboard shortcut', (tester) async {
    await pumpRoot(tester, desktop: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });
}
