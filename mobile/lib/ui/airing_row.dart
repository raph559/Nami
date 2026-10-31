import 'package:flutter/material.dart';

import '../anilist.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Today's episodes in time order: small cover, time, title, episode, and
/// a mark on the anime of your list.
class AiringRow extends StatelessWidget {
  const AiringRow({super.key, required this.items, required this.listIds});
  final List<AiringItem> items;
  final Set<int> listIds;

  @override
  Widget build(BuildContext context) {
    final side = isDesktop ? MediaQuery.paddingOf(context).left + 24 : 20.0;
    final scaler = MediaQuery.textScalerOf(context);
    final height = 90 + (scaler.scale(12) - 12) * 4;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: side),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _AiringCard(item: items[i], inList: listIds.contains(items[i].media.id)),
      ),
    );
  }
}

class _AiringCard extends StatelessWidget {
  const _AiringCard({required this.item, required this.inList});
  final AiringItem item;
  final bool inList;

  @override
  Widget build(BuildContext context) {
    final time = clockTime(context, item.airingAt);
    final when = item.aired ? t('$time · sorti', '$time · out') : time;
    return FocusOutline(
      radius: Nami.radiusButton,
      child: Material(
        color: const Color(0xFF131315),
        borderRadius: BorderRadius.circular(Nami.radiusButton),
        child: InkWell(
          borderRadius: BorderRadius.circular(Nami.radiusButton),
          onTap: () => openMedia(context, item.media),
          child: SizedBox(
            width: 240,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(width: 52, height: 74, child: CoverImage(item.media.coverSmall)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(when, style: Nami.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                        Text(
                          item.media.title.display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Nami.caption.copyWith(color: Nami.text, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          t('Épisode ${item.episode}', 'Episode ${item.episode}'),
                          style: Nami.caption.copyWith(fontSize: 11),
                        ),
                        if (inList)
                          Text(
                            t('Dans ta liste', 'In your list'),
                            style: Nami.caption.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Nami.accentOf(item.media.color),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
