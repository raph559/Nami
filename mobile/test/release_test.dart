import 'package:flutter_test/flutter_test.dart';
import 'package:nami/extensions.dart';
import 'package:nami/release.dart';
import 'package:nami/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

TorrentResult r(String title, int seeders, {String source = 'NekoBT', String? type}) =>
    TorrentResult({'title': title, 'link': title, 'seeders': seeders, 'type': ?type}, source);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'en'});
    await AppSettings.load();
  });

  // Titles from a real search for Cyberpunk: Edgerunners 2, episode 1.
  final dubPre = r(
    '[ToonsHub] Cyberpunk Edgerunners S02E01 1080p TWITCH WEB-DL ENG AAC2.0 H.264 (English Dub, Prerelease)',
    2410,
    source: 'AnimeTosho (New)',
  );
  final varyg = r(
    '[VARYG] Cyberpunk Edgerunners S02 1080p NF WEB-DL DUAL DDP5.1 H (Cyberpunk: Edgerunners 2, Multi-Subs)',
    357,
  );
  final erai = r(
    '[Erai-raws] Cyberpunk: Edgerunners S02 [1080p NF WEB-DL HEVC EAC3][MultiSub] [BATCH] (Cyberpunk: Edgerunners 2)',
    165,
  );
  final whomst = r('[whomst-mini] Cyberpunk Edgerunners - S02 v2 [WEB 1080p AV1 Opus] [Dual Audio]', 134);

  test('reads the facts out of release names', () {
    final a = ReleaseInfo.parse(dubPre);
    expect(a.group, 'ToonsHub');
    expect(a.resolution, '1080');
    expect(a.source, 'WEB');
    expect(a.codec, 'H.264');
    expect(a.dub, isTrue);
    expect(a.prerelease, isTrue);
    expect(a.batch, isFalse, reason: 'S02E01 is one episode');

    final b = ReleaseInfo.parse(erai);
    expect(b.group, 'Erai-raws');
    expect(b.codec, 'HEVC');
    expect(b.multiSubs, isTrue);
    expect(b.batch, isTrue);
    expect(b.facts, ['1080p', 'WEB', 'HEVC', 'Original audio', 'Multi subs', 'Full season']);

    final c = ReleaseInfo.parse(whomst);
    expect(c.codec, 'AV1');
    expect(c.dualAudio, isTrue);
    expect(c.batch, isTrue, reason: 'S02 without an episode number');

    expect(ReleaseInfo.parse(varyg).dualAudio, isTrue);
  });

  test('a well-seeded original-audio release beats a dub pre-release with more seeders', () {
    final ranked = rankReleases([dubPre, varyg, erai, whomst]);
    expect(ranked.first.result, same(varyg));
    expect(ranked.last.result, same(dubPre));
  });

  test('a seeded single episode beats a season pack with far more seeders', () {
    // Seen on episode 1 of Edgerunners 2: VARYG's 12.8 GB season pack was recommended.
    final single = r('[Onalrie] Cyberpunk Edgerunners 2 - 01 [1080p WEB AV1]', 37);
    expect(rankReleases([varyg, single]).first.result, same(single));
    final dead = r('[Onalrie] Cyberpunk Edgerunners 2 - 01 [1080p WEB AV1]', 1);
    expect(rankReleases([varyg, dead]).first.result, same(varyg));
  });

  test('reads 1440p and 4K releases', () {
    expect(ReleaseInfo.parse(r('[Group] Show - 01 [1440p WEB]', 10)).resolution, '1440');
    expect(ReleaseInfo.parse(r('[Group] Show - 01 [4K HDR]', 10)).resolution, '2160');
    expect(ReleaseInfo.parse(r('[Group] Show S01 UHD BluRay', 10)).resolution, '2160');
  });

  test('seeders map to a health level', () {
    expect(ReleaseInfo.parse(r('a', 50)).health, SeedHealth.good);
    expect(ReleaseInfo.parse(r('a', 49)).health, SeedHealth.fair);
    expect(ReleaseInfo.parse(r('a', 5)).health, SeedHealth.fair);
    expect(ReleaseInfo.parse(r('a', 4)).health, SeedHealth.low);
  });

  test("an extension's own pick is preferred when seeders are close", () {
    final picked = r('[SubsPlease] Show - 01 (1080p) [ABCD].mkv', 300, type: 'best', source: 'Seadex');
    final other = r('[Other] Show - 01 (1080p).mkv', 350);
    expect(rankReleases([other, picked]).first.result, same(picked));
  });
}
