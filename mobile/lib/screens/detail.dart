import 'package:flutter/material.dart';

import '../anilist.dart';
import '../mappings.dart';
import '../player_center.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'list_editor.dart';

/// Opens the sources for [episode]; the player then runs above the app and
/// moves on to the next episodes by itself.
void startWatching(BuildContext context, Media media, int episode) => PlayerCenter.instance.openSources(media, episode);

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.media, this.heroTag});
  final Media media;

  /// Tag of the cover that was tapped, so it grows into this page's cover.
  final String? heroTag;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Media media = widget.media;
  Mappings? mappings;
  bool expanded = false;
  final scroll = ScrollController();

  /// Once the main button has scrolled away, the top bar offers it instead.
  bool showBarButton = false;

  @override
  void initState() {
    super.initState();
    // The player may have moved the AniList progress.
    PlayerCenter.instance.addListener(_onPlayer);
    scroll.addListener(() {
      final show = scroll.offset > 360;
      if (show != showBarButton) setState(() => showBarButton = show);
    });
    _refresh();
    Mappings.load(media.id).then((m) {
      if (mounted) setState(() => mappings = m);
    });
  }

  int _finished = PlayerCenter.instance.finished;

  void _onPlayer() {
    if (PlayerCenter.instance.finished == _finished) return;
    _finished = PlayerCenter.instance.finished;
    _refresh();
  }

  @override
  void dispose() {
    PlayerCenter.instance.removeListener(_onPlayer);
    scroll.dispose();
    super.dispose();
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

  bool get canWatch => media.isMovie || media.availableEpisodes > 0;

  void _watch(int episode) => startWatching(context, media, episode);

  String get watchLabel => media.isMovie
      ? t('Regarder', 'Watch')
      : AppSettings.instance.resumeFraction(media.id, nextEpisode) != null
      ? t("Reprendre l'épisode $nextEpisode", 'Resume episode $nextEpisode')
      : t("Regarder l'épisode $nextEpisode", 'Watch episode $nextEpisode');

  String get metaLine {
    final parts = <String>[
      if (media.format != null) media.format!.replaceAll('_', ' '),
      if (media.seasonYear != null) '${media.seasonYear}',
      if (media.episodes != null) t('${media.episodes} épisodes', '${media.episodes} episodes'),
      if (media.averageScore != null) '${media.averageScore} %',
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

  Widget _cover(double width) {
    Widget c = SizedBox(width: width, height: width * 1.45, child: CoverImage(media.cover));
    if (widget.heroTag != null) c = Hero(tag: widget.heroTag!, child: c);
    return c;
  }

  Widget get _watchButton => FocusOutline(
    child: FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
      onPressed: canWatch ? () => _watch(media.isMovie ? 1 : nextEpisode) : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 22),
      label: Text(watchLabel),
    ),
  );

  Future<void> _editList() async {
    final updated = await showListEditor(context, media);
    if (updated != null && mounted) setState(() => media = updated);
  }

  /// Opens the list editor; its label is where the anime stands in the list.
  Widget get _listButton {
    final status = media.listEntry?.status;
    return FocusOutline(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
        onPressed: _editList,
        icon: Icon(status == null ? Icons.bookmark_add_outlined : Icons.bookmark, size: 20),
        label: Text(status == null ? t('Ma liste', 'My list') : listStatusLabel(status)),
      ),
    );
  }

  /// The watch button, with the list button beside it when logged in.
  Widget _actions({required bool wide}) {
    if (!AniList.instance.isLoggedIn) {
      return wide ? Align(alignment: Alignment.centerLeft, child: _watchButton) : _watchButton;
    }
    if (wide) return Wrap(spacing: 12, runSpacing: 12, children: [_watchButton, _listButton]);
    return Row(
      children: [
        Expanded(child: _watchButton),
        const SizedBox(width: 10),
        _listButton,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: showBarButton ? Nami.ground.withValues(alpha: 0.94) : Colors.transparent,
        // Keeps the status bar and back button readable once the page scrolls under them.
        flexibleSpace: showBarButton
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Nami.ground.withValues(alpha: 0.85), Nami.ground.withValues(alpha: 0)],
                  ),
                ),
              ),
        title: showBarButton ? Text(media.title.display, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            tooltip: t('Retour', 'Back'),
            style: IconButton.styleFrom(backgroundColor: Nami.ground.withValues(alpha: 0.55)),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        actions: [
          if (showBarButton && canWatch)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FocusOutline(
                child: FilledButton.icon(
                  onPressed: () => _watch(media.isMovie ? 1 : nextEpisode),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    media.isMovie ? t('Regarder', 'Watch') : t('Épisode $nextEpisode', 'Episode $nextEpisode'),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        controller: scroll,
        padding: EdgeInsets.zero,
        children: [wide ? _wideHeader() : _phoneHeader(), _episodes(wide)],
      ),
    );
  }

  Widget _info({required bool wide}) {
    final accent = Nami.accentOf(media.color);
    final total = media.episodes ?? media.availableEpisodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(media.title.display, style: wide ? Nami.pageTitle.copyWith(fontSize: 38) : Nami.pageTitle),
        ),
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
        _actions(wide: wide),
        if (media.plainDescription.isNotEmpty) ...[
          const SizedBox(height: 16),
          // About 80 characters a line at most, even on a wide window.
          ContentWidth(
            maxWidth: 680,
            alignment: Alignment.topLeft,
            child: FocusOutline(
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
      ],
    );
  }

  /// Phone: the banner, then the cover beside the title, overlapping it.
  Widget _phoneHeader() {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 240 + top,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: CoverImage(media.banner ?? media.cover, radius: 0),
              ),
              const GroundFade(from: 0.3),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -70),
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: _cover(104)),
                  const SizedBox(height: 16),
                  _info(wide: false),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Wide window: a tall banner fading into the ground, the cover and the
  /// information side by side over its lower part.
  Widget _wideHeader() {
    return Stack(
      children: [
        SizedBox(
          height: 420,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: CoverImage(media.banner ?? media.cover, radius: 0, alignment: const Alignment(0.4, -0.3)),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.25, 0.55, 0.96],
                    colors: [
                      Nami.ground.withValues(alpha: 0.5),
                      Nami.ground.withValues(alpha: 0.1),
                      Nami.ground.withValues(alpha: 0.6),
                      Nami.ground,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 250, 48, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(210),
                const SizedBox(width: 32),
                // Text starts below the banner's bright part, on the faded ground.
                Expanded(
                  child: Padding(padding: const EdgeInsets.only(top: 110), child: _info(wide: true)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _episodes(bool wide) {
    if (media.isMovie) return const SizedBox(height: 32);
    final accent = Nami.accentOf(media.color);
    final side = wide ? 48.0 : 20.0;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(side, wide ? 32 : 0, side, 12),
      child: Semantics(header: true, child: Text(t('Épisodes', 'Episodes'), style: Nami.section)),
    );
    if (media.availableEpisodes == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: EdgeInsets.fromLTRB(side, 0, side, 32),
            child: Text(t("Aucun épisode diffusé pour l'instant.", 'No episode has aired yet.'), style: Nami.meta),
          ),
        ],
      );
    }
    final numbers = [for (var n = 1; n <= media.availableEpisodes; n++) n];
    if (!wide) {
      return Transform.translate(
        offset: const Offset(0, -50),
        child: ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Padding(
                padding: EdgeInsets.symmetric(horizontal: side),
                child: Column(children: [for (final n in numbers) _episodeRow(n, accent)]),
              ),
            ],
          ),
        ),
      );
    }
    // A grid of pictures on wide windows: more episodes at a glance.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Padding(
          padding: EdgeInsets.fromLTRB(side, 0, side, 40),
          child: LayoutBuilder(
            builder: (context, box) {
              final columns = (box.maxWidth / 280).floor().clamp(2, 6);
              final cardWidth = (box.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 20,
                children: [for (final n in numbers) SizedBox(width: cardWidth, child: _episodeCard(n, accent))],
              );
            },
          ),
        ),
      ],
    );
  }

  ({EpisodeInfo? ep, bool watched, bool isNext, String? state, double? resume}) _episode(int n) {
    final watched = n <= media.progress;
    final isNext = n == nextEpisode && !watched && (AniList.instance.isLoggedIn || n > 1);
    final resume = AppSettings.instance.resumeFraction(media.id, n);
    final state = watched
        ? t('Vu', 'Watched')
        : resume != null
        ? t('En cours', 'In progress')
        : (isNext ? t('À voir', 'Up next') : null);
    return (ep: mappings?.episode(n), watched: watched, isNext: isNext, state: state, resume: resume);
  }

  /// Picture with the watched dimming, the "up next" ring and how far you got.
  Widget _thumb(int n, Color accent, double? width, double height) {
    final e = _episode(n);
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(e.isNext ? 2 : 0),
      decoration: e.isNext
          ? BoxDecoration(
              border: Border.all(color: accent, width: 2),
              borderRadius: BorderRadius.circular(Nami.radiusImage + 2),
            )
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Watched episodes dim their picture only: dimmed text would drop under 4.5:1.
          Opacity(opacity: e.watched ? 0.45 : 1, child: CoverImage(e.ep?.image ?? media.banner ?? media.coverSmall)),
          if (e.resume != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: ProgressLine(value: e.resume!, color: accent),
            ),
        ],
      ),
    );
  }

  Widget _episodeRow(int n, Color accent) {
    final e = _episode(n);
    return FocusOutline(
      radius: Nami.radiusImage,
      child: InkWell(
        onTap: () => _watch(n),
        borderRadius: BorderRadius.circular(Nami.radiusImage),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              _thumb(n, accent, 120, 68),
              const SizedBox(width: 14),
              Expanded(child: _episodeText(n, e, accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _episodeCard(int n, Color accent) {
    final e = _episode(n);
    return FocusOutline(
      radius: Nami.radiusImage,
      child: InkWell(
        onTap: () => _watch(n),
        borderRadius: BorderRadius.circular(Nami.radiusImage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _thumb(n, accent, null, double.infinity)),
            const SizedBox(height: 8),
            _episodeText(n, e, accent),
          ],
        ),
      ),
    );
  }

  Widget _episodeText(
    int n,
    ({EpisodeInfo? ep, bool watched, bool isNext, String? state, double? resume}) e,
    Color accent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ['$n', ?e.state].join(' · '),
          style: Nami.caption.copyWith(color: e.isNext || e.resume != null ? accent : Nami.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          e.ep?.title(AppSettings.instance.language.name) ?? t('Épisode $n', 'Episode $n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Nami.body.copyWith(color: e.watched ? Nami.textSecondary : Nami.text),
        ),
        if (e.ep?.runtime != null) Text('${e.ep!.runtime} min', style: Nami.caption),
      ],
    );
  }
}
