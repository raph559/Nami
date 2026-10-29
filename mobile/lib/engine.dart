import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'settings.dart';

class EngineFile {
  EngineFile(this.index, this.path, this.length);
  final int index;
  final String path;
  final int length;

  String get name => path.split(RegExp(r'[/\\]')).last;
  bool get isVideo => const {
    'mkv',
    'mp4',
    'avi',
    'webm',
    'm4v',
    'mov',
    'ts',
  }.contains(name.contains('.') ? name.split('.').last.toLowerCase() : '');
}

class EngineTorrent {
  EngineTorrent(this.hash, this.name, this.files);
  final String hash;
  final String name;
  final List<EngineFile> files;
}

class EngineStats {
  EngineStats(Map<String, dynamic> j)
    : peers = j['peers'] ?? 0,
      downloaded = j['downloaded'] ?? 0,
      total = j['total'] ?? 0;
  final int peers;
  final int downloaded;
  final int total;
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef _StartNative = Int32 Function(Pointer<Utf8>);
typedef _StartDart = int Function(Pointer<Utf8>);

/// Client for the embedded Go torrent engine (nami_engine), which serves a
/// small HTTP API on 127.0.0.1.
class Engine {
  Engine._();
  static final instance = Engine._();

  int _port = -1;
  Future<int>? _starting;

  static DynamicLibrary _open() {
    if (Platform.isWindows) return DynamicLibrary.open('nami_engine.dll');
    if (Platform.isAndroid) return DynamicLibrary.open('libnami_engine.so');
    // iOS links the engine statically into the app.
    return DynamicLibrary.process();
  }

  Future<int> start() {
    if (_port > 0) return Future.value(_port);
    return _starting ??= () async {
      final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}nami-torrents');
      // Nothing is kept between launches.
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      final start = _open().lookupFunction<_StartNative, _StartDart>('NamiStart');
      final path = dir.path.toNativeUtf8();
      try {
        _port = start(path);
      } finally {
        malloc.free(path);
      }
      if (_port <= 0) throw EngineException(t("Le moteur torrent n'a pas démarré", 'The torrent engine did not start'));
      return _port;
    }();
  }

  Future<Uri> _url(String path) async => Uri.parse('http://127.0.0.1:${await start()}/$path');

  Future<dynamic> _call(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final url = await _url(path);
    final res =
        await (body == null
                ? http.post(url)
                : http.post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)))
            .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = 'HTTP ${res.statusCode}';
      try {
        message = (jsonDecode(res.body) as Map)['error'] ?? message;
      } catch (_) {}
      throw EngineException(message);
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<EngineTorrent> add(String link) async {
    final j = await _call('add', body: {'uri': link}, timeout: const Duration(seconds: 100)) as Map<String, dynamic>;
    return EngineTorrent(j['hash'], j['name'] ?? '', [
      for (final f in j['files'] as List) EngineFile(f['index'], f['path'], f['length']),
    ]);
  }

  Future<EngineStats?> stats(String hash) async {
    try {
      final res = await http.get(await _url('stats/$hash')).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 ? EngineStats(jsonDecode(res.body)) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> drop(String hash) async {
    try {
      await _call('drop/$hash');
    } catch (_) {}
  }

  Future<String> streamUrl(String hash, EngineFile file) async => (await _url('stream/$hash/${file.index}')).toString();

  /// Picks the file for an episode: the only video, or the one whose name
  /// carries the episode number in a batch.
  static EngineFile? pick(List<EngineFile> files, int episode) {
    final videos = files.where((f) => f.isVideo).toList();
    if (videos.length <= 1) {
      if (videos.isNotEmpty) return videos.first;
      if (files.isEmpty) return null;
      return files.reduce((a, b) => a.length >= b.length ? a : b);
    }
    final matches = videos.where((f) => episodeNumber(f.name) == episode).toList();
    if (matches.isEmpty) return null;
    return matches.reduce((a, b) => a.length >= b.length ? a : b);
  }

  static int? episodeNumber(String name) {
    var s = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    // Drop bracketed tags, resolutions, years and codecs before looking.
    for (final p in [
      r'\[[^\]]*\]',
      r'\([^)]*\)',
      r'\b\d{3,4}[pP]\b',
      r'\b(19|20)\d{2}\b',
      r'\b(?:[xXhH])\.?26[45]\b',
      r'\b[sS]\d{1,2}\b',
    ]) {
      s = s.replaceAll(RegExp(p), ' ');
    }
    for (final p in [
      r'[sS]\d{1,2}[eE](\d{1,4})',
      r'\b[eE][pP]?\.?\s?(\d{1,4})\b',
      r'\s-\s(\d{1,4})(?:v\d)?\b',
      r'\b(\d{1,4})(?:v\d)?\b',
    ]) {
      final m = RegExp(p).firstMatch(s);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }
}
