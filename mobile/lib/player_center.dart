import 'package:flutter/material.dart';

import 'anilist.dart';
import 'extensions.dart';
import 'playback.dart';
import 'screens/player.dart';
import 'screens/sources.dart';

/// What is playing and how it is shown, for the whole app. The playback lives
/// in a [PlaybackSession]; the full-screen player is a route over the app and
/// the mini-player sits above the navigation, so swiping the player down keeps
/// it playing while you browse.
class PlayerCenter extends ChangeNotifier {
  PlayerCenter._();
  static final instance = PlayerCenter._();

  /// The app's navigator, to open the sources sheet and the player from anywhere.
  final navigatorKey = GlobalKey<NavigatorState>();

  PlaybackSession? session;
  bool minimized = false;

  /// Bumped when a session ends, so pages can refresh the AniList progress.
  int finished = 0;

  Route<void>? _fullRoute;

  NavigatorState? get _nav => navigatorKey.currentState;

  /// Opens the sources for [episode]; with [autoPick] the recommended one plays
  /// as soon as it is known (after the next-episode countdown).
  Future<void> openSources(Media media, int episode, {bool autoPick = false}) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final result = await pickSource(context, media, episode, autoPick: autoPick);
    if (result != null) play(media, episode, result);
  }

  void play(Media media, int episode, TorrentResult result) {
    _dropSession();
    session = PlaybackSession(media: media, episode: episode, result: result, onNext: next);
    minimized = false;
    notifyListeners();
    _showFull();
  }

  void minimize() {
    if (session == null || minimized) return;
    minimized = true;
    _hideFull();
    notifyListeners();
  }

  void expand() {
    if (session == null || !minimized) return;
    minimized = false;
    notifyListeners();
    _showFull();
  }

  void close() {
    _hideFull();
    _dropSession();
    minimized = false;
    finished++;
    notifyListeners();
  }

  /// A season pack that holds the next episode is played again; otherwise the
  /// sheet opens, and after a countdown it plays its recommendation.
  void next(PlayerExit exit) {
    final s = session;
    if (s == null) return;
    final episode = s.episode + 1;
    final reuse = exit.reuse;
    if (reuse != null) {
      play(s.media, episode, reuse);
    } else {
      close();
      openSources(s.media, episode, autoPick: exit.auto);
    }
  }

  void _showFull() {
    final s = session;
    if (s == null || _fullRoute != null) return;
    final route = PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => PlayerScreen(session: s),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
    _fullRoute = route;
    _nav?.push(route).then((_) {
      // Closed by the system (back gesture handled by the screen) or removed below.
      if (_fullRoute == route) _fullRoute = null;
    });
  }

  void _hideFull() {
    final route = _fullRoute;
    _fullRoute = null;
    if (route == null) return;
    final nav = _nav;
    if (nav == null) return;
    if (route.isCurrent) {
      nav.pop();
    } else if (route.isActive) {
      nav.removeRoute(route);
    }
  }

  void _dropSession() {
    session?.dispose();
    session = null;
  }
}
