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
      // The page's shape while it loads, so nothing jumps when it arrives.
      return Scaffold(
        body: Semantics(
          label: t('Chargement des animes…', 'Loading anime…'),
          liveRegion: true,
          child: const HomeSkeleton(),
        ),
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
    // Without AniList, the anime played on this device that still have an episode to go.
    final local = [
      for (final e in AppSettings.instance.recent)
        if (Media(e.media) case final m when e.episode <= (m.isMovie ? 1 : m.availableEpisodes)) (m, e.episode),
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
                // How far into the next episode you are, else how far into the series.
                progress: (m) {
                  final w = rest.firstWhere((w) => w.media == m);
                  final inEpisode = AppSettings.instance.resumeFraction(m.id, w.progress + 1);
                  if (inEpisode != null) return inEpisode;
                  final total = m.episodes ?? m.availableEpisodes;
                  return total > 0 ? w.progress / total : null;
                },
                badge: (m) {
                  final w = rest.firstWhere((w) => w.media == m);
                  if (AppSettings.instance.resumeFraction(m.id, w.progress + 1) != null) {
                    return t('Reprendre l\'épisode ${w.progress + 1}', 'Resume episode ${w.progress + 1}');
                  }
                  return w.hasNewEpisode ? t('Épisode ${w.progress + 1} dispo', 'Episode ${w.progress + 1} out') : null;
                },
              ),
            ] else if (!AniList.instance.isLoggedIn && local.isNotEmpty) ...[
              const SizedBox(height: 22),
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
                  colors: [Nami.ground, Nami.ground.withValues(alpha: 0.9), Nami.ground.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 700;
    final label = resuming ? t('À reprendre', 'Up next') : t('En tendance', 'Trending');
    final actions = Wrap(
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
    );
    if (width >= 900) {
      return _WideHero(media: media, label: label, meta: meta, actions: actions);
    }
    // The banner fills the block; the text sits on a scrim at the bottom and
    // the block grows with it, so large text sizes never clip.
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: 2,
          child: CoverImage(media.banner ?? media.cover, radius: 0, alignment: const Alignment(0.2, 0)),
        ),
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
                  style: TextStyle(fontFamily: Nami.sans, fontSize: 22, fontWeight: FontWeight.w700, color: Nami.text),
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
                      Text(label, style: Nami.caption.copyWith(fontSize: 13)),
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
                      actions,
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

/// Banner for wide windows: the artwork fills the width and the text sits on
/// the left, where a dark fade from the left keeps it readable (at least 85 %
/// black under the text column, so 4.5:1 holds over a white pixel). The
/// bottom fades into the ground, so the page has no edge under the banner.
class _WideHero extends StatelessWidget {
  const _WideHero({required this.media, required this.label, required this.meta, required this.actions});
  final Media media;
  final String label;
  final String meta;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = (width * 0.42).clamp(440.0, 620.0);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Stack(
        children: [
          // Stops short of the bottom: rounding could leave one row of the image under the fade.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 2,
            child: CoverImage(media.banner ?? media.cover, radius: 0, alignment: const Alignment(0.6, -0.2)),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  stops: const [0, 0.45, 0.75],
                  colors: [
                    Nami.ground.withValues(alpha: 0.92),
                    Nami.ground.withValues(alpha: 0.85),
                    Nami.ground.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Solid ground over the last pixels, so no seam shows under the banner.
                  stops: const [0, 0.18, 0.6, 0.96],
                  colors: [
                    Nami.ground.withValues(alpha: 0.5),
                    Nami.ground.withValues(alpha: 0),
                    Nami.ground.withValues(alpha: 0),
                    Nami.ground,
                  ],
                ),
              ),
            ),
          ),
          Container(
            constraints: BoxConstraints(minHeight: height),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Nami.caption.copyWith(fontSize: 14)),
                  const SizedBox(height: 10),
                  Semantics(
                    header: true,
                    child: Text(
                      media.title.display,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Nami.heroTitle.copyWith(fontSize: 48, height: 1.05),
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(meta, maxLines: 3, overflow: TextOverflow.ellipsis, style: Nami.meta.copyWith(fontSize: 15)),
                  ],
                  if (media.plainDescription.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      media.plainDescription,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Nami.body.copyWith(fontSize: 14, color: Nami.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 22),
                  actions,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
