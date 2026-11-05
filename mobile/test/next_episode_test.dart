import 'package:flutter_test/flutter_test.dart';
import 'package:nami/aniskip.dart';
import 'package:nami/playback.dart';

void main() {
  const length = Duration(minutes: 24);
  final ending = SkipInterval(SkipKind.ending, const Duration(minutes: 21), const Duration(minutes: 22, seconds: 30));
  final opening = SkipInterval(SkipKind.opening, const Duration(minutes: 1), const Duration(minutes: 2, seconds: 30));

  test('from the start of the ending when AniSkip knows it', () {
    expect(atEpisodeEnd(const Duration(minutes: 20, seconds: 59), length, [opening, ending]), isFalse);
    expect(atEpisodeEnd(const Duration(minutes: 21), length, [opening, ending]), isTrue);
    // Still after it: the preview of the next episode.
    expect(atEpisodeEnd(const Duration(minutes: 23), length, [opening, ending]), isTrue);
  });

  test('otherwise the last 90 seconds', () {
    expect(atEpisodeEnd(const Duration(minutes: 22, seconds: 29), length, [opening]), isFalse);
    expect(atEpisodeEnd(const Duration(minutes: 22, seconds: 30), length, [opening]), isTrue);
  });

  test('once it has ended, and never before the length is known', () {
    expect(atEpisodeEnd(Duration.zero, length, const [], ended: true), isTrue);
    expect(atEpisodeEnd(const Duration(seconds: 10), Duration.zero, const []), isFalse);
  });

  test('a short video only near its very end', () {
    const short = Duration(minutes: 3);
    expect(atEpisodeEnd(const Duration(minutes: 2), short, const []), isFalse);
    expect(atEpisodeEnd(const Duration(minutes: 2, seconds: 45), short, const []), isTrue);
  });
}
