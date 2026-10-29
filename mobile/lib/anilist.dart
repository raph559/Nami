import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

/// AniList API client registered for Nami (redirect URL nami://auth).
const aniListClientId = '55284';
final aniListAuthorizeUrl = Uri.parse(
  'https://anilist.co/api/v2/oauth/authorize?client_id=$aniListClientId&response_type=token',
);

class MediaTitle {
  MediaTitle(this.romaji, this.english, this.native, this.userPreferred);

  final String? romaji, english, native, userPreferred;

  factory MediaTitle.fromJson(Map<String, dynamic>? j) =>
      MediaTitle(j?['romaji'], j?['english'], j?['native'], j?['userPreferred']);

  Map<String, dynamic> toJson() => {
    'romaji': romaji,
    'english': english,
    'native': native,
    'userPreferred': userPreferred,
  };

  String get display {
    final preferred = switch (AppSettings.instance.titleLanguage) {
      TitleLanguage.romaji => romaji,
      TitleLanguage.english => english,
      TitleLanguage.native => native,
    };
    return preferred ?? romaji ?? english ?? native ?? userPreferred ?? '?';
  }

  List<String> get all => {romaji, english, native, userPreferred}.whereType<String>().toList();
}

/// The states of an entry in the viewer's AniList, in the order AniList shows them.
const listStatuses = ['CURRENT', 'PLANNING', 'COMPLETED', 'REPEATING', 'PAUSED', 'DROPPED'];

String listStatusLabel(String status) => switch (status) {
  'CURRENT' => t('En cours', 'Watching'),
  'PLANNING' => t('À voir', 'Planning'),
  'COMPLETED' => t('Terminé', 'Completed'),
  'REPEATING' => t('Revisionnage', 'Rewatching'),
  'PAUSED' => t('En pause', 'Paused'),
  'DROPPED' => t('Abandonné', 'Dropped'),
  _ => status,
};

class ListEntry {
  ListEntry({this.id, this.progress, this.status, this.score});

  final int? id;
  final int? progress;
  final String? status;

  /// Out of 100 (AniList's POINT_100); 0 means not rated.
  final double? score;

  factory ListEntry.fromJson(Map<String, dynamic> j) =>
      ListEntry(id: j['id'], progress: j['progress'], status: j['status'], score: (j['score'] as num?)?.toDouble());

  Map<String, dynamic> toJson() => {'id': id, 'progress': progress, 'status': status, 'score': score};
}

class Media {
  Media(this.json)
    : id = json['id'],
      title = MediaTitle.fromJson(json['title']),
      listEntry = json['mediaListEntry'] == null ? null : ListEntry.fromJson(json['mediaListEntry']);

  /// Raw AniList object, also handed to extensions as `query.media`.
  final Map<String, dynamic> json;
  final int id;
  final MediaTitle title;
  final ListEntry? listEntry;

  int? get idMal => json['idMal'];
  String? get cover => json['coverImage']?['extraLarge'] ?? json['coverImage']?['large'];
  String? get coverSmall => json['coverImage']?['large'] ?? cover;
  String? get banner => json['bannerImage'];
  int? get episodes => json['episodes'];
  String? get format => json['format'];
  String? get status => json['status'];
  int? get seasonYear => json['seasonYear'];
  int? get averageScore => json['averageScore'];
  List<String> get genres => List<String>.from(json['genres'] ?? const []);
  List<String> get synonyms => List<String>.from(json['synonyms'] ?? const []);
  int? get nextEpisode => json['nextAiringEpisode']?['episode'];
  int? get nextAiringAt => json['nextAiringEpisode']?['airingAt'];
  bool get isMovie => format == 'MOVIE';
  int get progress => listEntry?.progress ?? 0;

  /// The same anime with another list entry (null when removed from the list).
  Media withEntry(ListEntry? entry) => Media({...json, 'mediaListEntry': entry?.toJson()});

  /// Episodes that can be watched now (aired so far for ongoing shows).
  int get availableEpisodes {
    final next = nextEpisode;
    if (next != null) return next - 1 < 0 ? 0 : next - 1;
    return episodes ?? 0;
  }

  String get plainDescription => (json['description'] as String? ?? '')
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  Color? get color {
    final hex = json['coverImage']?['color'] as String?;
    if (hex == null || hex.length != 7) return null;
    return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
  }

  @override
  bool operator ==(Object other) => other is Media && other.id == id;
  @override
  int get hashCode => id;
}

class Viewer {
  Viewer(this.json);
  final Map<String, dynamic> json;
  int get id => json['id'];
  String get name => json['name'];
  String? get avatar => json['avatar']?['large'];
  String? get banner => json['bannerImage'];
  Map<String, dynamic>? get _stats => json['statistics']?['anime'];
  int get animeCount => _stats?['count'] ?? 0;
  int get episodesWatched => _stats?['episodesWatched'] ?? 0;
  int get minutesWatched => _stats?['minutesWatched'] ?? 0;
}

/// One anime of the viewer's list with its entry.
class LibraryEntry {
  LibraryEntry(this.media, this.entry);
  final Media media;
  final ListEntry entry;
}

class WatchingEntry {
  WatchingEntry(this.media, this.progress);
  final Media media;
  final int progress;
  bool get hasNewEpisode => media.availableEpisodes > progress;
}

class AniListException implements Exception {
  AniListException(this.message);
  final String message;
  @override
  String toString() => 'AniList : $message';
}

const mediaFields = '''
id idMal title { romaji english native userPreferred } coverImage { extraLarge large color }
bannerImage description(asHtml: false) episodes duration format status season seasonYear
averageScore genres synonyms nextAiringEpisode { episode airingAt } startDate { year month day }
mediaListEntry { id progress status score(format: POINT_100) }
''';

class AniList extends ChangeNotifier {
  AniList._();
  static final instance = AniList._();

  Viewer? viewer;

  /// Goes up each time Nami changes the viewer's list, so screens showing it reload.
  int listRevision = 0;

  String get _token => AppSettings.instance.prefs.getString('anilistToken') ?? '';
  bool get isLoggedIn => _token.isNotEmpty;

  Future<Map<String, dynamic>> query(String q, [Map<String, dynamic> variables = const {}]) async {
    final res = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'query': q, 'variables': variables}),
    );
    if (res.statusCode == 401) logout();
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final errors = body['errors'] as List?;
    if (errors != null && errors.isNotEmpty) throw AniListException(errors.first['message']);
    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) throw AniListException(t('réponse vide', 'empty response'));
    return data;
  }

  List<Media> _page(Map<String, dynamic> d) =>
      (d['Page']['media'] as List).map((m) => Media(m as Map<String, dynamic>)).toList();

  Future<List<Media>> trending() async => _page(
    await query(
      'query { Page(perPage: 30) { media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { $mediaFields } } }',
    ),
  );

  Future<List<Media>> seasonal() async {
    final (season, year) = currentSeason();
    return _page(
      await query(
        r'query($s: MediaSeason, $y: Int) { Page(perPage: 30) { media(type: ANIME, season: $s, seasonYear: $y, sort: POPULARITY_DESC, isAdult: false) { '
        '$mediaFields } } }',
        {'s': season, 'y': year},
      ),
    );
  }

  /// Searches by text and/or genre; with neither, returns the most popular.
  Future<List<Media>> search(String text, {String? genre}) async {
    final vars = <String, dynamic>{
      'sort': [text.isEmpty ? 'POPULARITY_DESC' : 'SEARCH_MATCH'],
      if (text.isNotEmpty) 'q': text,
      'g': ?genre,
    };
    return _page(
      await query(
        r'query($q: String, $g: String, $sort: [MediaSort]) { Page(perPage: 40) { media(type: ANIME, search: $q, genre: $g, sort: $sort, isAdult: false) { '
        '$mediaFields } } }',
        vars,
      ),
    );
  }

  Future<Media> media(int id) async => Media(
    (await query(
      r'query($id: Int) { Media(id: $id) { '
      '$mediaFields } }',
      {'id': id},
    ))['Media'],
  );

  static (String, int) currentSeason([DateTime? now]) {
    final d = now ?? DateTime.now();
    final season = switch (d.month) {
      <= 3 => 'WINTER',
      <= 6 => 'SPRING',
      <= 9 => 'SUMMER',
      _ => 'FALL',
    };
    return (season, d.year);
  }

  Future<void> loadViewer() async {
    if (!isLoggedIn) {
      viewer = null;
    } else {
      try {
        viewer = Viewer(
          (await query(
            'query { Viewer { id name avatar { large } bannerImage statistics { anime { count episodesWatched minutesWatched } } } }',
          ))['Viewer'],
        );
      } catch (_) {
        viewer = null;
      }
    }
    notifyListeners();
  }

  Future<List<WatchingEntry>> watching() async {
    final v = viewer;
    if (v == null) return [];
    final d = await query(
      r'query($u: Int) { MediaListCollection(userId: $u, type: ANIME, status_in: [CURRENT, REPEATING], sort: UPDATED_TIME_DESC) { lists { entries { progress media { '
      '$mediaFields } } } } }',
      {'u': v.id},
    );
    return [
      for (final list in d['MediaListCollection']['lists'] as List)
        for (final e in list['entries'] as List) WatchingEntry(Media(e['media']), e['progress'] ?? 0),
    ];
  }

  /// Records an episode as watched; completes the entry on the last episode.
  Future<void> setProgress(Media media, int episode) async {
    if (!isLoggedIn || media.progress >= episode) return;
    final status = (media.episodes != null && episode >= media.episodes!) ? 'COMPLETED' : 'CURRENT';
    await query(
      r'mutation($id: Int, $p: Int, $s: MediaListStatus) { SaveMediaListEntry(mediaId: $id, progress: $p, status: $s) { progress } }',
      {'id': media.id, 'p': episode, 's': status},
    );
    _listChanged();
  }

  /// The viewer's whole anime list, grouped by status (custom lists left out).
  Future<Map<String, List<LibraryEntry>>> library() async {
    final v = viewer;
    if (v == null) return {};
    final d = await query(
      r'query($u: Int) { MediaListCollection(userId: $u, type: ANIME, sort: UPDATED_TIME_DESC) { lists { isCustomList entries { id progress status score(format: POINT_100) media { '
      '$mediaFields } } } } }',
      {'u': v.id},
    );
    final byStatus = <String, List<LibraryEntry>>{};
    for (final list in d['MediaListCollection']['lists'] as List) {
      if (list['isCustomList'] == true) continue;
      for (final e in list['entries'] as List) {
        final entry = ListEntry.fromJson(e);
        (byStatus[entry.status ?? 'CURRENT'] ??= []).add(LibraryEntry(Media(e['media']), entry));
      }
    }
    return byStatus;
  }

  /// Adds or updates the viewer's entry for [media]. [score] is out of 100, 0 for none.
  Future<ListEntry> saveEntry(
    Media media, {
    required String status,
    required int progress,
    required double score,
  }) async {
    final d = await query(
      r'mutation($id: Int, $s: MediaListStatus, $p: Int, $r: Int) { SaveMediaListEntry(mediaId: $id, status: $s, progress: $p, scoreRaw: $r) { id progress status score(format: POINT_100) } }',
      {'id': media.id, 's': status, 'p': progress, 'r': score.round()},
    );
    _listChanged();
    return ListEntry.fromJson(d['SaveMediaListEntry']);
  }

  Future<void> deleteEntry(int entryId) async {
    await query(r'mutation($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }', {'id': entryId});
    _listChanged();
  }

  void _listChanged() {
    listRevision++;
    // Episode and anime counts change with the list.
    loadViewer();
  }

  /// Stores the token from an implicit-grant callback (nami://auth#access_token=...).
  Future<bool> completeLogin(Uri callback) async {
    final params = Uri.splitQueryString(callback.fragment);
    final token = params['access_token'];
    if (token == null || token.isEmpty) return false;
    await AppSettings.instance.prefs.setString('anilistToken', token);
    await loadViewer();
    return true;
  }

  void logout() {
    AppSettings.instance.prefs.remove('anilistToken');
    viewer = null;
    notifyListeners();
  }
}
