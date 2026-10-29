import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/platform.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/hover_card.dart';
import 'package:nami/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

final media = Media({
  'id': 7,
  'title': <String, dynamic>{'romaji': 'Frieren'},
  'episodes': 28,
  'format': 'TV',
  'description': 'A mage outlives her party.',
});

Future<TestGesture> pumpCard(WidgetTester tester, {required bool desktop}) async {
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: Nami.desktopTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(padding: const EdgeInsets.all(100), child: MediaCard(media, width: 120)),
        ),
      ),
    ),
  );
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1500, 850));
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  testWidgets('hover opens the card after 400 ms', (tester) async {
    final mouse = await pumpCard(tester, desktop: true);
    await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MediaHoverCard), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.byType(MediaHoverCard), findsOneWidget);
    expect(find.text("Regarder l'épisode 1"), findsOneWidget);
  });

  testWidgets('leaving closes it', (tester) async {
    final mouse = await pumpCard(tester, desktop: true);
    await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MediaHoverCard), findsOneWidget);
    await mouse.moveTo(const Offset(1500, 850));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MediaHoverCard), findsNothing);
  });

  testWidgets('moving onto the card keeps it open', (tester) async {
    final mouse = await pumpCard(tester, desktop: true);
    await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
    await tester.pump(const Duration(milliseconds: 500));
    await mouse.moveTo(tester.getCenter(find.byType(MediaHoverCard)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MediaHoverCard), findsOneWidget);
  });

  testWidgets('focus opens it and Escape closes it', (tester) async {
    await pumpCard(tester, desktop: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(MediaHoverCard), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MediaHoverCard), findsNothing);
  });

  testWidgets('no hover card on touch', (tester) async {
    final mouse = await pumpCard(tester, desktop: false);
    await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MediaHoverCard), findsNothing);
  });

  testWidgets('the card stays inside the window near the right edge', (tester) async {
    debugDesktopOverride = true;
    addTearDown(() => debugDesktopOverride = null);
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: Nami.desktopTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(padding: const EdgeInsets.all(20), child: MediaCard(media, width: 120)),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
    await tester.pump(const Duration(milliseconds: 500));
    final rect = tester.getRect(find.byType(MediaHoverCard));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.left, greaterThanOrEqualTo(0));
  });

  testWidgets('the card fades and grows in', (tester) async {
    final mouse = await pumpCard(tester, desktop: true);
    await mouse.moveTo(tester.getCenter(find.byType(MediaCard)));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 30));
    double opacity() => tester
        .widget<FadeTransition>(
          find.ancestor(of: find.byType(MediaHoverCard), matching: find.byType(FadeTransition)).first,
        )
        .opacity
        .value;
    expect(opacity(), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });
}
