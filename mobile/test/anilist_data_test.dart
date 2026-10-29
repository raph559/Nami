import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibraryEntry entry(String title, {double score = 0, int progress = 0, int? episodes}) => LibraryEntry(
  Media({
    'id': title.hashCode,
    'title': {'romaji': title},
    'episodes': episodes,
  }),
  ListEntry(id: 1, progress: progress, status: 'CURRENT', score: score),
);

List<String> titles(List<LibraryEntry> l) => [for (final e in l) e.media.title.display];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.load();
  });

  test('studio is read from the first main studio', () {
    final m = Media({
      'id': 1,
      'title': <String, dynamic>{},
      'studios': {
        'nodes': [
          {'name': 'TRIGGER'},
          {'name': 'Other'},
        ],
      },
    });
    expect(m.studio, 'TRIGGER');
    expect(Media({'id': 1, 'title': <String, dynamic>{}, 'studios': null}).studio, isNull);
    expect(
      Media({
        'id': 1,
        'title': <String, dynamic>{},
        'studios': {'nodes': []},
      }).studio,
      isNull,
    );
  });

  test('dayBounds covers the local day', () {
    final (start, end) = AniList.dayBounds(DateTime(2026, 10, 29, 21, 42));
    expect(start, DateTime(2026, 10, 29));
    expect(end, DateTime(2026, 10, 30));
  });

  final list = [
    entry('Charlie', score: 80, progress: 1, episodes: 12),
    entry('alpha', score: 0, progress: 3, episodes: 10),
    entry('Bravo', score: 95, progress: 5),
  ];

  test('sortLibrary by activity keeps the order', () {
    expect(titles(sortLibrary(list, LibrarySort.activity)), ['Charlie', 'alpha', 'Bravo']);
  });

  test('sortLibrary by title ignores case', () {
    expect(titles(sortLibrary(list, LibrarySort.title)), ['alpha', 'Bravo', 'Charlie']);
  });

  test('sortLibrary by score puts unrated last', () {
    expect(titles(sortLibrary(list, LibrarySort.score)), ['Bravo', 'Charlie', 'alpha']);
  });

  test('sortLibrary by progress puts unknown totals last', () {
    expect(titles(sortLibrary(list, LibrarySort.progress)), ['alpha', 'Charlie', 'Bravo']);
  });

  test('sortLibrary leaves its input untouched', () {
    sortLibrary(list, LibrarySort.title);
    expect(titles(list), ['Charlie', 'alpha', 'Bravo']);
  });

  test('an airing item is aired once its time has passed', () {
    final m = Media({'id': 1, 'title': <String, dynamic>{}});
    final now = DateTime(2026, 10, 29, 12);
    expect(AiringItem(m, 5, DateTime(2026, 10, 29, 11)).airedAt(now), isTrue);
    expect(AiringItem(m, 5, DateTime(2026, 10, 29, 13)).airedAt(now), isFalse);
  });
}
