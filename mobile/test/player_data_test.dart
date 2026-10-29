import 'package:flutter_test/flutter_test.dart';
import 'package:nami/aniskip.dart';
import 'package:nami/extensions.dart';

void main() {
  test('AniSkip timings: one opening and one ending, mixed parts ignored', () {
    // Shape of a real answer from api.aniskip.com/v2 (anime 52991, episode 1).
    final skips = AniSkip.parse({
      'found': true,
      'results': [
        {
          'interval': {'startTime': 116.748, 'endTime': 206.748},
          'skipType': 'op',
          'episodeLength': 1510.092,
        },
        {
          'interval': {'startTime': 1417.135, 'endTime': 1507.135},
          'skipType': 'ed',
          'episodeLength': 1510.102,
        },
        {
          'interval': {'startTime': 58.713, 'endTime': 148.713},
          'skipType': 'mixed-op',
          'episodeLength': 1470,
        },
        {
          'interval': {'startTime': 3.2, 'endTime': 93.2},
          'skipType': 'op',
          'episodeLength': 1510,
        },
      ],
    });
    expect(skips.map((s) => s.kind), [SkipKind.opening, SkipKind.ending]);
    expect(skips.first.start, const Duration(milliseconds: 116748));
    expect(skips.first.contains(const Duration(seconds: 150)), isTrue);
    expect(skips.first.contains(const Duration(milliseconds: 206748)), isFalse);
    expect(AniSkip.parse({'found': false, 'results': []}), isEmpty);
  });

  test('repositories on one host read apart', () {
    expect(ExtensionStore.repoLabel('https://exten.pages.dev/index.json'), 'exten.pages.dev');
    expect(ExtensionStore.repoLabel('https://exten.pages.dev/dub/index.json'), 'exten.pages.dev/dub');
    expect(ExtensionStore.repoLabel('https://example.com/repo/'), 'example.com/repo');
  });
}
