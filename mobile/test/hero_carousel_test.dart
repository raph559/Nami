import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/home_feed.dart';
import 'package:nami/platform.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/airing_row.dart';
import 'package:nami/ui/hero_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media anime(int id) => Media({
  'id': id,
  'title': <String, dynamic>{'romaji': 'Anime $id'},
  'episodes': 12,
  'format': 'TV',
});

final items = [
  HeroItem(anime(1), 4, HeroReason.resume),
  HeroItem(anime(2), 3, HeroReason.newEpisode),
  HeroItem(anime(3), 1, HeroReason.trending),
];

Future<void> pumpHero(WidgetTester tester, {bool reduceMotion = false, bool desktop = true}) async {
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = desktop ? const Size(1600, 900) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: Nami.desktopTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: ListView(
              children: [HeroCarousel(items: items, onOpen: (_) {})],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  testWidgets('shows the first anime with why it is there', (tester) async {
    await pumpHero(tester);
    expect(find.text('Anime 1'), findsOneWidget);
    expect(find.text('Reprendre · épisode 4'), findsOneWidget);
    expect(find.text("Reprendre l'épisode 4"), findsOneWidget);
  });

  testWidgets('advances after 8 s', (tester) async {
    await pumpHero(tester);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('Anime 2'), findsOneWidget);
    expect(find.text('Nouvel épisode · 3'), findsOneWidget);
  });

  testWidgets('pauses while hovered', (tester) async {
    await pumpHero(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(HeroCarousel)));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('Anime 1'), findsOneWidget);
  });

  testWidgets('no auto-advance with reduced motion', (tester) async {
    await pumpHero(tester, reduceMotion: true);
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('Anime 1'), findsOneWidget);
  });

  testWidgets('the next arrow moves on, on desktop', (tester) async {
    await pumpHero(tester, reduceMotion: true);
    await tester.tap(find.byTooltip('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Anime 2'), findsOneWidget);
  });

  testWidgets('swiping moves on, on touch', (tester) async {
    await pumpHero(tester, reduceMotion: true, desktop: false);
    await tester.fling(find.byType(HeroCarousel), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Anime 2'), findsOneWidget);
  });

  testWidgets('airing row marks list anime and aired episodes', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        theme: Nami.theme(),
        home: Scaffold(
          body: AiringRow(
            items: [
              AiringItem(anime(1), 5, now.subtract(const Duration(hours: 1))),
              AiringItem(anime(2), 8, now.add(const Duration(hours: 1))),
            ],
            listIds: const {1},
          ),
        ),
      ),
    );
    expect(find.text('Dans ta liste'), findsOneWidget);
    expect(find.textContaining('sorti'), findsOneWidget);
    expect(find.text('Épisode 8'), findsOneWidget);
  });
}
