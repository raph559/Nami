import 'package:flutter/material.dart';

import '../anilist.dart';
import '../extensions.dart';
import '../release.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shows the sources for one episode and pops the chosen [TorrentResult].
/// With [autoPick], the recommended source is played as soon as it is known.
Future<TorrentResult?> pickSource(BuildContext context, Media media, int episode, {bool autoPick = false}) {
  return showModalBottomSheet<TorrentResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SourcesSheet(media: media, episode: episode, autoPick: autoPick),
  );
}

class SourcesSheet extends StatefulWidget {
  const SourcesSheet({super.key, required this.media, required this.episode, this.autoPick = false});
  final Media media;
  final int episode;
  final bool autoPick;

  @override
  State<SourcesSheet> createState() => _SourcesSheetState();
}

class _SourcesSheetState extends State<SourcesSheet> {
  SourceSearch? search;
  List<ReleaseInfo> releases = [];
  bool showFailures = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _run() {
    if (ExtensionStore.instance.enabled.isEmpty) return;
    setState(() {
      search = null;
      releases = [];
    });
    SourceSearch.run(widget.media, widget.episode).then((s) {
      if (mounted) {
        setState(() {
          search = s;
          releases = rankReleases(s.results);
        });
        if (widget.autoPick && releases.isNotEmpty) Navigator.pop(context, releases.first.result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(child: _header()),
          ..._body(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _header() {
    final media = widget.media;
    final title = media.isMovie ? media.title.display : t('Épisode ${widget.episode}', 'Episode ${widget.episode}');
    final sub = [
      if (!media.isMovie) media.title.display,
      if (releases.isNotEmpty) t('${releases.length} sources', '${releases.length} sources'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Nami.textMuted, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(header: true, child: Text(title, style: Nami.section)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: Nami.meta),
          ],
        ],
      ),
    );
  }

  List<Widget> _body() {
    final s = search;
    if (ExtensionStore.instance.enabled.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: StateMessage(
            title: t('Aucune source installée', 'No sources installed'),
            body: t(
              "Ajoute un dépôt d'extensions dans Réglages, puis reviens ici.",
              'Add an extension repository in Settings, then come back here.',
            ),
          ),
        ),
      ];
    }
    if (s == null) {
      return [
        SliverToBoxAdapter(
          child: StateMessage(
            loading: true,
            title: widget.autoPick
                ? t('Recherche de la meilleure source…', 'Finding the best source…')
                : t('Recherche des sources…', 'Looking for sources…'),
          ),
        ),
      ];
    }
    if (releases.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: StateMessage(
            title: t('Aucune source trouvée', 'No source found'),
            body: s.failures.isEmpty
                ? t(
                    "Tes extensions n'ont rien pour cet épisode. Essaie une autre qualité dans Réglages.",
                    'Your extensions have nothing for this episode. Try another quality in Settings.',
                  )
                : [for (final f in s.failures) '${f.name} : ${f.message}'].join('\n'),
            action: t('Relancer la recherche', 'Search again'),
            onAction: _run,
          ),
        ),
      ];
    }

    final pref = AppSettings.instance.resolution;
    final best = releases.first;
    final rest = releases.skip(1).toList();
    final single = [
      for (final r in rest)
        if (!r.batch) r,
    ];
    final batches = [
      for (final r in rest)
        if (r.batch) r,
    ];

    return [
      SliverToBoxAdapter(
        child: _Recommended(release: best, reason: best.reason(pref), accent: Nami.accentOf(widget.media.color)),
      ),
      if (single.isNotEmpty) ...[
        SliverToBoxAdapter(child: _SectionLabel(t('Cet épisode', 'This episode'))),
        SliverList.builder(
          itemCount: single.length,
          itemBuilder: (_, i) => _SourceRow(release: single[i]),
        ),
      ],
      if (batches.isNotEmpty) ...[
        SliverToBoxAdapter(child: _SectionLabel(t('Saisons complètes', 'Full seasons'))),
        SliverList.builder(
          itemCount: batches.length,
          itemBuilder: (_, i) => _SourceRow(release: batches[i]),
        ),
      ],
      if (s.failures.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FocusOutline(
                  child: TextButton(
                    onPressed: () => setState(() => showFailures = !showFailures),
                    child: Text(
                      t(
                        "${s.failures.length} extension(s) n'ont pas répondu",
                        "${s.failures.length} extension(s) didn't answer",
                      ),
                    ),
                  ),
                ),
                if (showFailures)
                  Text([for (final f in s.failures) '${f.name} : ${f.message}'].join('\n'), style: Nami.caption),
              ],
            ),
          ),
        ),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
    child: Semantics(header: true, child: Text(text, style: Nami.section.copyWith(fontSize: 16))),
  );
}

/// The pick at the top: what it is, why it was chosen, and one button.
/// Tinted by the anime's color, like its page.
class _Recommended extends StatelessWidget {
  const _Recommended({required this.release, required this.reason, required this.accent});
  final ReleaseInfo release;
  final String reason;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final size = release.result.size;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1E),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(Nami.radiusButton + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('Recommandée', 'Recommended'), style: Nami.caption.copyWith(color: accent)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(release.title, style: Nami.body.copyWith(fontWeight: FontWeight.w700, fontSize: 17)),
              ),
              if (size != null && size > 0) Text(formatBytes(size), style: Nami.meta),
            ],
          ),
          const SizedBox(height: 6),
          _Facts(release.facts),
          const SizedBox(height: 8),
          _Health(release),
          const SizedBox(height: 4),
          Text(reason, style: Nami.caption.copyWith(fontSize: 13)),
          const SizedBox(height: 14),
          FocusOutline(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: accent,
                foregroundColor: Nami.ground,
              ),
              onPressed: () => Navigator.pop(context, release.result),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(t('Lire cette source', 'Play this source')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Facts as small outlined tags; they are real data from the release name.
class _Facts extends StatelessWidget {
  const _Facts(this.facts);
  final List<String> facts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final f in facts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: Nami.border),
              borderRadius: BorderRadius.circular(Nami.radiusImage),
            ),
            child: Text(f, style: Nami.caption.copyWith(color: Nami.text)),
          ),
      ],
    );
  }
}

/// Seeders with a signal icon and a word, in a color that matches the level.
/// The word and the bar count carry the meaning, the color only repeats it.
class _Health extends StatelessWidget {
  const _Health(this.release);
  final ReleaseInfo release;

  static const _good = Color(0xFF6FD39B);
  static const _fair = Color(0xFFF2C14E);
  static const _low = Color(0xFFFF8A80);

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (release.health) {
      SeedHealth.good => (_good, Icons.signal_cellular_alt),
      SeedHealth.fair => (_fair, Icons.signal_cellular_alt_2_bar),
      SeedHealth.low => (_low, Icons.signal_cellular_alt_1_bar),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '${release.result.seeders} seeders, ${release.health.label}',
            style: Nami.caption.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.release});
  final ReleaseInfo release;

  void _details(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(release.title),
        content: SelectableText(release.result.title, style: Nami.meta),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Fermer', 'Close'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, release.result);
            },
            child: Text(t('Lire', 'Play')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = release.result;
    return FocusOutline(
      radius: 0,
      gap: -2,
      child: Semantics(
        button: true,
        label: '${release.title}, ${release.facts.join(', ')}, ${r.seeders} seeders, ${release.health.label}',
        hint: t('Appui long pour le nom complet', 'Long press for the full name'),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => Navigator.pop(context, r),
          onLongPress: () => _details(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(release.title, style: Nami.body.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (r.size != null && r.size! > 0) Text(formatBytes(r.size!), style: Nami.meta),
                  ],
                ),
                const SizedBox(height: 6),
                _Facts(release.facts),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Health(release),
                    Text('·  ${r.source}', style: Nami.caption),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
