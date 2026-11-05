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
    String number(double v) => v.toStringAsFixed(1).replaceAll('.', t(',', '.'));
    final facts = [
      (t('Animes', 'Anime'), '${s.count}'),
      (t('Épisodes vus', 'Episodes watched'), '${s.episodes}'),
      (t('Jours', 'Days'), number(days)),
      if (s.meanScore > 0) (t('Note moyenne', 'Mean score'), format.show(s.meanScore)),
      if (s.standardDeviation > 0) (t('Écart type', 'Standard deviation'), '± ${number(s.standardDeviation)}'),
    ];
    final years = s.releaseYears.entries.where((e) => e.key > 0).toList()..sort((a, b) => a.key.compareTo(b.key));
    final scores = s.scores.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
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
                              Text(value, style: Nami.section),
                              Text(label, style: Nami.caption),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (s.genres.isNotEmpty) ...[_Heading('Genres'), _Bars(s.genres)],
                  if (s.studios.isNotEmpty) ...[_Heading('Studios'), _Bars(s.studios)],
                  if (s.formats.isNotEmpty) ...[
                    _Heading('Formats'),
                    _Bars([for (final f in s.formats) StatCount(formatLabel(f.name), f.count)]),
                  ],
                  if (s.statuses.isNotEmpty) ...[
                    _Heading(t('Statuts', 'Statuses')),
                    _Bars([for (final f in s.statuses) StatCount(statusLabel(f.name), f.count)]),
                  ],
                  if (scores.isNotEmpty) ...[
                    _Heading(t('Notes', 'Scores')),
                    _Columns(
                      label: t('Répartition des notes', 'Score distribution'),
                      entries: [for (final e in scores) (format.show(e.key.toDouble()), e.value)],
                    ),
                  ],
                  if (years.isNotEmpty) ...[
                    _Heading(t('Années de sortie', 'Release years')),
                    _Columns(
                      label: t('Animes par année de sortie', 'Anime by release year'),
                      entries: [for (final e in years) (e.key % 5 == 0 ? '${e.key}' : '', e.value)],
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
  final List<StatCount> items;

  @override
  Widget build(BuildContext context) {
    final most = items.fold(1, (a, b) => a > b.count ? a : b.count);
    return Column(
      children: [
        for (final item in items)
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
                          decoration: BoxDecoration(color: Nami.textSecondary, borderRadius: BorderRadius.circular(3)),
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
  final List<(String, int)> entries;

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
            for (final (name, count) in entries)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(height: 2 + 90 * count / most, color: Nami.textSecondary),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 16,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
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
