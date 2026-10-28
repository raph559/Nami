import 'dart:async';

import 'package:flutter/material.dart';

import '../anilist.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Horror', 'Mecha', 'Music', 'Mystery',
    'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports', 'Supernatural', 'Thriller',
  ];

  final _controller = TextEditingController();
  String? genre;
  List<Media> results = [];
  bool loading = false;
  bool failed = false;
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onText(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length == 1) return;
    final request = ++_request;
    setState(() => loading = true);
    try {
      final found = await AniList.instance.search(q, genre: genre);
      if (mounted && request == _request) setState(() { results = found; failed = false; });
    } catch (_) {
      if (mounted && request == _request) setState(() { results = []; failed = true; });
    } finally {
      if (mounted && request == _request) setState(() => loading = false);
    }
  }

  String get heading {
    if (_controller.text.trim().isNotEmpty) return t('Résultats', 'Results');
    return genre == null ? t('Les plus populaires', 'Most popular') : genreLabel(genre!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          onChanged: _onText,
          decoration: InputDecoration(
            hintText: t("Titre d'un anime", 'Anime title'),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: genres.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => FilterChip(
                  label: Text(genreLabel(genres[i])),
                  selected: genre == genres[i],
                  onSelected: (on) {
                    setState(() => genre = on ? genres[i] : null);
                    _search();
                  },
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(heading, style: Nami.section),
            ),
          ),
          if (loading && results.isEmpty)
            SliverToBoxAdapter(child: StateMessage(loading: true, title: t('Recherche…', 'Searching…'))),
          if (!loading && failed)
            SliverToBoxAdapter(
              child: StateMessage(
                title: t('La recherche a échoué', 'Search failed'),
                body: networkError(Exception()),
                action: t('Réessayer', 'Try again'),
                onAction: _search,
              ),
            ),
          if (!loading && !failed && results.isEmpty)
            SliverToBoxAdapter(
              child: StateMessage(
                title: t('Aucun anime trouvé', 'No anime found'),
                body: t("Vérifie l'orthographe ou essaie le titre japonais.", 'Check the spelling or try the Japanese title.'),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                childAspectRatio: 1 / 1.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => LayoutBuilder(builder: (_, c) => MediaCard(results[i], width: c.maxWidth)),
                childCount: results.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
