
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'anilist.dart';
import 'platform.dart';
import 'screens/detail.dart';
import 'settings.dart';
import 'theme.dart';

/// Network image that fills the space it is given.
class CoverImage extends StatelessWidget {
  const CoverImage(this.url, {super.key, this.radius = Nami.radiusImage, this.alignment = Alignment.center});
  final String? url;
  final double radius;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: const Color(0xFF18181A));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              fit: BoxFit.cover,
              alignment: alignment,
              width: double.infinity,
              height: double.infinity,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => placeholder,
              frameBuilder: (_, child, frame, sync) => frame == null && !sync ? placeholder : child,
            ),
    );
  }
}

/// Draws a visible ring around [child] while keyboard focus is inside it.
/// Material's own focus overlay is too faint on the black ground (1.5:1),
/// so focusable rows, cards and buttons are wrapped in this instead.
class FocusOutline extends StatefulWidget {
  const FocusOutline({super.key, required this.child, this.radius = Nami.radiusButton, this.gap = 3});
  final Widget child;
  final double radius;
  final double gap;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) {
    if (focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final show = focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (f) => setState(() => focused = f),
      child: CustomPaint(foregroundPainter: show ? _RingPainter(widget.radius, widget.gap) : null, child: widget.child),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.radius, this.gap);
  final double radius;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(gap);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + gap)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Nami.text,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.radius != radius || old.gap != gap;
}

/// Fades a banner into the black ground. Text never sits on this fade: it
/// goes on [TextScrim], which keeps the background dark enough for 4.5:1
/// even over a white image.
class GroundFade extends StatelessWidget {
  const GroundFade({super.key, this.from = 0.45});
  final double from;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.22, from, 1],
          colors: [
            Nami.ground.withValues(alpha: 0.6),
            Nami.ground.withValues(alpha: 0),
            Nami.ground.withValues(alpha: 0.3),
            Nami.ground,
          ],
        ),
      ),
    );
  }
}

/// Background for text over artwork: a short fade, then at least 80 % black.
/// Secondary text needs 76 % over a white pixel to reach 4.5:1.
class TextScrim extends StatelessWidget {
  const TextScrim({super.key, required this.child, this.fade = 90});
  final Widget child;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: fade,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Nami.ground.withValues(alpha: 0), Nami.ground.withValues(alpha: 0.8)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Nami.ground.withValues(alpha: 0.8), Nami.ground],
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

void openMedia(BuildContext context, Media media, {String? heroTag}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DetailScreen(media: media, heroTag: heroTag),
    ),
  );
}

/// A cover with its title. On a mouse, hovering lifts it and shows the score
/// and genres; a long press (touch) opens a short sheet with the same facts
/// and the two actions. Opening it, the cover grows into the anime page.
class MediaCard extends StatefulWidget {
  const MediaCard(this.media, {super.key, this.badge, this.width = 108, this.progress, this.heroTag});
  final Media media;
  final String? badge;
  final double width;

  /// Watched fraction, drawn as a thin line under the cover.
  final double? progress;

  /// Shared with the anime page's cover for the opening transition; unique per screen.
  final String? heroTag;

  /// Height of a card of [width] at the current text size.
  static double heightFor(BuildContext context, double width, {bool withBadge = false, bool withProgress = false}) {
    final scaler = MediaQuery.textScalerOf(context);
    return width * 1.45 +
        8 +
        scaler.scale(13) * 1.3 * 2 +
        (withBadge ? scaler.scale(12) * 1.3 : 0) +
        (withProgress ? 8 : 0) +
        4;
  }

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool hovered = false;

  Media get media => widget.media;

  String get facts => [
    if (media.averageScore != null) '${media.averageScore} %',
    if (media.seasonYear != null) '${media.seasonYear}',
    ...media.genres.take(2).map(genreLabel),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    Widget cover = CoverImage(media.coverSmall);
    if (widget.heroTag != null) cover = Hero(tag: widget.heroTag!, child: cover);
    return FocusOutline(
      radius: Nami.radiusImage,
      child: Semantics(
        button: true,
        label: [media.title.display, ?widget.badge].join(', '),
        hint: isDesktop ? null : t('Appui long pour un aperçu', 'Long press for a preview'),
        excludeSemantics: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: InkWell(
            borderRadius: BorderRadius.circular(Nami.radiusImage),
            onTap: () => openMedia(context, media, heroTag: widget.heroTag),
            onLongPress: () {
              HapticFeedback.mediumImpact();
              showMediaPreview(context, media);
            },
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedScale(
                    scale: hovered ? 1.04 : 1,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: SizedBox(
                      width: width,
                      height: width * 1.45,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          cover,
                          // Score and genres on hover, on a scrim so they stay readable.
                          if (hovered && facts.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Nami.radiusImage)),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Nami.ground.withValues(alpha: 0), Nami.ground.withValues(alpha: 0.88)],
                                      stops: const [0, 0.35],
                                    ),
                                  ),
                                  child: Text(
                                    facts,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Nami.caption.copyWith(color: Nami.text),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.progress != null) ...[
                    const SizedBox(height: 6),
                    ProgressLine(value: widget.progress!, color: Nami.accentOf(media.color)),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    media.title.display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Nami.caption.copyWith(fontSize: 13, color: hovered ? Nami.text : const Color(0xFFD9D5CD)),
                  ),
                  if (widget.badge != null)
                    Text(widget.badge!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Nami.caption),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The long-press preview: what the anime is and the two things you can do.
Future<void> showMediaPreview(BuildContext context, Media media) {
  final next = media.isMovie
      ? 1
      : (media.progress + 1).clamp(1, media.availableEpisodes < 1 ? 1 : media.availableEpisodes);
  final facts = [
    if (media.format != null) media.format!.replaceAll('_', ' '),
    if (media.seasonYear != null) '${media.seasonYear}',
    if (media.averageScore != null) '${media.averageScore} %',
    if (media.genres.isNotEmpty) media.genres.take(3).map(genreLabel).join(', '),
  ].join(' · ');
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 72, height: 104, child: CoverImage(media.coverSmall)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.title.display, style: Nami.section.copyWith(fontSize: 18)),
                    if (facts.isNotEmpty) ...[const SizedBox(height: 6), Text(facts, style: Nami.meta)],
                  ],
                ),
              ),
            ],
          ),
          if (media.plainDescription.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              media.plainDescription,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Nami.body.copyWith(fontSize: 14, color: Nami.textSecondary),
            ),
          ],
          const SizedBox(height: 18),
          if (media.isMovie || media.availableEpisodes > 0)
            FocusOutline(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () {
                  Navigator.pop(sheet);
                  startWatching(context, media, next);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  media.isMovie ? t('Regarder', 'Watch') : t("Regarder l'épisode $next", 'Watch episode $next'),
                ),
              ),
            ),
          const SizedBox(height: 10),
          FocusOutline(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                Navigator.pop(sheet);
                openMedia(context, media);
              },
              child: Text(t('Voir la fiche', 'See details')),
            ),
          ),
        ],
      ),
    ),
  );
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: Stack(
        children: [
          Container(color: Nami.line),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(color: color),
          ),
        ],
      ),
    );
  }
}

/// A titled row of covers. On a mouse, arrows appear on hover to page through
/// it and the row can be dragged; on touch it scrolls as usual.
class MediaRow extends StatefulWidget {
  const MediaRow({super.key, required this.title, required this.items, this.badge, this.progress});
  final String title;
  final List<Media> items;
  final String? Function(Media)? badge;
  final double? Function(Media)? progress;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final scroll = ScrollController();
  bool hovered = false;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void _page(int direction) {
    if (!scroll.hasClients) return;
    final p = scroll.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent);
    scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    // Wider covers on tablets and desktops, so a row is not a strip of stamps.
    // Covers widen with the text size so titles break between words, not inside them.
    final screen = MediaQuery.sizeOf(context).width;
    final textFactor = (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, 1.6);
    final width = (screen >= 700 ? 140.0 : 108.0) * textFactor;
    final side = screen >= 900 ? 48.0 : 20.0;
    final height = MediaCard.heightFor(
      context,
      width,
      withBadge: widget.badge != null,
      withProgress: widget.progress != null,
    );
    final list = ScrollConfiguration(
      // Mouse drag scrolls the row too, as on a touch screen.
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: ListView.separated(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(side, 8, side, 8),
        clipBehavior: Clip.none,
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final m = widget.items[i];
          return MediaCard(
            m,
            width: width,
            badge: widget.badge?.call(m),
            progress: widget.progress?.call(m),
            heroTag: 'row-${widget.title}-${m.id}',
          );
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Semantics(header: true, child: Text(widget.title, style: Nami.section)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height + 16,
          child: !isDesktop
              ? list
              : MouseRegion(
                  onEnter: (_) => setState(() => hovered = true),
                  onExit: (_) => setState(() => hovered = false),
                  child: Stack(
                    children: [
                      list,
                      if (hovered) ...[
                        _RowArrow(left: true, height: width * 1.45, onPressed: () => _page(-1)),
                        _RowArrow(left: false, height: width * 1.45, onPressed: () => _page(1)),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _RowArrow extends StatelessWidget {
  const _RowArrow({required this.left, required this.height, required this.onPressed});
  final bool left;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 8,
      height: height,
      width: 44,
      child: Material(
        color: Nami.ground.withValues(alpha: 0.82),
        child: InkWell(
          onTap: onPressed,
          child: Tooltip(
            message: left ? t('Précédents', 'Previous') : t('Suivants', 'Next'),
            child: Icon(left ? Icons.chevron_left : Icons.chevron_right, color: Nami.text, size: 30),
          ),
        ),
      ),
    );
  }
}

/// Keeps reading width comfortable on tablets and desktops.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 760,
    this.alignment = Alignment.topCenter,
    this.shrinkWrap = false,
  });
  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  /// Only as tall as [child], for sheets and dialogs.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      heightFactor: shrinkWrap ? 1 : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Loading, error and empty states share one layout: a message and, when
/// there is something to do, the action that fixes it.
class StateMessage extends StatelessWidget {
  const StateMessage({super.key, required this.title, this.body, this.action, this.onAction, this.loading = false});
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(height: 16),
            ],
            Text(title, textAlign: TextAlign.center, style: Nami.section.copyWith(fontSize: 18)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!, textAlign: TextAlign.center, style: Nami.meta),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              FocusOutline(
                child: OutlinedButton(onPressed: onAction, child: Text(action!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String networkError() => t(
  'Impossible de joindre AniList. Vérifie ta connexion, puis réessaie.',
  "Can't reach AniList. Check your connection, then try again.",
);

/// Grey shape of content that is loading. It breathes slowly (unless the
/// system asks for reduced motion) so the page does not look frozen.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = Nami.radiusImage});
  final double? width;
  final double? height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(color: const Color(0xFF1B1B1E), borderRadius: BorderRadius.circular(widget.radius)),
    );
    if (still) return box;
    return FadeTransition(opacity: Tween(begin: 0.55, end: 1.0).animate(pulse), child: box);
  }
}

/// Home while it loads: the banner, then two rows of covers.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;
    final side = wide ? 48.0 : 20.0;
    final cover = size.width >= 700 ? 140.0 : 108.0;
    Widget row() => Padding(
      padding: EdgeInsets.fromLTRB(side, 26, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 160, height: 20),
          const SizedBox(height: 14),
          SizedBox(
            height: cover * 1.45,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 10; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SkeletonBox(width: cover, height: cover * 1.45),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        SkeletonBox(height: wide ? (size.width * 0.42).clamp(440.0, 620.0) : 420, radius: 0),
        row(),
        row(),
      ],
    );
  }
}

/// Search results while they load.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = ((box.maxWidth + 12) / (130 + 12)).ceil().clamp(2, 10);
        final cell = (box.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [for (var i = 0; i < columns * 2; i++) SkeletonBox(width: cell, height: cell * 1.45)],
        );
      },
    );
  }
}
