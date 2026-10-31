import 'package:flutter/material.dart';

import '../anilist.dart';
import '../mappings.dart';
import '../platform.dart';
import '../player_center.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/tags.dart';
import '../widgets.dart';
import 'home.dart' show HomeScreen;
import 'list_editor.dart';

/// Opens the sources for [episode]; the player then runs above the app and
/// moves on to the next episodes by itself.
void startWatching(BuildContext context, Media media, int episode) => PlayerCenter.instance.openSources(media, episode);

/// "ONA · Automne 2026 · 10 épisodes de 28 min · TRIGGER", leaving out what AniList does not know.
String animeMetaLine(Media media) {
  final season = media.json['season'] as String?;
  final duration = media.json['duration'] as int?;
  final episodes = media.episodes;
  return [
    if (media.format != null) media.format!.replaceAll('_', ' '),
    if (media.seasonYear != null)
      season != null ? '${HomeScreen.seasonName(season)} ${media.seasonYear}' : '${media.seasonYear}',
    if (episodes != null)
      duration != null
          ? t('$episodes épisodes de $duration min', '$episodes episodes of $duration min')
          : t('$episodes épisodes', '$episodes episodes'),
    if (episodes == null && media.isMovie && duration != null) '$duration min',
    ?media.studio,
  ].join(' · ');
}

String? _statusLabel(String? status) => switch (status) {
  'FINISHED' => t('Terminé', 'Finished'),
  'RELEASING' => t('En cours de diffusion', 'Airing'),
  'NOT_YET_RELEASED' => t('À venir', 'Upcoming'),
  'CANCELLED' => t('Annulé', 'Cancelled'),
  'HIATUS' => t('En pause', 'On hiatus'),
  _ => null,
};

String _score(double outOf100) {
  final v = outOf100 / 10;
  return v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1).replaceAll('.', t(',', '.'));
}

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

  String? get airingLine {
    final airing = media.nextAiringAt;
    if (airing == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(airing * 1000).difference(DateTime.now());
    final when = d.inDays > 0
        ? t('dans ${d.inDays} j', 'in ${d.inDays} d')
        : t('dans ${d.inHours} h', 'in ${d.inHours} h');
    return t('Épisode ${media.nextEpisode} $when', 'Episode ${media.nextEpisode} $when');
  }

  /// Score, status, genres and studio, each only when known.
  List<(String, String)> get facts => [
    if (media.averageScore != null) (t('Score', 'Score'), '${media.averageScore} %'),
    if (_statusLabel(media.status) case final s?) (t('Statut', 'Status'), s),
    if (media.genres.isNotEmpty) (t('Genres', 'Genres'), media.genres.take(3).map(genreLabel).join(', ')),
    if (media.studio case final s?) (t('Studio', 'Studio'), s),
  ];

  Future<void> _editList() async {
    final updated = await showListEditor(context, media);
    if (updated != null && mounted) setState(() => media = updated);
  }

  Widget _cover(double width) {
    Widget c = SizedBox(width: width, height: width * 1.45, child: CoverImage(media.cover));
    if (widget.heroTag != null) c = Hero(tag: widget.heroTag!, child: c);
    return c;
  }

  Widget _watchButton({required bool expand}) => FocusOutline(
    child: FilledButton.icon(
      style: expand ? FilledButton.styleFrom(minimumSize: const Size(0, 50)) : null,
      onPressed: canWatch ? () => _watch(media.isMovie ? 1 : nextEpisode) : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 22),
      label: Text(watchLabel),
    ),
  );

  /// Where the anime stands in the list, and the score when rated; both open the editor.
  List<Widget> _listButtons({required bool tall}) {
    if (!AniList.instance.isLoggedIn) return const [];
    final status = media.listEntry?.status;
    final score = media.listEntry?.score ?? 0;
    final style = tall ? OutlinedButton.styleFrom(minimumSize: const Size(0, 50)) : null;
    return [
      FocusOutline(
        child: OutlinedButton.icon(
          style: style,
          onPressed: _editList,
          icon: Icon(status == null ? Icons.bookmark_add_outlined : Icons.bookmark, size: 20),
          label: Text(status == null ? t('Ma liste', 'My list') : listStatusLabel(status)),
        ),
      ),
      if (score > 0)
        FocusOutline(
          // An icon, not "★": the app font has no star glyph.
          child: OutlinedButton.icon(
            style: style,
            onPressed: _editList,
            icon: const Icon(Icons.star_rounded, size: 18),
            label: Text(
              _score(score),
              semanticsLabel: t('Ta note : ${_score(score)} sur 10', 'Your score: ${_score(score)} out of 10'),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop;
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
          padding: EdgeInsets.only(left: desktop ? MediaQuery.paddingOf(context).left + 8 : 8),
          child: IconButton(
            tooltip: t('Retour', 'Back'),
            style: IconButton.styleFrom(backgroundColor: Nami.ground.withValues(alpha: 0.55)),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        leadingWidth: desktop ? MediaQuery.paddingOf(context).left + 64 : null,
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
        children: [desktop ? _desktopHeader() : _phoneHeader(), _episodes(desktop)],
      ),
    );
  }

  Widget _progress({required double fontSize}) {
    final total = media.episodes ?? media.availableEpisodes;
    if (!AniList.instance.isLoggedIn || media.isMovie || total <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Row(
          children: [
            Text(t('Ta progression', 'Your progress'), style: Nami.caption.copyWith(fontSize: fontSize)),
            const SizedBox(width: 10),
            Expanded(
              child: ProgressLine(value: media.progress / total, color: Nami.accentOf(media.color)),
            ),
            const SizedBox(width: 10),
            Text('${media.progress} / $total', style: Nami.caption.copyWith(fontSize: fontSize)),
          ],
        ),
      ),
    );
  }

  Widget _description({required double maxWidth}) {
    if (media.plainDescription.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ContentWidth(
        maxWidth: maxWidth,
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FocusOutline(
              radius: Nami.radiusImage,
              child: InkWell(
                onTap: () => setState(() => expanded = !expanded),
                child: Text(
                  media.plainDescription,
                  maxLines: expanded ? null : (isDesktop ? 3 : 4),
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: Nami.body.copyWith(fontSize: isDesktop ? 13 : 14, color: Nami.textSecondary),
                  semanticsLabel: media.plainDescription,
                ),
              ),
            ),
            if (!expanded)
              TextButton(
                onPressed: () => setState(() => expanded = true),
                child: Text(t('Lire la suite', 'Read more')),
              ),
          ],
        ),
      ),
    );
  }

  /// Score, status and each genre as tags (the studio is already in the line under the title).
  Widget _factTags() {
    final tags = [
      if (media.averageScore != null) FlatTag('${media.averageScore} %'),
      if (_statusLabel(media.status) case final s?) FlatTag(s),
      for (final g in media.genres.take(4)) FlatTag(genreLabel(g)),
    ];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: tags),
    );
  }

  /// Phone: the banner, then the cover beside the title, overlapping it.
  Widget _phoneHeader() {
    final top = MediaQuery.paddingOf(context).top;
    final meta = animeMetaLine(media);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 240 + top,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(padding: const EdgeInsets.only(bottom: 2), child: BannerPicture(media)),
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
                  Semantics(header: true, child: Text(media.title.display, style: Nami.pageTitle)),
                  if (meta.isNotEmpty) ...[const SizedBox(height: 10), Text(meta, style: Nami.meta)],
                  if (airingLine != null) ...[const SizedBox(height: 4), Text(airingLine!, style: Nami.meta)],
                  _progress(fontSize: 13),
                  const SizedBox(height: 16),
                  // Watch gets the full width; the list and the score go on a row below.
                  _watchButton(expand: true),
                  if (_listButtons(tall: true) case final buttons when buttons.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: buttons.first),
                        for (final b in buttons.skip(1)) ...[const SizedBox(width: 10), b],
                      ],
                    ),
                  ],
                  _description(maxWidth: 680),
                  _factTags(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Desktop: the banner to the top edge, the cover and the title over its
  /// faded part, and a short facts card on the right when the window is wide.
  Widget _desktopHeader() {
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final left = pad.left + 24;
    final showCard = facts.isNotEmpty && width >= 1100;
    final meta = animeMetaLine(media);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            media.title.display,
            style: Nami.pageTitle.copyWith(fontSize: width >= 1000 ? 38 : 30, height: 1.05),
          ),
        ),
        if (meta.isNotEmpty) ...[const SizedBox(height: 8), Text(meta, style: Nami.meta.copyWith(fontSize: 13))],
        if (airingLine != null) ...[
          const SizedBox(height: 4),
          Text(airingLine!, style: Nami.meta.copyWith(fontSize: 13)),
        ],
        _progress(fontSize: 12),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [_watchButton(expand: false), ..._listButtons(tall: false)]),
        _description(maxWidth: 640),
        if (!showCard) _factTags(),
      ],
    );
    return Stack(
      children: [
        SizedBox(
          height: 430,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: BannerPicture(media, alignment: const Alignment(0.4, -0.3)),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.3, 0.7, 0.98],
                    colors: [
                      Nami.ground.withValues(alpha: 0.3),
                      Nami.ground.withValues(alpha: 0.15),
                      Nami.ground.withValues(alpha: 0.75),
                      Nami.ground,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(left, 200, 40, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cover(width >= 1000 ? 180 : 130),
              const SizedBox(width: 30),
              // Text starts below the banner's bright part, on the faded ground.
              Expanded(
                child: Padding(padding: const EdgeInsets.only(top: 70), child: info),
              ),
              if (showCard) ...[
                const SizedBox(width: 30),
                Padding(
                  padding: const EdgeInsets.only(top: 110),
                  child: _FactsCard(facts: facts),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _episodes(bool desktop) {
    if (media.isMovie) return const SizedBox(height: 32);
    final accent = Nami.accentOf(media.color);
    final side = desktop ? MediaQuery.paddingOf(context).left + 24 : 20.0;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(side, desktop ? 32 : 0, side, 12),
      child: Semantics(
        header: true,
        child: Text(t('Épisodes', 'Episodes'), style: desktop ? Nami.section.copyWith(fontSize: 15) : Nami.section),
      ),
    );
    if (media.availableEpisodes == 0) {
      return Transform.translate(
        offset: Offset(0, desktop ? 0 : -50),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 32),
              child: Text(t("Aucun épisode diffusé pour l'instant.", 'No episode has aired yet.'), style: Nami.meta),
            ),
          ],
        ),
      );
    }
    final numbers = [for (var n = 1; n <= media.availableEpisodes; n++) n];
    if (!desktop) {
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
    // A grid of pictures on desktop: more episodes at a glance.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Padding(
          padding: EdgeInsets.fromLTRB(side, 0, 40, 40),
          child: LayoutBuilder(
            builder: (context, box) {
              final columns = (box.maxWidth / 300).floor().clamp(2, 6);
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

  ({EpisodeInfo? ep, bool watched, bool isNext, String? state, double? resume, int? runtime}) _episode(int n) {
    final watched = n <= media.progress;
    final isNext = n == nextEpisode && !watched && (AniList.instance.isLoggedIn || n > 1);
    final resume = AppSettings.instance.resumeFraction(media.id, n);
    final ep = mappings?.episode(n);
    final runtime = ep?.runtime ?? media.json['duration'] as int?;
    final left = resume != null && runtime != null ? ((1 - resume) * runtime).round() : null;
    final state = watched
        ? t('Vu', 'Watched')
        : resume != null
        ? (left != null
              ? t('En cours · $left min restantes', 'In progress · $left min left')
              : t('En cours', 'In progress'))
        : (isNext ? t('À voir', 'Up next') : null);
    return (ep: ep, watched: watched, isNext: isNext, state: state, resume: resume, runtime: runtime);
  }

  /// Picture with the watched dimming, the "up next" ring, the length and how far you got.
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
          if (isDesktop && e.runtime != null)
            Positioned(
              right: 6,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Nami.ground.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  child: Text('${e.runtime} min', style: Nami.caption.copyWith(fontSize: 11, color: Nami.text)),
                ),
              ),
            ),
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
    ({EpisodeInfo? ep, bool watched, bool isNext, String? state, double? resume, int? runtime}) e,
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
          style: Nami.body.copyWith(fontSize: isDesktop ? 13 : 15, color: e.watched ? Nami.textSecondary : Nami.text),
        ),
        if (!isDesktop && e.runtime != null) Text('${e.runtime} min', style: Nami.caption),
      ],
    );
  }
}

/// The short facts beside the title on a wide desktop window.
class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131315).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Nami.line),
      ),
      child: Column(
        children: [
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Nami.caption.copyWith(color: Nami.textMuted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: Nami.caption.copyWith(color: Nami.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
