import 'dart:io';

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'anilist.dart';
import 'engine.dart';
import 'extensions.dart';
import 'screens/home.dart';
import 'screens/search.dart';
import 'screens/settings_screen.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  // On the desktop, debug builds show the app inside a phone frame.
  final preview = kDebugMode && Platform.isWindows;
  DevicePreview.enable(enabled: preview);
  WidgetsFlutterBinding.ensureInitialized();
  if (preview) DevicePreview.maybeController?.applyPreset(DevicePresets.iPhone16);
  MediaKit.ensureInitialized();
  await AppSettings.load();
  Engine.instance.start().catchError((_) => 0);
  AniList.instance.loadViewer();
  ExtensionStore.instance.refresh();
  runApp(const NamiApp());
}

class NamiApp extends StatelessWidget {
  const NamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        // Strings are read when widgets build, so rebuild everything on change.
        key: ValueKey('${settings.language}-${settings.titleLanguage}'),
        title: 'Nami',
        debugShowCheckedModeBanner: false,
        // Dark by design: Nami is a viewing room (DESIGN.md), so there is no light theme.
        theme: Nami.theme(),
        home: const RootScreen(),
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: tab, children: const [HomeScreen(), SearchScreen(), SettingsScreen()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t('Accueil', 'Home')),
          NavigationDestination(icon: const Icon(Icons.search), label: t('Recherche', 'Search')),
          NavigationDestination(
              icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune), label: t('Réglages', 'Settings')),
        ],
      ),
    );
  }
}
