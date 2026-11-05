import 'package:flutter/painting.dart';

import 'settings.dart';

/// How the viewer rates anime on AniList. Nami keeps scores out of 100 and shows
/// them in this format.
enum ScoreFormat {
  point100,
  point10Decimal,
  point10,
  point5,
  point3;

  static ScoreFormat parse(String? anilist) => switch (anilist) {
    'POINT_10_DECIMAL' => point10Decimal,
    'POINT_10' => point10,
    'POINT_5' => point5,
    'POINT_3' => point3,
    _ => point100,
  };

  /// A score out of 100, the way AniList shows it in this format.
  String show(double outOf100) => switch (this) {
    point100 => '${outOf100.round()}',
    point10Decimal => _decimal(outOf100 / 10),
    point10 => '${(outOf100 / 10).round()}',
    point5 => '★' * (outOf100 / 20).round().clamp(1, 5),
    point3 => outOf100 >= 61 ? '🙂' : (outOf100 >= 36 ? '😐' : '🙁'),
  };

  /// AniList gives the score distribution in the viewer's format, apart from
  /// "10 with decimals", which comes out of 100.
  double distributionToOutOf100(int score) => switch (this) {
    point100 || point10Decimal => score.toDouble(),
    point10 => score * 10.0,
    point5 => score * 20.0,
    point3 => switch (score) {
      1 => 35.0,
      2 => 60.0,
      _ => 85.0,
    },
  };

  static String _decimal(double v) {
    final text = v.toStringAsFixed(1);
    final trimmed = text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
    return trimmed.replaceAll('.', t(',', '.'));
  }
}

class StatCount {
  const StatCount(this.name, this.count);
  final String name;
  final int count;
}

/// The viewer's anime statistics, as AniList counts them.
class ProfileStats {
  const ProfileStats({
    this.count = 0,
    this.episodes = 0,
    this.minutes = 0,
    this.meanScore = 0,
    this.standardDeviation = 0,
    this.genres = const [],
    this.studios = const [],
    this.formats = const [],
    this.statuses = const [],
    this.scores = const {},
    this.releaseYears = const {},
  });

  factory ProfileStats.fromJson(Map<String, dynamic>? anime, ScoreFormat format) {
    final a = anime ?? const {};
    List<StatCount> counts(String key, String Function(Map<String, dynamic>) name) => [
      for (final e in (a[key] as List?) ?? const [])
        if (e is Map<String, dynamic>) StatCount(name(e), (e['count'] as num?)?.toInt() ?? 0),
    ];
    // Entries that end up on the same number add up; 0 and below (not rated, no year) are left out.
    Map<int, int> byNumber(String key, int Function(Map<String, dynamic>) number) {
      final out = <int, int>{};
      for (final e in (a[key] as List?) ?? const []) {
        if (e is! Map<String, dynamic>) continue;
        final n = number(e);
        if (n <= 0) continue;
        out[n] = (out[n] ?? 0) + ((e['count'] as num?)?.toInt() ?? 0);
      }
      return out;
    }

    return ProfileStats(
      count: (a['count'] as num?)?.toInt() ?? 0,
      episodes: (a['episodesWatched'] as num?)?.toInt() ?? 0,
      minutes: (a['minutesWatched'] as num?)?.toInt() ?? 0,
      meanScore: (a['meanScore'] as num?)?.toDouble() ?? 0,
      standardDeviation: (a['standardDeviation'] as num?)?.toDouble() ?? 0,
      genres: counts('genres', (e) => e['genre'] ?? ''),
      studios: counts('studios', (e) => e['studio']?['name'] ?? ''),
      formats: counts('formats', (e) => e['format'] ?? ''),
      statuses: counts('statuses', (e) => e['status'] ?? ''),
      scores: byNumber('scores', (e) {
        final score = (e['score'] as num?)?.toInt() ?? 0;
        return score <= 0 ? 0 : format.distributionToOutOf100(score).round();
      }),
      releaseYears: byNumber('releaseYears', (e) => (e['releaseYear'] as num?)?.toInt() ?? 0),
    );
  }

  final int count;
  final int episodes;
  final int minutes;

  /// Out of 100, whatever the score format; 0 when nothing is rated.
  final double meanScore;
  final double standardDeviation;
  final List<StatCount> genres;
  final List<StatCount> studios;
  final List<StatCount> formats;
  final List<StatCount> statuses;

  /// Scores out of 100, and how many anime got each.
  final Map<int, int> scores;
  final Map<int, int> releaseYears;

  bool get isEmpty => count == 0;
}

/// A piece of an AniList bio, as Nami shows it.
sealed class BioPart {
  const BioPart();
}

class BioText extends BioPart {
  const BioText(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is BioText && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'BioText($text)';
}

class BioLink extends BioPart {
  const BioLink(this.text, this.url);
  final String text;
  final String url;
  @override
  bool operator ==(Object other) => other is BioLink && other.text == text && other.url == url;
  @override
  int get hashCode => Object.hash(text, url);
  @override
  String toString() => 'BioLink($text, $url)';
}

class BioSpoiler extends BioPart {
  const BioSpoiler(this.text);
  final String text;
  @override
  bool operator ==(Object other) => other is BioSpoiler && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'BioSpoiler($text)';
}

final _media = RegExp(
  r'(img\d*%?|youtube|webm)\([^)]*\)|<(img|video|iframe|source)\b[^>]*>|</(video|iframe)>',
  caseSensitive: false,
);
final _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final _pieces = RegExp(
  r'~!(.*?)!~|<a\b[^>]*?\bhref="([^"]+)"[^>]*>(.*?)</a>|\[([^\]]*)\]\((https?://[^)\s]+)\)|(https?://[^\s<>"\x27)\]]+)',
  dotAll: true,
  caseSensitive: false,
);
final _tags = RegExp(r'<[^>]+>');
final _marks = RegExp(r'__|\*\*|~~~');
final _headers = RegExp(r'^#+\s*', multiLine: true);
final _strike = RegExp(r'~~(.+?)~~');
// Single * or _ around words; an underscore inside a word (snake_case) stays.
final _italics = RegExp(r'(?<![\w*])[*_](?=\S)(.+?)(?<=\S)[*_](?![\w*])');
const _entities = {'&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&apos;': "'", '&nbsp;': ' '};
final _entity = RegExp(r'&(amp|lt|gt|quot|apos|nbsp|#39);|&#(\d+);');

/// A link Nami can open: a web address that parses.
bool _web(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

final _spaces = RegExp(r'[ \t]{2,}');
final _blankLines = RegExp(r'\n{3,}');

/// An AniList bio (Markdown, some HTML and AniList's own codes) as plain text,
/// links and spoilers. Images and videos are left out.
List<BioPart> parseBio(String? about) {
  if (about == null || about.trim().isEmpty) return const [];
  final source = about.replaceAll(_media, '').replaceAll(_lineBreak, '\n');
  String clean(String s) => s
      .replaceAll(_tags, '')
      .replaceAll(_marks, '')
      .replaceAll(_headers, '')
      .replaceAllMapped(_strike, (m) => m[1]!)
      .replaceAllMapped(_italics, (m) => m[1]!)
      .replaceAllMapped(_entity, (m) => m[2] != null ? String.fromCharCode(int.parse(m[2]!)) : _entities[m[0]]!)
      .replaceAll(_spaces, ' ')
      .replaceAll(_blankLines, '\n\n');

  final parts = <BioPart>[];
  void addText(String s) {
    final text = clean(s);
    if (text.isEmpty) return;
    if (parts.isNotEmpty && parts.last is BioText) {
      parts[parts.length - 1] = BioText((parts.last as BioText).text + text);
    } else {
      parts.add(BioText(text));
    }
  }

  var at = 0;
  for (final m in _pieces.allMatches(source)) {
    addText(source.substring(at, m.start));
    at = m.end;
    if (m[1] != null) {
      final hidden = clean(m[1]!).trim();
      if (hidden.isNotEmpty) parts.add(BioSpoiler(hidden));
    } else if (m[2] != null) {
      // A link around nothing left (an image) is dropped.
      final text = clean(m[3]!).trim();
      if (text.isNotEmpty) _web(m[2]!) ? parts.add(BioLink(text, m[2]!)) : addText(text);
    } else if (m[4] != null) {
      final text = clean(m[4]!).trim();
      if (text.isNotEmpty) _web(m[5]!) ? parts.add(BioLink(text, m[5]!)) : addText(text);
    } else {
      final url = m[6]!;
      _web(url) ? parts.add(BioLink(url.replaceFirst(RegExp(r'^https?://'), ''), url)) : addText(url);
    }
  }
  addText(source.substring(at));

  // No blank space at either end.
  while (parts.isNotEmpty && parts.first is BioText && (parts.first as BioText).text.trim().isEmpty) {
    parts.removeAt(0);
  }
  while (parts.isNotEmpty && parts.last is BioText && (parts.last as BioText).text.trim().isEmpty) {
    parts.removeLast();
  }
  if (parts.isNotEmpty && parts.first is BioText) parts[0] = BioText((parts.first as BioText).text.trimLeft());
  if (parts.isNotEmpty && parts.last is BioText) {
    parts[parts.length - 1] = BioText((parts.last as BioText).text.trimRight());
  }
  return parts;
}

/// The colour the viewer picked for their AniList profile: one of AniList's seven,
/// or a hex colour (donators). Blue, AniList's own, when there is none.
Color profileAccent(String? name) {
  const named = {
    'blue': 0xFF3DB4F2,
    'purple': 0xFFC063FF,
    'pink': 0xFFFC9DD6,
    'orange': 0xFFEF881A,
    'red': 0xFFE13333,
    'green': 0xFF4CCA51,
    'gray': 0xFF677B94,
  };
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(name ?? '');
  if (hex != null) return Color(0xFF000000 | int.parse(hex[1]!, radix: 16));
  return Color(named[name] ?? named['blue']!);
}

/// A score's colour, from red to green, as on AniList. Most scores are between 60
/// and 100, so red starts at 30 to spread them over the whole range.
Color scoreColor(double outOf100) =>
    HSVColor.fromAHSV(1, ((outOf100 - 30) / 70).clamp(0.0, 1.0) * 120, 0.7, 0.9).toColor();
