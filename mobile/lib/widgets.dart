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
              errorBuilder: (_, _, _) => placeholder,
              frameBuilder: (_, child, frame, sync) => frame == null && !sync ? placeholder : child,
            ),
    );
  }
}

/// Fades a banner into the black ground, from transparent at [from].
class GroundFade extends StatelessWidget {
  const GroundFade({super.key, this.from = 0.45, this.topShade = true});
  final double from;
  final bool topShade;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.22, from, 1],
          colors: [
            Nami.ground.withValues(alpha: topShade ? 0.55 : 0),
            Nami.ground.withValues(alpha: 0),
            Nami.ground.withValues(alpha: 0.3),
            Nami.ground,
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: media.title.display,
      child: InkWell(
        borderRadius: BorderRadius.circular(Nami.radiusImage),
        onTap: () => openMedia(context, media),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 1 / 1.45, child: CoverImage(media.coverSmall)),
              if (progress != null) ...[
                const SizedBox(height: 6),
                ProgressLine(value: progress!, color: Nami.accentOf(media.color)),
              ],
              const SizedBox(height: 8),
              Text(media.title.display,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: Nami.caption.copyWith(fontSize: 13, color: const Color(0xFFD9D5CD))),
              if (badge != null) Text(badge!, style: Nami.caption),
            ],
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
      child: Stack(children: [
        Container(color: Nami.line),
        FractionallySizedBox(widthFactor: value.clamp(0.0, 1.0), child: Container(color: color)),
      ]),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(title, style: Nami.section)),
        const SizedBox(height: 14),
        SizedBox(
          height: 108 * 1.45 + 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => MediaCard(items[i], badge: badge?.call(items[i]), progress: progress?.call(items[i])),
          ),
        ),
      ],
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
            OutlinedButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
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

String networkError(Object e) => t(
      "Impossible de joindre AniList. Vérifie ta connexion, puis réessaie.",
      "Can't reach AniList. Check your connection, then try again.",
    );
