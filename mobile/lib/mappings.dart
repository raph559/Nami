import 'dart:convert';

import 'package:http/http.dart' as http;

/// Cross-database ids and episode metadata from api.ani.zip, which the
/// source extensions need (AniDB, TVDB, TMDB ids).
class Mappings {
  Mappings(this.json);
  final Map<String, dynamic> json;

  Map<String, dynamic> get ids => (json['mappings'] as Map<String, dynamic>?) ?? const {};
  int? get anidbId => ids['anidb_id'];
  int? get tvdbId => ids['thetvdb_id'];
  String? get tmdbId => ids['themoviedb_id']?.toString();
  String? get imdbId => ids['imdb_id'];

  EpisodeInfo? episode(int n) {
    final e = (json['episodes'] as Map<String, dynamic>?)?['$n'];
    return e == null ? null : EpisodeInfo(e as Map<String, dynamic>);
  }

  static final _cache = <int, Mappings>{};

  static Future<Mappings?> load(int anilistId) async {
    final cached = _cache[anilistId];
    if (cached != null) return cached;
    try {
      final res = await http.get(Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId'));
      if (res.statusCode != 200) return null;
      return _cache[anilistId] = Mappings(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class EpisodeInfo {
  EpisodeInfo(this.json);
  final Map<String, dynamic> json;

  String? get image => json['image'];
  int? get anidbEid => json['anidbEid'];
  int? get tvdbId => json['tvdbId'];
  int? get runtime => json['runtime'] ?? json['length'];

  String? title(String lang) {
    final t = json['title'] as Map<String, dynamic>?;
    return t?[lang] ?? t?['en'] ?? t?['x-jat'];
  }
}
