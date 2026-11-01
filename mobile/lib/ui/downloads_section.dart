import 'dart:io';

import 'package:flutter/material.dart';

import '../anilist.dart';
import '../downloads.dart';
import '../platform.dart';
import '../player_center.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// What a download is doing, in words.
String downloadLabel(DownloadEntry e) => switch (e.state) {
  DownloadState.running => t(
    'Téléchargement · ${(e.fraction * 100).floor()} %',
    'Downloading · ${(e.fraction * 100).floor()} %',
  ),
  DownloadState.queued => t('En attente', 'Waiting'),
  DownloadState.paused => t('En pause · ${(e.fraction * 100).floor()} %', 'Paused · ${(e.fraction * 100).floor()} %'),
  DownloadState.failed => t('Téléchargement bloqué', 'Download stuck'),
  DownloadState.done => formatBytes(e.total),
};

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

/// Asks first: a download can take a lot of space and data.
Future<void> confirmDownload(BuildContext context, Media media, int episode) async {
  final yes = await _ask(
    context,
    title: t("Télécharger l'épisode $episode ?", 'Download episode $episode?'),
    body: t(
      'Nami prend la meilleure source dans ta résolution et garde cet épisode sur cet appareil.',
      'Nami takes the best source for your resolution and keeps this episode on this device.',
    ),
    refuse: t('Annuler', 'Cancel'),
    accept: t('Télécharger', 'Download'),
  );
  if (yes) Downloads.instance.start(media, episode);
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
              ProgressLine(value: done ? 1 : e.fraction, color: Nami.text),
              const SizedBox(height: 8),
              Text(_figures(e), style: Nami.caption),
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
      icon: Icon(paused ? Icons.play_arrow : Icons.pause),
    );
  }
}

/// At the bottom of every screen while something is downloading, above the
/// mini-player and under the full-screen one. A tap opens the downloads.
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
        final e = store.current;
        if (e == null || (center.session != null && !center.minimized)) return const SizedBox.shrink();
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final inset = MediaQuery.paddingOf(context).bottom;
        return Positioned(
          left: wide ? null : 8,
          right: wide ? 16 : 8,
          bottom: (wide ? 16 : inset + 76) + (center.minimized ? _miniHeight : 0),
          width: wide ? 380 : null,
          child: Material(
            color: const Color(0xFF1B1B1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Nami.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                // The bar sits above the navigator, so the sheet opens from the navigator.
                final page = center.navigatorKey.currentContext;
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
                  ProgressLine(value: e.fraction, color: Nami.text),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Everything kept on the device. It needs no network, so it shows above
/// whatever "Ma liste" can or cannot load.
class DownloadsSection extends StatelessWidget {
  const DownloadsSection({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Downloads.instance,
      builder: (context, _) {
        final store = Downloads.instance;
        final entries = store.entries;
        if (entries.isEmpty) return const SizedBox.shrink();
        final total = entries.where((e) => e.state == DownloadState.done).fold<int>(0, (sum, e) => sum + e.total);
        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                [t('Téléchargements', 'Downloads'), if (total > 0) formatBytes(total)].join(' · '),
                style: Nami.section,
              ),
              const SizedBox(height: 8),
              for (final e in entries) _DownloadRow(e),
            ],
          ),
        );
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow(this.entry);
  final DownloadEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final store = Downloads.instance;
    final cover = File(store.coverPath(e.media.id));
    final done = e.state == DownloadState.done;
    return FocusOutline(
      radius: Nami.radiusImage,
      child: InkWell(
        onTap: () => done ? PlayerCenter.instance.openSources(e.media, e.episode) : showDownloadDetails(context, e),
        borderRadius: BorderRadius.circular(Nami.radiusImage),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
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
                      style: Nami.caption,
                    ),
                    if (e.state == DownloadState.running)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ProgressLine(value: e.fraction, color: Nami.text),
                      ),
                  ],
                ),
              ),
              if (e.state != DownloadState.failed && !done) DownloadPauseButton(e),
              if (e.state == DownloadState.failed)
                IconButton(
                  tooltip: t('Réessayer', 'Retry'),
                  onPressed: () => store.retry(e),
                  icon: const Icon(Icons.refresh),
                ),
              IconButton(
                tooltip: done || e.state == DownloadState.failed
                    ? t('Supprimer le téléchargement', 'Delete download')
                    : t('Annuler le téléchargement', 'Cancel download'),
                onPressed: () => confirmRemove(context, e),
                icon: Icon(done || e.state == DownloadState.failed ? Icons.delete_outline : Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
