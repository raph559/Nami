import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/home.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media anime(int id, {int? nextEpisode}) => Media({
  'id': id,
  'title': <String, dynamic>{'romaji': 'Anime $id'},
  'episodes': 12,
  'format': 'TV',
  if (nextEpisode != null) 'nextAiringEpisode': {'episode': nextEpisode, 'airingAt': 0},
});

class FakeApi implements HomeApi {
  FakeApi({this.failing = const {}});
  final Set<String> failing;

  Future<T> _maybe<T>(String name, T value) async {
    if (failing.contains(name)) throw Exception(name);
    return value;
  }

  @override
  Future<List<WatchingEntry>> watching() => _maybe('watching', [WatchingEntry(anime(1, nextEpisode: 5), 2)]);
  @override
  Future<List<Media>> seasonal() => _maybe('seasonal', [anime(20), anime(21)]);
  @override
  Future<List<Media>> trending() => _maybe('trending', [for (var i = 30; i < 40; i++) anime(i)]);
  @override
  Future<List<Media>> topRated() => _maybe('topRated', [anime(40), anime(41)]);
  @override
  Future<List<AiringItem>> airingToday() =>
      _maybe('airingToday', [AiringItem(anime(50), 3, DateTime.now().add(const Duration(hours: 1)))]);
  @override
  Future<Map<String, List<LibraryEntry>>> library() => _maybe('library', {
    'PLANNING': [LibraryEntry(anime(60), ListEntry(id: 60, status: 'PLANNING'))],
    'CURRENT': [LibraryEntry(anime(1), ListEntry(id: 1, status: 'CURRENT'))],
  });
  @override
  Future<List<Media>> recommendationsFor(int id) => _maybe('recommendations', [anime(70), anime(60)]);
}

Future<void> pumpHome(
  WidgetTester tester, {
  HomeApi? api,
  bool desktop = false,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool loggedIn = true,
}) async {
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr', if (loggedIn) 'anilistToken': 'token'});
  await AppSettings.load();
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: desktop ? Nami.desktopTheme() : Nami.theme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: true),
          child: HomeScreen(api: api ?? FakeApi()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Section titles in the order they appear (the view is tall enough to build them all).
List<String> sectionOrder(WidgetTester tester, List<String> titles) {
  final found = {
    for (final title in titles)
      if (find.text(title).evaluate().isNotEmpty) title: tester.getTopLeft(find.text(title)).dy,
  };
  return found.keys.toList()..sort((a, b) => found[a]!.compareTo(found[b]!));
}

const tall = Size(390, 6000);

const ordered = [
  'Continuer',
  "Aujourd'hui",
  'À voir dans ta liste',
  'Parce que tu regardes Anime 1',
  'Tendances',
  'Les mieux notés',
];

void main() {
  testWidgets('shows every non-empty section in order', (tester) async {
    await pumpHome(tester, size: tall);
    final order = sectionOrder(tester, ordered);
    expect(order, ordered);
  });

  testWidgets('suggestions leave out anime already in the list', (tester) async {
    await pumpHome(tester, size: tall);
    expect(find.text('Anime 70'), findsWidgets);
    final because = find.ancestor(of: find.text('Parce que tu regardes Anime 1'), matching: find.byType(Column));
    expect(find.descendant(of: because.first, matching: find.text('Anime 60')), findsNothing);
  });

  testWidgets('a failing source hides only its section', (tester) async {
    await pumpHome(
      tester,
      api: FakeApi(failing: {'airingToday', 'topRated'}),
      size: tall,
    );
    expect(find.text("Aujourd'hui"), findsNothing);
    expect(find.text('Les mieux notés'), findsNothing);
    expect(find.text('Continuer'), findsOneWidget);
    expect(find.text('Tendances'), findsOneWidget);
  });

  testWidgets('everything failing shows the retry message', (tester) async {
    await pumpHome(
      tester,
      api: FakeApi(
        failing: {'watching', 'seasonal', 'trending', 'topRated', 'airingToday', 'library', 'recommendations'},
      ),
    );
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('logged out shows only the public sections', (tester) async {
    await pumpHome(tester, loggedIn: false, size: tall);
    expect(find.text('Continuer'), findsNothing);
    expect(find.text('À voir dans ta liste'), findsNothing);
    expect(find.text("Aujourd'hui"), findsOneWidget);
    expect(find.text('Les mieux notés'), findsOneWidget);
  });

  testWidgets('home at 200 % text', (tester) async {
    await pumpHome(tester, textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home at the smallest window', (tester) async {
    await pumpHome(tester, desktop: true, size: const Size(720, 480));
    expect(tester.takeException(), isNull);
    expect(find.text('Anime 1'), findsWidgets);
  });
}
