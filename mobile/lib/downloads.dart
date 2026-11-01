import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'anilist.dart';
import 'engine.dart';
import 'extensions.dart';
import 'release.dart';
import 'settings.dart';

enum DownloadState { queued, running, paused, failed, done }

/// One episode kept on the device. File names are relative to the downloads
/// folder, whose full path changes when the iPhone app is reinstalled.
class DownloadEntry {
  DownloadEntry({
    required this.media,
    required this.episode,
    this.state = DownloadState.queued,
    this.link,
    this.hash,
    this.fileIndex,
    this.file,
    this.done = 0,
    this.total = 0,
  });

  factory DownloadEntry.fromJson(Map<String, dynamic> j) => DownloadEntry(
    media: Media(Map<String, dynamic>.from(j['media'] as Map)),
    episode: j['episode'],
    state: DownloadState.values.asNameMap()[j['state']] ?? DownloadState.queued,
    link: j['link'],
    hash: j['hash'],
    fileIndex: j['fileIndex'],
    file: j['file'],
    done: j['done'] ?? 0,
    total: j['total'] ?? 0,
  );

  final Media media;
  final int episode;
  DownloadState state;
  String? link;
  String? hash;
  int? fileIndex;
  String? file;
  int done;
  int total;

  /// Live figures of a running download; not saved.
  int speed = 0;
  int peers = 0;

  double get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : 0;

  Map<String, dynamic> toJson() => {
    'media': media.json,
    'episode': episode,
    'state': state.name,
    'link': link,
    'hash': hash,
    'fileIndex': fileIndex,
    'file': file,
    'done': done,
    'total': total,
  };
}

/// The outside world of the store, replaced in tests.
abstract class DownloadBackend {
  Future<List<String>> sources(Media media, int episode);
  Future<EngineTorrent> add(String link, String dir);
  Future<void> keep(String hash, int index);
  Future<void> pause(String hash, int index);
  Future<KeepStats?> stats(String hash, int index);
  Future<void> finish(String hash, int index, String dest);
  Future<void> unkeep(String hash, int index);
  Future<void> saveCover(String url, String dest);
}

class EngineDownloads implements DownloadBackend {
  @override
  Future<List<String>> sources(Media media, int episode) async {
    final found = await SourceSearch.run(media, episode);
    return [for (final r in rankReleases(found.results)) r.result.link];
  }

  @override
  Future<EngineTorrent> add(String link, String dir) => Engine.instance.addKept(link, dir);

  @override
  Future<void> keep(String hash, int index) => Engine.instance.keep(hash, index);

  @override
  Future<void> pause(String hash, int index) => Engine.instance.pause(hash, index);

  @override
  Future<KeepStats?> stats(String hash, int index) => Engine.instance.keepStats(hash, index);

  @override
  Future<void> finish(String hash, int index, String dest) => Engine.instance.finish(hash, index, dest);

  @override
  Future<void> unkeep(String hash, int index) => Engine.instance.unkeep(hash, index);

  @override
  Future<void> saveCover(String url, String dest) async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) await File(dest).writeAsBytes(res.bodyBytes);
  }
}

/// Episodes kept on the device and the queue that fetches them, one at a time.
/// The store is the source of truth: the engine knows nothing of it, and the
/// queue is rebuilt from here at launch.
class Downloads extends ChangeNotifier {
  Downloads({DownloadBackend? backend, Future<void> Function(Duration)? wait})
    : _backend = backend ?? EngineDownloads(),
      _wait = wait ?? Future<void>.delayed;

  static Downloads instance = Downloads();

  /// A download with no new data for this long gives up, so the queue moves on.
  static const stallLimit = Duration(minutes: 10);
  static const _sourceTries = 3;
  static const _prefsKey = 'downloads';

  final DownloadBackend _backend;
  final Future<void> Function(Duration) _wait;

  final List<DownloadEntry> entries = [];
  String root = '';

  /// The torrent the player has open: it cannot be moved or released yet.
  String? Function() playerHash = () => null;

  /// Shows the downloads section; set by the root screen.
  VoidCallback? onOpen;

  DownloadEntry? _running;
  final _waitingForPlayer = <DownloadEntry>{};
  final _releaseLater = <(String, int)>[];

  bool get active => _running != null;

  /// The download to show at the bottom of every screen: the one running,
  /// or else the next in line, or else a paused one.
  DownloadEntry? get current {
    for (final state in [DownloadState.running, DownloadState.queued, DownloadState.paused]) {
      for (final e in entries) {
        if (e.state == state) return e;
      }
    }
    return null;
  }

  /// How many more are in line behind [current].
  int get waiting => entries.where((e) => e.state == DownloadState.queued && e != current).length;

  String get partialDir => '$root${Platform.pathSeparator}partial';

  /// Where a finished episode is, when it can be played.
  String? localPath(int mediaId, int episode) {
    final e = entry(mediaId, episode);
    return e?.state == DownloadState.done ? path(e!) : null;
  }

  String path(DownloadEntry e) => '$root${Platform.pathSeparator}${e.file}';
  String coverPath(int mediaId) => '$root${Platform.pathSeparator}$mediaId.jpg';

  DownloadEntry? entry(int mediaId, int episode) {
    for (final e in entries) {
      if (e.media.id == mediaId && e.episode == episode) return e;
    }
    return null;
  }

  /// Reads the saved entries and picks the queue back up.
  Future<void> load() async {
    if (root.isEmpty) {
      root = '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}downloads';
    }
    Directory(root).createSync(recursive: true);
    final raw = AppSettings.instance.prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        entries.addAll([for (final e in jsonDecode(raw) as List) DownloadEntry.fromJson(e)]);
      } catch (_) {}
    }
    entries.removeWhere((e) => e.state == DownloadState.done && !File(path(e)).existsSync());
    for (final e in entries) {
      if (e.state == DownloadState.running) e.state = DownloadState.queued;
    }
    _save();
    notifyListeners();
    _pump();
  }

  void start(Media media, int episode) {
    if (entry(media.id, episode) != null) return;
    final e = DownloadEntry(media: media, episode: episode);
    entries.add(e);
    _save();
    notifyListeners();
    final cover = media.coverSmall;
    if (cover != null) {
      _backend.saveCover(cover, coverPath(media.id)).catchError((_) {});
    }
    _pump();
  }

  /// Tries the same source first, so what was fetched is not lost.
  void retry(DownloadEntry e) {
    if (e.state != DownloadState.failed) return;
    e.state = DownloadState.queued;
    _retrying.add(e);
    _save();
    notifyListeners();
    _pump();
  }

  final _retrying = <DownloadEntry>{};

  /// What was fetched stays, and the queue moves on to the next episode.
  void pause(DownloadEntry e) {
    if (e.state != DownloadState.running && e.state != DownloadState.queued) return;
    final wasRunning = e.state == DownloadState.running;
    e.state = DownloadState.paused;
    _waitingForPlayer.remove(e);
    _save();
    notifyListeners();
    if (wasRunning) _pauseEngine(e);
  }

  void resume(DownloadEntry e) {
    if (e.state != DownloadState.paused) return;
    e.state = DownloadState.queued;
    _save();
    notifyListeners();
    _pump();
  }

  void _pauseEngine(DownloadEntry e) {
    final hash = e.hash;
    final index = e.fileIndex;
    if (hash != null && index != null) _backend.pause(hash, index).catchError((_) {});
  }

  /// Cancels a download or deletes a finished episode, and whatever it left.
  Future<void> remove(DownloadEntry e) async {
    entries.remove(e);
    _waitingForPlayer.remove(e);
    _save();
    notifyListeners();
    final hash = e.hash;
    final index = e.fileIndex;
    if (e.state == DownloadState.done) {
      _deleteFile(path(e));
    } else if (hash != null && index != null) {
      if (hash == playerHash()) {
        _releaseLater.add((hash, index));
      } else {
        await _release(hash, index);
      }
    }
    if (!entries.any((o) => o.media.id == e.media.id)) _deleteFile(coverPath(e.media.id));
  }

  /// The player opened or closed something: what waited for it can go on.
  void sessionChanged() {
    _waitingForPlayer.clear();
    final later = [..._releaseLater];
    _releaseLater.clear();
    for (final (hash, index) in later) {
      _release(hash, index);
    }
    _pump();
  }

  Future<void> _release(String hash, int index) async {
    try {
      await _backend.unkeep(hash, index);
    } catch (_) {}
    _deletePartial(hash);
  }

  void _deletePartial(String hash) {
    if (entries.any((e) => e.hash == hash && e.state != DownloadState.done)) return;
    try {
      final dir = Directory('$partialDir${Platform.pathSeparator}$hash');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  void _deleteFile(String file) {
    try {
      File(file).deleteSync();
    } catch (_) {}
  }

  void _save() {
    AppSettings.instance.prefs.setString(_prefsKey, jsonEncode([for (final e in entries) e.toJson()]));
  }

  void _pump() {
    if (_running != null) return;
    for (final e in entries) {
      if (e.state == DownloadState.queued && !_waitingForPlayer.contains(e)) {
        _running = e;
        _run(e).whenComplete(() {
          _running = null;
          _pump();
        });
        return;
      }
    }
    notifyListeners();
  }

  Future<void> _run(DownloadEntry e) async {
    e.state = DownloadState.running;
    _save();
    notifyListeners();
    final retrying = _retrying.remove(e);
    try {
      final recovering = e.link != null && !retrying;
      final attached = recovering ? await _reattach(e) : await _attach(e, stored: retrying);
      // Paused while it was still looking for its torrent.
      if (e.state == DownloadState.paused) {
        _pauseEngine(e);
        return;
      }
      if (!attached) {
        _fail(e);
        return;
      }
      if (await _follow(e)) await _finish(e);
    } on EngineBusy {
      // The torrent is playing as a stream; this entry waits for the player to close.
      if (e.state == DownloadState.paused) return;
      e.state = DownloadState.queued;
      _waitingForPlayer.add(e);
      _save();
      notifyListeners();
    } catch (_) {
      _fail(e);
    }
  }

  void _fail(DownloadEntry e) {
    if (!entries.contains(e) || e.state == DownloadState.paused) return;
    e.state = DownloadState.failed;
    _save();
    notifyListeners();
  }

  /// After a restart, only the stored source: others would start from zero.
  /// With no network it fails, so it tries again until the stall limit.
  Future<bool> _reattach(DownloadEntry e) async {
    for (var tries = 0; tries < stallLimit.inMinutes && entries.contains(e); tries++) {
      try {
        await _use(e, e.link!);
        return true;
      } on EngineBusy {
        rethrow;
      } catch (_) {
        await _wait(const Duration(minutes: 1));
      }
    }
    return false;
  }

  Future<bool> _attach(DownloadEntry e, {required bool stored}) async {
    if (stored && e.link != null) {
      try {
        await _use(e, e.link!);
        return true;
      } on EngineBusy {
        rethrow;
      } catch (_) {}
    }
    final List<String> links;
    try {
      links = await _backend.sources(e.media, e.episode);
    } catch (_) {
      return false;
    }
    for (final link in links.take(_sourceTries)) {
      try {
        await _use(e, link);
        return true;
      } on EngineBusy {
        rethrow;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _use(DownloadEntry e, String link) async {
    final t = await _backend.add(link, partialDir);
    final file = Engine.pick(t.files, e.episode);
    if (file == null) {
      await _release(t.hash, -1);
      throw EngineException('no file for this episode');
    }
    await _backend.keep(t.hash, file.index);
    final previous = e.hash;
    e
      ..link = link
      ..hash = t.hash
      ..fileIndex = file.index
      ..total = file.length
      ..file = '${e.media.id}-${e.episode}${_extension(file.name)}';
    _save();
    if (previous != null && previous != t.hash) _deletePartial(previous);
  }

  String _extension(String name) => name.contains('.') ? '.${name.split('.').last}' : '';

  /// Follows the file until it is complete; false if it stalled or was removed.
  /// Seconds are counted, not read from the clock: a suspended app must not stall.
  Future<bool> _follow(DownloadEntry e) async {
    var quiet = 0;
    var last = -1;
    while (entries.contains(e) && e.state == DownloadState.running) {
      await _wait(const Duration(seconds: 1));
      if (!entries.contains(e) || e.state != DownloadState.running) return false;
      quiet++;
      final s = await _backend.stats(e.hash!, e.fileIndex!);
      if (s != null) {
        e
          ..speed = last < 0 ? 0 : (s.done - last).clamp(0, s.total)
          ..peers = s.peers
          ..done = s.done
          ..total = s.total;
        if (s.total > 0 && s.done == s.total) return true;
        if (s.done > last) {
          last = s.done;
          quiet = 0;
        }
        notifyListeners();
      }
      if (quiet >= stallLimit.inSeconds) {
        _save();
        _fail(e);
        return false;
      }
    }
    return false;
  }

  Future<void> _finish(DownloadEntry e) async {
    while (e.hash == playerHash()) {
      await _wait(const Duration(seconds: 1));
      if (!entries.contains(e)) return;
    }
    await _backend.finish(e.hash!, e.fileIndex!, path(e));
    e.state = DownloadState.done;
    _deletePartial(e.hash!);
    _save();
    notifyListeners();
  }
}
