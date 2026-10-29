import 'package:flutter/material.dart';

import '../anilist.dart';
import '../mappings.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<WatchingEntry> watching = [];
  List<Media> seasonal = [];
  List<Media> trending = [];
  EpisodeInfo? heroEpisode;
  bool loading = true;
  Object? error;
  int? _loadedFor;

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
    if (AniList.instance.viewer?.id != _loadedFor) _load();
  }

  Future<void> _load() async {
    final anilist = AniList.instance;
    _loadedFor = anilist.viewer?.id;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([anilist.watching(), anilist.seasonal(), anilist.trending()]);
      if (!mounted) return;
      setState(() {
        watching = results[0] as List<WatchingEntry>;
        seasonal = results[1] as List<Media>;
        trending = results[2] as List<Media>;
        loading = false;
      });
      final (media, episode) = _hero;
      if (media != null) {
        final maps = await Mappings.load(media.id);
        if (mounted) setState(() => heroEpisode = maps?.episode(episode));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  /// The anime to resume (first in the list with an aired, unwatched
  /// episode), else the top trending one.
  (Media?, int) get _hero {
    for (final w in watching) {
      if (w.hasNewEpisode) return (w.media, w.progress + 1);
    }
    if (trending.isNotEmpty) return (trending.first, 1);
    return (null, 1);
  }

  static String seasonName(String s) => switch (s) {
    'WINTER' => t('Hiver', 'Winter'),
    'SPRING' => t('Printemps', 'Spring'),
    'SUMMER' => t('Été', 'Summer'),
    _ => t('Automne', 'Fall'),
  };

  @override
  Widget build(BuildContext context) {
    if (loading && trending.isEmpty) {
      return Scaffold(
        body: Center(child: StateMessage(loading: true, title: t('Chargement des animes…', 'Loading anime…'))),
      );
    }
    if (error != null && trending.isEmpty) {
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
    final (heroMedia, heroEp) = _hero;
    final rest = [
      for (final w in watching)
        if (w.media != heroMedia) w,
    ];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (heroMedia != null)
              _Hero(media: heroMedia, episode: heroEp, info: heroEpisode, resuming: watching.isNotEmpty),
            if (!AniList.instance.isLoggedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  t(
                    'Connecte AniList dans Réglages pour reprendre là où tu en es.',
                    'Log in to AniList in Settings to pick up where you left off.',
                  ),
                  style: Nami.meta,
                ),
              ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: 22),
              MediaRow(
                title: t('Continuer', 'Continue watching'),
                items: [for (final w in rest) w.media],
                progress: (m) {
                  final w = rest.firstWhere((w) => w.media == m);
                  final total = m.episodes ?? m.availableEpisodes;
                  return total > 0 ? w.progress / total : null;
                },
                badge: (m) {
                  final w = rest.firstWhere((w) => w.media == m);
                  return w.hasNewEpisode ? t('Épisode ${w.progress + 1} dispo', 'Episode ${w.progress + 1} out') : null;
                },
              ),
            ],
            if (seasonal.isNotEmpty) ...[
              const SizedBox(height: 26),
              MediaRow(title: '${seasonName(season)} $year', items: seasonal),
            ],
            if (trending.length > 1) ...[
              const SizedBox(height: 26),
              MediaRow(
                title: t('Tendances', 'Trending'),
                items: trending.skip(heroMedia == trending.first ? 1 : 0).toList(),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    ).withStatusScrim(context);
  }
}

extension on Scaffold {
  /// Keeps the status bar readable once the page scrolls under it.
  Widget withStatusScrim(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(children: [
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
                colors: [Nami.ground, Nami.ground.withValues(alpha: 0.9), Nami.ground.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.media, required this.episode, required this.info, required this.resuming});
  final Media media;
  final int episode;
  final EpisodeInfo? info;
  final bool resuming;

  @override
  Widget build(BuildContext context) {
    final total = media.episodes;
    final epTitle = info?.title(AppSettings.instance.language.name);
    final meta = [
      if (!media.isMovie)
        total != null
            ? t('Épisode $episode sur $total', 'Episode $episode of $total')
            : t('Épisode $episode', 'Episode $episode'),
      if (epTitle != null) '« $epTitle »',
      if (info?.runtime != null) '${info!.runtime} min',
    ].join(' · ');
    final top = MediaQuery.paddingOf(context).top;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    // The banner fills the block; the text sits on a scrim at the bottom and
    // the block grows with it, so large text sizes never clip.
    return Stack(
      children: [
        Positioned.fill(child: CoverImage(media.banner ?? media.cover, radius: 0, alignment: const Alignment(0.2, 0))),
        const Positioned.fill(child: GroundFade(from: 0.6)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, top + 8, 20, 0),
              child: Semantics(
                header: true,
                child: const Text(
                  'Nami',
                  style: TextStyle(fontFamily: Nami.serif, fontSize: 26, color: Nami.text),
                ),
              ),
            ),
            SizedBox(height: wide ? 220 : 170),
            TextScrim(
              // Left-aligned with the logo and the rows; capped so lines stay readable.
              child: ContentWidth(
                maxWidth: 760,
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resuming ? t('À reprendre', 'Up next') : t('En tendance', 'Trending'),
                        style: Nami.caption.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        header: true,
                        child: Text(
                          media.title.display,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Nami.heroTitle,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(meta, maxLines: 4, overflow: TextOverflow.ellipsis, style: Nami.meta),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FocusOutline(
                            child: FilledButton.icon(
                              onPressed: () => startWatching(context, media, episode),
                              icon: const Icon(Icons.play_arrow_rounded, size: 22),
                              label: Text(
                                media.isMovie
                                    ? t('Regarder', 'Watch')
                                    : resuming
                                    ? t("Reprendre l'épisode $episode", 'Resume episode $episode')
                                    : t("Regarder l'épisode $episode", 'Watch episode $episode'),
                              ),
                            ),
                          ),
                          FocusOutline(
                            child: OutlinedButton(
                              onPressed: () => openMedia(context, media),
                              child: Text(t('Voir la fiche', 'See details')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
