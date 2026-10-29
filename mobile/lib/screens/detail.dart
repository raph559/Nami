import 'package:flutter/material.dart';

import '../anilist.dart';
import '../mappings.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player.dart';
import 'sources.dart';

/// Picks a source for [episode], plays it, and keeps going while the player
/// asks for the next episode. Returns when the user stops.
Future<void> startWatching(BuildContext context, Media media, int episode) async {
  final navigator = Navigator.of(context);
  var ep = episode;
  PlayerExit? previous;
  while (navigator.mounted) {
    // A season pack that holds the next episode is played again; otherwise
    // the sheet opens, and after a countdown it plays its recommendation.
    final result =
        previous?.reuse ??
        // navigator.mounted is checked by the loop condition.
        // ignore: use_build_context_synchronously
        await pickSource(navigator.context, media, ep, autoPick: previous?.auto ?? false);
    if (result == null || !navigator.mounted) return;
    previous = await navigator.push<PlayerExit>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlayerScreen(media: media, episode: ep, result: result),
      ),
    );
    if (previous == null) return;
    ep++;
  }
}

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.media});
  final Media media;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Media media = widget.media;
  Mappings? mappings;
  bool expanded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    Mappings.load(media.id).then((m) {
      if (mounted) setState(() => mappings = m);
    });
  }

  Future<void> _refresh() async {
    try {
      final fresh = await AniList.instance.media(media.id);
      if (mounted) setState(() => media = fresh);
    } catch (_) {}
  }

  int get nextEpisode {
    final total = media.availableEpisodes < 1 ? 1 : media.availableEpisodes;
    return (media.progress + 1).clamp(1, total);
  }

  Future<void> _watch(int episode) async {
    await startWatching(context, media, episode);
    await _refresh();
  }

  String get metaLine {
    final parts = <String>[
      if (media.format != null) media.format!.replaceAll('_', ' '),
      if (media.seasonYear != null) '${media.seasonYear}',
      if (media.episodes != null) t('${media.episodes} épisodes', '${media.episodes} episodes'),
      if (media.genres.isNotEmpty) media.genres.take(3).map(genreLabel).join(', '),
    ];
    return parts.join(' · ');
  }

  String? get airingLine {
    final airing = media.nextAiringAt;
    if (airing == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(airing * 1000).difference(DateTime.now());
    final when = d.inDays > 0
        ? t('dans ${d.inDays} j', 'in ${d.inDays} d')
        : t('dans ${d.inHours} h', 'in ${d.inHours} h');
    return t('Épisode ${media.nextEpisode} $when', 'Episode ${media.nextEpisode} $when');
  }

  @override
  Widget build(BuildContext context) {
    final accent = Nami.accentOf(media.color);
    final canWatch = media.isMovie || media.availableEpisodes > 0;
    final total = media.episodes ?? media.availableEpisodes;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // Keeps the status bar and back button readable once the page scrolls under them.
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Nami.ground.withValues(alpha: 0.85), Nami.ground.withValues(alpha: 0)],
            ),
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: t('Retour', 'Back'),
            style: IconButton.styleFrom(backgroundColor: Nami.ground.withValues(alpha: 0.55)),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 300 + top,
            child: Stack(
              fit: StackFit.expand,
              children: [CoverImage(media.banner ?? media.cover, radius: 0), const GroundFade(from: 0.3)],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -84),
            child: ContentWidth(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(header: true, child: Text(media.title.display, style: Nami.pageTitle)),
                    const SizedBox(height: 10),
                    Text(metaLine, style: Nami.meta),
                    if (airingLine != null) ...[const SizedBox(height: 4), Text(airingLine!, style: Nami.meta)],
                    if (AniList.instance.isLoggedIn && !media.isMovie && total > 0) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(t('Ta progression', 'Your progress'), style: Nami.caption.copyWith(fontSize: 13)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ProgressLine(value: media.progress / total, color: accent),
                          ),
                          const SizedBox(width: 10),
                          Text('${media.progress} / $total', style: Nami.caption.copyWith(fontSize: 13)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    FocusOutline(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: canWatch ? () => _watch(media.isMovie ? 1 : nextEpisode) : null,
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: Text(
                          media.isMovie
                              ? t('Regarder', 'Watch')
                              : t("Regarder l'épisode $nextEpisode", 'Watch episode $nextEpisode'),
                        ),
                      ),
                    ),
                    if (media.plainDescription.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      FocusOutline(
                        radius: Nami.radiusImage,
                        child: InkWell(
                          onTap: () => setState(() => expanded = !expanded),
                          child: Text(
                            media.plainDescription,
                            maxLines: expanded ? null : 4,
                            overflow: expanded ? null : TextOverflow.ellipsis,
                            style: Nami.body.copyWith(fontSize: 14, color: Nami.textSecondary),
                            semanticsLabel: media.plainDescription,
                          ),
                        ),
                      ),
                      if (!expanded)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() => expanded = true),
                            child: Text(t('Lire la suite', 'Read more')),
                          ),
                        ),
                    ],
                    if (!media.isMovie) ...[
                      const SizedBox(height: 26),
                      Semantics(header: true, child: Text(t('Épisodes', 'Episodes'), style: Nami.section)),
                      const SizedBox(height: 12),
                      if (media.availableEpisodes == 0)
                        Text(t("Aucun épisode diffusé pour l'instant.", 'No episode has aired yet.'), style: Nami.meta),
                      for (var n = 1; n <= media.availableEpisodes; n++) _episodeRow(n, accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _episodeRow(int n, Color accent) {
    final ep = mappings?.episode(n);
    final watched = n <= media.progress;
    final isNext = AniList.instance.isLoggedIn && n == nextEpisode && !watched;
    final state = watched ? t('Vu', 'Watched') : (isNext ? t('À voir', 'Up next') : null);
    // Watched episodes dim their picture only: dimmed text would drop under 4.5:1.
    return FocusOutline(
      radius: Nami.radiusImage,
      child: InkWell(
        onTap: () => _watch(n),
        borderRadius: BorderRadius.circular(Nami.radiusImage),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 120,
                height: 68,
                padding: EdgeInsets.all(isNext ? 2 : 0),
                decoration: isNext
                    ? BoxDecoration(
                        border: Border.all(color: accent, width: 2),
                        borderRadius: BorderRadius.circular(Nami.radiusImage + 2),
                      )
                    : null,
                child: Opacity(
                  opacity: watched ? 0.45 : 1,
                  child: CoverImage(ep?.image ?? media.banner ?? media.coverSmall),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ['$n', ?state].join(' · '),
                      style: Nami.caption.copyWith(color: isNext ? accent : Nami.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ep?.title(AppSettings.instance.language.name) ?? t('Épisode $n', 'Episode $n'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Nami.body.copyWith(color: watched ? Nami.textSecondary : Nami.text),
                    ),
                    if (ep?.runtime != null) Text('${ep!.runtime} min', style: Nami.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
