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

  AppLanguage get language =>
      AppLanguage.values.asNameMap()[_prefs.getString('appLanguage')] ?? AppLanguage.fr;
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
