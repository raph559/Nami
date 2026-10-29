import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import 'anilist.dart';
import 'aniskip.dart';
import 'engine.dart';
import 'extensions.dart';
import 'settings.dart';
import 'widgets.dart' show formatBytes;

/// What the player asks for when it closes on the way to the next episode.
class PlayerExit {
  const PlayerExit({required this.auto, this.reuse});

  /// The countdown ran out: pick the recommended source without asking.
  final bool auto;

  /// The torrent just played also holds the next episode (a season pack).
  final TorrentResult? reuse;
}

enum PlaybackPhase { connecting, chooseFile, playing, failed }

/// One episode being played: the torrent, mpv and everything that follows the
/// playback position (resume, AniSkip, countdown, subtitles). It lives apart
/// from the screens so the full-screen player and the mini-player can both
/// show it while it keeps playing.
class PlaybackSession extends ChangeNotifier {
  PlaybackSession({required this.media, required this.episode, required this.result, required this.onNext}) {
    final native = player.platform;
    if (native is mk.NativePlayer) {
      for (final (key, value) in [
        ('cache', 'yes'),
        ('demuxer-max-bytes', '64MiB'),
        ('network-timeout', '90'),
        ('sub-scale', (AppSettings.instance.subtitleSize / 100).toString()),
        // mpv draws subtitles at the size of its output, which is the screen
        // while the player is full screen (see setOutputSize), so they keep
        // their size when the video is cropped to fill it.
        ('sub-scale-with-window', 'yes'),
        ('sub-ass-scale-with-window', 'yes'),
        ('sub-use-margins', 'yes'),
        ('sub-ass-force-margins', 'yes'),
      ]) {
        native.setProperty(key, value);
      }
    }
    _subs.addAll([
      player.stream.position.listen(_onPosition),
      player.stream.duration.listen(_onDuration),
      player.stream.tracks.listen(_chooseSubtitle),
      player.stream.completed.listen((done) {
        if (!done) return;
        _checkWatched(force: true);
        if (hasNext && AppSettings.instance.autoNext) startCountdown();
      }),
      for (final s in [player.stream.playing, player.stream.buffering, player.stream.tracks, player.stream.track])
        s.listen((_) => notifyListeners()),
    ]);
    _start();
  }

  final Media media;
  final int episode;
  final TorrentResult result;
  final void Function(PlayerExit exit) onNext;

  final player = mk.Player();
  late final controller = VideoController(player);

  PlaybackPhase phase = PlaybackPhase.connecting;
  String? failure;
  EngineTorrent? torrent;
  EngineStats? stats;
  double speed = 0;
  bool markedWatched = false;
  bool fill = false;
  bool _disposed = false;
  Timer? _statsTimer;
  final _subs = <StreamSubscription>[];

  // Resume
  bool _durationSeen = false;
  Duration _lastSaved = Duration.zero;

  // AniSkip
  List<SkipInterval> skips = [];
  final _skipped = <SkipKind>{};
  SkipInterval? offered;

  // Short message over the video, with an optional action ("Recommencer", "Revoir").
  ({String text, String? action, VoidCallback? onAction})? notice;
  Timer? _noticeTimer;

  // Next episode
  int? countdown;
  bool countdownCancelled = false;
  Timer? _countdownTimer;

  // Subtitles
  bool _subtitleChosen = false;
  double subDelay = 0;

  bool get hasNext => !media.isMovie && episode < media.availableEpisodes;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveResume();
    _statsTimer?.cancel();
    _noticeTimer?.cancel();
    _countdownTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    final hash = torrent?.hash;
    if (hash != null) Engine.instance.drop(hash);
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final t = await Engine.instance.add(result.link);
      if (_disposed) {
        Engine.instance.drop(t.hash);
        return;
      }
      torrent = t;
      _pollStats();
      final file = Engine.pick(t.files, episode);
      if (file == null) {
        phase = PlaybackPhase.chooseFile;
        notifyListeners();
      } else {
        play(file);
      }
    } catch (e) {
      if (_disposed) return;
      phase = PlaybackPhase.failed;
      failure = explainEngineError(e);
      notifyListeners();
    }
  }

  Future<void> play(EngineFile file) async {
    final url = await Engine.instance.streamUrl(torrent!.hash, file);
    phase = PlaybackPhase.playing;
    notifyListeners();
    await player.open(mk.Media(url));
  }

  void _pollStats() {
    var last = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final s = await Engine.instance.stats(torrent!.hash);
      if (s == null || _disposed) return;
      if (last > 0) speed = (s.downloaded - last).clamp(0, 1 << 40).toDouble();
      last = s.downloaded;
      stats = s;
      notifyListeners();
    });
  }

  void _checkWatched({bool force = false}) {
    final duration = player.state.duration.inMilliseconds;
    if (markedWatched || duration <= 0) return;
    if (force || player.state.position.inMilliseconds / duration >= 0.85) {
      markedWatched = true;
      AppSettings.instance.setResume(media.id, episode, null, media: media.json);
      AniList.instance.setProgress(media, episode).catchError((_) {});
    }
  }

  void _onPosition(Duration position) {
    _checkWatched();
    if ((position - _lastSaved).abs() > const Duration(seconds: 5)) _saveResume();

    SkipInterval? inside;
    for (final i in skips) {
      if (!i.contains(position)) continue;
      if (i.kind == SkipKind.ending && hasNext && AppSettings.instance.autoNext && !countdownCancelled) {
        startCountdown();
        return;
      }
      if (AppSettings.instance.autoSkip && _skipped.add(i.kind)) {
        player.seek(i.end);
        _showNotice(
          i.kind == SkipKind.opening ? t('Intro passée', 'Opening skipped') : t('Générique passé', 'Ending skipped'),
          action: t('Revoir', 'Watch it'),
          onAction: () => player.seek(i.start),
        );
        return;
      }
      inside = i;
    }
    if (inside != offered) {
      offered = inside;
      notifyListeners();
    }
  }

  /// The first known duration: AniSkip needs it, and so does resuming.
  void _onDuration(Duration duration) {
    if (_durationSeen || duration <= Duration.zero) return;
    _durationSeen = true;
    final at = AppSettings.instance.resumeAt(media.id, episode);
    if (at != null && at > const Duration(seconds: 30) && at < duration - const Duration(minutes: 2)) {
      player.seek(at);
      _lastSaved = at;
      _showNotice(
        t('Reprise à ${clock(at)}', 'Resumed at ${clock(at)}'),
        action: t('Recommencer', 'Start over'),
        onAction: () => player.seek(Duration.zero),
      );
    }
    final malId = media.idMal;
    if (malId != null) {
      AniSkip.fetch(malId, episode, duration).then((found) {
        skips = found;
        notifyListeners();
      });
    }
  }

  void _saveResume() {
    if (markedWatched || !_durationSeen) return;
    final position = player.state.position;
    _lastSaved = position;
    if (position > const Duration(seconds: 30)) {
      AppSettings.instance.setResume(media.id, episode, position, length: player.state.duration, media: media.json);
    }
  }

  void _showNotice(String text, {String? action, VoidCallback? onAction}) {
    _noticeTimer?.cancel();
    notice = (text: text, action: action, onAction: onAction);
    notifyListeners();
    _noticeTimer = Timer(const Duration(seconds: 6), dismissNotice);
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  /// Picks the subtitle track in the user's language once the file's tracks are known.
  void _chooseSubtitle(mk.Tracks tracks) {
    final real = tracks.subtitle.where((s) => s.id != 'auto' && s.id != 'no').toList();
    if (_subtitleChosen || real.isEmpty) return;
    _subtitleChosen = true;
    final (codes, names) = switch (AppSettings.instance.subtitleLanguage) {
      SubtitleLanguage.fr => (const {'fr', 'fre', 'fra', 'fr-fr'}, const ['french', 'français', 'francais']),
      SubtitleLanguage.en => (const {'en', 'eng', 'en-us', 'en-gb'}, const ['english']),
      SubtitleLanguage.file => (const <String>{}, const <String>[]),
    };
    if (codes.isEmpty) return;
    bool matches(mk.SubtitleTrack s) {
      final title = (s.title ?? '').toLowerCase();
      return codes.contains((s.language ?? '').toLowerCase()) || names.any(title.contains);
    }

    // "Signs & Songs" tracks only translate on-screen text; prefer the full dialogue track.
    bool partial(mk.SubtitleTrack s) => RegExp(r'sign|song|forced', caseSensitive: false).hasMatch(s.title ?? '');
    final candidates = real.where(matches).toList()..sort((a, b) => (partial(a) ? 1 : 0) - (partial(b) ? 1 : 0));
    if (candidates.isNotEmpty) player.setSubtitleTrack(candidates.first);
  }

  void setSubDelay(double seconds) {
    final native = player.platform;
    if (native is! mk.NativePlayer) return;
    subDelay = double.parse(seconds.toStringAsFixed(2));
    native.setProperty('sub-delay', subDelay.toString());
    notifyListeners();
  }

  void seekBy(int seconds) {
    final target = player.state.position + Duration(seconds: seconds);
    player.seek(target < Duration.zero ? Duration.zero : target);
  }

  /// S or the floating button: skip the part playing now, else the fixed 85 s jump.
  void skipNow() {
    final i = offered;
    if (i != null) {
      _skipped.add(i.kind);
      player.seek(i.end);
      offered = null;
      notifyListeners();
    } else {
      seekBy(85);
    }
  }

  void startCountdown() {
    if (countdown != null || countdownCancelled) return;
    countdown = 10;
    notifyListeners();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) return timer.cancel();
      if (countdown! <= 1) {
        timer.cancel();
        goNext(auto: true);
      } else {
        countdown = countdown! - 1;
        notifyListeners();
      }
    });
  }

  void cancelCountdown() {
    _countdownTimer?.cancel();
    countdown = null;
    countdownCancelled = true;
    notifyListeners();
  }

  void goNext({required bool auto}) {
    _countdownTimer?.cancel();
    final files = torrent?.files ?? const <EngineFile>[];
    final packHasNext = files.where((f) => f.isVideo).length > 1 && Engine.pick(files, episode + 1) != null;
    onNext(PlayerExit(auto: auto, reuse: packHasNext ? result : null));
  }

  // MARK: Fill and output size

  /// Fills the screen by cropping the video to its shape (mpv's panscan).
  /// Subtitles are drawn at the output's size, so they do not grow.
  void setFill(bool on) {
    fill = on;
    final native = player.platform;
    if (native is mk.NativePlayer) native.setProperty('panscan', on ? '1.0' : '0.0');
    notifyListeners();
  }

  Size? _output;
  StreamSubscription? _rectGuard;

  /// media_kit gives mpv an image the size of the video and lets Flutter scale
  /// it; subtitles are drawn into that image, so they would scale with it.
  /// Full screen, mpv gets an image the size of the screen instead, letterboxes
  /// the video itself and draws the subtitles at screen size. [size] is in
  /// physical pixels; null goes back to the video's size (mini-player).
  Future<void> setOutputSize(Size? size) async {
    if (size == _output) return;
    _output = size;
    if (Platform.isAndroid) {
      await _androidSurface(size);
    } else {
      await controller.setSize(width: size?.width.round(), height: size?.height.round());
    }
  }

  /// media_kit has no setSize on Android: resize the surface the same way it does
  /// (same channel, then tell mpv the new size), and keep it when media_kit
  /// puts the video's size back after a change of video parameters.
  Future<void> _androidSurface(Size? size) async {
    final platform = await controller.platform.future;
    final params = player.state.videoParams;
    final w = size?.width.round() ?? params.dw ?? 0;
    final h = size?.height.round() ?? params.dh ?? 0;
    if (w <= 0 || h <= 0) return;
    await const MethodChannel('com.alexmercerind/media_kit_video').invokeMethod('VideoOutputManager.SetSurfaceSize', {
      'handle': (await player.handle).toString(),
      'width': w.toString(),
      'height': h.toString(),
    });
    final native = player.platform;
    if (native is mk.NativePlayer) await native.setProperty('android-surface-size', '${w}x$h');
    platform.rect.value = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    _rectGuard ??= Stream.periodic(const Duration(seconds: 2)).listen((_) {
      final want = _output;
      final now = platform.rect.value;
      if (want != null && now != null && (now.width != want.width.round() || now.height != want.height.round())) {
        _output = null;
        setOutputSize(want);
      }
    });
    _subs.add(_rectGuard!);
  }

  String get statsLine {
    final s = stats;
    if (s == null) return t('Mise en mémoire tampon…', 'Buffering…');
    return '${t('${s.peers} pairs', '${s.peers} peers')} · ${formatBytes(speed)}/s';
  }

  static String clock(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60 % 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:$mm:$ss' : '${s ~/ 60}:$ss';
  }
}

/// The engine reports in English; this says what happened and what to try.
String explainEngineError(Object e) {
  final raw = e.toString();
  if (raw.contains('no peers sent metadata') || e is TimeoutException) {
    return t(
      "Personne ne partage ce torrent en ce moment. Essaie une autre source dans la liste.",
      'Nobody is sharing this torrent right now. Try another source from the list.',
    );
  }
  if (raw.contains("n'a pas démarré") || raw.contains('did not start')) {
    return t(
      "Le moteur torrent n'a pas démarré. Ferme Nami et rouvre-la.",
      'The torrent engine did not start. Close Nami and open it again.',
    );
  }
  return t(
    'Le torrent n\'a pas pu être ouvert ($raw). Essaie une autre source.',
    'The torrent could not be opened ($raw). Try another source.',
  );
}
