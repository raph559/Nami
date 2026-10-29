import 'dart:math' as math;

import 'extensions.dart';
import 'settings.dart';

/// What a torrent release name says, pulled out so the sources list can show
/// facts instead of raw file names.
class ReleaseInfo {
  ReleaseInfo._(this.result);

  final TorrentResult result;
  String? group;
  String? resolution;
  String? source;
  String? codec;
  bool dualAudio = false;
  bool multiAudio = false;
  bool dub = false;
  bool multiSubs = false;
  bool batch = false;
  bool prerelease = false;

  static final _group = RegExp(r'^\s*\[([^\]]+)\]');
  static final _resolution = RegExp(r'\b(2160|1080|720|480)p\b', caseSensitive: false);

  factory ReleaseInfo.parse(TorrentResult r) {
    final t = r.title;
    final info = ReleaseInfo._(r);
    info.group = _group.firstMatch(t)?.group(1)?.trim();
    info.resolution = _resolution.firstMatch(t)?.group(1);
    bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(t);
    if (has(r'\b(BD|Blu-?Ray|BDRip|BDMV)\b')) {
      info.source = 'Blu-ray';
    } else if (has(r'\bWEB(-?DL|-?Rip)?\b')) {
      info.source = 'WEB';
    }
    if (has(r'\b(HEVC|x265|H\.?265)\b')) {
      info.codec = 'HEVC';
    } else if (has(r'\bAV1\b')) {
      info.codec = 'AV1';
    } else if (has(r'\b(AVC|x264|H\.?264)\b')) {
      info.codec = 'H.264';
    }
    info.dualAudio = has(r'\bDual[- ]?Audio\b|\bDUAL\b');
    info.multiAudio = !info.dualAudio && has(r'\bMULTi\b|\bMulti[- ]?Audio\b');
    info.dub = !info.dualAudio && !info.multiAudio && has(r'\b(English )?Dub(bed)?\b');
    info.multiSubs = has(r'\bMulti[- ]?Subs?\b|\bMultiSub\b');
    info.prerelease = has(r'\bPre-?release\b');
    // A batch says so, or names a season without an episode (S02 but not S02E01).
    info.batch = has(r'\bBATCH\b|\bComplete\b') || (has(r'\bS\d{1,2}\b') && !has(r'\bS\d{1,2}E\d{1,4}\b'));
    return info;
  }

  /// How well the torrent is shared, which decides how fast playback starts.
  SeedHealth get health => result.seeders >= 50
      ? SeedHealth.good
      : result.seeders >= 5
      ? SeedHealth.fair
      : SeedHealth.low;

  /// The name shown first: the release group, else the extension.
  String get title => group ?? result.source;

  String get audioLabel {
    if (dualAudio) return t('Double audio', 'Dual audio');
    if (multiAudio) return t('Multi-audio', 'Multi-audio');
    if (dub) return t('Doublage', 'Dub');
    return t('VO', 'Original audio');
  }

  /// Short facts, in reading order.
  List<String> get facts => [
    if (resolution != null) '${resolution}p',
    ?source,
    ?codec,
    audioLabel,
    if (multiSubs) t('Multi sous-titres', 'Multi subs'),
    if (batch) t('Saison complète', 'Full season'),
    if (prerelease) t('Pré-version', 'Pre-release'),
  ];

  /// Ranking for the recommended source. Seeders matter most (they decide
  /// whether playback starts), then the user's quality, original audio,
  /// and a finished release over a pre-release. A full season always has more
  /// seeders than one episode, so it is held back: a single-episode release
  /// with a few dozen seeders wins over a season pack with a few hundred.
  double score(String preferredResolution) {
    var s = math.log(result.seeders + 1) * 10;
    if (result.isBest) s += 25;
    if (resolution == preferredResolution) {
      s += 20;
    } else if (resolution != null) {
      s -= 5;
    }
    if (dub) s -= 40;
    if (prerelease) s -= 30;
    if (batch) s -= 25;
    if (result.seeders == 0) s -= 30;
    return s;
  }

  /// One plain sentence on why a source was picked.
  String reason(String preferredResolution) {
    final parts = <String>[
      if (resolution == preferredResolution) t('ta qualité préférée', 'your preferred quality'),
      if (!dub) t('VO', 'original audio'),
      if (result.isBest) t('conseillée par ${result.source}', 'picked by ${result.source}'),
      t('${result.seeders} seeders', '${result.seeders} seeders'),
    ];
    return parts.join(' · ');
  }
}

enum SeedHealth {
  good,
  fair,
  low;

  String get label => switch (this) {
    good => t('bien partagée', 'well seeded'),
    fair => t('partage moyen', 'fairly seeded'),
    low => t('lancement lent', 'slow start'),
  };
}

/// Sorts results best first and returns them parsed.
List<ReleaseInfo> rankReleases(List<TorrentResult> results) {
  final pref = AppSettings.instance.resolution;
  final parsed = [for (final r in results) ReleaseInfo.parse(r)];
  parsed.sort((a, b) => b.score(pref).compareTo(a.score(pref)));
  return parsed;
}
