import 'package:flutter/material.dart';

import '../anilist.dart';
import '../extensions.dart';
import '../mappings.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'player.dart';

/// Picks a source for [episode], plays it, and keeps going while the player
/// asks for the next episode. Returns when the user stops.
Future<void> startWatching(BuildContext context, Media media, int episode) async {
  final navigator = Navigator.of(context);
  var ep = episode;
  while (navigator.mounted) {
    final result = await showModalBottomSheet<TorrentResult>(
      // navigator.mounted is checked by the loop condition.
      // ignore: use_build_context_synchronously
      context: navigator.context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SourcesSheet(media: media, episode: ep),
    );
    if (result == null || !navigator.mounted) return;
    final next = await navigator.push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlayerScreen(media: media, episode: ep, result: result)),
    );
    if (next != true) return;
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
    final when = d.inDays > 0 ? t('dans ${d.inDays} j', 'in ${d.inDays} d') : t('dans ${d.inHours} h', 'in ${d.inHours} h');
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
            child: Stack(fit: StackFit.expand, children: [
              CoverImage(media.banner ?? media.cover, radius: 0),
              const GroundFade(from: 0.3),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -84),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(media.title.display, style: Nami.pageTitle),
                  const SizedBox(height: 10),
                  Text(metaLine, style: Nami.meta),
                  if (airingLine != null) ...[
                    const SizedBox(height: 4),
                    Text(airingLine!, style: Nami.meta),
                  ],
                  if (AniList.instance.isLoggedIn && !media.isMovie && total > 0) ...[
                    const SizedBox(height: 14),
                    Row(children: [
                      Text(t('Ta progression', 'Your progress'), style: Nami.caption.copyWith(fontSize: 13)),
                      const SizedBox(width: 10),
                      Expanded(child: ProgressLine(value: media.progress / total, color: accent)),
                      const SizedBox(width: 10),
                      Text('${media.progress} / $total', style: Nami.caption.copyWith(fontSize: 13)),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: canWatch ? () => _watch(media.isMovie ? 1 : nextEpisode) : null,
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: Text(media.isMovie ? t('Regarder', 'Watch') : t("Regarder l'épisode $nextEpisode", 'Watch episode $nextEpisode')),
                  ),
                  if (media.plainDescription.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () => setState(() => expanded = !expanded),
                      child: Text(
                        media.plainDescription,
                        maxLines: expanded ? null : 4,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                        style: Nami.body.copyWith(fontSize: 14, color: Nami.textSecondary),
                      ),
                    ),
                  ],
                  if (!media.isMovie) ...[
                    const SizedBox(height: 26),
                    Text(t('Épisodes', 'Episodes'), style: Nami.section),
                    const SizedBox(height: 12),
                    if (media.availableEpisodes == 0)
                      Text(t("Aucun épisode diffusé pour l'instant.", 'No episode has aired yet.'), style: Nami.meta),
                    for (var n = 1; n <= media.availableEpisodes; n++) _episodeRow(n, accent),
                  ],
                ],
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
    return Opacity(
      opacity: watched ? 0.55 : 1,
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
                    ? BoxDecoration(border: Border.all(color: accent, width: 2), borderRadius: BorderRadius.circular(Nami.radiusImage + 2))
                    : null,
                child: CoverImage(ep?.image ?? media.banner ?? media.coverSmall),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(['$n', ?state].join(' · '),
                        style: Nami.caption.copyWith(color: isNext ? accent : Nami.textSecondary)),
                    const SizedBox(height: 2),
                    Text(ep?.title(AppSettings.instance.language.name) ?? t('Épisode $n', 'Episode $n'),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: Nami.body),
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

class SourcesSheet extends StatefulWidget {
  const SourcesSheet({super.key, required this.media, required this.episode});
  final Media media;
  final int episode;

  @override
  State<SourcesSheet> createState() => _SourcesSheetState();
}

class _SourcesSheetState extends State<SourcesSheet> {
  SourceSearch? search;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    if (ExtensionStore.instance.enabled.isEmpty) return;
    setState(() => search = null);
    SourceSearch.run(widget.media, widget.episode).then((s) {
      if (mounted) setState(() => search = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = search;
    final title = widget.media.isMovie ? widget.media.title.display : t('Épisode ${widget.episode}', 'Episode ${widget.episode}');
    Widget body;
    if (ExtensionStore.instance.enabled.isEmpty) {
      body = StateMessage(
        title: t('Aucune source installée', 'No sources installed'),
        body: t("Ajoute un dépôt d'extensions dans Réglages, puis reviens ici.",
            'Add an extension repository in Settings, then come back here.'),
      );
    } else if (s == null) {
      body = StateMessage(loading: true, title: t('Recherche des sources…', 'Looking for sources…'));
    } else if (s.results.isEmpty) {
      body = StateMessage(
        title: t('Aucune source trouvée', 'No source found'),
        body: s.failures.isEmpty
            ? t("Tes extensions n'ont rien pour cet épisode. Essaie une autre qualité dans Réglages.",
                'Your extensions have nothing for this episode. Try another quality in Settings.')
            : [for (final f in s.failures) '${f.name} : ${f.message}'].join('\n'),
        action: t('Relancer la recherche', 'Search again'),
        onAction: _run,
      );
    } else {
      body = Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.pop(context, s.results.first),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(t('Lire la meilleure source', 'Play the best source')),
              ),
            ),
            for (final r in s.results)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                title: Text(r.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: Nami.body.copyWith(fontSize: 14)),
                subtitle: Text(
                  [
                    if (r.isBest) t('Recommandée', 'Recommended'),
                    '${r.seeders} seeders',
                    if (r.size != null && r.size! > 0) formatBytes(r.size!),
                    r.source,
                  ].join(' · '),
                ),
                onTap: () => Navigator.pop(context, r),
              ),
            if (s.failures.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  [for (final f in s.failures) t('${f.name} a échoué : ${f.message}', '${f.name} failed: ${f.message}')].join('\n'),
                  style: Nami.caption,
                ),
              ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Nami.section.copyWith(fontSize: 24)),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}
