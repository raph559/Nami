import 'anilist.dart';
import 'screens/home.dart' show HomeScreen;
import 'settings.dart';

/// Enough of an anime for a cover; its page loads the rest.
const _cardFields = '''
id title { romaji english native userPreferred } coverImage { extraLarge large color }
format type status episodes seasonYear averageScore nextAiringEpisode { episode airingAt }
''';

const _detailsFields =
    '''
trailer { id site thumbnail }
tags { name rank isMediaSpoiler isGeneralSpoiler }
rankings { rank type allTime season year }
externalLinks { site url type }
stats { scoreDistribution { score amount } statusDistribution { status amount } }
relations { edges { relationType(version: 2) node { $_cardFields } } }
characters(sort: [ROLE, RELEVANCE], perPage: 12) { edges { role
  voiceActors(language: JAPANESE, sort: [RELEVANCE]) { name { full } image { large } }
  node { name { full } image { large } } } }
staff(sort: [RELEVANCE], perPage: 8) { edges { role node { name { full } image { large } } } }
recommendations(sort: [RATING_DESC], perPage: 12) { nodes { mediaRecommendation { $_cardFields } } }
''';

class Trailer {
  Trailer(this.id, this.site, this.thumbnail);
  final String id;
  final String site;
  final String? thumbnail;

  bool get isYouTube => site == 'youtube';

  /// The page that plays it, for an embedded player.
  String get embedUrl => isYouTube
      ? 'https://www.youtube-nocookie.com/embed/$id?autoplay=1&playsinline=1&rel=0'
      : 'https://www.dailymotion.com/embed/video/$id?autoplay=1';

  /// Its own page on the site.
  String get pageUrl => isYouTube ? 'https://www.youtube.com/watch?v=$id' : 'https://www.dailymotion.com/video/$id';
}

class AnimeTag {
  AnimeTag(this.name, this.rank, this.spoiler);
  final String name;
  final int rank;
  final bool spoiler;
}

class RelatedAnime {
  RelatedAnime(this.media, this.relation);
  final Media media;
  final String relation;

  bool get isBefore => relation == 'PREQUEL' || relation == 'PARENT';
  bool get isAfter => relation == 'SEQUEL';
}

String relationLabel(String relation) => switch (relation) {
  'SEQUEL' => t('Suite', 'Sequel'),
  'PREQUEL' => t('Préquelle', 'Prequel'),
  'SIDE_STORY' => t('Histoire parallèle', 'Side story'),
  'SPIN_OFF' => t('Spin-off', 'Spin-off'),
  'ALTERNATIVE' => t('Autre version', 'Alternative'),
  'PARENT' => t('Série principale', 'Main story'),
  'SUMMARY' => t('Résumé', 'Summary'),
  'COMPILATION' => t('Compilation', 'Compilation'),
  'CONTAINS' => t('Contient', 'Contains'),
  _ => t('Lié', 'Related'),
};

class Person {
  Person(this.name, this.image, this.role);
  final String name;
  final String? image;
  final String? role;

  static Person? fromJson(Map<String, dynamic>? j, {String? role}) {
    final name = j?['name']?['full'] as String?;
    return name == null ? null : Person(name, j?['image']?['large'], role);
  }
}

class CastMember {
  CastMember(this.character, this.voice, this.main);
  final Person character;
  final Person? voice;
  final bool main;
}

class AnimeLink {
  AnimeLink(this.site, this.url);
  final String site;
  final String url;
}

class AnimeDetails {
  AnimeDetails(Map<String, dynamic> j)
    : trailer = _trailer(j['trailer']),
      tags = [
        for (final tag in j['tags'] as List? ?? const [])
          AnimeTag(tag['name'], tag['rank'] ?? 0, tag['isMediaSpoiler'] == true || tag['isGeneralSpoiler'] == true),
      ],
      rankings = [for (final r in j['rankings'] as List? ?? const []) ?_ranking(r)],
      links = [
        for (final l in j['externalLinks'] as List? ?? const [])
          if (l['url'] != null) AnimeLink(l['site'] ?? l['url'], l['url']),
      ],
      scores = {
        for (final s in j['stats']?['scoreDistribution'] as List? ?? const [])
          (s['score'] as num).toInt(): (s['amount'] as num).toInt(),
      },
      statuses = {
        for (final s in j['stats']?['statusDistribution'] as List? ?? const [])
          s['status'] as String: (s['amount'] as num).toInt(),
      },
      related = [
        for (final e in j['relations']?['edges'] as List? ?? const [])
          if (e['node']?['type'] == 'ANIME')
            RelatedAnime(Media(Map<String, dynamic>.from(e['node'])), e['relationType'] ?? 'OTHER'),
      ],
      cast = [
        for (final e in j['characters']?['edges'] as List? ?? const [])
          if (Person.fromJson(e['node']) case final character?)
            CastMember(
              character,
              (e['voiceActors'] as List?)?.isNotEmpty == true ? Person.fromJson(e['voiceActors'][0]) : null,
              e['role'] == 'MAIN',
            ),
      ],
      staff = [
        for (final e in j['staff']?['edges'] as List? ?? const []) ?Person.fromJson(e['node'], role: e['role']),
      ],
      recommendations = [
        for (final r in j['recommendations']?['nodes'] as List? ?? const [])
          if (r['mediaRecommendation'] != null) Media(Map<String, dynamic>.from(r['mediaRecommendation'])),
      ];

  final Trailer? trailer;
  final List<AnimeTag> tags;
  final List<String> rankings;
  final List<AnimeLink> links;

  /// How many viewers gave each score, out of 100.
  final Map<int, int> scores;

  /// How many viewers are at each list status.
  final Map<String, int> statuses;
  final List<RelatedAnime> related;
  final List<CastMember> cast;
  final List<Person> staff;
  final List<Media> recommendations;

  static Trailer? _trailer(Map<String, dynamic>? j) {
    // AniList keeps ids as they were typed, stray spaces included.
    final id = (j?['id'] as String?)?.trim();
    final site = j?['site'] as String?;
    if (id == null || (site != 'youtube' && site != 'dailymotion')) return null;
    return Trailer(id, site!, j?['thumbnail']);
  }

  static String? _ranking(Map<String, dynamic> r) {
    final kind = switch (r['type']) {
      'RATED' => t('mieux noté', 'highest rated'),
      'POPULAR' => t('plus populaire', 'most popular'),
      _ => null,
    };
    if (kind == null) return null;
    final String when;
    if (r['allTime'] == true) {
      when = t('de tous les temps', 'of all time');
    } else if (r['season'] != null && r['year'] != null) {
      when = '${HomeScreen.seasonName(r['season'])} ${r['year']}';
    } else if (r['year'] != null) {
      when = '${r['year']}';
    } else {
      return null;
    }
    return '#${r['rank']} $kind $when';
  }
}

extension AnimeDetailsQuery on AniList {
  /// What only the anime page needs, apart from the fields every list uses.
  Future<AnimeDetails> details(int id) async {
    final d = await query(
      r'query($id: Int) { Media(id: $id) { '
      '$_detailsFields } }',
      {'id': id},
    );
    return AnimeDetails(d['Media']);
  }
}
