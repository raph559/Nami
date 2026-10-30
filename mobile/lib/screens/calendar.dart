import 'package:flutter/material.dart';

import '../anilist.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/tabs.dart';
import '../widgets.dart';

/// The seven days from [now], each with its episodes in time order.
List<(DateTime, List<AiringItem>)> weekDays(List<AiringItem> items, DateTime now) => [
  for (var i = 0; i < 7; i++)
    () {
      final day = DateTime(now.year, now.month, now.day + i);
      return (
        day,
        [
          for (final item in items)
            if (DateUtils.isSameDay(item.airingAt, day)) item,
        ],
      );
    }(),
];

/// "Today", "Tomorrow", then the short weekday and the date.
String dayLabel(DateTime day, int index) {
  if (index == 0) return t("Aujourd'hui", 'Today');
  if (index == 1) return t('Demain', 'Tomorrow');
  final name = t('Lun Mar Mer Jeu Ven Sam Dim', 'Mon Tue Wed Thu Fri Sat Sun').split(' ')[day.weekday - 1];
  return '$name ${day.day}';
}

/// The week's episodes, one tab per day, with the anime of your list marked.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.listIds = const {}, this.load});
  final Set<int> listIds;

  /// Replaces AniList in tests.
  final Future<List<AiringItem>> Function()? load;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<AiringItem>? items;
  bool failed = false;
  int day = 0;
  bool onlyMine = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => failed = false);
    try {
      final found = await (widget.load ?? AniList.instance.airingWeek)();
      if (mounted) setState(() => items = found);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  bool _shown(AiringItem item) => !onlyMine || widget.listIds.contains(item.media.id);

  @override
  Widget build(BuildContext context) {
    final side = isDesktop ? 36.0 : 20.0;
    final days = weekDays([...?items?.where(_shown)], DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(t('Calendrier', 'Calendar'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(side, 8, side, 0),
                child: UnderlineTabs(
                  labels: [for (var i = 0; i < 7; i++) dayLabel(days[i].$1, i)],
                  counts: [for (final d in days) items == null ? null : d.$2.length],
                  selected: day,
                  onSelect: (i) => setState(() => day = i),
                ),
              ),
              if (widget.listIds.isNotEmpty)
                SwitchListTile.adaptive(
                  value: onlyMine,
                  onChanged: (v) => setState(() => onlyMine = v),
                  contentPadding: EdgeInsets.symmetric(horizontal: side),
                  title: Text(t('Seulement ma liste', 'Only my list'), style: Nami.meta),
                ),
              Expanded(child: _content(days[day].$2, side)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(List<AiringItem> shown, double side) {
    if (failed) {
      return StateMessage(
        title: t('Calendrier indisponible', 'Calendar unavailable'),
        body: t("AniList n'a pas répondu.", "AniList didn't answer."),
        action: t('Réessayer', 'Try again'),
        onAction: _load,
      );
    }
    if (items == null) {
      return StateMessage(title: t('Chargement du calendrier…', 'Loading the calendar…'), loading: true);
    }
    if (shown.isEmpty) {
      return StateMessage(
        title: onlyMine
            ? t('Rien de ta liste ce jour-là', 'Nothing from your list that day')
            : t('Aucun épisode ce jour-là', 'No episodes that day'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: shown.length,
      itemBuilder: (context, i) =>
          _CalendarRow(item: shown[i], inList: widget.listIds.contains(shown[i].media.id), side: side),
    );
  }
}

class _CalendarRow extends StatelessWidget {
  const _CalendarRow({required this.item, required this.inList, required this.side});
  final AiringItem item;
  final bool inList;
  final double side;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(item.airingAt).format(context);
    return FocusOutline(
      radius: 0,
      gap: -2,
      child: InkWell(
        onTap: () => openMedia(context, item.media),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: side, vertical: 8),
          child: Row(
            children: [
              SizedBox(width: 52, height: 74, child: CoverImage(item.media.coverSmall)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.aired ? t('$time · sorti', '$time · out') : time,
                      style: Nami.caption.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      item.media.title.display,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Nami.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(t('Épisode ${item.episode}', 'Episode ${item.episode}'), style: Nami.caption),
                    if (inList)
                      Text(
                        t('Dans ta liste', 'In your list'),
                        style: Nami.caption.copyWith(color: Nami.text, fontWeight: FontWeight.w600),
                      ),
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
