import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/home_feed.dart';

Media anime(int id, {int? nextEpisode, int? episodes}) => Media({
  'id': id,
  'title': <String, dynamic>{'romaji': 'A$id'},
  'episodes': episodes,
  if (nextEpisode != null) 'nextAiringEpisode': {'episode': nextEpisode, 'airingAt': 0},
});

/// Watching at [progress]; [aired] episodes are out (so a new one is out when aired > progress).
WatchingEntry watching(int id, {required int progress, required int aired}) =>
    WatchingEntry(anime(id, nextEpisode: aired + 1), progress);

LibraryEntry planned(int id) => LibraryEntry(anime(id), ListEntry(id: id, status: 'PLANNING'));

HomeFeed build({
  bool loggedIn = true,
  List<WatchingEntry> watch = const [],
  List<LibraryEntry> planning = const [],
  List<Media> recs = const [],
  Media? recSource,
  List<Media> trending = const [],
  Set<int> listIds = const {},
  Map<int, double> resumed = const {},
}) => HomeFeed.build(
  loggedIn: loggedIn,
  watching: watch,
  planning: planning,
  recommendations: recs,
  recommendationSource: recSource,
  today: [AiringItem(anime(900), 3, DateTime(2026))],
  season: [anime(800)],
  trending: trending,
  topRated: [anime(700)],
  resumeFraction: (id, ep) => resumed[id],
  listIds: listIds,
);

List<int> ids(Iterable<Media> l) => [for (final m in l) m.id];

void main() {
  test('hero takes resume then new episodes then trending, max 5', () {
    final feed = build(
      watch: [
        watching(1, progress: 3, aired: 3), // nothing new, not resumed: skipped
        watching(2, progress: 2, aired: 5), // new episode
        watching(3, progress: 4, aired: 6), // resumed
      ],
      resumed: {3: 0.4},
      trending: [anime(10), anime(11), anime(12), anime(13)],
    );
    expect([for (final h in feed.hero) h.media.id], [3, 2, 10, 11, 12]);
    expect(
      [for (final h in feed.hero) h.reason],
      [HeroReason.resume, HeroReason.newEpisode, HeroReason.trending, HeroReason.trending, HeroReason.trending],
    );
    expect(feed.hero.first.episode, 5);
    expect(feed.hero[1].episode, 3);
  });

  test('hero has no duplicates', () {
    final feed = build(watch: [watching(2, progress: 2, aired: 5)], trending: [anime(2), anime(10)]);
    expect([for (final h in feed.hero) h.media.id], [2, 10]);
  });

  test('continue lists every watched anime and marks the ones with an episode out', () {
    final feed = build(watch: [watching(1, progress: 3, aired: 3), watching(2, progress: 2, aired: 5)]);
    expect(ids(feed.continueWatching.map((c) => c.media)), [1, 2]);
    expect([for (final c in feed.continueWatching) c.available], [false, true]);
    expect(feed.continueWatching[1].nextEpisode, 3);
  });

  test('recommendations skip anime already in the list', () {
    final feed = build(recs: [anime(1), anime(20), anime(21)], recSource: anime(5), listIds: {1, 5});
    expect(feed.because!.$1.id, 5);
    expect(ids(feed.because!.$2), [20, 21]);
  });

  test('no recommendations row when nothing is left', () {
    expect(build(recs: [anime(1)], recSource: anime(5), listIds: {1}).because, isNull);
    expect(build(recs: [anime(20)]).because, isNull);
  });

  test('trending skips the hero anime', () {
    final feed = build(trending: [anime(10), anime(11)]);
    expect(ids(feed.trending), isEmpty);
    final more = build(trending: [for (var i = 10; i < 17; i++) anime(i)]);
    expect(ids(more.trending), [15, 16]);
  });

  test('logged out keeps only public sections', () {
    final feed = build(
      loggedIn: false,
      watch: [watching(2, progress: 2, aired: 5)],
      planning: [planned(30)],
      recs: [anime(20)],
      recSource: anime(5),
      trending: [anime(10)],
    );
    expect(feed.continueWatching, isEmpty);
    expect(feed.planning, isEmpty);
    expect(feed.because, isNull);
    expect([for (final h in feed.hero) h.reason], everyElement(HeroReason.trending));
    expect(feed.today, hasLength(1));
    expect(ids(feed.season), [800]);
    expect(ids(feed.topRated), [700]);
  });

  test('planning keeps the list order', () {
    expect(ids(build(planning: [planned(31), planned(30)]).planning), [31, 30]);
  });

  test('the feed knows every anime of the list', () {
    final feed = build(listIds: {1, 2, 3});
    expect(feed.listIds, {1, 2, 3});
  });
}
