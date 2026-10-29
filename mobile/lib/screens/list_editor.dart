import 'package:flutter/material.dart';

import '../anilist.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/tags.dart';
import '../widgets.dart';

/// Edits the viewer's AniList entry for [media]: status, progress and score.
/// Returns the anime with its new entry, or null when nothing changed.
Future<Media?> showListEditor(BuildContext context, Media media) => showModalBottomSheet<Media>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ListEditor(media: media),
);

class ListEditor extends StatefulWidget {
  const ListEditor({super.key, required this.media});
  final Media media;

  @override
  State<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<ListEditor> {
  Media get media => widget.media;
  late String status = media.listEntry?.status ?? 'PLANNING';
  late int progress = media.progress;

  /// Out of 10, by halves; 0 means not rated.
  late double score = ((media.listEntry?.score ?? 0) / 5).round() / 2;
  bool saving = false;
  String? error;

  /// Highest episode that can be set: the total, or what has aired so far.
  int? get maxProgress => media.episodes ?? (media.nextEpisode != null ? media.availableEpisodes : null);

  void _setStatus(String s) => setState(() {
    status = s;
    // Finishing an anime ticks off every episode.
    if (s == 'COMPLETED' && media.episodes != null) progress = media.episodes!;
  });

  void _setProgress(int p) => setState(() {
    progress = p;
    // The last episode completes the anime, as the player does.
    if (media.episodes != null && p >= media.episodes! && status == 'CURRENT') status = 'COMPLETED';
    if (p > 0 && status == 'PLANNING') status = 'CURRENT';
  });

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final entry = await AniList.instance.saveEntry(media, status: status, progress: progress, score: score * 10);
      if (mounted) Navigator.pop(context, media.withEntry(entry));
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = t("L'enregistrement a échoué. Réessaie.", 'Saving failed. Try again.');
        });
      }
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('Retirer de ta liste ?', 'Remove from your list?')),
        content: Text(
          t(
            'Ta progression et ta note pour ${media.title.display} seront effacées sur AniList.',
            'Your progress and score for ${media.title.display} will be erased on AniList.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(t('Annuler', 'Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(dialog).colorScheme.error),
            child: Text(t('Retirer', 'Remove')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await AniList.instance.deleteEntry(media.listEntry!.id!);
      if (mounted) Navigator.pop(context, media.withEntry(null));
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = t('La suppression a échoué. Réessaie.', 'Removing failed. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inList = media.listEntry?.id != null;
    final max = maxProgress;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: ContentWidth(
        maxWidth: 560,
        shrinkWrap: true,
        // Only as tall as its content; scrolls when the screen is too short.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        SizedBox(width: 48, height: 70, child: CoverImage(media.coverSmall)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                media.title.display,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Nami.section.copyWith(fontSize: 18),
                              ),
                              Text(
                                inList
                                    ? t('Dans ta liste', 'In your list')
                                    : t('Pas encore dans ta liste', 'Not in your list yet'),
                                style: Nami.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(t('Statut', 'Status'), style: Nami.meta),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in listStatuses)
                          FlatTag(
                            listStatusLabel(s),
                            selected: status == s,
                            onTap: saving ? null : () => _setStatus(s),
                          ),
                      ],
                    ),
                    if (!media.isMovie) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Text(t('Épisodes vus', 'Episodes watched'), style: Nami.meta)),
                          IconButton(
                            tooltip: t('Un de moins', 'One less'),
                            onPressed: saving || progress == 0 ? null : () => _setProgress(progress - 1),
                            icon: const Icon(Icons.remove),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 64),
                            child: Text(
                              max == null ? '$progress' : '$progress / $max',
                              textAlign: TextAlign.center,
                              style: Nami.body.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: t('Un de plus', 'One more'),
                            onPressed: saving || (max != null && progress >= max)
                                ? null
                                : () => _setProgress(progress + 1),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text(t('Ta note', 'Your score'), style: Nami.meta)),
                        Text(
                          score == 0 ? t('Pas de note', 'Not rated') : '${_formatScore(score)} / 10',
                          style: Nami.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Slider(
                      value: score,
                      max: 10,
                      divisions: 20,
                      label: score == 0 ? t('Pas de note', 'Not rated') : _formatScore(score),
                      semanticFormatterCallback: (v) =>
                          v == 0 ? t('Pas de note', 'Not rated') : '${_formatScore(v)} / 10',
                      onChanged: saving ? null : (v) => setState(() => score = v),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 4),
                      Semantics(
                        liveRegion: true,
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                error!,
                                style: Nami.meta.copyWith(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (inList)
                          TextButton.icon(
                            onPressed: saving ? null : _remove,
                            icon: const Icon(Icons.delete_outline),
                            label: Text(t('Retirer', 'Remove')),
                          ),
                        const Spacer(),
                        FocusOutline(
                          child: FilledButton(
                            onPressed: saving ? null : _save,
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(inList ? t('Enregistrer', 'Save') : t('Ajouter à ma liste', 'Add to my list')),
                          ),
                        ),
                      ],
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

String _formatScore(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', t(',', '.'));
