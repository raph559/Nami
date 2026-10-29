import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/library.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
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
}
