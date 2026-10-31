import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nami/anilist.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/detail.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/widgets.dart';
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

  group('marking episodes', () {
    late List<Map<String, dynamic>> saves;

    void answerSaves({bool fail = false}) {
      saves = [];
      AniList.instance.post = (uri, headers, body) async {
        final request = jsonDecode(body) as Map<String, dynamic>;
        if (!(request['query'] as String).contains('SaveMediaListEntry')) return http.Response('{}', 500);
        if (fail) return http.Response('{}', 500);
        final v = request['variables'] as Map<String, dynamic>;
        saves.add(v);
        return http.Response(
          jsonEncode({
            'data': {
              'SaveMediaListEntry': {'id': 1, 'progress': v['p'], 'status': v['s'], 'score': v['r']},
            },
          }),
          200,
        );
      };
      addTearDown(() => AniList.instance.post = null);
    }

    test('the status follows the progress', () {
      expect(full().statusAt(10), 'COMPLETED');
      expect(full().statusAt(4), 'CURRENT');
      expect(full().statusAt(0), 'CURRENT');
      final done = full().withEntry(ListEntry(id: 1, progress: 10, status: 'COMPLETED'));
      expect(done.statusAt(4), 'CURRENT');
      final rewatch = full().withEntry(ListEntry(id: 1, progress: 2, status: 'REPEATING'));
      expect(rewatch.statusAt(4), 'REPEATING');
      expect(rewatch.statusAt(10), 'COMPLETED');
      final airing = Media({...full().json, 'episodes': null});
      expect(airing.statusAt(500), 'CURRENT');
    });

    testWidgets('a long press marks everything up to an episode, keeping the score', (tester) async {
      answerSaves();
      await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
      await tester.longPress(find.text('Épisode 6'));
      await tester.pumpAndSettle();
      expect(find.text("Non vu à partir d'ici"), findsNothing);
      await tester.tap(find.text('Vu jusqu\'ici'));
      await tester.pumpAndSettle();
      expect(saves, [
        {'id': 195539, 's': 'CURRENT', 'p': 6, 'r': 85},
      ]);
      expect(find.text('6 · Vu'), findsOneWidget);
      expect(find.text('7 · À voir'), findsOneWidget);
    });

    testWidgets('marking a watched episode unwatched brings the progress back before it', (tester) async {
      answerSaves();
      await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
      await tester.longPress(find.text('Épisode 2'));
      await tester.pumpAndSettle();
      expect(find.text('Vu jusqu\'ici'), findsNothing);
      await tester.tap(find.text("Non vu à partir d'ici"));
      await tester.pumpAndSettle();
      expect(saves.single['p'], 1);
      expect(find.text('2 · À voir'), findsOneWidget);
    });

    testWidgets('the last episode completes the anime', (tester) async {
      answerSaves();
      await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
      await tester.longPress(find.text('Épisode 10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vu jusqu\'ici'));
      await tester.pumpAndSettle();
      expect(saves.single, containsPair('s', 'COMPLETED'));
    });

    testWidgets('a right click opens the same menu on Windows', (tester) async {
      answerSaves();
      await pumpDetail(tester, full(), desktop: true, size: const Size(1600, 2400));
      await tester.tap(find.text('Épisode 6'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Vu jusqu\'ici'), findsOneWidget);
    });

    testWidgets('the menu key opens it for the focused episode', (tester) async {
      answerSaves();
      await pumpDetail(tester, full(), desktop: true, size: const Size(1600, 2400));
      Focus.of(tester.element(find.text('Épisode 6'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.text('Vu jusqu\'ici'), findsOneWidget);
    });

    testWidgets('a failed save says so and changes nothing', (tester) async {
      answerSaves(fail: true);
      await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
      await tester.longPress(find.text('Épisode 6'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vu jusqu\'ici'));
      await tester.pumpAndSettle();
      expect(find.text("L'enregistrement a échoué. Réessaie."), findsOneWidget);
      expect(find.text('3 · Vu'), findsOneWidget);
      expect(find.text('6 · Vu'), findsNothing);
    });

    testWidgets('without an AniList account there is no menu', (tester) async {
      await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400), loggedIn: false);
      await tester.longPress(find.text('Épisode 6'));
      await tester.pumpAndSettle();
      expect(find.text('Vu jusqu\'ici'), findsNothing);
    });

    testWidgets('a watched episode no longer shows where it was left', (tester) async {
      SharedPreferences.setMockInitialValues({'appLanguage': 'fr', 'anilistToken': 'x'});
      await AppSettings.load();
      AppSettings.instance.setResume(195539, 2, const Duration(minutes: 10), length: const Duration(minutes: 28));
      debugDesktopOverride = false;
      addTearDown(() => debugDesktopOverride = null);
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: Nami.theme(),
          home: DetailScreen(media: full()),
        ),
      );
      await tester.pump();
      expect(find.text('2 · Vu'), findsOneWidget);
      expect(find.byType(ProgressLine), findsOneWidget); // The progress bar under the title only.
    });
  });
}
