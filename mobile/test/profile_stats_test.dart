import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/screens/profile_stats.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> anime({List<Map<String, dynamic>> studios = const []}) => {
  'count': 244,
  'episodesWatched': 3888,
  'minutesWatched': 95546,
  'meanScore': 81.82,
  'standardDeviation': 14.7,
  'genres': [
    {'genre': 'Action', 'count': 174},
    {'genre': 'Fantasy', 'count': 119},
  ],
  'studios': studios,
  'formats': [
    {'format': 'TV', 'count': 179},
    {'format': 'MOVIE', 'count': 19},
  ],
  'statuses': [
    {'status': 'COMPLETED', 'count': 200},
  ],
  'scores': [
    {'score': 80, 'count': 50},
    {'score': 90, 'count': 30},
  ],
  'releaseYears': [
    {'releaseYear': 2019, 'count': 10},
    {'releaseYear': 2020, 'count': 12},
  ],
};

Future<void> pumpStats(WidgetTester tester, Map<String, dynamic> stats) async {
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
  await AppSettings.load();
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final viewer = Viewer({
    'id': 1,
    'name': 'raph559',
    'mediaListOptions': {'scoreFormat': 'POINT_10_DECIMAL'},
    'statistics': {'anime': stats},
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: Nami.theme(),
      home: ProfileStatsScreen(viewer: viewer),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('stats screen shows each section', (tester) async {
    await pumpStats(
      tester,
      anime(
        studios: [
          {
            'studio': {'name': 'MAPPA'},
            'count': 16,
          },
        ],
      ),
    );
    for (final text in [
      'En bref',
      'Genres',
      'Action',
      'Studios',
      'MAPPA',
      'Formats',
      'TV',
      'Film',
      'Statuts',
      'Terminé',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Années de sortie'), findsOneWidget);
    expect(find.textContaining('8,2'), findsWidgets);
  });

  testWidgets('an empty section is left out', (tester) async {
    await pumpStats(tester, anime());
    expect(find.text('Studios'), findsNothing);
    expect(find.text('Genres'), findsOneWidget);
  });
}
