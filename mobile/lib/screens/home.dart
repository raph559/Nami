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
            body: networkError(error!),
            action: t('Réessayer', 'Try again'),
            onAction: _load,
          ),
        ),
      );
    }
    final (season, year) = AniList.currentSeason();
    final (heroMedia, heroEp) = _hero;
    final rest = [for (final w in watching) if (w.media != heroMedia) w];
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (heroMedia != null) _Hero(media: heroMedia, episode: heroEp, info: heroEpisode, resuming: watching.isNotEmpty),
            if (!AniList.instance.isLoggedIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  t('Connecte AniList dans Réglages pour reprendre là où tu en es.',
                      'Log in to AniList in Settings to pick up where you left off.'),
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
              MediaRow(title: t('Tendances', 'Trending'), items: trending.skip(heroMedia == trending.first ? 1 : 0).toList()),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
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
      if (!media.isMovie) total != null ? t('Épisode $episode sur $total', 'Episode $episode of $total') : t('Épisode $episode', 'Episode $episode'),
      if (epTitle != null) '« $epTitle »',
      if (info?.runtime != null) '${info!.runtime} min',
    ].join(' · ');
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: 470 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverImage(media.banner ?? media.cover, radius: 0, alignment: const Alignment(0.2, 0)),
          const GroundFade(from: 0.55),
          Positioned(
            top: top + 8,
            left: 20,
            child: const Text('Nami', style: TextStyle(fontFamily: Nami.serif, fontSize: 26, color: Nami.text)),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(resuming ? t('À reprendre', 'Up next') : t('En tendance', 'Trending'), style: Nami.caption.copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                Text(media.title.display, maxLines: 3, overflow: TextOverflow.ellipsis, style: Nami.heroTitle),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: Nami.meta),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Flexible(
                    child: FilledButton.icon(
                      onPressed: () => startWatching(context, media, episode),
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text(
                        media.isMovie
                            ? t('Regarder', 'Watch')
                            : resuming
                                ? t("Reprendre l'épisode $episode", 'Resume episode $episode')
                                : t("Regarder l'épisode $episode", 'Watch episode $episode'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(onPressed: () => openMedia(context, media), child: Text(t('Fiche', 'Details'))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
