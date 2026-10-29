import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { fr, en }

enum TitleLanguage { romaji, english, native }

/// User preferences, persisted with SharedPreferences.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static late AppSettings instance;

  static Future<void> load() async {
    instance = AppSettings._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _prefs;
  SharedPreferences get prefs => _prefs;

  AppLanguage get language => AppLanguage.values.asNameMap()[_prefs.getString('appLanguage')] ?? AppLanguage.fr;
  set language(AppLanguage v) {
    _prefs.setString('appLanguage', v.name);
    notifyListeners();
  }

  TitleLanguage get titleLanguage =>
      TitleLanguage.values.asNameMap()[_prefs.getString('titleLanguage')] ?? TitleLanguage.romaji;
  set titleLanguage(TitleLanguage v) {
    _prefs.setString('titleLanguage', v.name);
    notifyListeners();
  }

  String get resolution => _prefs.getString('resolution') ?? '1080';
  set resolution(String v) {
    _prefs.setString('resolution', v);
    notifyListeners();
  }

  /// Skip openings and endings when AniSkip knows where they are.
  bool get autoSkip => _prefs.getBool('autoSkip') ?? true;
  set autoSkip(bool v) {
    _prefs.setBool('autoSkip', v);
    notifyListeners();
  }

  /// Start the next episode after a countdown.
  bool get autoNext => _prefs.getBool('autoNext') ?? true;
  set autoNext(bool v) {
    _prefs.setBool('autoNext', v);
    notifyListeners();
  }

  SubtitleLanguage get subtitleLanguage =>
      SubtitleLanguage.values.asNameMap()[_prefs.getString('subtitleLanguage')] ?? SubtitleLanguage.fr;
  set subtitleLanguage(SubtitleLanguage v) {
    _prefs.setString('subtitleLanguage', v.name);
    notifyListeners();
  }

  /// Subtitle scale in percent, passed to mpv as sub-scale.
  int get subtitleSize => _prefs.getInt('subtitleSize') ?? 100;
  set subtitleSize(int v) {
    _prefs.setInt('subtitleSize', v);
    notifyListeners();
  }

  /// Where an episode was left, in seconds; null once it was watched to the end.
  Duration? resumeAt(int mediaId, int episode) {
    final s = _prefs.getInt('resume:$mediaId:$episode');
    return s == null ? null : Duration(seconds: s);
  }

  void setResume(int mediaId, int episode, Duration? at) {
    final key = 'resume:$mediaId:$episode';
    at == null ? _prefs.remove(key) : _prefs.setInt(key, at.inSeconds);
  }
}

/// Subtitle track picked when an episode starts. `file` keeps the release's own default.
enum SubtitleLanguage { fr, en, file }

extension SubtitleLanguageLabel on SubtitleLanguage {
  String get label => switch (this) {
    SubtitleLanguage.fr => 'Français',
    SubtitleLanguage.en => 'English',
    SubtitleLanguage.file => t('Celle du fichier', "The file's default"),
  };
}

/// Returns the string for the current interface language.
String t(String fr, String en) => AppSettings.instance.language == AppLanguage.en ? en : fr;

extension TitleLanguageLabel on TitleLanguage {
  String get label => switch (this) {
    TitleLanguage.romaji => 'Romaji',
    TitleLanguage.english => t('Anglais', 'English'),
    TitleLanguage.native => t('Japonais', 'Japanese'),
  };
}

/// AniList genre names are English identifiers; this is how they read in the UI.
String genreLabel(String g) => switch (g) {
  'Action' => 'Action',
  'Adventure' => t('Aventure', 'Adventure'),
  'Comedy' => t('Comédie', 'Comedy'),
  'Drama' => t('Drame', 'Drama'),
  'Fantasy' => t('Fantastique', 'Fantasy'),
  'Horror' => t('Horreur', 'Horror'),
  'Music' => t('Musique', 'Music'),
  'Mystery' => t('Mystère', 'Mystery'),
  'Psychological' => t('Psychologique', 'Psychological'),
  'Sci-Fi' => t('Science-fiction', 'Sci-Fi'),
  'Slice of Life' => t('Tranche de vie', 'Slice of Life'),
  'Supernatural' => t('Surnaturel', 'Supernatural'),
  _ => g,
};

extension AppLanguageLabel on AppLanguage {
  String get label => this == AppLanguage.fr ? 'Français' : 'English';
}
