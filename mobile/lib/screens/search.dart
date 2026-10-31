import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anilist.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/tags.dart';
import '../widgets.dart';

typedef SearchFunction = Future<List<Media>> Function(String text, {List<String> genres});

/// Hands the search field's focus node down from the root, so Ctrl+K and "/"
/// can focus it from any page.
class SearchFocus extends InheritedWidget {
  const SearchFocus({super.key, required this.node, required super.child});
  final FocusNode node;

  static FocusNode? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SearchFocus>()?.node;

  @override
  bool updateShouldNotify(SearchFocus old) => old.node != node;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.search});

  /// Replaces the AniList search in tests.
  final SearchFunction? search;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const genres = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Horror',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
  ];

  final _controller = TextEditingController();
  FocusNode? _ownFocus;
  final selected = <String>{};
  List<Media> results = [];
  bool loading = false;
  bool failed = false;
  Timer? _debounce;
  int _request = 0;

  FocusNode get _focus => SearchFocus.maybeOf(context) ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onText(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  void _toggle(String genre) {
    setState(() => selected.contains(genre) ? selected.remove(genre) : selected.add(genre));
    _search();
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    _onText('');
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length == 1) return;
    final request = ++_request;
    setState(() => loading = true);
    try {
      // Kept in the order of the list, so the same choice always sends the same request.
      final picked = [
        for (final g in genres)
          if (selected.contains(g)) g,
      ];
      final found = await (widget.search ?? AniList.instance.search)(q, genres: picked);
      if (mounted && request == _request) {
        setState(() {
          results = found;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          results = [];
          failed = true;
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => loading = false);
    }
  }

  String get heading {
    final base = _controller.text.trim().isNotEmpty
        ? t('Résultats', 'Results')
        : selected.isEmpty
        ? t('Les plus populaires', 'Most popular')
        : selected.map(genreLabel).join(', ');
    if (loading || results.isEmpty) return base;
    final n = results.length;
    return '$base · ${n == 1 ? '1 anime' : t('$n animes', '$n anime')}';
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop;
    final side = desktop ? MediaQuery.paddingOf(context).left + 24 : 16.0;
    final field = CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onChanged: _onText,
        textInputAction: TextInputAction.search,
        style: Nami.body.copyWith(fontSize: desktop ? 16 : 15),
        decoration: InputDecoration(
          hintText: t('Rechercher un anime', 'Search for an anime'),
          prefixIcon: const Icon(Icons.search),
          suffixText: desktop ? t('Ctrl K', 'Ctrl K') : null,
          suffixStyle: Nami.caption.copyWith(color: Nami.textMuted),
          filled: desktop,
          fillColor: Nami.text.withValues(alpha: 0.08),
          border: desktop
              ? OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)
              : InputBorder.none,
          contentPadding: desktop ? const EdgeInsets.symmetric(vertical: 13) : null,
        ),
      ),
    );
    return Scaffold(
      appBar: desktop ? null : AppBar(title: field),
      body: CustomScrollView(
        slivers: [
          if (desktop)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, MediaQuery.paddingOf(context).top + 12, 40, 0),
              sliver: SliverToBoxAdapter(child: field),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, desktop ? 14 : 8, desktop ? 40 : 16, 0),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in genres)
                    FlatTag(genreLabel(g), selected: selected.contains(g), onTap: () => _toggle(g)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 20, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Semantics(header: true, child: Text(heading, style: MediaRow.titleStyle)),
            ),
          ),
          if (loading && results.isEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 16, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Semantics(label: t('Recherche…', 'Searching…'), liveRegion: true, child: const SkeletonGrid()),
              ),
            ),
          if (!loading && failed)
            SliverToBoxAdapter(
              child: StateMessage(
                title: t('La recherche a échoué', 'Search failed'),
                body: networkError(),
                action: t('Réessayer', 'Try again'),
                onAction: _search,
              ),
            ),
          if (!loading && !failed && results.isEmpty)
            SliverToBoxAdapter(
              child: StateMessage(
                title: t('Aucun anime trouvé', 'No anime found'),
                body: t(
                  "Vérifie l'orthographe, essaie le titre japonais ou retire un genre.",
                  'Check the spelling, try the Japanese title or remove a genre.',
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, 8, desktop ? 40 : 16, 24),
            sliver: SliverLayoutBuilder(
              builder: (context, c) {
                // Columns of about 120-130 px; the cell height follows the text size so titles never clip.
                final available = c.crossAxisExtent;
                final target = desktop ? 120.0 : 130.0;
                final columns = ((available + 12) / (target + 12)).ceil().clamp(2, 12);
                final cell = (available - 12 * (columns - 1)) / columns;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: MediaCard.heightFor(context, cell),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => MediaCard(results[i], width: cell, heroTag: 'search-${results[i].id}'),
                    childCount: results.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
