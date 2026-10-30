import 'package:flutter/material.dart';

import '../anilist.dart';
import '../home_feed.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/airing_row.dart';
import '../ui/hero_carousel.dart';
import '../ui/motion.dart';
import '../widgets.dart';

/// Where the home gets its data; tests pass a fake.
abstract class HomeApi {
  Future<List<WatchingEntry>> watching();
  Future<List<Media>> seasonal();
  Future<List<Media>> trending();
  Future<List<Media>> topRated();
  Future<List<AiringItem>> airingToday();
  Future<Map<String, List<LibraryEntry>>> library();
  Future<List<Media>> recommendationsFor(int id);
}

class AniListHomeApi implements HomeApi {
  const AniListHomeApi();
  AniList get _a => AniList.instance;
  @override
  Future<List<WatchingEntry>> watching() => _a.watching();
  @override
  Future<List<Media>> seasonal() => _a.seasonal();
  @override
  Future<List<Media>> trending() => _a.trending();
  @override
  Future<List<Media>> topRated() => _a.topRated();
  @override
  Future<List<AiringItem>> airingToday() => _a.airingToday();
  @override
  Future<Map<String, List<LibraryEntry>>> library() => _a.library();
  @override
  Future<List<Media>> recommendationsFor(int id) => _a.recommendationsFor(id);
}

/// What the home was built from, kept so a refresh can reuse what it does not fetch again.
class HomeInputs {
  const HomeInputs({
    this.watching = const [],
    this.library = const {},
    this.recommendations = const [],
    this.today = const [],
    this.season = const [],
    this.trending = const [],
    this.topRated = const [],
  });

  final List<WatchingEntry> watching;
  final Map<String, List<LibraryEntry>> library;
  final List<Media> recommendations;
  final List<AiringItem> today;
  final List<Media> season;
  final List<Media> trending;
  final List<Media> topRated;

  HomeFeed feed({required bool loggedIn}) {
    final source = watching.isEmpty ? null : watching.first.media;
    return HomeFeed.build(
      loggedIn: loggedIn,
      watching: watching,
      planning: library['PLANNING'] ?? const [],
      recommendations: recommendations,
      recommendationSource: source,
      today: today,
      season: season,
      trending: trending,
      topRated: topRated,
      resumeFraction: AppSettings.instance.resumeFraction,
      listIds: {
        for (final list in library.values)
          for (final e in list) e.media.id,
        for (final w in watching) w.media.id,
      },
    );
  }
}

/// Fetches the home's sources at once. A source that fails keeps what [previous] had
/// (or stays empty), so one failed request never blanks a row that was on screen.
/// With [accountOnly], only the rows that depend on your list are fetched again.
/// Returns null when every request failed and there was nothing before.
Future<HomeInputs?> fetchHomeInputs(
  HomeApi api, {
  required bool loggedIn,
  HomeInputs? previous,
  bool accountOnly = false,
}) async {
  final before = previous ?? const HomeInputs();
  var failures = 0, attempts = 0;
  Future<T> fetch<T>(Future<T> Function() f, T fallback) async {
    attempts++;
    try {
      return await f();
    } catch (_) {
      failures++;
      return fallback;
    }
  }

  Future<T> public<T>(Future<T> Function() f, T kept) => accountOnly ? Future.value(kept) : fetch(f, kept);

  final watchingF = loggedIn ? fetch(api.watching, before.watching) : Future.value(<WatchingEntry>[]);
  final libraryF = loggedIn ? fetch(api.library, before.library) : Future.value(<String, List<LibraryEntry>>{});
  final todayF = public(api.airingToday, before.today);
  final seasonF = public(api.seasonal, before.season);
  final trendingF = public(api.trending, before.trending);
  final topF = public(api.topRated, before.topRated);
  final watching = await watchingF;
  // Suggestions from the anime you watched most recently.
  final source = watching.isEmpty ? null : watching.first.media;
  final recs = source == null
      ? <Media>[]
      : await fetch(() => api.recommendationsFor(source.id), before.recommendations);
  final inputs = HomeInputs(
    watching: watching,
    library: await libraryF,
    recommendations: recs,
    today: await todayF,
    season: await seasonF,
    trending: await trendingF,
    topRated: await topF,
  );
  if (attempts > 0 && failures == attempts && previous == null) return null;
  return inputs;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api = const AniListHomeApi()});
  final HomeApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();

  static String seasonName(String s) => switch (s) {
    'WINTER' => t('Hiver', 'Winter'),
    'SPRING' => t('Printemps', 'Spring'),
    'SUMMER' => t('Été', 'Summer'),
    _ => t('Automne', 'Fall'),
  };
}

class _HomeScreenState extends State<HomeScreen> {
  HomeFeed? feed;
  HomeInputs? _inputs;

  /// Goes up with every load: an older load that finishes last is dropped.
  int _request = 0;
  bool loading = true;
  bool failed = false;
  int? _loadedFor;
  int _revision = AniList.instance.listRevision;

  @override
  void initState() {
    super.initState();
    AniList.instance.addListener(_onAccount);
    _load();
  }

  @override
  void dispose() {
    AniList.instance.removeListener(_onAccount);
    super.dispose();
  }

  void _onAccount() {
    final anilist = AniList.instance;
    if (anilist.viewer?.id != _loadedFor) {
      _load();
    } else if (anilist.listRevision != _revision) {
      // The list changed (edited, or an episode watched): only the rows that depend on it.
      _load(accountOnly: true);
    }
  }

  Future<void> _load({bool accountOnly = false}) async {
    final anilist = AniList.instance;
    final request = ++_request;
    final sameAccount = anilist.viewer?.id == _loadedFor;
    _loadedFor = anilist.viewer?.id;
    _revision = anilist.listRevision;
    setState(() => loading = feed == null);
    final loggedIn = anilist.isLoggedIn;
    final inputs = await fetchHomeInputs(
      widget.api,
      loggedIn: loggedIn,
      previous: sameAccount ? _inputs : null,
      accountOnly: accountOnly && _inputs != null,
    );
    if (!mounted || request != _request) return;
    setState(() {
      loading = false;
      failed = inputs == null && feed == null;
      if (inputs != null) {
        _inputs = inputs;
        feed = inputs.feed(loggedIn: loggedIn);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The loading shapes, the message or the page: they cross-fade into each other.
    final state = feed != null ? 'feed' : (loading ? 'loading' : 'failed');
    return AnimatedSwitcher(
      duration: Motion.of(context).medium,
      child: KeyedSubtree(key: ValueKey(state), child: _page(context)),
    );
  }

  Widget _page(BuildContext context) {
    final feed = this.feed;
    if (loading && feed == null) {
      // The page's shape while it loads, so nothing jumps when it arrives.
      return Scaffold(
        body: Semantics(
          label: t('Chargement des animes…', 'Loading anime…'),
          liveRegion: true,
          child: const HomeSkeleton(),
        ),
      );
    }
    if (feed == null) {
      return Scaffold(
        body: Center(
          child: StateMessage(
            title: t('Rien à afficher pour le moment', 'Nothing to show yet'),
            body: networkError(),
            action: t('Réessayer', 'Try again'),
            onAction: _load,
          ),
        ),
      );
    }
    final (season, year) = AniList.currentSeason();
    final loggedIn = AniList.instance.isLoggedIn;
    // Without AniList, the anime played on this device that still have an episode to go.
    final local = [
      for (final e in AppSettings.instance.recent)
        if (Media(e.media) case final m when e.episode <= (m.isMovie ? 1 : m.availableEpisodes)) (m, e.episode),
    ];
    final continueItems = feed.continueWatching;
    final because = feed.because;
    const gap = SizedBox(height: 28);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (feed.hero.isNotEmpty)
              HeroCarousel(items: feed.hero, onOpen: (item) => openMedia(context, item.media))
            else
              SizedBox(height: MediaQuery.paddingOf(context).top + 24),
            if (!loggedIn)
              Padding(
                padding: EdgeInsets.fromLTRB(_side(context), 4, 20, 0),
                child: Text(
                  t(
                    'Connecte AniList dans Réglages pour reprendre là où tu en es.',
                    'Log in to AniList in Settings to pick up where you left off.',
                  ),
                  style: Nami.meta,
                ),
              ),
            if (continueItems.isNotEmpty) ...[
              gap,
              MediaRow(
                title: t('Continuer', 'Continue watching'),
                items: [for (final c in continueItems) c.media],
                // How far into the next episode you are, else how far into the series.
                progress: (m) {
                  final c = continueItems.firstWhere((c) => c.media == m);
                  if (c.fraction != null) return c.fraction;
                  final total = m.episodes ?? m.availableEpisodes;
                  return total > 0 ? (c.nextEpisode - 1) / total : null;
                },
                badge: (m) {
                  final c = continueItems.firstWhere((c) => c.media == m);
                  if (c.fraction != null) {
                    return t("Reprendre l'épisode ${c.nextEpisode}", 'Resume episode ${c.nextEpisode}');
                  }
                  return c.available
                      ? t('Épisode ${c.nextEpisode} dispo', 'Episode ${c.nextEpisode} out')
                      : t('Épisode ${c.nextEpisode}', 'Episode ${c.nextEpisode}');
                },
              ),
            ] else if (!loggedIn && local.isNotEmpty) ...[
              gap,
              MediaRow(
                title: t('Continuer', 'Continue watching'),
                items: [for (final e in local) e.$1],
                progress: (m) {
                  final ep = local.firstWhere((e) => e.$1 == m).$2;
                  return AppSettings.instance.resumeFraction(m.id, ep) ?? 0;
                },
                badge: (m) {
                  final ep = local.firstWhere((e) => e.$1 == m).$2;
                  return m.isMovie ? null : t('Épisode $ep', 'Episode $ep');
                },
              ),
            ],
            if (feed.today.isNotEmpty) ...[
              gap,
              _SectionTitle(t("Aujourd'hui", 'Today')),
              const SizedBox(height: 10),
              AiringRow(items: feed.today, listIds: feed.listIds),
            ],
            if (feed.planning.isNotEmpty) ...[
              gap,
              MediaRow(title: t('À voir dans ta liste', 'Planned in your list'), items: feed.planning),
            ],
            if (because != null) ...[
              gap,
              MediaRow(
                title: t(
                  'Parce que tu regardes ${because.$1.title.display}',
                  'Because you watch ${because.$1.title.display}',
                ),
                items: because.$2,
              ),
            ],
            if (feed.season.isNotEmpty) ...[
              gap,
              MediaRow(title: '${HomeScreen.seasonName(season)} $year', items: feed.season),
            ],
            if (feed.trending.isNotEmpty) ...[gap, MediaRow(title: t('Tendances', 'Trending'), items: feed.trending)],
            if (feed.topRated.isNotEmpty) ...[
              gap,
              MediaRow(title: t('Les mieux notés', 'Top rated'), items: feed.topRated, ranked: true),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    ).withStatusScrim(context);
  }
}

/// Left edge shared by every home section: beside the rail on desktop.
double _side(BuildContext context) => isDesktop ? MediaQuery.paddingOf(context).left + 36 : 20;

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: _side(context)),
    child: Semantics(header: true, child: Text(text, style: MediaRow.titleStyle)),
  );
}

extension on Scaffold {
  /// Keeps the status bar (or the window buttons) readable once the page scrolls under it.
  Widget withStatusScrim(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        this,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top + 16,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, top / (top + 16), 1],
                  colors: [
                    Nami.ground.withValues(alpha: isDesktop ? 0.6 : 1),
                    Nami.ground.withValues(alpha: isDesktop ? 0.4 : 0.9),
                    Nami.ground.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
