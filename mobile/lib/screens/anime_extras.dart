import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../anilist.dart';
import '../anime_details.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/tags.dart';
import '../widgets.dart';

/// The trailer, played in the app. The site's own page stays one tap away.
class TrailerScreen extends StatelessWidget {
  const TrailerScreen({super.key, required this.trailer, required this.title});
  final Trailer trailer;
  final String title;

  /// YouTube refuses an embed with no origin, so the page gets one.
  static String page(Trailer trailer) =>
      '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style></head>
<body><iframe src="${trailer.embedUrl}" allow="autoplay; encrypted-media; fullscreen" allowfullscreen></iframe></body></html>
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => launchUrl(Uri.parse(trailer.pageUrl), mode: LaunchMode.externalApplication),
            child: Text(trailer.isYouTube ? t('Ouvrir sur YouTube', 'Open on YouTube') : t('Ouvrir le site', 'Open the site')),
          ),
        ],
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: InAppWebView(
            initialData: InAppWebViewInitialData(data: page(trailer), baseUrl: WebUri(sourcePage)),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              transparentBackground: true,
            ),
          ),
        ),
      ),
    );
  }

  static const sourcePage = 'https://github.com/raph559/Nami';
}

void openTrailer(BuildContext context, Media media, Trailer trailer) => Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => TrailerScreen(trailer: trailer, title: media.title.display)),
);

String _short(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)} M'
    : n >= 1000
    ? '${(n / 1000).round()} k'
    : '$n';

String _status(String status) => switch (status) {
  'CURRENT' => t('regardent', 'watching'),
  'PLANNING' => t('prévoient de voir', 'planning'),
  'COMPLETED' => t('ont terminé', 'completed'),
  'DROPPED' => t('ont abandonné', 'dropped'),
  'PAUSED' => t('en pause', 'paused'),
  _ => status.toLowerCase(),
};

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Semantics(header: true, child: Text(text, style: Nami.section)),
  );
}

/// The trailer's picture, with a play mark.
class _TrailerCard extends StatelessWidget {
  const _TrailerCard({required this.media, required this.trailer});
  final Media media;
  final Trailer trailer;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: FocusOutline(
          radius: Nami.radiusImage,
          child: Semantics(
            button: true,
            label: t('Lire la bande-annonce', 'Play the trailer'),
            child: InkWell(
              borderRadius: BorderRadius.circular(Nami.radiusImage),
              onTap: () => openTrailer(context, media, trailer),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverImage(trailer.thumbnail ?? media.banner),
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Nami.ground.withValues(alpha: 0.7), shape: BoxShape.circle),
                      child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.play_arrow_rounded, size: 34)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreChart extends StatelessWidget {
  const _ScoreChart(this.scores);
  final Map<int, int> scores;

  @override
  Widget build(BuildContext context) {
    final most = scores.values.fold(1, (a, b) => a > b ? a : b);
    final entries = scores.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Semantics(
      label: t('Répartition des notes', 'Score distribution'),
      child: SizedBox(
        height: 110,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final e in entries)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(height: 2 + 80 * e.value / most, color: Nami.textSecondary),
                      const SizedBox(height: 4),
                      Text('${e.key ~/ 10}', style: Nami.caption.copyWith(fontSize: 11)),
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

/// Spoiler tags stay hidden until asked for.
class _Tags extends StatefulWidget {
  const _Tags(this.tags);
  final List<AnimeTag> tags;

  @override
  State<_Tags> createState() => _TagsState();
}

class _TagsState extends State<_Tags> {
  bool spoilers = false;

  @override
  Widget build(BuildContext context) {
    final hidden = widget.tags.where((tag) => tag.spoiler).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in widget.tags)
              if (spoilers || !tag.spoiler) FlatTag('${tag.name} ${tag.rank} %'),
          ],
        ),
        if (hidden > 0 && !spoilers)
          TextButton(
            onPressed: () => setState(() => spoilers = true),
            child: Text(t('Montrer $hidden tags avec spoilers', 'Show $hidden spoiler tags')),
          ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person, this.detail});
  final Person person;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 44, height: 60, child: CoverImage(person.image)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(person.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Nami.body.copyWith(fontSize: 14)),
              if (detail != null) Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Nami.caption),
            ],
          ),
        ),
      ],
    );
  }
}

/// Everything about the anime that is not its episodes.
class AnimeDetailsTab extends StatelessWidget {
  const AnimeDetailsTab({super.key, required this.media, required this.details});
  final Media media;
  final AnimeDetails details;

  @override
  Widget build(BuildContext context) {
    final d = details;
    final watching = d.statuses.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.trailer != null) ...[
          _Heading(t('Bande-annonce', 'Trailer')),
          _TrailerCard(media: media, trailer: d.trailer!),
        ],
        if (d.rankings.isNotEmpty) ...[
          _Heading(t('Classements', 'Rankings')),
          for (final r in d.rankings.take(4)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(r, style: Nami.meta)),
        ],
        if (d.scores.isNotEmpty) ...[_Heading(t('Notes', 'Scores')), _ScoreChart(d.scores)],
        if (watching.isNotEmpty) ...[
          _Heading(t('Sur AniList', 'On AniList')),
          Text([for (final s in watching) '${_short(s.value)} ${_status(s.key)}'].join(' · '), style: Nami.meta),
        ],
        if (d.tags.isNotEmpty) ...[_Heading(t('Tags', 'Tags')), _Tags(d.tags)],
        if (d.staff.isNotEmpty) ...[
          _Heading(t('Équipe', 'Staff')),
          _Grid(children: [for (final p in d.staff) _PersonTile(person: p, detail: p.role)]),
        ],
        if (d.links.isNotEmpty) ...[
          _Heading(t('Liens', 'Links')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in d.links)
                OutlinedButton(
                  onPressed: () => launchUrl(Uri.parse(l.url), mode: LaunchMode.externalApplication),
                  child: Text(l.site),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Fills the width with as many columns of [itemWidth] as fit.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});
  final List<Widget> children;
  static const itemWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / itemWidth).floor().clamp(1, 4);
        final width = (box.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

class AnimeCastTab extends StatelessWidget {
  const AnimeCastTab({super.key, required this.details});
  final AnimeDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.cast.isEmpty) {
      return StateMessage(title: t('Aucun personnage connu', 'No characters known'));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _Grid(
        children: [
          for (final c in details.cast)
            Row(
              children: [
                Expanded(
                  child: _PersonTile(
                    person: c.character,
                    detail: c.main ? t('Principal', 'Main') : t('Secondaire', 'Supporting'),
                  ),
                ),
                if (c.voice != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _PersonTile(person: c.voice!, detail: t('Voix', 'Voice'))),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// What came before, this anime, what comes after; then everything else linked to it.
class AnimeRelatedTab extends StatelessWidget {
  const AnimeRelatedTab({super.key, required this.media, required this.details});
  final Media media;
  final AnimeDetails details;

  Widget _node(Media m, String label) => SizedBox(
    width: 118,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MediaCard(m, width: 110),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Nami.caption),
      ],
    ),
  );

  Widget _arrow() => Padding(
    padding: const EdgeInsets.fromLTRB(2, 60, 8, 0),
    child: Icon(Icons.arrow_forward, size: 18, color: Nami.textSecondary),
  );

  @override
  Widget build(BuildContext context) {
    final before = details.related.where((r) => r.isBefore).toList();
    final after = details.related.where((r) => r.isAfter).toList();
    final others = details.related.where((r) => !r.isBefore && !r.isAfter).toList();
    final chain = before.isNotEmpty || after.isNotEmpty;
    final desktop = isDesktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chain) ...[
          _Heading(t('Dans quel ordre', 'In order')),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in before) ...[_node(r.media, relationLabel(r.relation)), _arrow()],
                _node(media, t('Cet anime', 'This anime')),
                for (final r in after) ...[_arrow(), _node(r.media, relationLabel(r.relation))],
              ],
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          _Heading(t('Aussi lié', 'Also related')),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [for (final r in others) _node(r.media, relationLabel(r.relation))],
          ),
        ],
        if (details.recommendations.isNotEmpty) ...[
          _Heading(t('Si tu as aimé', 'If you liked this')),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [for (final m in details.recommendations.take(desktop ? 12 : 9)) MediaCard(m, width: 110)],
          ),
        ],
        if (!chain && others.isEmpty && details.recommendations.isEmpty)
          StateMessage(title: t('Rien de lié pour le moment', 'Nothing related yet')),
      ],
    );
  }
}
