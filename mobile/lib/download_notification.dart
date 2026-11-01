import 'package:flutter/services.dart';

import 'downloads.dart';
import 'settings.dart';

/// Android only: the notification that keeps a download going in the
/// background (see DownloadService).
class DownloadNotification {
  DownloadNotification(this._store, [this._channel = const MethodChannel('nami/downloads')]) {
    _store.addListener(_update);
  }

  final Downloads _store;
  final MethodChannel _channel;
  bool _shown = false;
  bool _asked = false;
  int _percent = -1;

  void _update() {
    DownloadEntry? running;
    for (final e in _store.entries) {
      if (e.state == DownloadState.running) running = e;
    }
    if (running == null) {
      if (_shown) _channel.invokeMethod<void>('stop');
      _shown = false;
      _percent = -1;
      return;
    }
    final percent = (running.fraction * 100).floor();
    if (_shown && percent == _percent) return;
    if (!_asked && AppSettings.instance.prefs.getBool('notificationsAsked') != true) {
      _channel.invokeMethod<void>('askPermission');
      AppSettings.instance.prefs.setBool('notificationsAsked', true);
    }
    _asked = true;
    _shown = true;
    _percent = percent;
    _channel.invokeMethod<void>('update', {
      'title': '${running.media.title.display} · ${t('Épisode ${running.episode}', 'Episode ${running.episode}')}',
      'text': t('Téléchargement · $percent %', 'Downloading · $percent %'),
      'percent': percent,
    });
  }
}
