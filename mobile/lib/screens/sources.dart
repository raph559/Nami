import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anilist.dart';
import '../extensions.dart';
import '../platform.dart';
import '../release.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shows the sources for one episode and pops the chosen [TorrentResult].
/// With [autoPick], the recommended source is played as soon as it is known.
/// On desktop it slides in from the right as a panel; on touch it is a bottom sheet.
Future<TorrentResult?> pickSource(BuildContext context, Media media, int episode, {bool autoPick = false}) {
  if (isDesktop) {
    return Navigator.of(context).push<TorrentResult>(
      SourcesPanel.route(SourcesSheet(media: media, episode: episode, autoPick: autoPick, panel: true)),
    );
  }
  return showModalBottomSheet<TorrentResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SourcesSheet(media: media, episode: episode, autoPick: autoPick),
  );
}

/// The desktop frame of the sources: a full-height panel on the right, over
/// a dark scrim. Escape, the close button or a click beside it closes it.
class SourcesPanel extends StatelessWidget {
  const SourcesPanel({super.key, required this.child});
  final Widget child;

  static const width = 440.0;
  static const panelKey = ValueKey('sources-panel');

  static Route<TorrentResult> route(Widget child) => PageRouteBuilder<TorrentResult>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Nami.ground.withValues(alpha: 0.55),
    barrierLabel: t('Fermer', 'Close'),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, _, _) => SourcesPanel(child: child),
    transitionsBuilder: (context, animation, _, page) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: page,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context)},
        child: Focus(
          autofocus: true,
          child: Material(
            key: panelKey,
            color: const Color(0xFF1B1B1E),
            shape: Border(left: BorderSide(color: Nami.line)),
            child: SizedBox(width: width, height: double.infinity, child: child),
          ),
        ),
      ),
    );
  }
}

class SourcesSheet extends StatefulWidget {
  const SourcesSheet({
    super.key,
    required this.media,
    required this.episode,
    this.autoPick = false,
    this.panel = false,
  });
  final Media media;
  final int episode;
  final bool autoPick;

  /// Shown in [SourcesPanel] (desktop) rather than a bottom sheet.
  final bool panel;

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
    if (widget.panel) {
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header()),
          ..._body(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
    }
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
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: widget.panel ? Nami.section.copyWith(fontSize: 16) : Nami.section),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Nami.meta.copyWith(fontSize: widget.panel ? 12 : null),
          ),
        ],
      ],
    );
    if (widget.panel) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            FocusOutline(
              child: IconButton(
                tooltip: t('Fermer', 'Close'),
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      );
    }
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
          heading,
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
        child: _SourceRow(release: best, reason: best.reason(pref)),
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

/// Seeders with a signal icon and a word.
class _Health extends StatelessWidget {
  const _Health(this.release);
  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    final icon = switch (release.health) {
      SeedHealth.good => Icons.signal_cellular_alt,
      SeedHealth.fair => Icons.signal_cellular_alt_2_bar,
      SeedHealth.low => Icons.signal_cellular_alt_1_bar,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Nami.textSecondary),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '${release.result.seeders} seeders, ${release.health.label}',
            style: Nami.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// One source; a tap plays it. The recommended one also says why it was chosen.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.release, this.reason});
  final ReleaseInfo release;

  /// Set on the recommended source.
  final String? reason;

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
                if (reason != null) ...[
                  Text(t('Recommandée', 'Recommended'), style: Nami.caption),
                  const SizedBox(height: 4),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(release.title, style: Nami.body.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (reason != null) const Icon(Icons.play_arrow_rounded, size: 22, color: Nami.text),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [...release.facts, if (r.size != null && r.size! > 0) formatBytes(r.size!)].join(' · '),
                  style: Nami.meta,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Health(release),
                    Text('·  ${r.source}', style: Nami.caption),
                  ],
                ),
                if (reason != null) ...[
                  const SizedBox(height: 4),
                  Text(reason!, style: Nami.caption.copyWith(fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
