import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/settings_screen.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpSettings(WidgetTester tester, {required bool desktop, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr', ...prefs});
  await AppSettings.load();
  PackageInfo.setMockInitialValues(
    appName: 'Nami',
    packageName: 'com.raphr.nami',
    version: '0.5.0',
    buildNumber: '5',
    buildSignature: '',
  );
  debugDesktopOverride = desktop;
  addTearDown(() => debugDesktopOverride = null);
  tester.view.physicalSize = desktop ? const Size(1600, 900) : const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: desktop ? Nami.desktopTheme() : Nami.theme(), home: const SettingsScreen()),
  );
  await tester.pump();
}

/// Each section and controls that must be found in it.
const sections = {
  'Compte': ['Se connecter à AniList'],
  'Lecture': [
    'Qualité préférée',
    "Passer l'intro et le générique",
    "Enchaîner l'épisode suivant",
    'Raccourcis du lecteur',
  ],
  'Sous-titres': ['Langue des sous-titres', 'Taille des sous-titres'],
  'Sources et extensions': ['URL du dépôt'],
  'Langue': ["Langue de l'app", 'Titres des animes'],
  'À propos': ['Créée par', 'Code source', 'Version', 'Licence et logiciels tiers'],
};

void main() {
  testWidgets('desktop shows one section at a time', (tester) async {
    await pumpSettings(tester, desktop: true);
    expect(find.text('Qualité préférée'), findsNothing);
    await tester.tap(find.text('Sous-titres'));
    await tester.pump();
    expect(find.text('Taille des sous-titres'), findsOneWidget);
    expect(find.text('Qualité préférée'), findsNothing);
  });

  testWidgets('every setting is still reachable on desktop', (tester) async {
    await pumpSettings(tester, desktop: true);
    for (final MapEntry(key: section, value: labels) in sections.entries) {
      await tester.tap(find.text(section).first);
      await tester.pump();
      for (final label in labels) {
        expect(find.text(label), findsOneWidget, reason: '$label in $section');
      }
    }
  });

  testWidgets('every setting is still reachable on the phone', (tester) async {
    await pumpSettings(tester, desktop: false);
    for (final labels in sections.values) {
      for (final label in labels) {
        if (label == 'Raccourcis du lecteur') continue;
        expect(find.text(label), findsOneWidget, reason: label);
      }
    }
    expect(find.text('Raccourcis du lecteur'), findsNothing);
  });

  testWidgets('2160p still warns', (tester) async {
    await pumpSettings(tester, desktop: true, prefs: {'resolution': '2160'});
    await tester.tap(find.text('Lecture').first);
    await tester.pump();
    expect(find.textContaining('4 à 10 Go'), findsOneWidget);
  });

  testWidgets('the shortcuts list matches the player keys', (tester) async {
    await pumpSettings(tester, desktop: true);
    await tester.tap(find.text('Lecture').first);
    await tester.pump();
    for (final key in ['Espace', 'K', 'Flèches', 'S', 'F', 'Z X', 'F11', 'Échap']) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
  });

  testWidgets('the chosen quality reads black on off-white', (tester) async {
    await pumpSettings(tester, desktop: true);
    await tester.tap(find.text('Lecture').first);
    await tester.pumpAndSettle();
    final text = tester.widget<RichText>(find.descendant(of: find.text('1080p'), matching: find.byType(RichText)));
    final style = text.text.style!;
    expect(style.color, Nami.ground);
    expect(style.fontWeight, FontWeight.w600);
  });

  testWidgets('desktop settings at the smallest window with large text', (tester) async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
    PackageInfo.setMockInitialValues(
      appName: 'Nami',
      packageName: 'n',
      version: '0.5.0',
      buildNumber: '5',
      buildSignature: '',
    );
    debugDesktopOverride = true;
    addTearDown(() => debugDesktopOverride = null);
    tester.view.physicalSize = const Size(720, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: Nami.desktopTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('À propos'), 100, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('À propos'));
    await tester.pump();
    expect(find.text('Code source'), findsOneWidget);
  });
}
