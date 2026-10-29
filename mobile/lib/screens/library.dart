import 'package:flutter/material.dart';

import '../anilist.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/tabs.dart';
import '../widgets.dart';
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
          if (viewer == null) return _loggedOut(context, anilist.isLoggedIn);
          final entries = sortLibrary(lists[status] ?? const <LibraryEntry>[], sort);
          final side = isDesktop ? MediaQuery.paddingOf(context).left + 36 : 16.0;
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
    final days = viewer.minutesWatched / 60 / 24;
    final stats = [
      t('${viewer.animeCount} animes', '${viewer.animeCount} anime'),
      t('${viewer.episodesWatched} épisodes vus', '${viewer.episodesWatched} episodes watched'),
      t('${days.toStringAsFixed(1).replaceAll('.', ',')} jours', '${days.toStringAsFixed(1)} days'),
    ].join(' · ');
    final avatar = isDesktop ? 64.0 : 52.0;
    return Row(
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
              Text(stats, style: Nami.meta.copyWith(fontSize: isDesktop ? 13 : null)),
            ],
          ),
        ),
      ],
    );
  }
}
