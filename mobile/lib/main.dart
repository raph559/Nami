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
import 'widgets.dart';

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
    final items = [
      (Icons.home_outlined, Icons.home, t('Accueil', 'Home')),
      (Icons.search, Icons.search, t('Recherche', 'Search')),
      (Icons.tune_outlined, Icons.tune, t('Réglages', 'Settings')),
    ];
    final pages = IndexedStack(index: tab, children: const [HomeScreen(), SearchScreen(), SettingsScreen()]);
    Widget item(int i, {required bool vertical}) => _NavItem(
      icon: tab == i ? items[i].$2 : items[i].$1,
      label: items[i].$3,
      selected: tab == i,
      vertical: vertical,
      onTap: () => setState(() => tab = i),
    );
    // Wide windows (tablet landscape, desktop) get a side rail so the
    // content keeps its height; phones keep the bottom bar.
    if (MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: SizedBox(
                width: 96,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    for (var i = 0; i < items.length; i++) item(i, vertical: true),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: Nami.line),
            Expanded(child: pages),
          ],
        ),
      );
    }
    return Scaffold(
      body: pages,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Nami.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [for (var i = 0; i < items.length; i++) Expanded(child: item(i, vertical: true))]),
          ),
        ),
      ),
    );
  }
}

/// One destination of the bottom bar or side rail. The selected one is told
/// apart by its filled icon and bold label, not by color alone.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.vertical,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Nami.text : Nami.textMuted;
    return FocusOutline(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Nami.radiusButton),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Nami.sans,
                      fontSize: 12,
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
