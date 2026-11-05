import 'package:flutter/material.dart';

import '../anilist.dart';
import '../platform.dart';
import '../profile.dart';
import '../settings.dart';
import '../theme.dart';

/// The viewer's anime statistics: the main numbers, what they watch most, how
/// they rate and which years their anime come from.
class ProfileStatsScreen extends StatelessWidget {
  const ProfileStatsScreen({super.key, required this.viewer});
  final Viewer viewer;

  @override
  Widget build(BuildContext context) {
    final s = viewer.stats;
    final format = viewer.scoreFormat;
    final days = s.minutes / 60 / 24;
    String number(double v) {
      final text = v.toStringAsFixed(1);
      return (text.endsWith('.0') ? text.substring(0, text.length - 2) : text).replaceAll('.', t(',', '.'));
    }

    final facts = [
      (t('Animes', 'Anime'), '${s.count}'),
      (t('Épisodes vus', 'Episodes watched'), '${s.episodes}'),
      (t('Jours', 'Days'), number(days)),
      if (s.meanScore > 0) (t('Note moyenne', 'Mean score'), format.show(s.meanScore)),
      if (s.standardDeviation > 0) (t('Écart type', 'Standard deviation'), '± ${number(s.standardDeviation)}'),
    ];
    final years = s.releaseYears.entries.where((e) => e.key > 0).toList()..sort((a, b) => a.key.compareTo(b.key));
    final scores = s.scores.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final accent = viewer.accent;
    // The most-watched first in full colour, the others fading a little.
    List<(StatCount, Color)> fading(List<StatCount> items) => [
      for (final (i, item) in items.indexed)
        (item, accent.withValues(alpha: items.length < 2 ? 1 : 1 - 0.5 * i / (items.length - 1))),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('Statistiques', 'Statistics'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(isDesktop ? 40 : 16, 8, isDesktop ? 40 : 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Heading(t('En bref', 'In brief')),
                  Wrap(
                    spacing: 28,
                    runSpacing: 14,
                    children: [
                      for (final (label, value) in facts)
                        Semantics(
                          label: '$label : $value',
                          excludeSemantics: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(value, style: Nami.section.copyWith(color: accent)),
                              Text(label, style: Nami.caption),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (s.genres.isNotEmpty) ...[_Heading('Genres'), _Bars(fading(s.genres))],
                  if (s.studios.isNotEmpty) ...[_Heading('Studios'), _Bars(fading(s.studios))],
                  if (s.formats.isNotEmpty) ...[
                    _Heading('Formats'),
                    _Bars(fading([for (final f in s.formats) StatCount(formatLabel(f.name), f.count)])),
                  ],
                  if (s.statuses.isNotEmpty) ...[
                    _Heading(t('Statuts', 'Statuses')),
                    _Bars([for (final f in s.statuses) (StatCount(statusLabel(f.name), f.count), statusColor(f.name))]),
                  ],
                  if (scores.isNotEmpty) ...[
                    _Heading(t('Notes', 'Scores')),
                    _Columns(
                      label: t('Répartition des notes', 'Score distribution'),
                      entries: [
                        for (final e in scores) (format.show(e.key.toDouble()), e.value, scoreColor(e.key.toDouble())),
                      ],
                    ),
                  ],
                  if (years.isNotEmpty) ...[
                    _Heading(t('Années de sortie', 'Release years')),
                    _Columns(
                      label: t('Animes par année de sortie', 'Anime by release year'),
                      entries: [for (final e in years) (e.key % 5 == 0 ? '${e.key}' : '', e.value, accent)],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AniList's format names, as Nami writes them.
String formatLabel(String format) => switch (format) {
  'TV' => 'TV',
  'TV_SHORT' => t('TV court', 'TV short'),
  'MOVIE' => t('Film', 'Movie'),
  'SPECIAL' => t('Spécial', 'Special'),
  'OVA' => 'OVA',
  'ONA' => 'ONA',
  'MUSIC' => 'Clip',
  _ => format,
};

/// Each list status in its own colour, the same ones as on AniList.
Color statusColor(String status) => switch (status) {
  'CURRENT' => const Color(0xFF4CCA51),
  'COMPLETED' => const Color(0xFF3DB4F2),
  'PAUSED' => const Color(0xFFEF881A),
  'DROPPED' => const Color(0xFFE13333),
  'PLANNING' => const Color(0xFF9FADBD),
  'REPEATING' => const Color(0xFFC063FF),
  _ => Nami.textSecondary,
};

/// AniList's list statuses, as Nami writes them.
String statusLabel(String status) => switch (status) {
  'CURRENT' => t('En cours', 'Watching'),
  'COMPLETED' => t('Terminé', 'Completed'),
  'PAUSED' => t('En pause', 'Paused'),
  'DROPPED' => t('Abandonné', 'Dropped'),
  'PLANNING' => t('À voir', 'Planning'),
  'REPEATING' => t('Revu', 'Rewatching'),
  _ => status,
};

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Semantics(header: true, child: Text(text, style: Nami.section)),
  );
}

/// Names with a bar for their count, the longest for the largest.
class _Bars extends StatelessWidget {
  const _Bars(this.items);
  final List<(StatCount, Color)> items;

  @override
  Widget build(BuildContext context) {
    final most = items.fold(1, (a, b) => a > b.$1.count ? a : b.$1.count);
    return Column(
      children: [
        for (final (item, color) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Semantics(
              label: '${item.name} : ${item.count}',
              excludeSemantics: true,
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(item.name, style: Nami.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 10,
                          width: 4 + (box.maxWidth - 4) * item.count / most,
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('${item.count}', style: Nami.meta, textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Columns with a label under each, like the anime page's score chart.
class _Columns extends StatelessWidget {
  const _Columns({required this.label, required this.entries});
  final String label;
  final List<(String, int, Color)> entries;

  @override
  Widget build(BuildContext context) {
    final most = entries.fold(1, (a, b) => a > b.$2 ? a : b.$2);
    return Semantics(
      label: label,
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (name, count, color) in entries)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: 2 + 90 * count / most,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 16,
                        // At full size, spilling over the narrow columns beside it (years).
                        child: OverflowBox(
                          maxWidth: 48,
                          child: Text(name, style: Nami.caption.copyWith(fontSize: 11), softWrap: false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
