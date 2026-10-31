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
  String? get studio {
    final nodes = json['studios']?['nodes'] as List?;
    return nodes == null || nodes.isEmpty ? null : nodes.first['name'] as String?;
  }

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

/// Orders for the viewer's list. [activity] is AniList's order (last updated first).
enum LibrarySort { activity, title, score, progress }

extension LibrarySortLabel on LibrarySort {
  String get label => switch (this) {
    LibrarySort.activity => t('Dernière activité', 'Last activity'),
    LibrarySort.title => t('Titre', 'Title'),
    LibrarySort.score => t('Note', 'Score'),
    LibrarySort.progress => t('Progression', 'Progress'),
  };
}

/// A sorted copy of [entries]: unrated anime and unknown totals go last.
List<LibraryEntry> sortLibrary(List<LibraryEntry> entries, LibrarySort sort) {
  double fraction(LibraryEntry e) {
    final total = e.media.episodes ?? 0;
    return total > 0 ? (e.entry.progress ?? 0) / total : -1;
  }

  // Dart's sort is not stable: ties fall back on the list's own order (last activity).
  final position = {for (final (i, e) in entries.indexed) e: i};
  int ties(LibraryEntry a, LibraryEntry b, int order) => order != 0 ? order : position[a]!.compareTo(position[b]!);
  final sorted = [...entries];
  switch (sort) {
    case LibrarySort.activity:
      break;
    case LibrarySort.title:
      sorted.sort(
        (a, b) => ties(a, b, a.media.title.display.toLowerCase().compareTo(b.media.title.display.toLowerCase())),
      );
    case LibrarySort.score:
      sorted.sort((a, b) => ties(a, b, (b.entry.score ?? 0).compareTo(a.entry.score ?? 0)));
    case LibrarySort.progress:
      sorted.sort((a, b) => ties(a, b, fraction(b).compareTo(fraction(a))));
  }
  return sorted;
}

/// An episode that airs (or aired) today.
class AiringItem {
  AiringItem(this.media, this.episode, this.airingAt);
  final Media media;
  final int episode;
  final DateTime airingAt;

  bool airedAt(DateTime now) => !airingAt.isAfter(now);
  bool get aired => airedAt(DateTime.now());
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
bannerImage description(asHtml: false) episodes duration format status season seasonYear studios(isMain: true) { nodes { name } }
averageScore genres synonyms nextAiringEpisode { episode airingAt } startDate { year month day }
mediaListEntry { id progress status score(format: POINT_100) }
''';

class AniList extends ChangeNotifier {
  AniList._();
  static final instance = AniList._();

  Viewer? viewer;

  /// The last profile request failed although the login is valid.
  bool viewerFailed = false;

  /// Goes up each time Nami changes the viewer's list, so screens showing it reload.
  int listRevision = 0;

  /// How many anime of your list have an episode to watch. The home keeps it up to date.
  final newEpisodes = ValueNotifier<int>(0);

  /// The anime of your list, for the calendar tab. The home keeps it up to date too.
  final listIds = ValueNotifier<Set<int>>(const {});

  /// Weeks already asked for, by first day, with when they were asked.
  final _weeks = <DateTime, (DateTime, List<AiringItem>)>{};

  String get _token => AppSettings.instance.prefs.getString('anilistToken') ?? '';
  bool get isLoggedIn => _token.isNotEmpty;

  /// Replaces the network in tests.
  @visibleForTesting
  Future<http.Response> Function(Uri uri, Map<String, String> headers, String body)? post;

  static const _rateLimitRetries = 2;

  Future<Map<String, dynamic>> query(String q, [Map<String, dynamic> variables = const {}]) async {
    final token = _token;
    final url = Uri.parse('https://graphql.anilist.co');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final payload = jsonEncode({'query': q, 'variables': variables});
    Future<http.Response> send() =>
        post?.call(url, headers, payload) ?? http.post(url, headers: headers, body: payload);

    var res = await send();
    // AniList limits requests per minute; it says how long to wait.
    for (var i = 0; res.statusCode == 429 && i < _rateLimitRetries; i++) {
      final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 5;
      await Future<void>.delayed(Duration(seconds: wait.clamp(0, 65)));
      res = await send();
    }
    // A late answer for an older token must not end the session of a newer one.
    if (res.statusCode == 401 && token == _token) logout();
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

  /// Searches by text and/or genres (all of them); with neither, returns the most popular.
  Future<List<Media>> search(String text, {List<String> genres = const []}) async {
    final vars = <String, dynamic>{
      'sort': [text.isEmpty ? 'POPULARITY_DESC' : 'SEARCH_MATCH'],
      if (text.isNotEmpty) 'q': text,
      if (genres.isNotEmpty) 'g': genres,
    };
    return _page(
      await query(
        r'query($q: String, $g: [String], $sort: [MediaSort]) { Page(perPage: 40) { media(type: ANIME, search: $q, genre_in: $g, sort: $sort, isAdult: false) { '
        '$mediaFields } } }',
        vars,
      ),
    );
  }

  Future<List<Media>> topRated() async => _page(
    await query(
      'query { Page(perPage: 30) { media(type: ANIME, sort: SCORE_DESC, isAdult: false) { $mediaFields } } }',
    ),
  );

  /// Local midnight to the next one.
  static (DateTime, DateTime) dayBounds(DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    return (start, DateTime(now.year, now.month, now.day + 1));
  }

  /// Episodes airing during the local day, in time order.
  Future<List<AiringItem>> airingToday({DateTime? now}) async {
    final (start, end) = dayBounds(now ?? DateTime.now());
    final d = await query(
      r'query($a: Int, $b: Int) { Page(perPage: 50) { airingSchedules(airingAt_greater: $a, airingAt_lesser: $b, sort: TIME) { episode airingAt media { isAdult '
      '$mediaFields } } } }',
      {'a': start.millisecondsSinceEpoch ~/ 1000 - 1, 'b': end.millisecondsSinceEpoch ~/ 1000},
    );
    return parseAiring(d['Page']['airingSchedules'] as List);
  }

  /// Episodes of the seven days from [from] (today by default), in time order. A week is more
  /// than one page, so it is kept for a while: coming back to it should not ask for it again.
  Future<List<AiringItem>> airingWeek({DateTime? from}) async {
    final now = DateTime.now();
    final (start, _) = dayBounds(from ?? now);
    final kept = _weeks[start];
    if (kept != null && kept.$1.day == now.day && now.difference(kept.$1).inMinutes < 15) return kept.$2;
    final end = DateTime(start.year, start.month, start.day + 7);
    final items = <AiringItem>[];
    for (var page = 1; page <= 6; page++) {
      final d = await query(
        r'query($a: Int, $b: Int, $p: Int) { Page(page: $p, perPage: 50) { pageInfo { hasNextPage } '
        r'airingSchedules(airingAt_greater: $a, airingAt_lesser: $b, sort: TIME) { episode airingAt media { isAdult '
        '$mediaFields } } } }',
        {'a': start.millisecondsSinceEpoch ~/ 1000 - 1, 'b': end.millisecondsSinceEpoch ~/ 1000, 'p': page},
      );
      items.addAll(parseAiring(d['Page']['airingSchedules'] as List));
      if (d['Page']['pageInfo']?['hasNextPage'] != true) break;
    }
    _weeks[start] = (now, items);
    return items;
  }

  /// Today's schedule entries, without adult anime and without entries AniList sent without an anime.
  static List<AiringItem> parseAiring(List schedules) => [
    for (final s in schedules)
      if (s['media'] case final Map<String, dynamic> m when m['isAdult'] != true)
        AiringItem(Media(m), s['episode'], DateTime.fromMillisecondsSinceEpoch((s['airingAt'] as int) * 1000)),
  ];

  /// AniList's best-rated recommendations for an anime.
  Future<List<Media>> recommendationsFor(int mediaId) async {
    final d = await query(
      r'query($id: Int) { Media(id: $id) { recommendations(sort: RATING_DESC, perPage: 15) { nodes { mediaRecommendation { '
      '$mediaFields } } } } }',
      {'id': mediaId},
    );
    return [
      for (final n in d['Media']['recommendations']['nodes'] as List)
        if (n['mediaRecommendation'] != null) Media(n['mediaRecommendation']),
    ];
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
      viewerFailed = false;
    } else {
      try {
        viewer = Viewer(
          (await query(
            'query { Viewer { id name avatar { large } bannerImage statistics { anime { count episodesWatched minutesWatched } } } }',
          ))['Viewer'],
        );
        viewerFailed = false;
      } catch (_) {
        // Still logged in: a failed refresh keeps what is on screen, and the
        // screens offer to try again when there is no profile yet.
        viewerFailed = true;
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
