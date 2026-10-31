import 'dart:io';

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'anilist.dart';
import 'engine.dart';
import 'extensions.dart';
import 'player_center.dart';
import 'screens/player.dart';
import 'screens/calendar.dart';
import 'screens/home.dart';
import 'screens/library.dart';
import 'screens/search.dart';
import 'screens/settings_screen.dart';
import 'platform.dart';
import 'ui/desktop_shell.dart';
import 'ui/motion.dart';
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
  if (Platform.isWindows && !preview) {
    // Nami draws its own transparent title bar (see WindowChrome).
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  }
  await AppSettings.load();
  _registerLicenses();
  Engine.instance.start().catchError((_) => 0);
  AniList.instance.loadViewer();
  ExtensionStore.instance.refresh();
  runApp(const NamiApp());
}

class NamiApp extends StatelessWidget {
  const NamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LanguageScope(
      child: MaterialApp(
        title: 'Nami',
        debugShowCheckedModeBanner: false,
        // Dark by design: Nami is a viewing room (DESIGN.md), so there is no light theme.
        theme: isDesktop ? Nami.desktopTheme() : Nami.theme(),
        navigatorKey: PlayerCenter.instance.navigatorKey,
        // The mini-player floats above every page, so browsing keeps it on screen.
        // Overlay.wrap gives its tooltips an overlay above the navigator.
        builder: (context, child) => Overlay.wrap(
          child: WindowChrome(child: Stack(children: [child!, const MiniPlayerHost()])),
        ),
        home: const RootScreen(),
      ),
    );
  }
}

/// Strings and titles are read when widgets build, so changing the language
/// rebuilds every widget below, in place: the page, the tab, the scroll position
/// and the player all stay where they are.
class LanguageScope extends StatefulWidget {
  const LanguageScope({super.key, required this.child});
  final Widget child;

  @override
  State<LanguageScope> createState() => _LanguageScopeState();
}

class _LanguageScopeState extends State<LanguageScope> {
  AppLanguage language = AppSettings.instance.language;
  TitleLanguage titles = AppSettings.instance.titleLanguage;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettings);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    final settings = AppSettings.instance;
    if (settings.language == language && settings.titleLanguage == titles) return;
    language = settings.language;
    titles = settings.titleLanguage;
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key, this.pages});

  /// Replaces the four tab pages in tests.
  @visibleForTesting
  final List<Widget>? pages;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int tab = 0;

  /// The calendar asks AniList for a whole week, so it waits until it is opened.
  bool _calendarOpened = false;
  final _searchFocus = FocusNode(debugLabel: 'search field');

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() {
    tab = i;
    if (i == 2) _calendarOpened = true;
  });

  void _openSearch() {
    setState(() => tab = 1);
    // After the frame: the field must be visible before it can take focus.
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  /// Ctrl+K anywhere, or "/" when no text field is being edited, opens the search.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final ctrlK = event.logicalKey == LogicalKeyboardKey.keyK && (keys.isControlPressed || keys.isMetaPressed);
    // EditableText puts its node in a Focus widget, so look for it among the ancestors.
    final focused = FocusManager.instance.primaryFocus?.context;
    final editing =
        focused != null &&
        (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null);
    final slash = event.logicalKey == LogicalKeyboardKey.slash && !editing;
    if (!ctrlK && !slash) return KeyEventResult.ignored;
    _openSearch();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home, t('Accueil', 'Home')),
      (Icons.search, Icons.search, t('Recherche', 'Search')),
      (Icons.calendar_today_outlined, Icons.calendar_today, t('Calendrier', 'Calendar')),
      (Icons.bookmark_border, Icons.bookmark, t('Ma liste', 'My list')),
      (Icons.tune_outlined, Icons.tune, t('Réglages', 'Settings')),
    ];
    final children =
        widget.pages ??
        [
          const HomeScreen(),
          const SearchScreen(),
          if (_calendarOpened)
            ValueListenableBuilder(
              valueListenable: AniList.instance.listIds,
              builder: (context, ids, _) => CalendarScreen(listIds: ids),
            )
          else
            const SizedBox.shrink(),
          const LibraryScreen(),
          const SettingsScreen(),
        ];
    if (isDesktop) {
      final shell = DesktopShell(
        items: [for (final i in items) (icon: i.$1, selectedIcon: i.$2, label: i.$3)],
        index: tab,
        onSelect: _select,
        pages: children,
        badgedIndex: 3,
        onAccount: () => AniList.instance.isLoggedIn
            ? _select(3)
            : Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
      );
      return SearchFocus(
        node: _searchFocus,
        child: Focus(autofocus: true, onKeyEvent: _onKey, child: shell),
      );
    }
    final pages = FadeIndexedStack(index: tab, children: children);
    Widget item(int i, {required bool vertical, bool showLabel = true}) => _NavItem(
      icon: tab == i ? items[i].$2 : items[i].$1,
      label: items[i].$3,
      selected: tab == i,
      vertical: vertical,
      badged: i == 3,
      showLabel: showLabel,
      onTap: () => _select(i),
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
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) Expanded(child: item(i, vertical: true, showLabel: tab == i)),
              ],
            ),
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
    this.showLabel = true,
    this.badged = false,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool vertical;
  final VoidCallback onTap;

  /// The phone bar names only the current tab; the others keep their name for screen readers and as a tooltip.
  final bool showLabel;

  /// Shows the count of new episodes on the icon.
  final bool badged;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Nami.text : Nami.textMuted;
    final glyph = Icon(icon, color: color, size: showLabel ? 24 : 22);
    return FocusOutline(
      child: Semantics(
        selected: selected,
        button: true,
        label: showLabel ? null : label,
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
                  if (badged) NewEpisodesBadge(child: glyph) else glyph,
                  if (showLabel) ...[
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On Windows the system title bar is hidden: the pages run to the top edge
/// and the window buttons sit on a transparent strip that also moves the
/// window. Pages get the strip's height as top padding, like a status bar.
class WindowChrome extends StatelessWidget {
  const WindowChrome({super.key, required this.child});
  final Widget child;

  static const height = 32.0;

  @override
  Widget build(BuildContext context) {
    // Debug builds show the app in a phone frame (DevicePreview) and keep the system bar.
    if (!Platform.isWindows || kDebugMode) return child;
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(top: height),
            viewPadding: media.viewPadding.copyWith(top: height),
          ),
          child: child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: ValueListenableBuilder(
            valueListenable: windowChromeVisible,
            builder: (context, show, _) => AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !show,
                child: const WindowCaption(backgroundColor: Colors.transparent, brightness: Brightness.dark),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Components that are not Dart packages, so the license page lists them too
/// (pub packages are added by Flutter itself). See THIRD_PARTY_NOTICES.md.
void _registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['mpv', 'FFmpeg'],
      'Played through media_kit, dynamically linked and shipped unmodified.\n'
      'GNU Lesser General Public License, version 2.1 or later.\n'
      'https://mpv.io · https://ffmpeg.org',
    );
    yield const LicenseEntryWithLineBreaks(
      ['anacrolix/torrent'],
      'The torrent engine, with the Go modules listed in THIRD_PARTY_NOTICES.md.\n'
      'Mozilla Public License 2.0. https://github.com/anacrolix/torrent',
    );
    yield LicenseEntryWithLineBreaks([
      'Hanken Grotesk',
    ], await rootBundle.loadString('assets/fonts/OFL-HankenGrotesk.txt'));
  });
}
