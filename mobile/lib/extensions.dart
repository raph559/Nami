import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import 'anilist.dart';
import 'mappings.dart';
import 'settings.dart';

// Source extensions use the same format as Hayase's: a repository index.json
// lists manifests, each pointing at an ES module whose default export has
// single/batch/movie(query, options) methods returning torrent results.

class ExtensionManifest {
  ExtensionManifest(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'];
  String get name => json['name'] ?? id;
  String? get version => json['version'];
  String? get media => json['media'];
  String? get icon => json['icon'];
  String get code => json['code'];
  Map<String, dynamic> get options => (json['options'] as Map<String, dynamic>?) ?? const {};
  bool get isSupported => (json['type'] ?? 'torrent') == 'torrent';
}

class InstalledExtension {
  InstalledExtension(this.repo, this.manifest, this.enabled, this.options);

  final String repo;
  ExtensionManifest manifest;
  bool enabled;
  final Map<String, dynamic> options;

  String get id => '$repo#${manifest.id}';

  Map<String, dynamic> get resolvedOptions => {
        for (final e in manifest.options.entries)
          if ((options[e.key] ?? (e.value as Map)['default']) != null) e.key: options[e.key] ?? (e.value as Map)['default'],
      };

  Map<String, dynamic> toJson() => {'repo': repo, 'manifest': manifest.json, 'enabled': enabled, 'options': options};

  factory InstalledExtension.fromJson(Map<String, dynamic> j) => InstalledExtension(
      j['repo'], ExtensionManifest(j['manifest']), j['enabled'] ?? true, Map<String, dynamic>.from(j['options'] ?? {}));
}

class TorrentResult {
  TorrentResult(this.json, this.source);
  final Map<String, dynamic> json;
  final String source;

  String get title => json['title']?.toString() ?? t('Sans titre', 'Untitled');
  String get link => json['link'].toString();
  String? get hash => json['hash']?.toString();
  double? get size => (json['size'] as num?)?.toDouble();
  int get seeders => (json['seeders'] as num?)?.toInt() ?? 0;
  bool get isBest => json['type'] == 'best';
  String get key => (hash ?? link).toLowerCase();
}

class ExtensionStore extends ChangeNotifier {
  ExtensionStore._() {
    final prefs = AppSettings.instance.prefs;
    repos = prefs.getStringList('extensionRepos') ?? [];
    final raw = prefs.getString('installedExtensions');
    if (raw != null) {
      installed = [for (final e in jsonDecode(raw) as List) InstalledExtension.fromJson(e)];
    }
  }
  static final instance = ExtensionStore._();

  List<String> repos = [];
  List<InstalledExtension> installed = [];

  List<InstalledExtension> get enabled => installed.where((e) => e.enabled && e.manifest.isSupported).toList();

  void _save() {
    final prefs = AppSettings.instance.prefs;
    prefs.setStringList('extensionRepos', repos);
    prefs.setString('installedExtensions', jsonEncode([for (final e in installed) e.toJson()]));
    notifyListeners();
  }

  Future<List<ExtensionManifest>> _fetchIndex(String repo) async {
    final res = await http.get(Uri.parse(repo));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return [for (final m in jsonDecode(res.body) as List) ExtensionManifest(m as Map<String, dynamic>)];
  }

  Future<void> addRepo(String raw) async {
    final repo = raw.trim();
    final manifests = await _fetchIndex(repo);
    if (!repos.contains(repo)) repos.add(repo);
    _merge(repo, manifests);
  }

  void removeRepo(String repo) {
    repos.remove(repo);
    installed.removeWhere((e) => e.repo == repo);
    _save();
  }

  /// Refreshes every repository so extensions pick up new versions.
  Future<void> refresh() async {
    for (final repo in List.of(repos)) {
      try {
        _merge(repo, await _fetchIndex(repo));
      } catch (_) {}
    }
  }

  void _merge(String repo, List<ExtensionManifest> manifests) {
    for (final m in manifests) {
      final existing = installed.where((e) => e.repo == repo && e.manifest.id == m.id).firstOrNull;
      if (existing != null) {
        existing.manifest = m;
      } else {
        installed.add(InstalledExtension(repo, m, m.isSupported, {}));
      }
    }
    _save();
  }

  void setEnabled(InstalledExtension ext, bool on) {
    ext.enabled = on;
    _save();
  }

  void setOption(InstalledExtension ext, String key, dynamic value) {
    ext.options[key] = value;
    _save();
  }
}

/// Runs extension modules in a headless WebView. `fetch` is routed through
/// Dart's HTTP client so extensions are not limited by CORS, like in Hayase.
class ExtensionRuntime {
  ExtensionRuntime._();
  static final instance = ExtensionRuntime._();

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Future<void>? _ready;
  final _loaded = <String, String>{}; // extension id -> code url
  final _pending = <String, Completer<String>>{};
  int _nextCall = 0;

  static const _bootstrap = r'''
(() => {
  const toB64 = (bytes) => { let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000)); return btoa(s) }
  const fromB64 = (s) => Uint8Array.from(atob(s), c => c.charCodeAt(0))
  const nativeFetch = async (input, init) => {
    const req = new Request(input, init)
    const headers = {}
    req.headers.forEach((v, k) => { headers[k] = v })
    const body = ['GET', 'HEAD'].includes(req.method) ? null : toB64(new Uint8Array(await req.arrayBuffer()))
    const r = await window.flutter_inappwebview.callHandler('nfetch', { url: req.url, method: req.method, headers, body })
    if (!r || r.error) throw new TypeError('Failed to fetch: ' + (r && r.error))
    const empty = r.status === 204 || r.status === 304 || req.method === 'HEAD'
    const resp = new Response(empty ? null : fromB64(r.body), { status: r.status, headers: r.headers })
    Object.defineProperty(resp, 'url', { value: r.url })
    return resp
  }
  window.fetch = nativeFetch
  const mods = {}
  const reply = (callId, payload) => window.flutter_inappwebview.callHandler('reply', callId, payload)
  window.__nami = {
    load (callId, id, code) {
      try {
        // Modules are evaluated as functions: the default export becomes the return value.
        const body = code.replace(/export\s+default\s+/, 'return ')
        mods[id] = new Function(body)()
        reply(callId, { ok: true })
      } catch (e) { reply(callId, { error: String(e && e.message || e) }) }
    },
    async run (callId, id, method, query, options) {
      try {
        const mod = mods[id]
        if (!mod || typeof mod[method] !== 'function') return reply(callId, { ok: '[]' })
        query.fetch = nativeFetch
        const res = await Promise.race([
          mod[method](query, options),
          new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 25000)),
        ])
        reply(callId, { ok: JSON.stringify(Array.isArray(res) ? res : []) })
      } catch (e) { reply(callId, { error: String(e && e.message || e) }) }
    },
  }
})()
''';

  Future<void> _setUp() async {
    final loaded = Completer<void>();
    _webView = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(data: '<!doctype html><title>nami</title>', baseUrl: WebUri('https://extensions.nami.local/')),
      initialUserScripts: UnmodifiableListView([
        UserScript(source: _bootstrap, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]),
      onWebViewCreated: (c) {
        _controller = c;
        c.addJavaScriptHandler(handlerName: 'nfetch', callback: (args) => _fetch(args.first as Map));
        c.addJavaScriptHandler(
          handlerName: 'reply',
          callback: (args) {
            final completer = _pending.remove(args[0].toString());
            final payload = args[1] as Map;
            if (payload['error'] != null) {
              completer?.completeError(Exception(payload['error']));
            } else {
              completer?.complete(payload['ok'] is String ? payload['ok'] as String : '');
            }
            return null;
          },
        );
      },
      onLoadStop: (c, url) {
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    await _webView!.run();
    await loaded.future.timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> _fetch(Map req) async {
    try {
      final r = http.Request(req['method'] ?? 'GET', Uri.parse(req['url']));
      (req['headers'] as Map?)?.forEach((k, v) => r.headers[k.toString()] = v.toString());
      if (req['body'] != null) r.bodyBytes = base64Decode(req['body']);
      final res = await http.Response.fromStream(await http.Client().send(r).timeout(const Duration(seconds: 20)));
      return {
        'status': res.statusCode,
        'headers': res.headers,
        'body': base64Encode(res.bodyBytes),
        'url': res.request?.url.toString() ?? req['url'],
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<String> _invoke(String js) {
    final id = '${_nextCall++}';
    final completer = _pending[id] = Completer<String>();
    _controller!.evaluateJavascript(source: js.replaceAll('__CALL__', jsonEncode(id)));
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('extension');
    });
  }

  Future<void> _ensureLoaded(InstalledExtension ext) async {
    await (_ready ??= _setUp());
    if (_loaded[ext.id] == ext.manifest.code) return;
    final res = await http.get(Uri.parse(ext.manifest.code));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    await _invoke('__nami.load(__CALL__, ${jsonEncode(ext.id)}, ${jsonEncode(utf8.decode(res.bodyBytes))})');
    _loaded[ext.id] = ext.manifest.code;
  }

  Future<List<TorrentResult>> run(InstalledExtension ext, String method, Map<String, dynamic> query) async {
    await _ensureLoaded(ext);
    final json = await _invoke('__nami.run(__CALL__, ${jsonEncode(ext.id)}, ${jsonEncode(method)}, '
        '${jsonEncode(query)}, ${jsonEncode(ext.resolvedOptions)})');
    return [
      for (final r in jsonDecode(json) as List)
        if (r is Map && r['link'] != null) TorrentResult(Map<String, dynamic>.from(r), ext.manifest.name),
    ];
  }
}

class SourceFailure {
  SourceFailure(this.name, this.message);
  final String name;
  final String message;
}

class SourceSearch {
  final results = <TorrentResult>[];
  final failures = <SourceFailure>[];

  static Future<SourceSearch> run(Media media, int episode) async {
    final maps = await Mappings.load(media.id);
    final ep = maps?.episode(episode);
    final query = <String, dynamic>{
      'anilistId': media.id,
      'titles': {...media.title.all, ...media.synonyms}.toList(),
      'episode': episode,
      'episodeCount': media.episodes ?? media.availableEpisodes,
      'resolution': AppSettings.instance.resolution,
      'exclusions': <String>[],
      'media': media.json,
      'malId': ?media.idMal,
      'anidbAid': ?maps?.anidbId,
      'anidbEid': ?ep?.anidbEid,
      'tvdbId': ?maps?.tvdbId,
      'tvdbEId': ?ep?.tvdbId,
      'tmdbId': ?maps?.tmdbId,
      'imdbId': ?maps?.imdbId,
    };
    final methods = [
      media.isMovie ? 'movie' : 'single',
      if (!media.isMovie && media.status == 'FINISHED' && (media.episodes ?? 0) > 1) 'batch',
    ];

    final out = SourceSearch();
    final calls = <(String, Future<List<TorrentResult>>)>[
      for (final ext in ExtensionStore.instance.enabled)
        for (final m in methods) (ext.manifest.name, ExtensionRuntime.instance.run(ext, m, query)),
    ];
    for (final (name, call) in calls) {
      try {
        out.results.addAll(await call);
      } catch (e) {
        out.failures.add(SourceFailure(name, e.toString()));
      }
    }
    final seen = <String>{};
    final unique = out.results.where((r) => seen.add(r.key)).toList()
      ..sort((a, b) {
        if (a.isBest != b.isBest) return a.isBest ? -1 : 1;
        return b.seeders.compareTo(a.seeders);
      });
    out.results
      ..clear()
      ..addAll(unique);
    return out;
  }
}
