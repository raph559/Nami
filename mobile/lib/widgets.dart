import 'package:flutter/material.dart';

import 'anilist.dart';
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

void openMedia(BuildContext context, Media media) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(media: media)));
}

class MediaCard extends StatelessWidget {
  const MediaCard(this.media, {super.key, this.badge, this.width = 108, this.progress});
  final Media media;
  final String? badge;
  final double width;

  /// Watched fraction, drawn as a thin line under the cover.
  final double? progress;

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
  Widget build(BuildContext context) {
    return FocusOutline(
      radius: Nami.radiusImage,
      child: Semantics(
        button: true,
        label: [media.title.display, ?badge].join(', '),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Nami.radiusImage),
          onTap: () => openMedia(context, media),
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: width, height: width * 1.45, child: CoverImage(media.coverSmall)),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  ProgressLine(value: progress!, color: Nami.accentOf(media.color)),
                ],
                const SizedBox(height: 8),
                Text(
                  media.title.display,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Nami.caption.copyWith(fontSize: 13, color: const Color(0xFFD9D5CD)),
                ),
                if (badge != null) Text(badge!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Nami.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

class MediaRow extends StatelessWidget {
  const MediaRow({super.key, required this.title, required this.items, this.badge, this.progress});
  final String title;
  final List<Media> items;
  final String? Function(Media)? badge;
  final double? Function(Media)? progress;

  @override
  Widget build(BuildContext context) {
    // Wider covers on tablets and desktops, so a row is not a strip of stamps.
    // Covers widen with the text size so titles break between words, not inside them.
    final textFactor = (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, 1.6);
    final width = (MediaQuery.sizeOf(context).width >= 700 ? 140.0 : 108.0) * textFactor;
    final height = MediaCard.heightFor(context, width, withBadge: badge != null, withProgress: progress != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Semantics(header: true, child: Text(title, style: Nami.section)),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: height + 8,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) =>
                MediaCard(items[i], width: width, badge: badge?.call(items[i]), progress: progress?.call(items[i])),
          ),
        ),
      ],
    );
  }
}

/// Keeps reading width comfortable on tablets and desktops.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 760, this.alignment = Alignment.topCenter});
  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
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
            Text(title, textAlign: TextAlign.center, style: Nami.section.copyWith(fontSize: 22)),
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
