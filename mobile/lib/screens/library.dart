import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import '../anilist.dart';
import '../platform.dart';
import '../profile.dart';
import '../downloads.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/downloads_section.dart';
import '../ui/tabs.dart';
import '../widgets.dart';
import 'profile_stats.dart';
import 'settings_screen.dart';

/// The viewer's AniList profile and list, one status at a time.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.loader});

  /// Replaces the AniList request in tests.
  final Future<Map<String, List<LibraryEntry>>> Function()? loader;

  static const sortKey = ValueKey('library-sort');

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Map<String, List<LibraryEntry>> lists = {};
  String status = 'CURRENT';
  LibrarySort sort =
      LibrarySort.values.asNameMap()[AppSettings.instance.prefs.getString('librarySort')] ?? LibrarySort.activity;
  bool loading = false;
  bool failed = false;
  int? _loadedFor;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    AniList.instance.addListener(_onAccount);
    _onAccount();
  }

  @override
  void dispose() {
    AniList.instance.removeListener(_onAccount);
    super.dispose();
  }

  void _onAccount() {
    final anilist = AniList.instance;
    if (anilist.viewer?.id != _loadedFor || anilist.listRevision != _revision) _load();
  }

  Future<void> _load() async {
    final anilist = AniList.instance;
    _loadedFor = anilist.viewer?.id;
    _revision = anilist.listRevision;
    if (anilist.viewer == null) {
      setState(() => lists = {});
      return;
    }
    setState(() {
      loading = lists.isEmpty;
      failed = false;
    });
    try {
      final found = await (widget.loader ?? anilist.library)();
      if (!mounted) return;
      setState(() {
        lists = found;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = lists.isEmpty;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final anilist = AniList.instance;
    return Scaffold(
      body: ListenableBuilder(
        listenable: anilist,
        builder: (context, _) {
          final viewer = anilist.viewer;
          if (viewer == null) return _noAccount(context, anilist.isLoggedIn);
          final entries = sortLibrary(lists[status] ?? const <LibraryEntry>[], sort);
          final side = isDesktop ? MediaQuery.paddingOf(context).left + 24 : 16.0;
          return RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      MediaQuery.paddingOf(context).top + (isDesktop ? 26 : 16),
                      24,
                      0,
                    ),
                    child: _ProfileHeader(viewer: viewer),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 22, isDesktop ? 40 : 16, 0),
                    child: UnderlineTabs(
                      labels: [for (final s in listStatuses) listStatusLabel(s)],
                      counts: [for (final s in listStatuses) lists[s]?.length],
                      selected: listStatuses.indexOf(status),
                      onSelect: (i) => setState(() => status = listStatuses[i]),
                      trailing: isDesktop ? _sortMenu() : null,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: DownloadsLink(padding: EdgeInsets.fromLTRB(side, 12, 16, 0))),
                if (!isDesktop)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(side - 8, 4, 16, 0),
                      child: Align(alignment: Alignment.centerLeft, child: _sortMenu()),
                    ),
                  ),
                if (loading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 16, 16, 16),
                    sliver: const SliverToBoxAdapter(child: SkeletonGrid()),
                  )
                else if (failed)
                  SliverToBoxAdapter(
                    child: StateMessage(
                      title: t("Ta liste n'a pas pu être chargée", "Your list couldn't be loaded"),
                      body: networkError(),
                      action: t('Réessayer', 'Try again'),
                      onAction: _load,
                    ),
                  )
                else if (entries.isEmpty)
                  SliverToBoxAdapter(
                    child: StateMessage(
                      title: t("Rien ici pour l'instant", 'Nothing here yet'),
                      body: t(
                        "Sur la page d'un anime, « Ma liste » le range dans ta liste AniList.",
                        "On an anime's page, \"My list\" files it in your AniList list.",
                      ),
                    ),
                  )
                else
                  _grid(entries, side),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sortMenu() {
    return PopupMenuButton<LibrarySort>(
      key: LibraryScreen.sortKey,
      tooltip: t('Trier', 'Sort'),
      initialValue: sort,
      onSelected: (s) {
        setState(() => sort = s);
        AppSettings.instance.prefs.setString('librarySort', s.name);
      },
      itemBuilder: (_) => [for (final s in LibrarySort.values) PopupMenuItem(value: s, child: Text(s.label))],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                t('Trier : ${sort.label}', 'Sort: ${sort.label}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Nami.caption.copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down, size: 18, color: Nami.textSecondary),
          ],
        ),
      ),
    );
  }

  /// With no profile (logged out, or AniList out of reach) downloads still show.
  Widget _noAccount(BuildContext context, bool tokenStored) {
    return ListenableBuilder(
      listenable: Downloads.instance,
      builder: (context, _) {
        final message = _loggedOut(context, tokenStored);
        if (Downloads.instance.entries.isEmpty) return message;
        return ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 16, 16, 16),
          children: [const DownloadsLink(), message],
        );
      },
    );
  }

  Widget _loggedOut(BuildContext context, bool tokenStored) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Center(
        child: tokenStored
            // The token is there but the profile has not loaded yet.
            ? StateMessage(
                title: t('Connexion à AniList…', 'Connecting to AniList…'),
                loading: true,
                action: t('Réessayer', 'Try again'),
                onAction: AniList.instance.loadViewer,
              )
            : Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_border, size: 40, color: Nami.textSecondary),
                    const SizedBox(height: 16),
                    Text(t('Ta liste AniList', 'Your AniList list'), style: Nami.section),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        'Connecte ton compte pour suivre tes animes, les noter et retrouver ce que tu as prévu de voir.',
                        'Log in to track your anime, rate them and find what you planned to watch.',
                      ),
                      textAlign: TextAlign.center,
                      style: Nami.meta,
                    ),
                    const SizedBox(height: 20),
                    FocusOutline(
                      child: FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                        icon: const Icon(Icons.login),
                        label: Text(t('Se connecter à AniList', 'Log in to AniList')),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _grid(List<LibraryEntry> entries, double side) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(side, 16, isDesktop ? 40 : 16, 32),
      sliver: SliverLayoutBuilder(
        builder: (context, c) {
          final available = c.crossAxisExtent;
          final cover = isDesktop ? 120.0 : 104.0;
          final columns = ((available + 12) / (cover + 12)).ceil().clamp(2, 12);
          final cell = (available - 12 * (columns - 1)) / columns;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: MediaCard.heightFor(context, cell, withBadge: true, withProgress: true),
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate((_, i) {
              final e = entries[i];
              return MediaCard(
                e.media,
                width: cell,
                badge: _badge(e),
                progress: _fraction(e),
                heroTag: 'library-${e.media.id}',
              );
            }, childCount: entries.length),
          );
        },
      ),
    );
  }

  /// Episodes watched out of the total, and the score when there is one.
  String _badge(LibraryEntry e) {
    final total = e.media.episodes;
    final progress = e.entry.progress ?? 0;
    final score = (e.entry.score ?? 0) / 10;
    return [
      if (!e.media.isMovie) total == null ? t('$progress ép.', '$progress ep.') : '$progress / $total',
      if (score > 0)
        // Words, not "★": the app font has no star glyph.
        t('note ', 'score ') +
            (score == score.roundToDouble()
                ? '${score.toInt()}'
                : score.toStringAsFixed(1).replaceAll('.', t(',', '.'))),
    ].join(' · ');
  }

  double? _fraction(LibraryEntry e) {
    final total = e.media.episodes ?? e.media.availableEpisodes;
    if (e.media.isMovie || total <= 0 || e.entry.status == 'COMPLETED') return null;
    return (e.entry.progress ?? 0) / total;
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.viewer});
  final Viewer viewer;

  @override
  Widget build(BuildContext context) {
    final stats = viewer.stats;
    final days = stats.minutes / 60 / 24;
    final line = [
      t('${stats.count} animes', '${stats.count} anime'),
      t('${stats.episodes} épisodes vus', '${stats.episodes} episodes watched'),
      t('${days.toStringAsFixed(1).replaceAll('.', ',')} jours', '${days.toStringAsFixed(1)} days'),
      if (stats.meanScore > 0)
        t(
          'note moyenne ${viewer.scoreFormat.show(stats.meanScore)}',
          'mean score ${viewer.scoreFormat.show(stats.meanScore)}',
        ),
    ].join(' · ');
    final bio = parseBio(viewer.about);
    final avatar = isDesktop ? 64.0 : 52.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: avatar,
              height: avatar,
              child: CoverImage(viewer.avatar, radius: avatar / 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(viewer.name, style: Nami.pageTitle)),
                  const SizedBox(height: 2),
                  Text(line, style: Nami.meta.copyWith(fontSize: isDesktop ? 13 : null)),
                ],
              ),
            ),
          ],
        ),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _Bio(key: const ValueKey('bio'), parts: bio),
          ),
        ],
        if (!stats.isEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileStatsScreen(viewer: viewer))),
            icon: const Icon(Icons.bar_chart_rounded, size: 18),
            label: Text(t('Statistiques', 'Statistics')),
          ),
        ],
      ],
    );
  }
}

/// The bio, cut to 3 lines until "Plus". Spoilers stay hidden until tapped.
class _Bio extends StatefulWidget {
  const _Bio({super.key, required this.parts});
  final List<BioPart> parts;

  @override
  State<_Bio> createState() => _BioState();
}

class _BioState extends State<_Bio> {
  bool _open = false;
  final _shown = <int>{};

  /// Long enough to need "Plus": measuring with the spoilers and links inside
  /// would need a layout pass, and length tells it as well.
  bool get _long {
    final text = widget.parts
        .map(
          (p) => switch (p) {
            BioText(:final text) => text,
            BioLink(:final text) => text,
            BioSpoiler() => 'Spoiler',
          },
        )
        .join();
    return text.length > 180 || '\n'.allMatches(text).length >= 3;
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final (i, part) in widget.parts.indexed) {
      switch (part) {
        case BioText(:final text):
          spans.add(TextSpan(text: text));
        case BioLink(:final text, :final url):
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(text, style: Nami.body.copyWith(decoration: TextDecoration.underline)),
                ),
              ),
            ),
          );
        case BioSpoiler(:final text):
          final shown = _shown.contains(i);
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Semantics(
                button: !shown,
                child: GestureDetector(
                  key: ValueKey('spoiler-$i'),
                  onTap: () => setState(() => _shown.add(i)),
                  child: MouseRegion(
                    cursor: shown ? MouseCursor.defer : SystemMouseCursors.click,
                    child: shown
                        ? Text(text, style: Nami.body)
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(color: Nami.border, borderRadius: BorderRadius.circular(4)),
                            child: Text('Spoiler', style: Nami.body.copyWith(color: Nami.textSecondary)),
                          ),
                  ),
                ),
              ),
            ),
          );
      }
    }
    final long = _long;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: Text.rich(
            TextSpan(children: spans),
            style: Nami.body,
            maxLines: _open || !long ? null : 3,
            overflow: _open || !long ? null : TextOverflow.ellipsis,
          ),
        ),
        if (long)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 36)),
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? t('Moins', 'Less') : t('Plus', 'More')),
          ),
      ],
    );
  }
}
