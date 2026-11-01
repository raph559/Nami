import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nami/anilist.dart';
import 'package:nami/downloads.dart';
import 'package:nami/engine.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/detail.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A download that never gets anywhere.
class HeldBackend implements DownloadBackend {
  @override
  Future<List<String>> sources(Media media, int episode) => Completer<List<String>>().future;
  @override
  Future<EngineTorrent> add(String link, String dir) => throw EngineException('no');
  @override
  Future<void> keep(String hash, int index) async {}
  @override
  Future<void> pause(String hash, int index) async {}
  @override
  Future<KeepStats?> stats(String hash, int index) async => null;
  @override
  Future<void> finish(String hash, int index, String dest) async {}
  @override
  Future<void> unkeep(String hash, int index) async {}
  @override
  Future<void> saveCover(String url, String dest) async {}
}

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

    testWidgets('without an AniList account the menu only downloads', (tester) async {
      await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400), loggedIn: false);
      await tester.longPress(find.text('Épisode 6'));
      await tester.pumpAndSettle();
      expect(find.text('Vu jusqu\'ici'), findsNothing);
      expect(find.text('Télécharger'), findsOneWidget);
    });

    group('downloads', () {
      late Downloads store;

      setUp(() {
        final previous = Downloads.instance;
        store = Downloads(backend: HeldBackend())..root = Directory.systemTemp.path;
        Downloads.instance = store;
        addTearDown(() => Downloads.instance = previous);
      });

      testWidgets('the menu starts a download and the row says so', (tester) async {
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        await tester.longPress(find.text('Épisode 6'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Télécharger'));
        await tester.pumpAndSettle();
        expect(store.entry(195539, 6), isNull);
        expect(find.text("Télécharger l'épisode 6 ?"), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Télécharger'));
        await tester.pumpAndSettle();
        expect(store.entry(195539, 6), isNotNull);
        expect(find.text('6 · Téléchargement · 0 %'), findsOneWidget);
        await tester.longPress(find.text('Épisode 6'));
        await tester.pumpAndSettle();
        expect(find.text('Annuler le téléchargement'), findsOneWidget);
        await tester.tap(find.text('Annuler le téléchargement'));
        await tester.pumpAndSettle();
        expect(store.entry(195539, 6), isNotNull);
        expect(find.text('Annuler le téléchargement ?'), findsOneWidget);
        await tester.tap(find.text('Continuer'));
        await tester.pumpAndSettle();
        expect(store.entry(195539, 6), isNotNull);
        await tester.longPress(find.text('Épisode 6'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annuler le téléchargement'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Annuler le téléchargement'));
        await tester.pumpAndSettle();
        expect(store.entry(195539, 6), isNull);
      });

      testWidgets('refusing the question starts nothing', (tester) async {
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        await tester.tap(find.byTooltip('Télécharger').at(5));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(store.entry(195539, 6), isNull);
      });

      testWidgets('every episode has a visible download button', (tester) async {
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        expect(find.byTooltip('Télécharger'), findsNWidgets(10));
        await tester.tap(find.byTooltip('Télécharger').at(5));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Télécharger'));
        await tester.pumpAndSettle();
        expect(store.entry(195539, 6), isNotNull);
        expect(find.byTooltip('Télécharger'), findsNWidgets(9));
        await tester.tap(find.byTooltip('Mettre en pause'));
        await tester.pump();
        expect(store.entry(195539, 6)!.state, DownloadState.paused);
        expect(find.text('6 · En pause · 0 %'), findsOneWidget);
        await tester.tap(find.byTooltip('Reprendre'));
        await tester.pump();
        expect(store.entry(195539, 6)!.state, isNot(DownloadState.paused));
      });

      testWidgets('the menu of a running download pauses or cancels, and a paused one resumes', (tester) async {
        final running = DownloadEntry(media: full(), episode: 6, state: DownloadState.running, done: 25, total: 100);
        store.entries.add(running);
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        await tester.longPress(find.text('Épisode 6'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Mettre en pause'), findsOneWidget);
        expect(find.text('Annuler le téléchargement'), findsOneWidget);
        await tester.tap(find.text('Mettre en pause'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(running.state, DownloadState.paused);
        await tester.longPress(find.text('Épisode 6'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Reprendre'), findsOneWidget);
      });

      testWidgets('the button also shows on the Windows episode cards', (tester) async {
        await pumpDetail(tester, full(), desktop: true, size: const Size(1600, 2400));
        expect(find.byTooltip('Télécharger'), findsNWidgets(10));
        expect(tester.takeException(), isNull);
      });

      testWidgets('without an account the button is there too', (tester) async {
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400), loggedIn: false);
        expect(find.byTooltip('Télécharger'), findsNWidgets(10));
      });

      testWidgets('a running download shows how far it got', (tester) async {
        store.entries.add(DownloadEntry(media: full(), episode: 6, state: DownloadState.running, done: 25, total: 100));
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
        expect(ring.value, 0.25);
      });

      testWidgets('one tap never deletes a finished episode', (tester) async {
        store.entries.add(DownloadEntry(media: full(), episode: 6, state: DownloadState.done, file: '1.mkv'));
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        expect(find.byTooltip('Supprimer le téléchargement'), findsNothing);
        expect(find.byTooltip('Annuler le téléchargement'), findsNothing);
      });

      testWidgets('a stuck download retries from its button', (tester) async {
        store.entries.add(DownloadEntry(media: full(), episode: 6, state: DownloadState.failed));
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        await tester.tap(find.byTooltip('Réessayer'));
        await tester.pump();
        expect(store.entry(195539, 6)!.state, isNot(DownloadState.failed));
      });

      testWidgets('a finished episode shows its icon and can be deleted', (tester) async {
        store.entries.add(DownloadEntry(media: full(), episode: 6, state: DownloadState.done, file: '1.mkv'));
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        expect(find.byIcon(Icons.download_done), findsOneWidget);
        await tester.longPress(find.text('Épisode 6'));
        await tester.pumpAndSettle();
        expect(find.text('Supprimer le téléchargement'), findsOneWidget);
        expect(find.text('Télécharger'), findsNothing);
      });

      testWidgets('a stuck download offers to retry or delete', (tester) async {
        store.entries.add(DownloadEntry(media: full(), episode: 6, state: DownloadState.failed));
        await pumpDetail(tester, full(), desktop: false, size: const Size(390, 2400));
        expect(find.text('6 · Téléchargement bloqué'), findsOneWidget);
        await tester.longPress(find.text('Épisode 6'));
        await tester.pumpAndSettle();
        expect(find.text('Réessayer'), findsOneWidget);
        expect(find.text('Supprimer le téléchargement'), findsOneWidget);
      });
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
