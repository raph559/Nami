import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/detail.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media full() => Media({
  'id': 195539,
  'title': <String, dynamic>{'romaji': 'Cyberpunk: Edgerunners 2'},
  'format': 'ONA',
  'season': 'FALL',
  'seasonYear': 2026,
  'episodes': 10,
  'duration': 28,
  'averageScore': 84,
  'status': 'FINISHED',
  'genres': ['Action', 'Drama', 'Sci-Fi'],
  'studios': {
    'nodes': [
      {'name': 'TRIGGER'},
    ],
  },
  'mediaListEntry': {'id': 1, 'progress': 3, 'status': 'CURRENT', 'score': 85},
});

Media sparse() => Media({
  'id': 2,
  'title': <String, dynamic>{'romaji': 'Sparse'},
});

Future<void> pumpDetail(
  WidgetTester tester,
  Media media, {
  required bool desktop,
  Size? size,
  bool loggedIn = true,
}) async {
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr', if (loggedIn) 'anilistToken': 'x'});
  await AppSettings.load();
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = size ?? (desktop ? const Size(1600, 900) : const Size(390, 844));
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: desktop ? Nami.desktopTheme() : Nami.theme(),
      home: DetailScreen(media: media),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  test('meta line has format, season, episodes with length, and studio', () {
    expect(animeMetaLine(full()), 'ONA · Automne 2026 · 10 épisodes de 28 min · TRIGGER');
  });

  test('meta line skips missing parts', () {
    expect(animeMetaLine(sparse()), '');
    final noStudio = Media({...full().json, 'studios': null, 'season': null, 'duration': null});
    expect(animeMetaLine(noStudio), 'ONA · 2026 · 10 épisodes');
    expect(animeMetaLine(noStudio), isNot(contains('· ·')));
  });

  testWidgets('score button shows when rated', (tester) async {
    await pumpDetail(tester, full(), desktop: true);
    expect(find.widgetWithIcon(OutlinedButton, Icons.star_rounded), findsOneWidget);
    expect(find.text('8,5'), findsOneWidget);
    expect(find.text('En cours'), findsWidgets);
  });

  testWidgets('desktop page shows the facts card', (tester) async {
    await pumpDetail(tester, full(), desktop: true);
    for (final label in ['Score', 'Statut', 'Genres', 'Studio']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('TRIGGER'), findsOneWidget);
    expect(find.text('Terminé'), findsOneWidget);
  });

  testWidgets('phone page shows facts as tags', (tester) async {
    await pumpDetail(tester, full(), desktop: false);
    expect(find.text('84 %'), findsOneWidget);
    expect(find.text('Score'), findsNothing);
  });

  testWidgets('anime page with sparse data', (tester) async {
    await pumpDetail(tester, sparse(), desktop: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Studio'), findsNothing);
    await pumpDetail(tester, sparse(), desktop: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop page at the smallest window', (tester) async {
    await pumpDetail(tester, full(), desktop: true, size: const Size(720, 480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resumed episode says how much is left', (tester) async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr', 'anilistToken': 'x'});
    await AppSettings.load();
    AppSettings.instance.setResume(195539, 4, const Duration(minutes: 10), length: const Duration(minutes: 28));
    debugDesktopOverride = true;
    addTearDown(() => debugDesktopOverride = null);
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: Nami.desktopTheme(),
        home: DetailScreen(media: full()),
      ),
    );
    await tester.pump();
    expect(find.text('4 · En cours · 18 min restantes'), findsOneWidget);
  });

  testWidgets('small window tags show each genre apart and no studio', (tester) async {
    await pumpDetail(tester, full(), desktop: true, size: const Size(900, 1200));
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Drame'), findsOneWidget);
    expect(find.text('Action, Drame, Science-fiction'), findsNothing);
    // The studio is already in the line under the title.
    expect(find.text('TRIGGER'), findsNothing);
  });

  testWidgets('no empty tag row when only the studio is known', (tester) async {
    final media = Media({
      'id': 3,
      'title': <String, dynamic>{'romaji': 'Only studio'},
      'studios': {
        'nodes': [
          {'name': 'TRIGGER'},
        ],
      },
    });
    await pumpDetail(tester, media, desktop: false);
    expect(find.byType(Wrap), findsNothing);
  });
}
