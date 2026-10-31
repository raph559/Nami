import 'dart:math';

import 'package:flutter/material.dart';

import '../anilist.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/motion.dart';
import '../widgets.dart';

/// The seven days from [start], each with its episodes in time order.
List<(DateTime, List<AiringItem>)> weekDays(List<AiringItem> items, DateTime start) => [
  for (var i = 0; i < 7; i++)
    () {
      final day = DateTime(start.year, start.month, start.day + i);
      return (
        day,
        [
          for (final item in items)
            if (DateUtils.isSameDay(item.airingAt, day)) item,
        ],
      );
    }(),
];

/// The start of [day].
DateTime dayStart(DateTime day) => DateTime(day.year, day.month, day.day);

String weekdayName(DateTime day) =>
    t('Lun Mar Mer Jeu Ven Sam Dim', 'Mon Tue Wed Thu Fri Sat Sun').split(' ')[day.weekday - 1];

/// "Novembre 2026".
String monthTitle(DateTime day) {
  final names = t(
    'Janvier Février Mars Avril Mai Juin Juillet Août Septembre Octobre Novembre Décembre',
    'January February March April May June July August September October November December',
  ).split(' ');
  return '${names[day.month - 1]} ${day.year}';
}

/// The seven days from [first]: "2 – 8 nov.", or "26 oct. – 1 nov." across two months.
String weekRange(DateTime first) {
  final last = DateTime(first.year, first.month, first.day + 6);
  final months = t(
    'janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.',
    'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec',
  ).split(' ');
  String month(DateTime d) => months[d.month - 1];
  final sameMonth = first.month == last.month;
  return t(
    '${first.day}${sameMonth ? '' : ' ${month(first)}'} – ${last.day} ${month(last)}',
    '${month(first)} ${first.day} – ${sameMonth ? '' : '${month(last)} '}${last.day}',
  );
}

/// Seven days of episodes with the anime of your list marked, today first: a strip of days
/// over the chosen day on a phone, a grid on desktop. Both page by seven days.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.listIds = const {}, this.load});
  final Set<int> listIds;

  /// Replaces AniList in tests. Gets the first day of the seven to load.
  final Future<List<AiringItem>> Function(DateTime start)? load;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime start = dayStart(DateTime.now());
  List<AiringItem>? items;
  bool failed = false;

  /// The chosen day on a phone, 0 for the first of the seven.
  int day = 0;
  bool onlyMine = false;

  /// Where the next content comes from: 1 from the right, -1 from the left, 0 in place.
  int _direction = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wanted = start;
    setState(() {
      failed = false;
      items = null;
    });
    try {
      final found = await (widget.load ?? (s) => AniList.instance.airingWeek(from: s))(wanted);
      if (mounted && wanted == start) setState(() => items = found);
    } catch (_) {
      if (mounted && wanted == start) setState(() => failed = true);
    }
  }

  void _shift(int weeks) {
    _direction = weeks.sign;
    start = DateTime(start.year, start.month, start.day + 7 * weeks);
    _load();
  }

  void _selectDay(int i) => setState(() {
    _direction = (i - day).sign;
    day = i;
  });

  void _goToday() {
    final today = dayStart(DateTime.now());
    if (start == today) return _selectDay(0);
    _direction = today.isAfter(start) ? 1 : -1;
    day = 0;
    start = today;
    _load();
  }

  void _setOnlyMine(bool value) => setState(() {
    _direction = 0;
    onlyMine = value;
  });

  /// Swaps [child] when [id] changes: the old one leaves as the new one comes from [_direction].
  Widget _moving(Object id, Widget child, {bool fill = true}) => AnimatedSwitcher(
    duration: Motion.of(context).medium,
    switchInCurve: Motion.curve,
    switchOutCurve: Motion.curve,
    layoutBuilder: fill
        ? (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current])
        : AnimatedSwitcher.defaultLayoutBuilder,
    transitionBuilder: (child, animation) {
      final incoming = child.key == ValueKey(id);
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: Offset(0.04 * (incoming ? _direction : -_direction), 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      );
    },
    child: KeyedSubtree(key: ValueKey(id), child: child),
  );

  bool _shown(AiringItem item) => !onlyMine || widget.listIds.contains(item.media.id);

  @override
  Widget build(BuildContext context) {
    final days = weekDays([...?items?.where(_shown)], start);
    final now = DateTime.now();
    return Scaffold(
      // The app bar already keeps clear of the rail.
      appBar: AppBar(
        titleSpacing: isDesktop ? 24 : null,
        title: isDesktop
            ? Text(t('Calendrier', 'Calendar'))
            : _moving(monthTitle(days[day].$1), Text(monthTitle(days[day].$1)), fill: false),
        actions: [
          if (!isDesktop && !DateUtils.isSameDay(days[day].$1, now))
            FocusOutline(
              child: TextButton(onPressed: _goToday, child: Text(t("Aujourd'hui", 'Today'))),
            ),
        ],
      ),
      body: isDesktop ? _desktop(days) : _phone(days),
    );
  }

  Widget _phone(List<(DateTime, List<AiringItem>)> days) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _moving(
            start,
            _WeekStrip(days: days, selected: day, listIds: widget.listIds, onSelect: _selectDay, onSwipe: _shift),
            fill: false,
          ),
          if (widget.listIds.isNotEmpty)
            SwitchListTile.adaptive(
              value: onlyMine,
              onChanged: _setOnlyMine,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(t('Seulement ma liste', 'Only my list'), style: Nami.meta),
            ),
          Expanded(
            child: _moving(
              (start, day, onlyMine),
              AnimatedSwitcher(
                duration: Motion.of(context).medium,
                child: KeyedSubtree(key: ValueKey((items == null, failed)), child: _state(_agenda(days[day]))),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// The loading and error states around what the week shows once it is there.
  Widget _state(Widget loaded) {
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
    return loaded;
  }

  /// One day: time on the left, the current time as a line between what is out and what is to come.
  Widget _agenda((DateTime, List<AiringItem>) selected) {
    final (date, shown) = selected;
    if (shown.isEmpty) {
      return StateMessage(
        title: onlyMine
            ? t('Rien de ta liste ce jour-là', 'Nothing from your list that day')
            : t('Aucun épisode ce jour-là', 'No episodes that day'),
      );
    }
    final now = DateTime.now();
    final today = DateUtils.isSameDay(date, now);
    final aired = today ? shown.where((i) => i.airedAt(now)).length : -1;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: shown.length + (today ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == aired) {
          return const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: NowLine());
        }
        final item = shown[today && i > aired ? i - 1 : i];
        return _AgendaRow(item: item, inList: widget.listIds.contains(item.media.id));
      },
    );
  }

  Widget _desktop(List<(DateTime, List<AiringItem>)> days) {
    final side = MediaQuery.paddingOf(context).left + 24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, 4, 24, 12),
          child: Row(
            children: [
              _WeekButton(
                icon: Icons.chevron_left,
                tooltip: t('Semaine précédente', 'Previous week'),
                onPressed: () => _shift(-1),
              ),
              const SizedBox(width: 4),
              _WeekButton(
                icon: Icons.chevron_right,
                tooltip: t('Semaine suivante', 'Next week'),
                onPressed: () => _shift(1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: _moving(
                        weekRange(start),
                        Text(
                          weekRange(start),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Nami.section.copyWith(fontSize: 17),
                        ),
                        fill: false,
                      ),
                    ),
                    if (start != dayStart(DateTime.now())) ...[
                      const SizedBox(width: 12),
                      FocusOutline(
                        child: TextButton(onPressed: _goToday, child: Text(t("Aujourd'hui", 'Today'))),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.listIds.isNotEmpty) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: _ListFilter(value: onlyMine, onChanged: _setOnlyMine),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _moving(
            (start, onlyMine, failed),
            failed
                ? _state(const SizedBox.shrink())
                : _WeekGrid(days: days, loading: items == null, listIds: widget.listIds, left: side),
          ),
        ),
      ],
    );
  }
}

/// The current time between the episodes of today.
class NowLine extends StatelessWidget {
  const NowLine({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: t('Maintenant', 'Now'),
    child: Container(height: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: Nami.text),
  );
}

/// The switch and its words as one control: only the switch's own track reacts to the mouse.
class _ListFilter extends StatelessWidget {
  const _ListFilter({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => QuietTap(
    onTap: () => onChanged(!value),
    builder: (context, hovered) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AnimatedDefaultTextStyle(
            duration: Motion.of(context).fast,
            style: Nami.meta.copyWith(color: hovered ? Nami.text : Nami.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: Text(t('Seulement ma liste', 'Only my list')),
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ],
    ),
  );
}

class _WeekButton extends StatelessWidget {
  const _WeekButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FocusOutline(
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: Nami.text.withValues(alpha: 0.08)),
      icon: Icon(icon, color: Nami.text),
    ),
  );
}

/// The week as seven days in a row, Apple Calendar style: swipe for the next or previous
/// week. A dot marks the days with something from your list, or anything without a list.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.selected,
    required this.listIds,
    required this.onSelect,
    required this.onSwipe,
  });
  final List<(DateTime, List<AiringItem>)> days;
  final int selected;
  final Set<int> listIds;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onSwipe;

  @override
  Widget build(BuildContext context) {
    final letters = t('L M M J V S D', 'M T W T F S S').split(' ');
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 200) onSwipe(v < 0 ? 1 : -1);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _StripDay(
                  letter: letters[days[i].$1.weekday - 1],
                  label: weekdayName(days[i].$1),
                  day: days[i].$1,
                  selected: i == selected,
                  marked: listIds.isEmpty
                      ? days[i].$2.isNotEmpty
                      : days[i].$2.any((item) => listIds.contains(item.media.id)),
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StripDay extends StatelessWidget {
  const _StripDay({
    required this.letter,
    required this.label,
    required this.day,
    required this.selected,
    required this.marked,
    required this.onTap,
  });
  final String letter;
  final String label;
  final DateTime day;
  final bool selected;
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(day, DateTime.now());
    return FocusOutline(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label ${day.day}',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Nami.radiusButton),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(letter, style: Nami.caption),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: Motion.of(context).fast,
                  curve: Motion.curve,
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Nami.text : Colors.transparent,
                    border: today && !selected ? Border.all(color: Nami.text, width: 1.5) : null,
                  ),
                  child: Text(
                    '${day.day}',
                    style: Nami.body.copyWith(
                      height: 1,
                      fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Nami.ground : Nami.text,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: marked ? Nami.textSecondary : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seven columns under fixed day headers. Below the width they need, the whole week scrolls sideways.
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.days, required this.loading, required this.listIds, required this.left});
  final List<(DateTime, List<AiringItem>)> days;
  final bool loading;
  final Set<int> listIds;
  final double left;

  static const gap = 10.0;
  static const narrowest = 150.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final column = max(narrowest, (box.maxWidth - left - 24 - gap * 6) / 7);
      Widget row(Widget Function((DateTime, List<AiringItem>) day) cell) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox(width: column, child: cell(days[i])),
          ],
        ],
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(left: left, right: 24),
        child: SizedBox(
          width: column * 7 + gap * 6,
          height: box.maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row((d) => _DayHeader(day: d.$1, count: d.$2.length)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.of(context).medium,
                  layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                  child: SingleChildScrollView(
                    key: ValueKey(loading),
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: row(
                      (d) => loading ? const _WaitingCards() : _DayColumn(day: d.$1, items: d.$2, listIds: listIds),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The shape of a day while its episodes load.
class _WaitingCards extends StatelessWidget {
  const _WaitingCards();

  @override
  Widget build(BuildContext context) => Semantics(
    label: t('Chargement du calendrier…', 'Loading the calendar…'),
    child: Column(
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            height: 66,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF131315),
              borderRadius: BorderRadius.circular(Nami.radiusButton),
            ),
          ),
      ],
    ),
  );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});
  final DateTime day;
  final int count;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(day, DateTime.now());
    return Semantics(
      header: true,
      label: t('${weekdayName(day)} ${day.day}, $count épisodes', '${weekdayName(day)} ${day.day}, $count episodes'),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: today ? Nami.text : Nami.line, width: today ? 2 : 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        weekdayName(day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Nami.meta.copyWith(
                          color: today ? Nami.text : Nami.textSecondary,
                          fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      alignment: Alignment.center,
                      decoration: today ? BoxDecoration(color: Nami.text, shape: BoxShape.circle) : null,
                      child: Text(
                        '${day.day}',
                        style: Nami.body.copyWith(
                          fontSize: 16,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: today ? Nami.ground : Nami.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (count > 0) Text('$count', maxLines: 1, style: Nami.caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day, required this.items, required this.listIds});
  final DateTime day;
  final List<AiringItem> items;
  final Set<int> listIds;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateUtils.isSameDay(day, now);
    final aired = today ? items.where((i) => i.airedAt(now)).length : -1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i <= items.length; i++) ...[
          if (i == aired) const NowLine(),
          if (i < items.length) _WeekCard(item: items[i], inList: listIds.contains(items[i].media.id)),
        ],
      ],
    );
  }
}

/// An episode in a day's column; the anime of your list sit on a lighter card with a bookmark.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.item, required this.inList});
  final AiringItem item;
  final bool inList;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Nami.radiusButton);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FocusOutline(
        radius: Nami.radiusButton,
        child: Material(
          color: inList ? const Color(0xFF26262A) : const Color(0xFF131315),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () => openMedia(context, item.media),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 38, height: 54, child: CoverImage(item.media.coverSmall)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                clockTime(context, item.airingAt),
                                style: Nami.caption.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (inList) _ListMark(),
                          ],
                        ),
                        Text(
                          item.media.title.display,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Nami.caption.copyWith(color: Nami.text, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Text(t('Épisode ${item.episode}', 'Episode ${item.episode}'), style: Nami.caption),
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

class _ListMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    label: t('Dans ta liste', 'In your list'),
    child: Icon(Icons.bookmark, size: 13, color: Nami.text),
  );
}

/// An episode of the chosen day on a phone, with its time in a column on the left.
class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.item, required this.inList});
  final AiringItem item;
  final bool inList;

  @override
  Widget build(BuildContext context) => FocusOutline(
    radius: 0,
    gap: -2,
    child: InkWell(
      onTap: () => openMedia(context, item.media),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 52),
              child: Text(clockTime(context, item.airingAt), style: Nami.caption.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 44, height: 62, child: CoverImage(item.media.coverSmall)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
