import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/downloads.dart';
import 'package:nami/platform.dart';
import 'package:nami/player_center.dart';
import 'package:nami/screens/library.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/downloads_section.dart';
import 'package:nami/ui/tabs.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibraryEntry entry(String title, double score) => LibraryEntry(
  Media({
    'id': title.hashCode,
    'title': <String, dynamic>{'romaji': title},
    'episodes': 12,
  }),
  ListEntry(id: title.hashCode, progress: 3, status: 'CURRENT', score: score),
);

Future<Map<String, List<LibraryEntry>>> fakeLibrary() async => {
  'CURRENT': [entry('Bravo', 70), entry('Alpha', 90), entry('Charlie', 0)],
  'PLANNING': [entry('Delta', 0)],
};

Future<void> pumpLibrary(WidgetTester tester, {bool desktop = true, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr', 'anilistToken': 'x', ...prefs});
  await AppSettings.load();
  AniList.instance.viewer = Viewer({
    'id': 1,
    'name': 'raph559',
    'statistics': {
      'anime': {'count': 243, 'episodesWatched': 3879, 'minutesWatched': 95328},
    },
  });
  addTearDown(() => AniList.instance.viewer = null);
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = desktop ? const Size(1600, 900) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: desktop ? Nami.desktopTheme() : Nami.theme(),
      home: const LibraryScreen(loader: fakeLibrary),
    ),
  );
  await tester.pump();
  await tester.pump();
}

List<String> titlesInOrder(WidgetTester tester, List<String> titles) {
  final found = {
    for (final t in titles)
      if (find.text(t).evaluate().isNotEmpty) t: tester.getTopLeft(find.text(t)),
  };
  return found.keys.toList()..sort((a, b) {
    final pa = found[a]!, pb = found[b]!;
    return pa.dy != pb.dy ? pa.dy.compareTo(pb.dy) : pa.dx.compareTo(pb.dx);
  });
}

void main() {
  testWidgets('statuses are underlined tabs with counts', (tester) async {
    await pumpLibrary(tester);
    expect(find.byType(UnderlineTabs), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('sort choice reorders and persists', (tester) async {
    await pumpLibrary(tester);
    expect(titlesInOrder(tester, ['Alpha', 'Bravo', 'Charlie']), ['Bravo', 'Alpha', 'Charlie']);
    await tester.tap(find.byKey(LibraryScreen.sortKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Note').last);
    await tester.pumpAndSettle();
    expect(titlesInOrder(tester, ['Alpha', 'Bravo', 'Charlie']), ['Alpha', 'Bravo', 'Charlie']);
    expect(AppSettings.instance.prefs.getString('librarySort'), 'score');

    await pumpLibrary(tester, prefs: {'librarySort': 'score'});
    expect(titlesInOrder(tester, ['Alpha', 'Bravo', 'Charlie']), ['Alpha', 'Bravo', 'Charlie']);
  });

  testWidgets('no empty block without banner', (tester) async {
    await pumpLibrary(tester);
    expect(tester.getTopLeft(find.text('raph559')).dy, lessThan(120));
  });

  testWidgets('phone layout has the same tabs', (tester) async {
    await pumpLibrary(tester, desktop: false);
    expect(find.byType(UnderlineTabs), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('downloads', () {
    Media downloaded() => Media({
      'id': 9,
      'title': <String, dynamic>{'romaji': 'Gardé'},
      'episodes': 12,
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
      await AppSettings.load();
      debugDesktopOverride = false;
      addTearDown(() => debugDesktopOverride = null);
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: Nami.theme(), home: const DownloadsScreen()));
      await tester.pump();
    }

    setUp(() {
      final previous = Downloads.instance;
      Downloads.instance = Downloads()
        ..root = Directory.systemTemp.path
        ..entries.addAll([
          DownloadEntry(media: downloaded(), episode: 1, state: DownloadState.done, file: '9-1.mkv', total: 300000000),
          DownloadEntry(media: downloaded(), episode: 2, state: DownloadState.running, done: 25, total: 100),
          DownloadEntry(media: downloaded(), episode: 3, state: DownloadState.failed),
        ]);
      addTearDown(() => Downloads.instance = previous);
    });

    testWidgets('the link says what is there and opens the screen', (tester) async {
      await pumpLibrary(tester, desktop: false);
      expect(find.text('2 en cours · 300 MB'), findsOneWidget);
      await tester.tap(find.text('Téléchargements'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadsScreen), findsOneWidget);
    });

    testWidgets('the screen lists active downloads then what is kept, by anime', (tester) async {
      await pumpScreen(tester);
      expect(find.text('3 épisodes · 300 MB utilisés'), findsOneWidget);
      expect(find.text('En cours'), findsOneWidget);
      expect(find.text('Épisode 1 · 300 MB'), findsOneWidget);
      expect(find.text('Épisode 2 · Téléchargement · 25 %'), findsOneWidget);
      expect(find.text('Épisode 3 · Téléchargement bloqué'), findsOneWidget);
      expect(find.byTooltip('Réessayer'), findsOneWidget);
      expect(tester.getTopLeft(find.text('En cours')).dy, lessThan(tester.getTopLeft(find.text('Épisode 1 · 300 MB')).dy));
    });

    testWidgets('pause all and resume all come and go', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Tout mettre en pause'));
      await tester.pump();
      expect(find.text('Tout mettre en pause'), findsNothing);
      expect(find.text('Tout reprendre'), findsOneWidget);
    });

    testWidgets('the running row shows the time left and speed', (tester) async {
      final e = Downloads.instance.entry(9, 2)!
        ..speed = 1000000
        ..total = 600000000
        ..done = 300000000;
      await pumpScreen(tester);
      expect(find.text('Épisode 2 · Téléchargement · 50 % · 5 min restantes · 1.0 MB/s'), findsOneWidget);
      e.quiet = 20;
      Downloads.instance.networkChanged();
      await tester.pump();
      expect(find.text('Épisode 2 · Téléchargement · 50 % · En attente de pairs'), findsOneWidget);
    });

    testWidgets('waiting rows can be dragged', (tester) async {
      Downloads.instance.entries.addAll([
        DownloadEntry(media: downloaded(), episode: 4),
        DownloadEntry(media: downloaded(), episode: 5),
      ]);
      await pumpScreen(tester);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
      final drag = await tester.startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).last));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await drag.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(Downloads.instance.queue.map((e) => e.episode), [5, 4]);
    });

    testWidgets('an empty screen says how to start', (tester) async {
      Downloads.instance.entries.clear();
      await pumpScreen(tester);
      expect(find.text('Aucun téléchargement'), findsOneWidget);
    });

    testWidgets('changing the quality asks first', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Épisode 2 · Téléchargement · 25 %'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Changer la qualité'));
      await tester.pumpAndSettle();
      expect(find.text('Changer la qualité ?'), findsOneWidget);
      await tester.tap(find.text('Annuler').last);
      await tester.pumpAndSettle();
      expect(Downloads.instance.entry(9, 2), isNotNull);
    });

    testWidgets('it stays reachable with no account and with no network', (tester) async {
      SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
      await AppSettings.load();
      debugDesktopOverride = false;
      addTearDown(() => debugDesktopOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: Nami.theme(), home: const LibraryScreen()));
      await tester.pump();
      expect(find.text('Téléchargements'), findsOneWidget);
      expect(find.text('Se connecter à AniList'), findsOneWidget);
      expect(tester.takeException(), isNull);

      SharedPreferences.setMockInitialValues({'appLanguage': 'fr', 'anilistToken': 'x'});
      await AppSettings.load();
      await tester.pumpWidget(MaterialApp(theme: Nami.theme(), home: const LibraryScreen(key: ValueKey('token'))));
      await tester.pump();
      expect(find.text('Téléchargements'), findsOneWidget);
      expect(find.text('Connexion à AniList…'), findsOneWidget);
    });

    testWidgets('the bar shows on any screen and opens the downloads', (tester) async {
      var opened = 0;
      Downloads.instance.onOpen = () => opened++;
      debugDesktopOverride = false;
      addTearDown(() => debugDesktopOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: Nami.theme(),
          navigatorKey: PlayerCenter.instance.navigatorKey,
          builder: (context, child) => Overlay.wrap(child: Stack(children: [child!, const DownloadBar()])),
          home: const Scaffold(body: Text('page')),
        ),
      );
      expect(find.text('Gardé · Épisode 2'), findsOneWidget);
      expect(find.text('Téléchargement · 25 %'), findsOneWidget);
      await tester.tap(find.text('Gardé · Épisode 2'));
      await tester.pumpAndSettle();
      expect(find.text('Épisode 2 · Téléchargement · 25 %'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Mettre en pause'), findsOneWidget);
      await tester.tap(find.text('Tous les téléchargements'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      await tester.tap(find.byTooltip('Mettre en pause'));
      await tester.pump();
      expect(find.text('En pause · 25 %'), findsOneWidget);
      expect(find.byTooltip('Reprendre'), findsOneWidget);
    });

    testWidgets('the bar eases away instead of vanishing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: Nami.theme(),
          builder: (context, child) => Overlay.wrap(child: Stack(children: [child!, const DownloadBar()])),
          home: const Scaffold(body: Text('page')),
        ),
      );
      expect(find.text('Gardé · Épisode 2'), findsOneWidget);
      await Downloads.instance.remove(Downloads.instance.entry(9, 2)!);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Gardé · Épisode 2'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Gardé · Épisode 2'), findsNothing);
    });

    testWidgets('deleting from the list asks, then removes the entry', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Annuler le téléchargement'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Épisode 2'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Annuler le téléchargement'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Épisode 2'), findsNothing);
    });

    testWidgets('tapping a running download opens its details and cancelling asks', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Épisode 2 · Téléchargement · 25 %'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Mettre en pause'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Annuler le téléchargement'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Annuler le téléchargement'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Épisode 2'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Mettre en pause'), findsNothing);
    });
  });
}
