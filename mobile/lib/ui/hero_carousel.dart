import 'dart:async';

import 'package:flutter/material.dart';

import '../anilist.dart';
import '../home_feed.dart';
import '../platform.dart';
import '../screens/detail.dart';
import '../screens/list_editor.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'motion.dart';

/// The home banner: up to five anime, one at a time. It moves on every 8 s,
/// holds still while the pointer or the focus is on it, and never moves by
/// itself when the system asks for reduced motion.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.items, required this.onOpen});
  final List<HeroItem> items;
  final void Function(HeroItem) onOpen;

  static const interval = Duration(seconds: 8);
  static const zoomKey = ValueKey('hero-zoom');

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  int index = 0;
  bool hovered = false;
  bool focused = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  @override
  void didUpdateWidget(HeroCarousel old) {
    super.didUpdateWidget(old);
    if (index >= widget.items.length) index = 0;
    if (old.items.length != widget.items.length) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.items.length < 2 || hovered || focused || MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(HeroCarousel.interval, (_) {
      if (mounted) _go(1);
    });
  }

  void _go(int step) {
    final n = widget.items.length;
    if (n < 2) return;
    setState(() => index = (index + step) % n);
  }

  /// Arrows and swipes also restart the wait, so a slide just chosen stays.
  void _goByHand(int step) {
    _go(step);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final item = widget.items[index];
    final slide = AnimatedSwitcher(
      duration: Motion.of(context).slow,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _Slide(
        key: ValueKey(item.media.id),
        item: item,
        onOpen: () => widget.onOpen(item),
        bars: _Bars(count: widget.items.length, index: index),
      ),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        focused = f;
        _restart();
      },
      child: MouseRegion(
        onEnter: (_) {
          hovered = true;
          _restart();
        },
        onExit: (_) {
          hovered = false;
          _restart();
        },
        child: GestureDetector(
          onHorizontalDragEnd: isDesktop
              ? null
              : (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v.abs() > 200) _goByHand(v < 0 ? 1 : -1);
                },
          child: Stack(
            children: [
              slide,
              if (isDesktop && widget.items.length > 1)
                Positioned(
                  right: 32,
                  bottom: 36,
                  child: Row(
                    children: [
                      _Arrow(icon: Icons.chevron_left, tooltip: t('Précédent', 'Previous'), onTap: () => _goByHand(-1)),
                      const SizedBox(width: 8),
                      _Arrow(icon: Icons.chevron_right, tooltip: t('Suivant', 'Next'), onTap: () => _goByHand(1)),
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

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FocusOutline(
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(backgroundColor: Nami.text.withValues(alpha: 0.12)),
      icon: Icon(icon, color: Nami.text),
    ),
  );
}

/// Where the banner is among its anime: one short bar per anime.
class _Bars extends StatelessWidget {
  const _Bars({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    return Semantics(
      label: t('${index + 1} sur $count', '${index + 1} of $count'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: i == index ? 30 : 18,
              height: 3,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: i == index ? Nami.text : Nami.text.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({super.key, required this.item, required this.onOpen, required this.bars});
  final HeroItem item;
  final VoidCallback onOpen;
  final Widget bars;

  Media get media => item.media;

  String get kicker => switch (item.reason) {
    HeroReason.resume => t('Reprendre · épisode ${item.episode}', 'Resume · episode ${item.episode}'),
    HeroReason.newEpisode => t('Nouvel épisode · ${item.episode}', 'New episode · ${item.episode}'),
    HeroReason.trending => t('Tendance', 'Trending'),
  };

  String get meta => [
    if (media.seasonYear != null) '${media.seasonYear}',
    if (media.episodes != null) t('${media.episodes} épisodes', '${media.episodes} episodes'),
    if (media.averageScore != null) '${media.averageScore} %',
    if (media.genres.isNotEmpty) media.genres.take(3).map(genreLabel).join(', '),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop;
    final pad = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final height = desktop ? (size.height * 0.58).clamp(380.0, 620.0) : 440.0 + pad.top;
    final left = desktop ? pad.left + 24 : 20.0;
    final textEnd = ((left + 560) / size.width).clamp(0.0, 1.0);
    final accent = Nami.accentOf(media.color);
    final status = media.listEntry?.status;
    final watch = item.reason == HeroReason.resume
        ? t("Reprendre l'épisode ${item.episode}", 'Resume episode ${item.episode}')
        : media.isMovie
        ? t('Regarder', 'Watch')
        : t("Regarder l'épisode ${item.episode}", 'Watch episode ${item.episode}');
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FocusOutline(
          child: FilledButton.icon(
            onPressed: () => startWatching(context, media, item.episode),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(watch),
          ),
        ),
        FocusOutline(
          child: OutlinedButton.icon(
            onPressed: () => AniList.instance.isLoggedIn ? showListEditor(context, media) : onOpen(),
            icon: Icon(
              !AniList.instance.isLoggedIn
                  ? Icons.info_outline
                  : status == null
                  ? Icons.bookmark_add_outlined
                  : Icons.bookmark,
              size: 18,
            ),
            label: Text(
              !AniList.instance.isLoggedIn
                  ? t('Voir la fiche', 'See details')
                  : status == null
                  ? t('Ma liste', 'My list')
                  : listStatusLabel(status),
            ),
          ),
        ),
      ],
    );
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
            // A very slow push into the picture while it is shown (none with reduced motion).
            child: ClipRect(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: MediaQuery.disableAnimationsOf(context) ? 1 : 1.06),
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(seconds: 6),
                curve: Curves.easeOut,
                builder: (context, scale, child) =>
                    Transform.scale(key: HeroCarousel.zoomKey, scale: scale, child: child),
                child: CoverImage(media.banner ?? media.cover, radius: 0, alignment: const Alignment(0.4, -0.3)),
              ),
            ),
          ),
          // Dark from the text side, and solid ground at the bottom: text keeps 4.5:1 over any picture.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  // Dark (82 % or more) until the end of the text column, whatever the window width.
                  stops: desktop ? [0, textEnd, (textEnd + 0.3).clamp(0.0, 1.0)] : const [0, 0.0, 0.0],
                  colors: [
                    Nami.ground.withValues(alpha: desktop ? 0.9 : 0),
                    Nami.ground.withValues(alpha: desktop ? 0.82 : 0),
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
                  stops: desktop ? const [0, 0.2, 0.55, 0.97] : const [0, 0.18, 0.45, 0.8],
                  colors: [
                    Nami.ground.withValues(alpha: 0.5),
                    Nami.ground.withValues(alpha: 0),
                    Nami.ground.withValues(alpha: desktop ? 0.15 : 0.35),
                    Nami.ground,
                  ],
                ),
              ),
            ),
          ),
          Container(
            constraints: BoxConstraints(minHeight: height),
            alignment: Alignment.bottomLeft,
            padding: desktop ? EdgeInsets.fromLTRB(left, pad.top + 24, 200, 40) : EdgeInsets.only(top: pad.top + 24),
            child: _onScrim(
              desktop,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kicker,
                      style: TextStyle(fontFamily: Nami.sans, fontSize: 13, fontWeight: FontWeight.w600, color: accent),
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: Text(
                        media.title.display,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Nami.heroTitle.copyWith(fontSize: desktop ? 40 : 28, height: 1.05),
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: Nami.meta.copyWith(fontSize: 13)),
                    ],
                    if (desktop && media.plainDescription.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        media.plainDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Nami.meta.copyWith(fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 16),
                    actions,
                    const SizedBox(height: 18),
                    bars,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Phones put the text on [TextScrim] (80 % ground or more, 4.5:1 over any picture);
  /// the desktop relies on the side fade, which covers the text column.
  Widget _onScrim(bool desktop, Widget text) => desktop
      ? text
      : TextScrim(
          child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: text),
        );
}
