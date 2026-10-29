import 'anilist.dart';

/// Why an anime is in the home banner.
enum HeroReason { resume, newEpisode, trending }

class HeroItem {
  HeroItem(this.media, this.episode, this.reason);
  final Media media;
  final int episode;
  final HeroReason reason;
}

class ContinueItem {
  ContinueItem(this.media, this.nextEpisode, {required this.available, this.fraction});
  final Media media;
  final int nextEpisode;

  /// The next episode is out.
  final bool available;

  /// How far into the next episode you are, when started.
  final double? fraction;
}

/// What the home shows, worked out once for every layout. Sections with
/// nothing in them are empty (or null) and the screens hide them.
class HomeFeed {
  HomeFeed._({
    required this.hero,
    required this.continueWatching,
    required this.today,
    required this.planning,
    required this.because,
    required this.season,
    required this.trending,
    required this.topRated,
  });

  final List<HeroItem> hero;
  final List<ContinueItem> continueWatching;
  final List<AiringItem> today;
  final List<Media> planning;

  /// Suggestions drawn from one anime you watch, without anime already in your list.
  final (Media, List<Media>)? because;
  final List<Media> season;
  final List<Media> trending;
  final List<Media> topRated;

  static const heroSize = 5;

  static HomeFeed build({
    required bool loggedIn,
    required List<WatchingEntry> watching,
    required List<LibraryEntry> planning,
    required List<Media> recommendations,
    Media? recommendationSource,
    required List<AiringItem> today,
    required List<Media> season,
    required List<Media> trending,
    required List<Media> topRated,
    required double? Function(int id, int episode) resumeFraction,
    required Set<int> listIds,
  }) {
    final watched = loggedIn ? watching : const <WatchingEntry>[];
    final hero = <HeroItem>[];
    final seen = <int>{};
    void add(Media m, int episode, HeroReason reason) {
      if (hero.length < heroSize && seen.add(m.id)) hero.add(HeroItem(m, episode, reason));
    }

    for (final w in watched) {
      if (resumeFraction(w.media.id, w.progress + 1) != null) add(w.media, w.progress + 1, HeroReason.resume);
    }
    for (final w in watched) {
      if (w.hasNewEpisode) add(w.media, w.progress + 1, HeroReason.newEpisode);
    }
    for (final m in trending) {
      add(m, 1, HeroReason.trending);
    }

    final suggestions = [
      for (final m in recommendations)
        if (!listIds.contains(m.id)) m,
    ];
    return HomeFeed._(
      hero: hero,
      continueWatching: [
        for (final w in watched)
          ContinueItem(
            w.media,
            w.progress + 1,
            available: w.hasNewEpisode,
            fraction: resumeFraction(w.media.id, w.progress + 1),
          ),
      ],
      today: today,
      planning: loggedIn ? [for (final e in planning) e.media] : const [],
      because: loggedIn && recommendationSource != null && suggestions.isNotEmpty
          ? (recommendationSource, suggestions)
          : null,
      season: season,
      trending: [
        for (final m in trending)
          if (!seen.contains(m.id)) m,
      ],
      topRated: topRated,
    );
  }
}
