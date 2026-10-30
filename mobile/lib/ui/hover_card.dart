import 'package:flutter/material.dart';

import '../anilist.dart';
import '../screens/detail.dart';
import '../screens/list_editor.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// What opens over a cover on a mouse: banner, facts, the start of the
/// summary, and the two things you can do. No shadow: the card surface and
/// a thin line set it apart (DESIGN.md).
class MediaHoverCard extends StatelessWidget {
  const MediaHoverCard({super.key, required this.media, this.onDone});
  final Media media;

  /// Called after an action, so the host can close the card.
  final VoidCallback? onDone;

  static const width = 300.0;

  /// Upper bound of its height, to choose a side before it is laid out.
  static const tallest = 340.0;
  static const surface = Color(0xFF1B1B1E);

  int get nextEpisode =>
      media.isMovie ? 1 : (media.progress + 1).clamp(1, media.availableEpisodes < 1 ? 1 : media.availableEpisodes);

  String get facts => [
    if (media.seasonYear != null) '${media.seasonYear}',
    if (media.episodes != null) t('${media.episodes} ép.', '${media.episodes} ep.'),
    if (media.averageScore != null) '${media.averageScore} %',
    if (media.genres.isNotEmpty) media.genres.take(2).map(genreLabel).join(', '),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final canWatch = media.isMovie || media.availableEpisodes > 0;
    final status = media.listEntry?.status;
    return Material(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Nami.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(media.banner ?? media.cover, radius: 0),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.45, 1],
                        colors: [surface.withValues(alpha: 0), surface],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title.display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Nami.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (facts.isNotEmpty) ...[const SizedBox(height: 3), Text(facts, style: Nami.caption)],
                  if (media.plainDescription.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      media.plainDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Nami.caption.copyWith(height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canWatch)
                        FocusOutline(
                          child: FilledButton.icon(
                            onPressed: () {
                              onDone?.call();
                              startWatching(context, media, nextEpisode);
                            },
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: Text(
                              media.isMovie
                                  ? t('Regarder', 'Watch')
                                  : t("Regarder l'épisode $nextEpisode", 'Watch episode $nextEpisode'),
                            ),
                          ),
                        ),
                      FocusOutline(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            onDone?.call();
                            if (AniList.instance.isLoggedIn) {
                              showListEditor(context, media);
                            } else {
                              openMedia(context, media);
                            }
                          },
                          icon: Icon(status == null ? Icons.bookmark_add_outlined : Icons.bookmark, size: 18),
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
