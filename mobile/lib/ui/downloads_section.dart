import 'dart:io';

import 'package:flutter/material.dart';

import '../anilist.dart';
import '../downloads.dart';
import '../platform.dart';
import '../player_center.dart';
import '../screens/sources.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'motion.dart';

/// After this many seconds with no data, "time left" means nothing.
const _quietLimit = 15;

/// "12 min", "1 h 05", "< 1 min".
String formatRemaining(Duration d) {
  if (d.inMinutes < 1) return '< 1 min';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
}

/// What a download is doing, in words.
String downloadLabel(DownloadEntry e) {
  final percent = (e.fraction * 100).floor();
  return switch (e.state) {
    DownloadState.running => [
      t('Téléchargement · $percent %', 'Downloading · $percent %'),
      if (e.quiet >= _quietLimit)
        t('En attente de pairs', 'Waiting for peers')
      else if (e.remaining != null) ...[
        t('${formatRemaining(e.remaining!)} restantes', '${formatRemaining(e.remaining!)} left'),
        '${formatBytes(e.speed)}/s',
      ],
    ].join(' · '),
    DownloadState.queued =>
      Downloads.instance.heldForWifi ? t('En attente du Wi-Fi', 'Waiting for Wi-Fi') : t('En attente', 'Waiting'),
    DownloadState.paused => t('En pause · $percent %', 'Paused · $percent %'),
    DownloadState.failed => t('Téléchargement bloqué', 'Download stuck'),
    DownloadState.done => formatBytes(e.total),
  };
}

/// Shows why a download stopped, from anywhere.
final downloadMessages = GlobalKey<ScaffoldMessengerState>();

void announceFailure(DownloadEntry e) {
  downloadMessages.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${t('Épisode ${e.episode}', 'Episode ${e.episode}')} : ${e.error}'),
        showCloseIcon: true,
        action: SnackBarAction(label: t('Réessayer', 'Retry'), onPressed: () => Downloads.instance.retry(e)),
      ),
    );
}

/// Eases progress between two readings, a second apart, so it never jumps.
class SmoothProgress extends StatelessWidget {
  const SmoothProgress({super.key, required this.value, required this.builder});
  final double value;
  final Widget Function(BuildContext context, double value) builder;

  @override
  Widget build(BuildContext context) {
    final still = Motion.of(context).medium == Duration.zero;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: still ? Duration.zero : const Duration(seconds: 1),
      builder: (context, shown, _) => builder(context, shown),
    );
  }
}

/// Opens the downloads from anywhere, even from above the navigator.
void openDownloads() {
  PlayerCenter.instance.navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const DownloadsScreen()));
}

Future<bool> _ask(
  BuildContext context, {
  required String title,
  required String body,
  required String refuse,
  required String accept,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(refuse)),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(accept)),
      ],
    ),
  );
  return answer ?? false;
}

/// The answer that means "let me pick the release myself".
const _chooseSource = 'source';

String qualityLabel(String quality) => quality == bestQuality ? t('Meilleure', 'Best') : '${quality}p';

/// Asks which quality; null when refused. With [found], a quality no source
/// has is greyed out, and with no source at all the question says so.
Future<String?> _askQuality(
  BuildContext context, {
  required String title,
  required String body,
  required String accept,
  required String refuse,
  bool source = false,
  Future<SourceQualities>? found,
}) {
  var quality = AppSettings.instance.downloadResolution;
  return showDialog<String>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialog, setState) => FutureBuilder<SourceQualities>(
        future: found,
        builder: (context, sources) {
          final known = sources.data?.qualities ?? const <String>[];
          final problem = sources.data?.problem;
          final noSources = sources.data?.noSources ?? false;
          bool available(String q) => known.isEmpty || q == bestQuality || known.contains(q);
          final picked = available(quality) ? quality : bestQuality;
          final missing = downloadQualities.where((q) => !available(q)).map(qualityLabel).join(', ');
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(problem ?? body),
                if (problem == null) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final q in downloadQualities)
                        ChoiceChip(
                          label: Text(qualityLabel(q)),
                          selected: q == picked,
                          onSelected: available(q) ? (_) => setState(() => quality = q) : null,
                        ),
                    ],
                  ),
                ],
                if (found != null && sources.connectionState != ConnectionState.done) ...[
                  const SizedBox(height: 8),
                  Text(t('Recherche des qualités disponibles…', 'Looking for available qualities…'), style: Nami.caption),
                ],
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(t('Aucune source en $missing.', 'No source in $missing.'), style: Nami.caption),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: Text(refuse)),
              if (source && problem == null)
                TextButton(
                  onPressed: () => Navigator.pop(dialog, _chooseSource),
                  child: Text(t('Choisir la source', 'Choose source')),
                ),
              if (noSources)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialog);
                    Downloads.instance.onOpenSources?.call();
                  },
                  child: Text(t('Ajouter des sources', 'Add sources')),
                )
              else
                FilledButton(
                  onPressed: problem != null ? null : () => Navigator.pop(dialog, picked),
                  child: Text(accept),
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// Asks first: a download can take a lot of space and data.
Future<void> confirmDownload(BuildContext context, Media media, int episode) async {
  final found = Downloads.instance.qualities(media, episode);
  // Closing the sources comes back to this question.
  while (true) {
    if (!context.mounted) return;
    final answer = await _askQuality(
      context,
      title: t("Télécharger l'épisode $episode ?", 'Download episode $episode?'),
      body: t(
        'Nami prend la meilleure source dans cette qualité et garde cet épisode sur cet appareil.',
        'Nami takes the best source in this quality and keeps this episode on this device.',
      ),
      refuse: t('Annuler', 'Cancel'),
      accept: t('Télécharger', 'Download'),
      source: true,
      found: found,
    );
    if (answer == null) return;
    if (answer != _chooseSource) {
      Downloads.instance.start(media, episode, resolution: answer);
      return;
    }
    if (!context.mounted) return;
    final picked = await pickSource(context, media, episode);
    if (picked != null) {
      Downloads.instance.start(media, episode, link: picked.link);
      return;
    }
  }
}

/// Every aired episode that is not on the device yet.
Future<void> confirmSeason(BuildContext context, Media media) async {
  final count = Downloads.instance.missing(media).length;
  final answer = await _askQuality(
    context,
    title: t('Télécharger $count épisodes ?', 'Download $count episodes?'),
    body: t(
      "Ils s'ajoutent à la file et se téléchargent l'un après l'autre.",
      'They join the queue and download one after the other.',
    ),
    refuse: t('Annuler', 'Cancel'),
    accept: t('Télécharger', 'Download'),
  );
  if (answer != null) Downloads.instance.startSeason(media, resolution: answer);
}

/// A finished file cannot be converted: another release replaces it.
Future<bool> confirmChangeQuality(BuildContext context, DownloadEntry e) async {
  final answer = await _askQuality(
    context,
    title: t('Changer la qualité ?', 'Change the quality?'),
    body: t(
      'Ce qui a été téléchargé sera supprimé, puis Nami téléchargera cet épisode dans la nouvelle qualité.',
      'What was downloaded will be deleted, then Nami will download this episode in the new quality.',
    ),
    refuse: t('Annuler', 'Cancel'),
    accept: t('Changer', 'Change'),
  );
  if (answer == null) return false;
  await Downloads.instance.changeQuality(e, answer);
  return true;
}

/// Asks first: what was fetched is lost. Says true when the entry is gone.
Future<bool> confirmRemove(BuildContext context, DownloadEntry e) async {
  final done = e.state == DownloadState.done;
  final yes = await _ask(
    context,
    title: done
        ? t('Supprimer cet épisode ?', 'Delete this episode?')
        : t('Annuler le téléchargement ?', 'Cancel the download?'),
    body: done
        ? t(
            'Il faudra le télécharger à nouveau pour le regarder hors ligne.',
            'You will have to download it again to watch it offline.',
          )
        : t('Ce qui a déjà été récupéré sera perdu.', 'What was already fetched will be lost.'),
    refuse: done ? t('Garder', 'Keep') : t('Continuer', 'Keep going'),
    accept: done ? t('Supprimer', 'Delete') : t('Annuler le téléchargement', 'Cancel download'),
  );
  if (yes) await Downloads.instance.remove(e);
  return yes;
}

/// Where a download stands and what can be done with it.
Future<void> showDownloadDetails(BuildContext context, DownloadEntry entry) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 520),
  builder: (_) => _DownloadDetails(entry),
);

class _DownloadDetails extends StatelessWidget {
  const _DownloadDetails(this.entry);
  final DownloadEntry entry;

  String _figures(DownloadEntry e) => [
    if (e.total > 0) '${formatBytes(e.done)} / ${formatBytes(e.total)}',
    if (e.state == DownloadState.running) ...[
      '${formatBytes(e.speed)}/s',
      t('${e.peers} pairs', '${e.peers} peers'),
    ],
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Downloads.instance,
      builder: (context, _) {
        final store = Downloads.instance;
        final e = entry;
        final done = e.state == DownloadState.done;
        final failed = e.state == DownloadState.failed;
        void close() => Navigator.of(context).pop();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                e.media.title.display,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Nami.section.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 2),
              Text(
                '${t('Épisode ${e.episode}', 'Episode ${e.episode}')} · ${downloadLabel(e)}',
                style: Nami.meta,
              ),
              const SizedBox(height: 14),
              SmoothProgress(
                value: done ? 1 : e.fraction,
                builder: (context, value) => ProgressLine(value: value, color: Nami.text),
              ),
              const SizedBox(height: 8),
              Text(_figures(e), style: Nami.caption),
              if (e.error != null) ...[const SizedBox(height: 8), Text(e.error!, style: Nami.meta)],
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (done)
                    FilledButton.icon(
                      onPressed: () {
                        close();
                        PlayerCenter.instance.openSources(e.media, e.episode);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text(t('Regarder', 'Watch')),
                    )
                  else if (failed)
                    FilledButton.icon(
                      onPressed: () => store.retry(e),
                      icon: const Icon(Icons.refresh),
                      label: Text(t('Réessayer', 'Retry')),
                    )
                  else if (e.state == DownloadState.paused)
                    FilledButton.icon(
                      onPressed: () => store.resume(e),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(t('Reprendre', 'Resume')),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => store.pause(e),
                      icon: const Icon(Icons.pause),
                      label: Text(t('Mettre en pause', 'Pause')),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      if (await confirmRemove(context, e) && context.mounted) close();
                    },
                    child: Text(
                      done || failed
                          ? t('Supprimer le téléchargement', 'Delete download')
                          : t('Annuler le téléchargement', 'Cancel download'),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      if (await confirmChangeQuality(context, e) && context.mounted) close();
                    },
                    child: Text(t('Changer la qualité', 'Change quality')),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    close();
                    store.onOpen?.call();
                  },
                  child: Text(t('Tous les téléchargements', 'All downloads')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pauses what is going, resumes what is paused.
class DownloadPauseButton extends StatelessWidget {
  const DownloadPauseButton(this.entry, {super.key});
  final DownloadEntry entry;

  @override
  Widget build(BuildContext context) {
    final paused = entry.state == DownloadState.paused;
    return IconButton(
      tooltip: paused ? t('Reprendre', 'Resume') : t('Mettre en pause', 'Pause'),
      onPressed: () => paused ? Downloads.instance.resume(entry) : Downloads.instance.pause(entry),
      icon: AnimatedSwitcher(
        duration: Motion.of(context).fast,
        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
        child: Icon(paused ? Icons.play_arrow : Icons.pause, key: ValueKey(paused)),
      ),
    );
  }
}

/// At the bottom of every screen while something is downloading, above the
/// mini-player and under the full-screen one. A tap opens its details.
class DownloadBar extends StatelessWidget {
  const DownloadBar({super.key});

  /// Height of the mini-player and its gap, when it sits in the same corner.
  static const _miniHeight = 88.0;

  @override
  Widget build(BuildContext context) {
    final center = PlayerCenter.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([Downloads.instance, center]),
      builder: (context, _) {
        final store = Downloads.instance;
        final motion = Motion.of(context);
        final e = center.session != null && !center.minimized ? null : store.current;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final inset = MediaQuery.paddingOf(context).bottom;
        return AnimatedPositioned(
          duration: motion.medium,
          curve: Motion.curve,
          left: wide ? null : 8,
          right: wide ? 16 : 8,
          bottom: (wide ? 16 : inset + 76) + (center.minimized ? _miniHeight : 0),
          width: wide ? 380 : null,
          child: AnimatedSwitcher(
            duration: motion.medium,
            switchInCurve: Motion.curve,
            switchOutCurve: Motion.curve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: e == null ? const SizedBox.shrink(key: ValueKey('none')) : _bar(context, store, e),
          ),
        );
      },
    );
  }

  Widget _bar(BuildContext context, Downloads store, DownloadEntry e) {
    return Material(
      key: const ValueKey('bar'),
      color: const Color(0xFF1B1B1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Nami.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // The bar sits above the navigator, so the sheet opens from the navigator.
          final page = PlayerCenter.instance.navigatorKey.currentContext;
          if (page != null) showDownloadDetails(page, e);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              child: Row(
                children: [
                  Icon(Icons.downloading, size: 22, color: Nami.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${e.media.title.display} · ${t('Épisode ${e.episode}', 'Episode ${e.episode}')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Nami.body.copyWith(fontSize: 13),
                        ),
                        Text(
                          [
                            downloadLabel(e),
                            if (store.waiting > 0) t('${store.waiting} en attente', '${store.waiting} waiting'),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Nami.caption,
                        ),
                      ],
                    ),
                  ),
                  DownloadPauseButton(e),
                ],
              ),
            ),
            SmoothProgress(
              value: e.fraction,
              builder: (context, value) => ProgressLine(value: value, color: Nami.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leads to the Downloads screen, with what is in it.
class DownloadsLink extends StatelessWidget {
  const DownloadsLink({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Downloads.instance,
      builder: (context, _) {
        final store = Downloads.instance;
        final active = store.entries.where((e) => e.state != DownloadState.done).length;
        return Padding(
          padding: padding,
          child: FocusOutline(
            radius: Nami.radiusImage,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen())),
              borderRadius: BorderRadius.circular(Nami.radiusImage),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline_outlined, color: Nami.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Téléchargements', 'Downloads'), style: Nami.body),
                          Text(
                            [
                              if (active > 0) t('$active en cours', '$active active'),
                              if (store.usedBytes > 0) formatBytes(store.usedBytes),
                              if (store.entries.isEmpty) t('Rien pour le moment', 'Nothing yet'),
                            ].join(' · '),
                            style: Nami.caption,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Nami.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Everything downloaded, in one list. It needs no network, so the home shows
/// it when nothing else can load.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Downloads.instance,
      builder: (context, _) {
        final store = Downloads.instance;
        if (store.entries.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [t('Téléchargements', 'Downloads'), if (store.usedBytes > 0) formatBytes(store.usedBytes)].join(' · '),
                style: Nami.section,
              ),
              const SizedBox(height: 8),
              for (final e in store.entries) _DownloadRow(e, key: ValueKey(e)),
            ],
          ),
        );
      },
    );
  }
}

/// Asks first, whatever is in [entries]: what they hold is lost.
Future<bool> confirmRemoveAll(BuildContext context, List<DownloadEntry> entries) async {
  final count = entries.length;
  final yes = await _ask(
    context,
    title: t('Supprimer $count téléchargements ?', 'Delete $count downloads?'),
    body: t(
      'Les épisodes et ce qui a déjà été récupéré seront perdus.',
      'The episodes and what was already fetched will be lost.',
    ),
    refuse: t('Garder', 'Keep'),
    accept: t('Supprimer', 'Delete'),
  );
  if (yes) await Downloads.instance.removeAll(entries);
  return yes;
}

/// The download manager: what is going on, then what is kept, by anime.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool selecting = false;
  final selected = <DownloadEntry>{};

  void _select(DownloadEntry e) => setState(() {
    selecting = true;
    if (!selected.remove(e)) selected.add(e);
  });

  void _stopSelecting() => setState(() {
    selecting = false;
    selected.clear();
  });

  Widget _row(DownloadEntry e, {int? dragIndex}) => _DownloadRow(
    e,
    key: ValueKey(e),
    dragIndex: selecting ? null : dragIndex,
    selecting: selecting,
    selected: selected.contains(e),
    onSelect: () => _select(e),
  );

  PreferredSizeWidget _bar(Downloads store) {
    if (!selecting) {
      return AppBar(
        title: Text(t('Téléchargements', 'Downloads')),
        actions: [
          if (store.entries.isNotEmpty) ...[
            IconButton(
              tooltip: t('Sélectionner', 'Select'),
              onPressed: () => setState(() => selecting = true),
              icon: const Icon(Icons.checklist),
            ),
            PopupMenuButton<VoidCallback>(
              tooltip: t("Plus d'actions", 'More actions'),
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                if (store.canPauseAll) PopupMenuItem(value: store.pauseAll, child: Text(t('Tout mettre en pause', 'Pause all'))),
                if (store.canResumeAll) PopupMenuItem(value: store.resumeAll, child: Text(t('Tout reprendre', 'Resume all'))),
                PopupMenuItem(
                  value: () => confirmRemoveAll(context, [...store.entries]),
                  child: Text(t('Tout supprimer', 'Delete all')),
                ),
              ],
            ),
          ],
        ],
      );
    }
    final everything = selected.length == store.entries.length;
    return AppBar(
      leading: IconButton(
        tooltip: t('Fermer la sélection', 'Close selection'),
        onPressed: _stopSelecting,
        icon: const Icon(Icons.close),
      ),
      title: Text(t('${selected.length} sélectionnés', '${selected.length} selected')),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            selected.clear();
            if (!everything) selected.addAll(store.entries);
          }),
          child: Text(everything ? t('Tout désélectionner', 'Select none') : t('Tout sélectionner', 'Select all')),
        ),
      ],
    );
  }

  Widget _actions(Downloads store) {
    final going = selected.where((e) => e.state == DownloadState.running || e.state == DownloadState.queued);
    final paused = selected.where((e) => e.state == DownloadState.paused);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: going.isEmpty ? null : () => setState(() => [...going].forEach(store.pause)),
              icon: const Icon(Icons.pause),
              label: Text(t('Mettre en pause', 'Pause')),
            ),
            OutlinedButton.icon(
              onPressed: paused.isEmpty ? null : () => setState(() => [...paused].forEach(store.resume)),
              icon: const Icon(Icons.play_arrow),
              label: Text(t('Reprendre', 'Resume')),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty
                  ? null
                  : () async {
                      if (await confirmRemoveAll(context, [...selected])) _stopSelecting();
                    },
              icon: const Icon(Icons.delete_outline),
              label: Text(t('Supprimer', 'Delete')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Downloads.instance,
      builder: (context, _) {
        final store = Downloads.instance;
        selected.removeWhere((e) => !store.entries.contains(e));
        final active = store.entries
            .where((e) => e.state != DownloadState.done && e.state != DownloadState.queued)
            .toList();
        final queue = store.queue;
        final done = store.entries.where((e) => e.state == DownloadState.done).toList();
        final animes = {for (final e in done) e.media.id: e.media};
        final side = isDesktop ? 24.0 : 16.0;
        return Scaffold(
          appBar: _bar(store),
          bottomNavigationBar: selecting ? _actions(store) : null,
          body: store.entries.isEmpty
              ? Center(
                  child: StateMessage(
                    title: t('Aucun téléchargement', 'No downloads'),
                    body: t(
                      "Sur la page d'un anime, la flèche à côté d'un épisode le garde sur cet appareil.",
                      "On an anime's page, the arrow beside an episode keeps it on this device.",
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(side, 8, side, selecting ? 16 : 110),
                  children: [
                    Text(
                      [
                        t('${store.entries.length} épisodes', '${store.entries.length} episodes'),
                        t('${formatBytes(store.usedBytes)} utilisés', '${formatBytes(store.usedBytes)} used'),
                      ].join(' · '),
                      style: Nami.meta,
                    ),
                    if (active.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(t('En cours', 'In progress'), style: Nami.section),
                      const SizedBox(height: 4),
                      _Growing(children: [for (final e in active) _row(e)]),
                    ],
                    if (queue.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(t("File d'attente", 'Queue'), style: Nami.section),
                      const SizedBox(height: 4),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: queue.length,
                        onReorderItem: store.reorder,
                        itemBuilder: (context, i) => _row(queue[i], dragIndex: i),
                      ),
                    ],
                    for (final media in animes.values) ...[
                      const SizedBox(height: 18),
                      Text(media.title.display, style: Nami.section),
                      const SizedBox(height: 4),
                      _Growing(
                        children: [
                          for (final e in done)
                            if (e.media.id == media.id) _row(e),
                        ],
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// A list of rows that eases to its new height when one comes or goes.
class _Growing extends StatelessWidget {
  const _Growing({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return AnimatedSize(
      duration: motion.medium,
      curve: Motion.curve,
      alignment: Alignment.topCenter,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow(
    this.entry, {
    super.key,
    this.dragIndex,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });
  final DownloadEntry entry;

  /// The screen is picking several downloads: a tap selects this one.
  final bool selecting;
  final bool selected;

  /// A long press starts selecting; none outside the Downloads screen.
  final VoidCallback? onSelect;

  /// Its place in the queue, when it can be dragged.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final store = Downloads.instance;
    final cover = File(store.coverPath(e.media.id));
    final done = e.state == DownloadState.done;
    final row = FocusOutline(
      radius: Nami.radiusImage,
      child: InkWell(
        onTap: selecting
            ? onSelect
            : () => done ? PlayerCenter.instance.openSources(e.media, e.episode) : showDownloadDetails(context, e),
        onLongPress: onSelect ?? () => showDownloadDetails(context, e),
        borderRadius: BorderRadius.circular(Nami.radiusImage),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              if (selecting) ...[
                Checkbox(value: selected, onChanged: (_) => onSelect?.call()),
                const SizedBox(width: 4),
              ],
              SizedBox(
                width: 44,
                height: 62,
                child: cover.existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(Nami.radiusImage),
                        child: Image.file(cover, fit: BoxFit.cover),
                      )
                    : CoverImage(e.media.coverSmall),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.media.title.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Nami.body.copyWith(fontSize: isDesktop ? 13 : 15),
                    ),
                    Text(
                      '${t('Épisode ${e.episode}', 'Episode ${e.episode}')} · ${downloadLabel(e)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Nami.caption,
                    ),
                    if (e.error != null) Text(e.error!, maxLines: 3, overflow: TextOverflow.ellipsis, style: Nami.caption),
                    if (e.state == DownloadState.running)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SmoothProgress(
                          value: e.fraction,
                          builder: (context, value) => ProgressLine(value: value, color: Nami.text),
                        ),
                      ),
                  ],
                ),
              ),
              if (e.state != DownloadState.failed && !done && !selecting) DownloadPauseButton(e),
              if (e.state == DownloadState.failed && !selecting)
                IconButton(
                  tooltip: t('Réessayer', 'Retry'),
                  onPressed: () => store.retry(e),
                  icon: const Icon(Icons.refresh),
                ),
              if (!selecting)
                IconButton(
                  tooltip: done || e.state == DownloadState.failed
                      ? t('Supprimer le téléchargement', 'Delete download')
                      : t('Annuler le téléchargement', 'Cancel download'),
                  onPressed: () => confirmRemove(context, e),
                  icon: Icon(done || e.state == DownloadState.failed ? Icons.delete_outline : Icons.close),
                ),
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: Semantics(
                    label: t('Déplacer dans la file', 'Move in the queue'),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.drag_handle, color: Nami.textSecondary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // A row fades in once, when it arrives.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context).medium,
      curve: Motion.curve,
      child: row,
      builder: (context, shown, child) => Opacity(opacity: shown, child: child),
    );
  }
}
