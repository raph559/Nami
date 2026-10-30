import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../aniskip.dart';
import '../platform.dart';
import '../playback.dart';
import '../player_center.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/motion.dart';
import '../widgets.dart';

/// The full-screen player: a view of the [PlaybackSession], which keeps playing
/// when this screen gives way to the mini-player.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.session});
  final PlaybackSession session;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  PlaybackSession get s => widget.session;

  bool controls = true;
  double? scrub;
  Timer? _hideTimer;
  // Pinch and swipe-down, read from one scale gesture.
  int _pointers = 0;
  double _pinch = 1;
  double _dragY = 0;

  /// Windows: the window covers the whole screen (double-click or F11).
  bool _windowFull = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _hideTimer?.cancel();
    windowChromeVisible.value = true;
    if (_windowFull) windowManager.setFullScreen(false);
    // The mini-player shows the video at its own size.
    s.setOutputSize(null);
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _setControls(bool show) {
    setState(() => controls = show);
    // The window buttons come and go with the controls.
    windowChromeVisible.value = show;
  }

  void _toggleControls() {
    _setControls(!controls);
    if (controls) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && s.player.state.playing && scrub == null) _setControls(false);
    });
  }

  Future<void> _toggleWindowFull() async {
    if (!Platform.isWindows) return;
    _windowFull = !_windowFull;
    await windowManager.setFullScreen(_windowFull);
    setState(() {});
  }

  /// Esc leaves the full-screen window first, then shrinks the player.
  void _escape() {
    if (_windowFull) {
      _toggleWindowFull();
    } else {
      PlayerCenter.instance.minimize();
    }
  }

  double _doubleTapX = 0;

  /// The signed seconds shown after a double tap; 0 when nothing is shown.
  int _flash = 0;
  Timer? _flashTimer;

  /// Goes up with each jump, so each one turns the arrow.
  int _flashPulse = 0;

  /// Double tap on a side jumps; several in a row add up in the feedback.
  void _seekFromDoubleTap() {
    final side = seekSide(_doubleTapX, context.size?.width ?? 0);
    if (side == 0) return _toggleControls();
    _jump(side * AppSettings.instance.seekStep);
  }

  void _jump(int seconds) {
    _seekBy(seconds);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flash = 0);
    });
    // Changing direction starts the count again.
    setState(() {
      _flash = _flash * seconds > 0 ? _flash + seconds : seconds;
      _flashPulse++;
    });
  }

  void _seekBy(int seconds) {
    s.seekBy(seconds);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final center = PlayerCenter.instance;
    return PopScope(
      // Back shrinks the player to the bottom of the app, like YouTube.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) center.minimize();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () {
            s.player.playOrPause();
            _scheduleHide();
          },
          const SingleActivator(LogicalKeyboardKey.keyK): () => s.player.playOrPause(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _jump(-AppSettings.instance.seekStep),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _jump(AppSettings.instance.seekStep),
          const SingleActivator(LogicalKeyboardKey.keyS): s.skipNow,
          const SingleActivator(LogicalKeyboardKey.keyF): () => s.setFill(!s.fill),
          const SingleActivator(LogicalKeyboardKey.keyZ): () => s.setSubDelay(s.subDelay - 0.25),
          const SingleActivator(LogicalKeyboardKey.keyX): () => s.setSubDelay(s.subDelay + 0.25),
          const SingleActivator(LogicalKeyboardKey.escape): _escape,
          const SingleActivator(LogicalKeyboardKey.f11): _toggleWindowFull,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: LayoutBuilder(
              builder: (context, box) {
                // mpv renders at the screen's size, so subtitles are drawn at screen size.
                final dpr = MediaQuery.devicePixelRatioOf(context);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => s.setOutputSize(Size(box.maxWidth * dpr, box.maxHeight * dpr)),
                );
                return ListenableBuilder(listenable: s, builder: (context, _) => _content());
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final center = PlayerCenter.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(controller: s.controller, controls: NoVideoControls, fill: Colors.black),
        // Tap for the controls, pinch to fill the screen, swipe down to shrink the player.
        // With a mouse: moving it shows the controls and the cursor, double-click fills the screen.
        MouseRegion(
          cursor: controls || !isDesktop ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) {
            if (!isDesktop) return;
            if (!controls) _setControls(true);
            _scheduleHide();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTapDown: (d) => _doubleTapX = d.localPosition.dx,
            onDoubleTap: Platform.isWindows ? _toggleWindowFull : _seekFromDoubleTap,
            onScaleStart: (d) {
              _pointers = d.pointerCount;
              _pinch = 1;
              _dragY = 0;
            },
            onScaleUpdate: (d) {
              if (d.pointerCount > _pointers) _pointers = d.pointerCount;
              _pinch = d.scale;
              _dragY += d.focalPointDelta.dy;
            },
            onScaleEnd: (_) {
              if (_pointers >= 2) {
                if (_pinch > 1.05) s.setFill(true);
                if (_pinch < 0.95) s.setFill(false);
              } else if (_dragY > 110) {
                center.minimize();
              }
            },
          ),
        ),
        if (s.phase == PlaybackPhase.connecting)
          _status(null, t('Connexion aux pairs…', 'Connecting to peers…'), s.result.title),
        if (s.phase == PlaybackPhase.failed)
          _status(Icons.warning_amber, t('Impossible de lire', 'Cannot play'), s.failure ?? ''),
        if (s.phase == PlaybackPhase.chooseFile) _fileChooser(),
        if (s.phase == PlaybackPhase.playing && (s.player.state.buffering || s.player.state.position == Duration.zero))
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 10),
                  Text(s.statsLine, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        if (s.phase == PlaybackPhase.playing && controls) _overlay(),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: Motion.of(context).medium,
              child: _flash == 0
                  ? const SizedBox.expand()
                  : SeekFeedback(
                      key: ValueKey(_flash > 0),
                      seconds: _flash,
                      step: AppSettings.instance.seekStep,
                      pulse: _flashPulse,
                    ),
            ),
          ),
        ),
        if (s.phase == PlaybackPhase.playing) _floating(),
        if (s.phase != PlaybackPhase.playing)
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                tooltip: t('Fermer', 'Close'),
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: center.close,
              ),
            ),
          ),
      ],
    );
  }

  /// Back or forward by [seconds], with the length written in the icon.
  Widget _seekButton(int seconds) {
    final step = seconds.abs();
    return FocusOutline(
      radius: 36,
      child: IconButton(
        tooltip: seconds < 0
            ? t('Reculer de $step secondes', 'Back $step seconds')
            : t('Avancer de $step secondes', 'Forward $step seconds'),
        iconSize: 36,
        style: IconButton.styleFrom(backgroundColor: const Color(0x8C000000)),
        onPressed: () => _seekBy(seconds),
        icon: SeekIcon(forward: seconds > 0, step: step, size: 36),
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
          if (s.phase == PlaybackPhase.connecting && s.stats != null)
            Text(
              t('${s.stats!.peers} pairs', '${s.stats!.peers} peers'),
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
              t("Choisis le fichier de l'épisode ${s.episode}", 'Pick the file for episode ${s.episode}'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final f in s.torrent!.files.where((f) => f.isVideo))
                  ListTile(
                    title: Text(f.name, style: const TextStyle(color: Colors.white, fontSize: 13)),
                    trailing: Text(formatBytes(f.length), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () => s.play(f),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _overlay() {
    final position = s.player.state.position;
    final duration = s.player.state.duration;
    final fraction = duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0;
    final shown = scrub ?? fraction.clamp(0.0, 1.0);
    final accent = s.media.color ?? Theme.of(context).colorScheme.primary;
    final knowsOpening = s.skips.any((i) => i.kind == SkipKind.opening);
    return Stack(
      children: [
        // The shade behind the controls lets taps and swipes through to the
        // gesture layer below (show/hide, pinch, swipe down).
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
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
            child: SizedBox.expand(),
          ),
        ),
        // Like Netflix: wide side margins keep the controls clear of rounded corners.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    FocusOutline(
                      child: IconButton(
                        tooltip: t('Réduire', 'Minimize'),
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                        onPressed: PlayerCenter.instance.minimize,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.media.title.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            s.media.isMovie
                                ? s.statsLine
                                : '${t('Épisode ${s.episode}', 'Episode ${s.episode}')} · ${s.statsLine}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _trackMenu(),
                    FocusOutline(
                      child: IconButton(
                        tooltip: s.fill
                            ? t("Voir l'image entière", 'Fit the picture')
                            : t("Remplir l'écran", 'Fill the screen'),
                        icon: Icon(s.fill ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                        onPressed: () {
                          s.setFill(!s.fill);
                          _scheduleHide();
                        },
                      ),
                    ),
                    FocusOutline(
                      child: IconButton(
                        tooltip: t('Fermer', 'Close'),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: PlayerCenter.instance.close,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    // Without AniSkip timings, a fixed jump over a typical 1:30 opening.
                    if (!knowsOpening)
                      FocusOutline(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: () => _seekBy(85),
                          child: Text(t("Passer l'intro (+85 s)", 'Skip intro (+85 s)')),
                        ),
                      ),
                    const Spacer(),
                    // The s.countdown card offers the same action while it runs.
                    if (s.hasNext && s.countdown == null)
                      FocusOutline(
                        child: FilledButton.icon(
                          onPressed: () => s.goNext(auto: false),
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
                    s.player.seek(duration * v);
                    setState(() => scrub = null);
                    _scheduleHide();
                  },
                ),
                Row(
                  children: [
                    Text(
                      PlaybackSession.clock(scrub == null ? position : duration * scrub!),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    Text(PlaybackSession.clock(duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Centred on the screen itself, not between the top bar and the taller bottom block.
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _seekButton(-AppSettings.instance.seekStep),
              const SizedBox(width: 40),
              _roundButton(
                s.player.state.playing ? Icons.pause : Icons.play_arrow,
                56,
                s.player.state.playing ? t('Pause', 'Pause') : t('Lecture', 'Play'),
                () {
                  s.player.playOrPause();
                  _scheduleHide();
                },
              ),
              const SizedBox(width: 40),
              _seekButton(AppSettings.instance.seekStep),
            ],
          ),
        ),
      ],
    );
  }

  /// Stays on screen while the controls are hidden: the skip button, a short
  /// s.notice and the next-episode s.countdown.
  Widget _floating() {
    final skip = s.offered;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, controls ? 110 : 24),
        child: Stack(
          children: [
            if (s.notice != null)
              Align(
                alignment: Alignment.bottomLeft,
                child: _panel(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(s.notice!.text, style: const TextStyle(color: Colors.white)),
                      ),
                      if (s.notice!.action != null) ...[
                        const SizedBox(width: 8),
                        FocusOutline(
                          child: TextButton(
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                            onPressed: () {
                              s.notice!.onAction?.call();
                              s.dismissNotice();
                            },
                            child: Text(s.notice!.action!),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (s.countdown != null)
              Align(alignment: Alignment.bottomRight, child: _countdownCard())
            else if (skip != null)
              Align(
                alignment: Alignment.bottomRight,
                child: FocusOutline(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Nami.text,
                      foregroundColor: Nami.ground,
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: s.skipNow,
                    icon: const Icon(Icons.fast_forward_rounded),
                    label: Text(
                      skip.kind == SkipKind.opening
                          ? t("Passer l'intro", 'Skip opening')
                          : t('Passer le générique', 'Skip ending'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _countdownCard() => _panel(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('Épisode ${s.episode + 1} dans ${s.countdown} s', 'Episode ${s.episode + 1} in ${s.countdown} s'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusOutline(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: s.cancelCountdown,
                child: Text(t('Annuler', 'Cancel')),
              ),
            ),
            const SizedBox(width: 8),
            FocusOutline(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Nami.text, foregroundColor: Nami.ground),
                onPressed: () => s.goNext(auto: true),
                icon: const Icon(Icons.skip_next),
                label: Text(t('Lire maintenant', 'Play now')),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  /// Near-black panel: white text keeps 15:1 whatever frame is behind it.
  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xE6131315), borderRadius: BorderRadius.circular(8)),
    child: child,
  );

  Future<void> _delayDialog() => showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) {
        void change(double v) {
          s.setSubDelay(v);
          setDialog(() {});
        }

        return AlertDialog(
          title: Text(t('Décalage des sous-titres', 'Subtitle delay')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: t('Plus tôt', 'Earlier'),
                    icon: const Icon(Icons.remove),
                    onPressed: () => change(s.subDelay - 0.25),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text('${_signed(s.subDelay)} s', textAlign: TextAlign.center, style: Nami.section),
                  ),
                  IconButton(
                    tooltip: t('Plus tard', 'Later'),
                    icon: const Icon(Icons.add),
                    onPressed: () => change(s.subDelay + 0.25),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'Positif si les sous-titres arrivent trop tôt. Au clavier : Z et X.',
                  'Positive when subtitles come too early. Keyboard: Z and X.',
                ),
                style: Nami.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => change(0), child: Text(t('Remettre à zéro', 'Reset'))),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('Fermer', 'Close'))),
          ],
        );
      },
    ),
  );

  Widget _trackMenu() {
    final tracks = s.player.state.tracks;
    final current = s.player.state.track;
    String label(String id, String? title, String? language) =>
        [title, language].whereType<String>().where((s) => s.isNotEmpty).join(' · ').ifEmpty(id);
    return PopupMenuButton<void Function()>(
      tooltip: t('Sous-titres et audio', 'Subtitles and audio'),
      icon: const Icon(Icons.subtitles, color: Colors.white),
      onSelected: (apply) => apply(),
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(t('Sous-titres', 'Subtitles'))),
        for (final sub in tracks.subtitle.where((s) => s.id != 'auto'))
          CheckedPopupMenuItem(
            checked: sub == current.subtitle,
            value: () => s.player.setSubtitleTrack(sub),
            child: Text(sub.id == 'no' ? t('Aucun', 'None') : label(sub.id, sub.title, sub.language)),
          ),
        PopupMenuItem(
          value: _delayDialog,
          child: Text(
            s.subDelay == 0
                ? t('Décalage des sous-titres…', 'Subtitle delay…')
                : t('Décalage : ${_signed(s.subDelay)} s', 'Delay: ${_signed(s.subDelay)} s'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: false, child: Text(t('Audio', 'Audio'))),
        for (final a in tracks.audio.where((a) => a.id != 'auto' && a.id != 'no'))
          CheckedPopupMenuItem(
            checked: a == current.audio,
            value: () => s.player.setAudioTrack(a),
            child: Text(label(a.id, a.title, a.language)),
          ),
      ],
    );
  }
}

/// Which side of the video a double tap at [x] means: -1 back, 1 forward,
/// 0 for the middle, which only shows the controls.
int seekSide(double x, double width) {
  if (x < width * 0.4) return -1;
  if (x > width * 0.6) return 1;
  return 0;
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

String _signed(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// The mini-player: above the bottom bar on a phone, a card in the corner on a
/// wide window. Tap or swipe up to go back to full screen, swipe down to close.
class MiniPlayerHost extends StatelessWidget {
  const MiniPlayerHost({super.key});

  @override
  Widget build(BuildContext context) {
    final center = PlayerCenter.instance;
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) {
        final s = center.session;
        if (s == null || !center.minimized) return const SizedBox.shrink();
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final bottom = MediaQuery.paddingOf(context).bottom;
        return Positioned(
          left: wide ? null : 8,
          right: wide ? 16 : 8,
          bottom: wide ? 16 : bottom + 76,
          width: wide ? 380 : null,
          child: _MiniPlayer(session: s),
        );
      },
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.session});
  final PlaybackSession session;

  @override
  Widget build(BuildContext context) {
    final center = PlayerCenter.instance;
    final s = session;
    return Material(
      color: const Color(0xFF1B1B1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Nami.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: center.expand,
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200) center.expand();
            if (v > 200) center.close();
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ListenableBuilder(
              listenable: s,
              builder: (context, _) {
                final playing = s.player.state.playing;
                final status = switch (s.phase) {
                  PlaybackPhase.connecting => t('Connexion…', 'Connecting…'),
                  PlaybackPhase.failed => t('Impossible de lire', 'Cannot play'),
                  PlaybackPhase.chooseFile => t('Choisis le fichier', 'Pick the file'),
                  PlaybackPhase.playing =>
                    '${PlaybackSession.clock(s.player.state.position)} / ${PlaybackSession.clock(s.player.state.duration)}',
                };
                return Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Nami.radiusImage),
                      child: SizedBox(
                        width: 112,
                        height: 63,
                        child: Video(controller: s.controller, controls: NoVideoControls, fill: Colors.black),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.media.title.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Nami.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [
                              if (!s.media.isMovie) t('Épisode ${s.episode}', 'Episode ${s.episode}'),
                              status,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Nami.caption,
                          ),
                        ],
                      ),
                    ),
                    FocusOutline(
                      child: IconButton(
                        tooltip: playing ? t('Pause', 'Pause') : t('Lecture', 'Play'),
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Nami.text),
                        onPressed: s.player.playOrPause,
                      ),
                    ),
                    FocusOutline(
                      child: IconButton(
                        tooltip: t('Fermer', 'Close'),
                        icon: Icon(Icons.close, color: Nami.text),
                        onPressed: center.close,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular arrow with the seek length written inside.
class SeekIcon extends StatelessWidget {
  const SeekIcon({super.key, required this.forward, required this.step, required this.size});
  final bool forward;
  final int step;
  final double size;

  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 6)];

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Transform.flip(
        flipX: forward,
        child: Icon(Icons.replay, size: size, color: Colors.white, shadows: _shadow),
      ),
      Padding(
        padding: EdgeInsets.only(top: size * 0.11),
        child: Text(
          '$step',
          style: TextStyle(
            fontFamily: Nami.sans,
            fontSize: size * 0.28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: _shadow,
          ),
        ),
      ),
    ],
  );
}

/// The answer to a jump: a circular arrow with the step inside gives a turn with each
/// jump and the total climbs under it. Nothing covers the picture.
class SeekFeedback extends StatelessWidget {
  const SeekFeedback({super.key, required this.seconds, required this.step, this.pulse = 0});
  final int seconds;

  /// The seek length, written in the arrow.
  final int step;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final forward = seconds > 0;
    final motion = Motion.of(context);
    return Align(
      alignment: Alignment(forward ? 0.56 : -0.56, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(pulse),
            tween: Tween(begin: 0, end: 1),
            duration: motion.medium * 1.75,
            curve: Curves.linear,
            // Quick out in the direction of the jump, then back with a small bounce.
            builder: (context, t, child) =>
                Transform.rotate(angle: (forward ? 1 : -1) * 0.9 * sin(t * pi * 2) * (1 - t), child: child),
            child: SeekIcon(forward: forward, step: step, size: 60),
          ),
          const SizedBox(height: 6),
          Text(
            '${forward ? '+' : '-'}${seconds.abs()} s',
            style: const TextStyle(
              fontFamily: Nami.sans,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              shadows: SeekIcon._shadow,
            ),
          ),
        ],
      ),
    );
  }
}
