import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../anilist.dart';
import '../engine.dart';
import '../extensions.dart';
import '../settings.dart';
import '../widgets.dart';

/// Resolves a source into a stream and plays it. Pops `true` to ask for the
/// next episode.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.media, required this.episode, required this.result});
  final Media media;
  final int episode;
  final TorrentResult result;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _Phase { connecting, chooseFile, playing, failed }

class _PlayerScreenState extends State<PlayerScreen> {
  final player = mk.Player();
  late final controller = VideoController(player);

  _Phase phase = _Phase.connecting;
  String? failure;
  EngineTorrent? torrent;
  EngineStats? stats;
  double speed = 0;
  bool controls = true;
  bool markedWatched = false;
  double? scrub;
  Timer? _hideTimer;
  Timer? _statsTimer;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    final native = player.platform;
    if (native is mk.NativePlayer) {
      native.setProperty('cache', 'yes');
      native.setProperty('demuxer-max-bytes', '64MiB');
      native.setProperty('network-timeout', '90');
    }
    _subs.addAll([
      player.stream.position.listen((_) => _checkWatched()),
      player.stream.completed.listen((done) {
        if (done) _checkWatched(force: true);
      }),
      for (final s in [player.stream.playing, player.stream.buffering, player.stream.tracks, player.stream.track])
        s.listen((_) {
          if (mounted) setState(() {});
        }),
    ]);
    _start();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _statsTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    final hash = torrent?.hash;
    if (hash != null) Engine.instance.drop(hash);
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final t = await Engine.instance.add(widget.result.link);
      if (!mounted) {
        Engine.instance.drop(t.hash);
        return;
      }
      torrent = t;
      _pollStats();
      final file = Engine.pick(t.files, widget.episode);
      if (file == null) {
        setState(() => phase = _Phase.chooseFile);
      } else {
        _play(file);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          phase = _Phase.failed;
          failure = _explain(e);
        });
      }
    }
  }

  Future<void> _play(EngineFile file) async {
    final url = await Engine.instance.streamUrl(torrent!.hash, file);
    setState(() => phase = _Phase.playing);
    await player.open(mk.Media(url));
    _scheduleHide();
  }

  void _pollStats() {
    var last = 0;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final s = await Engine.instance.stats(torrent!.hash);
      if (s == null || !mounted) return;
      setState(() {
        if (last > 0) speed = (s.downloaded - last).clamp(0, 1 << 40).toDouble();
        last = s.downloaded;
        stats = s;
      });
    });
  }

  void _checkWatched({bool force = false}) {
    final duration = player.state.duration.inMilliseconds;
    if (markedWatched || duration <= 0) return;
    if (force || player.state.position.inMilliseconds / duration >= 0.85) {
      markedWatched = true;
      AniList.instance.setProgress(widget.media, widget.episode).catchError((_) {});
    }
  }

  void _toggleControls() {
    setState(() => controls = !controls);
    if (controls) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && player.state.playing && scrub == null) setState(() => controls = false);
    });
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

  void _seekBy(int seconds) {
    final target = player.state.position + Duration(seconds: seconds);
    player.seek(target < Duration.zero ? Duration.zero : target);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          player.playOrPause();
          _scheduleHide();
        },
        const SingleActivator(LogicalKeyboardKey.keyK): () => player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(10),
        const SingleActivator(LogicalKeyboardKey.keyS): () => _seekBy(85),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Video(controller: controller, controls: NoVideoControls, fill: Colors.black),
              ),
              if (phase == _Phase.connecting)
                _status(null, t('Connexion aux pairs…', 'Connecting to peers…'), widget.result.title),
              if (phase == _Phase.failed)
                _status(Icons.warning_amber, t('Impossible de lire', 'Cannot play'), failure ?? ''),
              if (phase == _Phase.chooseFile) _fileChooser(),
              if (phase == _Phase.playing && (player.state.buffering || player.state.position == Duration.zero))
                IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 10),
                        Text(statsLine, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              if (phase == _Phase.playing && controls) _overlay(),
              if (phase != _Phase.playing)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      tooltip: t('Fermer', 'Close'),
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(IconData? icon, String title, String detail) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon == null
              ? const CircularProgressIndicator(color: Colors.white)
              : Icon(icon, color: Colors.amber, size: 40),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            maxLines: 4,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (phase == _Phase.connecting && stats != null)
            Text(
              t('${stats!.peers} pairs', '${stats!.peers} peers'),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
        ],
      ),
    ),
  );

  Widget _fileChooser() => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 340),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              t("Choisis le fichier de l'épisode ${widget.episode}", 'Pick the file for episode ${widget.episode}'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final f in torrent!.files.where((f) => f.isVideo))
                  ListTile(
                    title: Text(f.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: Text(formatBytes(f.length), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () => _play(f),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _overlay() {
    final position = player.state.position;
    final duration = player.state.duration;
    final fraction = duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0;
    final shown = scrub ?? fraction.clamp(0.0, 1.0);
    final accent = widget.media.color ?? Theme.of(context).colorScheme.primary;
    final hasNext = !widget.media.isMovie && widget.episode < widget.media.availableEpisodes;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.2, 0.42, 0.58, 0.8, 1],
          colors: [
            Color(0xE6000000),
            Color(0xCC000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0xCC000000),
            Color(0xE6000000),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  FocusOutline(
                    child: IconButton(
                      tooltip: t('Fermer', 'Close'),
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.media.title.display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          widget.media.isMovie
                              ? statsLine
                              : '${t('Épisode ${widget.episode}', 'Episode ${widget.episode}')} · $statsLine',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _trackMenu(),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _roundButton(Icons.replay_10, 36, t('Reculer de 10 secondes', 'Back 10 seconds'), () => _seekBy(-10)),
                  const SizedBox(width: 40),
                  _roundButton(
                    player.state.playing ? Icons.pause : Icons.play_arrow,
                    56,
                    player.state.playing ? t('Pause', 'Pause') : t('Lecture', 'Play'),
                    () {
                      player.playOrPause();
                      _scheduleHide();
                    },
                  ),
                  const SizedBox(width: 40),
                  _roundButton(
                    Icons.forward_10,
                    36,
                    t('Avancer de 10 secondes', 'Forward 10 seconds'),
                    () => _seekBy(10),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  FocusOutline(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: () => _seekBy(85),
                      child: Text(t("Passer l'intro (+85 s)", 'Skip intro (+85 s)')),
                    ),
                  ),
                  const Spacer(),
                  if (hasNext)
                    FocusOutline(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.skip_next),
                        label: Text(t('Épisode suivant', 'Next episode')),
                      ),
                    ),
                ],
              ),
              Slider(
                value: shown,
                activeColor: accent,
                onChanged: (v) => setState(() => scrub = v),
                onChangeEnd: (v) {
                  player.seek(duration * v);
                  setState(() => scrub = null);
                  _scheduleHide();
                },
              ),
              Row(
                children: [
                  Text(
                    clock(scrub == null ? position : duration * scrub!),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(clock(duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackMenu() {
    final tracks = player.state.tracks;
    final current = player.state.track;
    String label(String id, String? title, String? language) =>
        [title, language].whereType<String>().where((s) => s.isNotEmpty).join(' · ').ifEmpty(id);
    return PopupMenuButton<void Function()>(
      tooltip: t('Sous-titres et audio', 'Subtitles and audio'),
      icon: const Icon(Icons.subtitles, color: Colors.white),
      onSelected: (apply) => apply(),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(t('Sous-titres', 'Subtitles'))),
        for (final s in tracks.subtitle.where((s) => s.id != 'auto'))
          CheckedPopupMenuItem(
            checked: s == current.subtitle,
            value: () => player.setSubtitleTrack(s),
            child: Text(s.id == 'no' ? t('Aucun', 'None') : label(s.id, s.title, s.language)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: false, child: Text(t('Audio', 'Audio'))),
        for (final a in tracks.audio.where((a) => a.id != 'auto' && a.id != 'no'))
          CheckedPopupMenuItem(
            checked: a == current.audio,
            value: () => player.setAudioTrack(a),
            child: Text(label(a.id, a.title, a.language)),
          ),
      ],
    );
  }
}

/// The engine reports in English; this says what happened and what to try.
String _explain(Object e) {
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

/// Control over the video: a dark disc keeps the icon at 3:1 or more even
/// over a white frame.
Widget _roundButton(IconData icon, double size, String label, VoidCallback onPressed) => FocusOutline(
  radius: size,
  child: IconButton(
    tooltip: label,
    iconSize: size,
    style: IconButton.styleFrom(backgroundColor: const Color(0x8C000000)),
    icon: Icon(icon, color: Colors.white),
    onPressed: onPressed,
  ),
);

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
