import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// How a platform shrinks the video to a small window above other apps.
abstract class PipWindow {
  Future<void> enter();
  Future<void> exit();
}

/// Android's own Picture-in-Picture: the system moves and sizes the window.
class AndroidPip implements PipWindow {
  const AndroidPip(this.channel);
  final MethodChannel channel;

  @override
  Future<void> enter() => channel.invokeMethod<void>('enter');

  /// The system's expand button is the way out.
  @override
  Future<void> exit() async {}
}

/// Windows has no such thing: Nami's own window becomes small and stays on top.
class WindowsPip implements PipWindow {
  static const _size = Size(480, 270);
  Rect? _bounds;

  @override
  Future<void> enter() async {
    _bounds = await windowManager.getBounds();
    await windowManager.setMinimumSize(const Size(320, 180));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(_size);
    await windowManager.setAlignment(Alignment.bottomRight);
  }

  @override
  Future<void> exit() async {
    await windowManager.setAlwaysOnTop(false);
    final bounds = _bounds;
    if (bounds != null) await windowManager.setBounds(bounds);
  }
}

/// The small floating video, for the whole app.
class Pip extends ChangeNotifier {
  Pip(this._window, {MethodChannel? channel}) : _channel = channel {
    channel?.setMethodCallHandler(_onCall);
  }

  static const _android = MethodChannel('nami/pip');

  static final instance = Pip(switch (Platform.operatingSystem) {
    'android' => const AndroidPip(_android),
    'windows' => WindowsPip(),
    _ => null,
  }, channel: Platform.isAndroid ? _android : null);

  final PipWindow? _window;
  final MethodChannel? _channel;

  bool active = false;

  /// The window's own pause button (Android).
  VoidCallback? onTogglePause;

  /// The window was closed, not expanded: nothing shows the video any more.
  VoidCallback? onClosed;

  bool get supported => _window != null;

  Future<void> enter() async {
    if (active) return;
    await _window?.enter();
    // Android says so itself once the window is up.
    if (_channel == null) _set(true);
  }

  Future<void> exit() async {
    if (!active) return;
    await _window?.exit();
    if (_channel == null) _set(false);
  }

  /// Keeps the system's pause button right.
  void setPlaying(bool playing) => _channel?.invokeMethod<void>('playing', playing);

  /// Android: leaving the app with Home goes to the small window by itself.
  void setAuto(bool on) => _channel?.invokeMethod<void>('auto', on);

  void _set(bool on) {
    active = on;
    notifyListeners();
  }

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'changed':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _set(args['active'] == true);
        if (args['closed'] == true) onClosed?.call();
      case 'togglePause':
        onTogglePause?.call();
    }
  }
}
