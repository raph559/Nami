import 'dart:convert';

import 'package:http/http.dart' as http;

enum SkipKind { opening, ending }

/// One stretch of an episode to skip, from AniSkip (crowd-sourced timings).
class SkipInterval {
  SkipInterval(this.kind, this.start, this.end);
  final SkipKind kind;
  final Duration start;
  final Duration end;

  bool contains(Duration t) => t >= start && t < end;
}

class AniSkip {
  /// Timings for one episode of the anime with MyAnimeList id [malId].
  /// [length] is the file's duration: AniSkip keeps the timings submitted for
  /// a file of about that length, so another release's cut does not shift them.
  /// Returns an empty list when nothing is known or the service is unreachable.
  static Future<List<SkipInterval>> fetch(int malId, int episode, Duration length) async {
    final uri = Uri.parse(
      'https://api.aniskip.com/v2/skip-times/$malId/$episode'
      '?types=op&types=ed&episodeLength=${length.inMilliseconds / 1000}',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      return parse(jsonDecode(res.body));
    } catch (_) {
      return [];
    }
  }

  static List<SkipInterval> parse(Object? body) {
    if (body is! Map || body['found'] != true) return [];
    final out = <SkipInterval>[];
    for (final r in body['results'] as List? ?? const []) {
      final kind = switch (r['skipType']) {
        'op' => SkipKind.opening,
        'ed' => SkipKind.ending,
        _ => null,
      };
      final interval = r['interval'] as Map?;
      if (kind == null || interval == null) continue;
      Duration at(String key) => Duration(milliseconds: ((interval[key] as num) * 1000).round());
      // One interval per kind: AniSkip may return several votes for the same part.
      if (out.any((i) => i.kind == kind)) continue;
      out.add(SkipInterval(kind, at('startTime'), at('endTime')));
    }
    return out;
  }
}
