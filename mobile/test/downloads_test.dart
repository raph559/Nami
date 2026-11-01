import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/downloads.dart';
import 'package:nami/engine.dart';
import 'package:nami/extensions.dart';
import 'package:nami/release.dart';
import 'package:nami/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media anime(int id) => Media({
  'id': id,
  'title': {'romaji': 'Anime $id'},
  'episodes': 12,
  'coverImage': {'large': 'https://x/$id.jpg'},
});

const size = 1000;

class FakeBackend implements DownloadBackend {
  FakeBackend();

  /// Links offered for any episode.
  List<String> links = ['good'];
  final added = <String>[];
  final kept = <String>[];
  final finished = <String>[];
  final unkept = <String>[];
  final paused = <String>[];
  final covers = <String>[];

  /// Bytes reported for each hash; a hash at `size` is complete.
  final progress = <String, int>{};
  final badLinks = <String>{};
  final busyLinks = <String>{};
  List<EngineFile> Function(String link) filesFor = (_) => [EngineFile(0, 'ep.mkv', size)];

  @override
  Future<List<String>> sources(Media media, int episode, String resolution) async {
    asked.add(resolution);
    if (problem != null) throw problem!;
    return links;
  }

  DownloadProblem? problem;
  bool finishFails = false;

  @override
  Future<SourceQualities> qualities(Media media, int episode) async {
    if (problem != null) throw problem!;
    return (qualities: const ['1080'], problem: null, noSources: false);
  }

  final asked = <String>[];
  final limits = <int>[];

  @override
  Future<void> limit(int bytesPerSecond) async => limits.add(bytesPerSecond);

  @override
  Future<EngineTorrent> add(String link, String dir) async {
    added.add(link);
    if (busyLinks.contains(link)) throw EngineBusy('busy');
    if (badLinks.contains(link)) throw EngineException('dead');
    return EngineTorrent('hash-$link', link, filesFor(link));
  }

  @override
  Future<void> keep(String hash, int index) async => kept.add('$hash/$index');

  @override
  Future<void> pause(String hash, int index) async => paused.add('$hash/$index');

  @override
  Future<KeepStats?> stats(String hash, int index) async => KeepStats({'done': progress[hash] ?? 0, 'total': size});

  @override
  Future<void> finish(String hash, int index, String dest) async {
    if (finishFails) throw EngineException('disk full');
    finished.add(hash);
    File(dest).writeAsStringSync('video');
  }

  @override
  Future<void> unkeep(String hash, int index) async => unkept.add('$hash/$index');

  @override
  Future<void> saveCover(String url, String dest) async => covers.add(url);
}

void main() {
  late Directory root;
  late FakeBackend backend;
  late Downloads store;
  late DateTime clock;

  /// Each wait moves the clock and lets the store go on.
  Future<void> wait(Duration d) async {
    clock = clock.add(d);
    await Future<void>.delayed(Duration.zero);
  }

  Downloads newStore() => Downloads(backend: backend, wait: wait)..root = root.path;

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
    root = Directory.systemTemp.createTempSync('nami-downloads');
    addTearDown(() => root.deleteSync(recursive: true));
    backend = FakeBackend();
    clock = DateTime(2026, 11, 1);
    store = newStore();
  });

  test('an entry survives a JSON round trip', () {
    final e = DownloadEntry(
      media: anime(1),
      episode: 3,
      state: DownloadState.done,
      link: 'l',
      hash: 'h',
      fileIndex: 2,
      file: '1-3.mkv',
      done: 5,
      total: 9,
    );
    final back = DownloadEntry.fromJson(jsonDecode(jsonEncode(e.toJson())));
    expect(back.media.id, 1);
    expect(back.episode, 3);
    expect(back.state, DownloadState.done);
    expect((back.link, back.hash, back.fileIndex, back.file, back.done, back.total), ('l', 'h', 2, '1-3.mkv', 5, 9));
  });

  test('a download runs to the end and stores a path relative to the folder', () async {
    backend.progress['hash-good'] = size;
    store.start(anime(1), 3);
    await settle();
    final e = store.entry(1, 3)!;
    expect(e.state, DownloadState.done);
    expect(e.file, '1-3.mkv');
    expect(store.localPath(1, 3), '${root.path}${Platform.pathSeparator}1-3.mkv');
    expect(File(store.localPath(1, 3)!).existsSync(), isTrue);
    expect(backend.covers, ['https://x/1.jpg']);
    final saved = File('${root.path}${Platform.pathSeparator}downloads.json');
    expect(jsonDecode(saved.readAsStringSync()).single['file'], '1-3.mkv');
  });

  test('one download at a time, in order', () async {
    store.start(anime(1), 1);
    store.start(anime(1), 2);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.running);
    expect(store.entry(1, 2)!.state, DownloadState.queued);
    backend.progress['hash-good'] = size;
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.done);
    expect(store.entry(1, 2)!.state, DownloadState.done);
  });

  test('tries the first three sources', () async {
    backend.links = ['a', 'b', 'c', 'd'];
    backend.badLinks.addAll(['a', 'b', 'c']);
    store.start(anime(1), 1);
    await settle();
    expect(backend.added, ['a', 'b', 'c']);
    expect(store.entry(1, 1)!.state, DownloadState.failed);
  });

  test('a source without the episode is released and the next one is tried', () async {
    backend.links = ['pack', 'single'];
    backend.filesFor = (link) => link == 'pack'
        ? [EngineFile(0, 'Show - 01.mkv', size), EngineFile(1, 'Show - 02.mkv', size)]
        : [EngineFile(0, 'ep.mkv', size)];
    store.start(anime(1), 5);
    await settle();
    expect(backend.unkept, ['hash-pack/-1']);
    expect(store.entry(1, 5)!.link, 'single');
  });

  test('a pack only keeps the file of the episode', () async {
    backend.filesFor = (_) => [EngineFile(0, 'Show - 01.mkv', size), EngineFile(1, 'Show - 02.mkv', size)];
    store.start(anime(1), 2);
    await settle();
    expect(backend.kept, ['hash-good/1']);
  });

  test('no source fails and the queue moves on', () async {
    backend.links = [];
    store.start(anime(1), 1);
    await settle();
    backend.links = ['good'];
    store.start(anime(1), 2);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.failed);
    expect(store.entry(1, 2)!.state, DownloadState.running);
  });

  test('ten minutes with no new data fails and the queue moves on', () async {
    store.start(anime(1), 1);
    store.start(anime(1), 2);
    for (var i = 0; i < 40 && store.entry(1, 1)!.state != DownloadState.failed; i++) {
      await settle();
    }
    expect(store.entry(1, 1)!.state, DownloadState.failed);
    expect(clock.difference(DateTime(2026, 11, 1)) >= Downloads.stallLimit, isTrue);
    expect(store.entry(1, 2)!.state, isNot(DownloadState.queued));
  });

  test('new data pushes the stall limit back', () async {
    store.start(anime(1), 1);
    final bytes = Timer.periodic(Duration.zero, (_) => backend.progress['hash-good'] = (clock.minute + 1) * 10);
    addTearDown(bytes.cancel);
    for (var i = 0; i < 80; i++) {
      await settle();
    }
    expect(store.entry(1, 1)!.state, DownloadState.running);
  });

  test('a stream of the same torrent makes the entry wait, then the queue goes on', () async {
    backend.busyLinks.add('good');
    store.start(anime(1), 1);
    await settle();
    expect(backend.added, ['good']);
    expect(store.entry(1, 1)!.state, DownloadState.queued);
    backend.busyLinks.clear();
    backend.progress['hash-good'] = size;
    store.sessionChanged();
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.done);
  });

  test('a waiting entry does not block the next one', () async {
    backend.busyLinks.add('good');
    store.start(anime(1), 1);
    await settle();
    backend.links = ['other'];
    store.start(anime(1), 2);
    await settle();
    expect(store.entry(1, 2)!.state, DownloadState.running);
  });

  test('finishing waits while the player has the torrent open', () async {
    var playing = true;
    store.playerHash = () => playing ? 'hash-good' : null;
    backend.progress['hash-good'] = size;
    store.start(anime(1), 1);
    await settle();
    expect(backend.finished, isEmpty);
    expect(store.entry(1, 1)!.state, DownloadState.running);
    playing = false;
    await settle();
    expect(backend.finished, ['hash-good']);
  });

  test('at launch a running entry goes on from its stored source', () async {
    backend.links = ['other'];
    AppSettings.instance.prefs.setString(
      'downloads',
      jsonEncode([
        DownloadEntry(
          media: anime(1),
          episode: 1,
          state: DownloadState.running,
          link: 'good',
          hash: 'hash-good',
          fileIndex: 0,
        ).toJson(),
      ]),
    );
    await store.load();
    await settle();
    expect(backend.added.first, 'good');
    expect(backend.added, isNot(contains('other')));
    expect(store.entry(1, 1)!.state, DownloadState.running);
  });

  test('at launch with no network the stored source is tried each minute, then gives up', () async {
    backend.badLinks.add('good');
    AppSettings.instance.prefs.setString(
      'downloads',
      jsonEncode([
        DownloadEntry(media: anime(1), episode: 1, state: DownloadState.running, link: 'good').toJson(),
      ]),
    );
    await store.load();
    await settle();
    expect(backend.added.length, 10);
    expect(store.entry(1, 1)!.state, DownloadState.failed);
  });

  test('at launch a finished episode whose file vanished is forgotten', () async {
    File('${root.path}${Platform.pathSeparator}1-2.mkv').writeAsStringSync('video');
    AppSettings.instance.prefs.setString(
      'downloads',
      jsonEncode([
        DownloadEntry(media: anime(1), episode: 1, state: DownloadState.done, file: '1-1.mkv').toJson(),
        DownloadEntry(media: anime(1), episode: 2, state: DownloadState.done, file: '1-2.mkv').toJson(),
      ]),
    );
    await store.load();
    expect(store.entry(1, 1), isNull);
    expect(store.entry(1, 2), isNotNull);
  });

  test('retry tries the stored source before searching', () async {
    backend.badLinks.add('good');
    store.start(anime(1), 1);
    await settle();
    final e = store.entry(1, 1)!;
    expect(e.state, DownloadState.failed);
    e.link = 'good';
    backend.badLinks.clear();
    backend.added.clear();
    store.retry(e);
    await settle();
    expect(backend.added, ['good']);
  });

  test('retry falls back on a new search', () async {
    backend.badLinks.add('dead');
    backend.links = ['dead'];
    store.start(anime(1), 1);
    await settle();
    final e = store.entry(1, 1)!;
    e.link = 'dead';
    backend.links = ['fresh'];
    store.retry(e);
    await settle();
    expect(e.link, 'fresh');
  });

  test('removing a running download releases it and removes its partial data', () async {
    store.start(anime(1), 1);
    await settle();
    final partial = Directory('${store.partialDir}${Platform.pathSeparator}hash-good')..createSync(recursive: true);
    await store.remove(store.entry(1, 1)!);
    expect(backend.unkept, ['hash-good/0']);
    expect(partial.existsSync(), isFalse);
    expect(store.entries, isEmpty);
  });

  test('partial data shared with another episode stays', () async {
    backend.filesFor = (_) => [EngineFile(0, 'Show - 01.mkv', size), EngineFile(1, 'Show - 02.mkv', size)];
    store.start(anime(1), 1);
    await settle();
    final first = store.entry(1, 1)!;
    first.state = DownloadState.failed;
    store.entries.add(
      DownloadEntry(media: anime(1), episode: 2, state: DownloadState.failed, hash: first.hash, fileIndex: 1),
    );
    final partial = Directory('${store.partialDir}${Platform.pathSeparator}hash-good')..createSync(recursive: true);
    await store.remove(first);
    expect(partial.existsSync(), isTrue);
  });

  test('removing a download the player has open waits for the player', () async {
    store.start(anime(1), 1);
    await settle();
    var playing = true;
    store.playerHash = () => playing ? 'hash-good' : null;
    await store.remove(store.entry(1, 1)!);
    expect(backend.unkept, isEmpty);
    playing = false;
    store.sessionChanged();
    await settle();
    expect(backend.unkept, ['hash-good/0']);
  });

  test('deleting one episode keeps the others and their cover', () async {
    backend.progress['hash-good'] = size;
    store.start(anime(1), 1);
    store.start(anime(1), 2);
    await settle();
    final cover = File(store.coverPath(1))..writeAsStringSync('x');
    final firstFile = File(store.path(store.entry(1, 1)!));
    await store.remove(store.entry(1, 1)!);
    expect(firstFile.existsSync(), isFalse);
    expect(File(store.path(store.entry(1, 2)!)).existsSync(), isTrue);
    expect(cover.existsSync(), isTrue);
    await store.remove(store.entry(1, 2)!);
    expect(cover.existsSync(), isFalse);
  });

  test('pausing keeps the data, moves the queue on, and resuming goes on', () async {
    store.start(anime(1), 1);
    await settle();
    backend.links = ['other'];
    store.start(anime(1), 2);
    await settle();
    final first = store.entry(1, 1)!;
    store.pause(first);
    await settle();
    expect(first.state, DownloadState.paused);
    expect(backend.paused, ['hash-good/0']);
    expect(backend.unkept, isEmpty);
    expect(store.entry(1, 2)!.state, DownloadState.running);
    backend.progress['hash-other'] = size;
    await settle();
    backend.progress['hash-good'] = size;
    backend.added.clear();
    store.resume(first);
    await settle();
    expect(backend.added, ['good']);
    expect(first.state, DownloadState.done);
  });

  test('a paused download never stalls', () async {
    store.start(anime(1), 1);
    await settle();
    store.pause(store.entry(1, 1)!);
    for (var i = 0; i < 40; i++) {
      await settle();
    }
    expect(store.entry(1, 1)!.state, DownloadState.paused);
  });

  test('a waiting download can be paused before it starts', () async {
    store.start(anime(1), 1);
    store.start(anime(1), 2);
    await settle();
    final second = store.entry(1, 2)!;
    store.pause(second);
    backend.progress['hash-good'] = size;
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.done);
    expect(second.state, DownloadState.paused);
    expect(backend.paused, isEmpty);
  });

  test('a paused download stays paused after a restart', () async {
    AppSettings.instance.prefs.setString(
      'downloads',
      jsonEncode([
        DownloadEntry(media: anime(1), episode: 1, state: DownloadState.paused, link: 'good').toJson(),
      ]),
    );
    await store.load();
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.paused);
    expect(backend.added, isEmpty);
  });

  test('removing a paused download releases its data', () async {
    store.start(anime(1), 1);
    await settle();
    final e = store.entry(1, 1)!;
    store.pause(e);
    await settle();
    await store.remove(e);
    expect(backend.unkept, ['hash-good/0']);
  });

  test('the bar shows what runs, then what waits, then what is paused', () async {
    store.start(anime(1), 1);
    store.start(anime(1), 2);
    store.start(anime(1), 3);
    await settle();
    expect(store.current?.episode, 1);
    expect(store.waiting, 2);
    store.pause(store.entry(1, 1)!);
    store.pause(store.entry(1, 2)!);
    store.pause(store.entry(1, 3)!);
    await settle();
    expect(store.current?.state, DownloadState.paused);
    expect(store.waiting, 0);
  });

  test('the quality asked for is the one searched, then the setting', () async {
    AppSettings.instance.downloadResolution = '720';
    store.start(anime(1), 1, resolution: '480');
    await settle();
    backend.progress['hash-good'] = size;
    store.start(anime(1), 2);
    await settle();
    expect(backend.asked, ['480', '720']);
  });

  test('download quality falls back on the streaming quality', () {
    AppSettings.instance.resolution = '720';
    expect(AppSettings.instance.downloadResolution, '720');
    AppSettings.instance.downloadResolution = '480';
    expect(AppSettings.instance.resolution, '720');
  });

  test('a source picked by hand is used without searching', () async {
    store.start(anime(1), 1, link: 'mine');
    await settle();
    expect(backend.added, ['mine']);
    expect(backend.asked, isEmpty);
  });

  test('a season adds every missing aired episode', () async {
    final airing = Media({...anime(1).json, 'nextAiringEpisode': {'episode': 5, 'airingAt': 1}});
    store.start(airing, 2);
    await settle();
    expect(store.missing(airing), [1, 3, 4]);
    store.startSeason(airing, resolution: '720');
    expect(store.missing(airing), isEmpty);
    expect(store.entries.map((e) => e.episode), [2, 1, 3, 4]);
    expect(store.entry(1, 4)!.resolution, '720');
  });

  test('changing the quality deletes the file and downloads again', () async {
    backend.progress['hash-good'] = size;
    store.start(anime(1), 1, resolution: '1080');
    await settle();
    final old = File(store.localPath(1, 1)!);
    backend.progress.clear();
    await store.changeQuality(store.entry(1, 1)!, '480');
    await settle();
    expect(old.existsSync(), isFalse);
    expect(store.entry(1, 1)!.state, DownloadState.running);
    expect(store.entry(1, 1)!.resolution, '480');
    expect(backend.asked.last, '480');
  });

  test('the queue can be reordered, around what is not waiting', () async {
    store.start(anime(1), 1);
    store.start(anime(1), 2);
    store.start(anime(1), 3);
    store.start(anime(1), 4);
    await settle();
    store.pause(store.entry(1, 3)!);
    await settle();
    expect(store.queue.map((e) => e.episode), [2, 4]);
    store.reorder(1, 0);
    expect(store.entries.map((e) => e.episode), [1, 4, 3, 2]);
    expect(store.queue.map((e) => e.episode), [4, 2]);
    final saved = File('${root.path}${Platform.pathSeparator}downloads.json');
    expect((jsonDecode(saved.readAsStringSync()) as List).map((e) => e['episode']), [1, 4, 3, 2]);
  });

  test('any speed limit can be typed', () {
    expect(parseSpeedLimit('2.5'), 2500000);
    expect(parseSpeedLimit('2,5'), 2500000);
    expect(parseSpeedLimit(' 7 '), 7000000);
    expect(parseSpeedLimit('0.3'), 300000);
    expect(parseSpeedLimit(''), 0);
    expect(parseSpeedLimit('0'), 0);
    expect(parseSpeedLimit('-3'), 0);
    expect(parseSpeedLimit('abc'), 0);
    expect(speedLimitText(2500000), '2.5');
    expect(speedLimitText(7000000), '7');
    expect(speedLimitText(0), '');
  });

  test('pause all and resume all', () async {
    store.start(anime(1), 1);
    store.start(anime(1), 2);
    await settle();
    expect(store.canPauseAll, isTrue);
    expect(store.canResumeAll, isFalse);
    store.pauseAll();
    await settle();
    expect(store.entries.every((e) => e.state == DownloadState.paused), isTrue);
    expect(store.canPauseAll, isFalse);
    store.resumeAll();
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.running);
    expect(store.entry(1, 2)!.state, DownloadState.queued);
  });

  test('Wi-Fi only holds the queue on mobile data and picks up on Wi-Fi', () async {
    AppSettings.instance.downloadWifiOnly = true;
    store.networkChanged(cellular: true);
    store.start(anime(1), 1);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.queued);
    expect(backend.added, isEmpty);
    store.networkChanged(cellular: false);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.running);
  });

  test('leaving Wi-Fi puts a running download back in line', () async {
    AppSettings.instance.downloadWifiOnly = true;
    store.start(anime(1), 1);
    await settle();
    store.networkChanged(cellular: true);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.queued);
    expect(backend.paused, ['hash-good/0']);
    store.networkChanged(cellular: false);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.running);
  });

  test('without the setting mobile data changes nothing', () async {
    store.networkChanged(cellular: true);
    store.start(anime(1), 1);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.running);
  });

  test('at launch partial data nothing needs is removed', () async {
    final keep = Directory('${store.partialDir}${Platform.pathSeparator}hash-keep')..createSync(recursive: true);
    final old = Directory('${store.partialDir}${Platform.pathSeparator}hash-old')..createSync(recursive: true);
    AppSettings.instance.prefs.setString(
      'downloads',
      jsonEncode([
        DownloadEntry(media: anime(1), episode: 1, state: DownloadState.paused, link: 'l', hash: 'hash-keep').toJson(),
      ]),
    );
    await store.load();
    expect(keep.existsSync(), isTrue);
    expect(old.existsSync(), isFalse);
  });

  test('the speed limit reaches the engine', () async {
    AppSettings.instance.downloadLimit = 2000000;
    await store.load();
    expect(backend.limits, [2000000]);
  });

  test('the time left comes from a smoothed speed', () async {
    var done = 0;
    final s = store;
    backend.progress['hash-good'] = 0;
    s.start(anime(1), 1);
    await settle();
    final e = s.entry(1, 1)!;
    expect(e.remaining, isNull);
    e
      ..speed = 2048
      ..done = 0
      ..total = 2048 * 60;
    done = e.remaining!.inSeconds;
    expect(done, 60);
    e.speed = 100;
    expect(e.remaining, isNull);
  });

  test('a list saved in the preferences by an older version is picked up', () async {
    AppSettings.instance.prefs.setString(
      'downloads',
      jsonEncode([DownloadEntry(media: anime(1), episode: 1, state: DownloadState.paused).toJson()]),
    );
    await store.load();
    expect(store.entry(1, 1), isNotNull);
    expect(File('${root.path}${Platform.pathSeparator}downloads.json').existsSync(), isTrue);
    final next = newStore();
    AppSettings.instance.prefs.remove('downloads');
    await next.load();
    expect(next.entry(1, 1), isNotNull);
  });

  test('a failure says why and tells the app', () async {
    final failed = <String?>[];
    store.onFailed = (e) => failed.add(e.error);
    backend.links = [];
    store.start(anime(1), 1);
    await settle();
    expect(store.entry(1, 1)!.error, 'Aucune source trouvée pour cet épisode.');
    expect(failed, ['Aucune source trouvée pour cet épisode.']);
  });

  test('the reason from the search reaches the viewer', () async {
    backend.problem = DownloadProblem('Aucune source installée.');
    store.start(anime(1), 1);
    await settle();
    expect(store.entry(1, 1)!.error, 'Aucune source installée.');
  });

  test('a dead torrent explains itself', () async {
    backend.badLinks.add('good');
    store.start(anime(1), 1);
    await settle();
    expect(store.entry(1, 1)!.error, contains('dead'));
  });

  test('a source without the episode says so', () async {
    backend.filesFor = (_) => [EngineFile(0, 'Show - 01.mkv', size), EngineFile(1, 'Show - 02.mkv', size)];
    store.start(anime(1), 5);
    await settle();
    expect(store.entry(1, 5)!.error, 'Cette source ne contient pas cet épisode.');
  });

  test('a stall says so, and retrying clears the reason', () async {
    store.start(anime(1), 1);
    for (var i = 0; i < 40 && store.entry(1, 1)!.state != DownloadState.failed; i++) {
      await settle();
    }
    final e = store.entry(1, 1)!;
    expect(e.error, contains('10 minutes'));
    store.retry(e);
    expect(e.error, isNull);
  });

  test('a file that cannot be moved says why', () async {
    backend.finishFails = true;
    backend.progress['hash-good'] = size;
    store.start(anime(1), 1);
    await settle();
    expect(store.entry(1, 1)!.state, DownloadState.failed);
    expect(store.entry(1, 1)!.error, contains('disk full'));
  });

  test('qualities come from the release names, highest first', () {
    TorrentResult named(String title) => TorrentResult({'title': title, 'link': title}, 'test');
    final found = qualitiesIn(
      [
        named('[A] Show - 01 [1080p]'),
        named('[B] Show - 01 (2160p)'),
        named('[C] Show - 01 720p'),
        named('[D] Show - 01 [1080p] again'),
        named('[E] Show - 01'),
      ].map(ReleaseInfo.parse),
    );
    expect(found, ['2160', '1080', '720']);
  });

  test('sources that cannot answer give no list', () async {
    expect((await store.qualities(anime(1), 1)).qualities, ['1080']);
    backend.problem = DownloadProblem('no');
    final answer = await store.qualities(anime(1), 1);
    expect(answer.qualities, isEmpty);
    expect(answer.problem, isNull);
  });

  test('starting an episode twice does nothing', () async {
    store.start(anime(1), 1);
    store.start(anime(1), 1);
    await settle();
    expect(store.entries.length, 1);
  });
}
