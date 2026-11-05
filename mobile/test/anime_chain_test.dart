import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/anime_details.dart';
import 'package:nami/screens/anime_extras.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> node(int id, String title, {String type = 'ANIME'}) => {
  'id': id,
  'type': type,
  'title': {'romaji': title},
};

Map<String, dynamic> edge(String relation, Map<String, dynamic> n) => {'relationType': relation, 'node': n};

// Gate on AniList: part 1 → part 2 → Gate 2, each knowing only its neighbours.
final gate1 = node(20994, 'GATE');
final gate1b = node(21364, 'GATE Part 2');
final gate2 = node(195496, 'GATE 2');

final relations = <int, List<Map<String, dynamic>>>{
  20994: [edge('SEQUEL', gate1b)],
  21364: [edge('PREQUEL', gate1), edge('SEQUEL', gate2)],
  195496: [edge('PREQUEL', gate1b), edge('ADAPTATION', node(1, 'GATE manga', type: 'MANGA'))],
};

AnimeDetails detailsOf(int id) => AnimeDetails({
  'relations': {'edges': relations[id]},
});

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  Future<List<Map<String, dynamic>>> fetch(List<int> ids) async => [
    for (final id in ids)
      {
        'id': id,
        'relations': {'edges': relations[id] ?? []},
      },
  ];

  test('from the first part, the whole order shows', () async {
    final chain = await followChain(Media(gate1), detailsOf(20994), fetch);
    expect(chain.before, isEmpty);
    expect(chain.after.map((r) => r.media.id), [21364, 195496]);
  });

  test('from the last season, everything before it shows, oldest first', () async {
    final chain = await followChain(Media(gate2), detailsOf(195496), fetch);
    expect(chain.before.map((r) => r.media.id), [20994, 21364]);
    expect(chain.after, isEmpty);
  });

  test('from the middle, one step each way', () async {
    var calls = 0;
    final chain = await followChain(Media(gate1b), detailsOf(21364), (ids) {
      calls++;
      return fetch(ids);
    });
    expect(chain.before.map((r) => r.media.id), [20994]);
    expect(chain.after.map((r) => r.media.id), [195496]);
    // One request asks for both sides at once.
    expect(calls, 1);
  });

  test('a failed request keeps what AniList gave with the page', () async {
    final chain = await followChain(Media(gate1), detailsOf(20994), (_) async => throw Exception('offline'));
    expect(chain.after.map((r) => r.media.id), [21364]);
  });

  test('relations that loop back stop', () async {
    final loop = <int, List<Map<String, dynamic>>>{
      1: [edge('SEQUEL', node(2, 'B'))],
      2: [edge('SEQUEL', node(1, 'A'))],
    };
    final chain = await followChain(
      Media(node(1, 'A')),
      AnimeDetails({
        'relations': {'edges': loop[1]},
      }),
      (ids) async => [
        for (final id in ids)
          {
            'id': id,
            'relations': {'edges': loop[id]},
          },
      ],
    );
    expect(chain.after.map((r) => r.media.id), [2]);
  });

  testWidgets('the Related tab shows the direct sequel, then the whole order', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: Nami.theme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimeRelatedTab(
              media: Media(gate1),
              details: detailsOf(20994),
              loadChain: (m, d) => followChain(m, d, fetch),
            ),
          ),
        ),
      ),
    );
    expect(find.text('GATE Part 2'), findsOneWidget);
    expect(find.text('GATE 2'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('GATE 2'), findsOneWidget);
  });
}
