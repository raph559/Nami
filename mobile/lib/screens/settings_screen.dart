import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../anilist.dart';
import '../extensions.dart';
import '../platform.dart';
import '../settings.dart';
import '../theme.dart';
import '../ui/motion.dart';
import '../widgets.dart';

const sourceUrl = 'https://github.com/raph559/Nami';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = TextEditingController();
  bool busy = false;
  String version = '';

  /// The section shown on desktop.
  int section = 0;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => version = p.version);
    });
  }

  @override
  void dispose() {
    _repo.dispose();
    super.dispose();
  }

  Future<void> _addRepo() async {
    setState(() => busy = true);
    try {
      await ExtensionStore.instance.addRepo(_repo.text);
      _repo.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('Impossible de charger ce dépôt : ', 'Could not load this repository: ') + e.toString()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirmRemove(String repo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Retirer ce dépôt ?', 'Remove this repository?')),
        content: Text(
          t(
            'Ses extensions ne seront plus utilisées pour chercher des sources.',
            'Its extensions will no longer be used to find sources.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Garder', 'Keep'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Retirer', 'Remove'))),
        ],
      ),
    );
    if (ok == true) ExtensionStore.instance.removeRepo(repo);
  }

  /// "2 of 3 on: NekoBT, AnimeTosho, …" so each repository says what it brings.
  String _repoSummary(ExtensionStore store, String repo) {
    final exts = store.installed.where((e) => e.repo == repo).toList();
    if (exts.isEmpty) return t('Aucune extension', 'No extensions');
    final on = exts.where((e) => e.enabled).length;
    final names = exts.map((e) => e.manifest.name).join(', ');
    return t('$on sur ${exts.length} activées : $names', '$on of ${exts.length} on: $names');
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final anilist = AniList.instance;
    final store = ExtensionStore.instance;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([anilist, store, settings]),
        builder: (context, _) {
          final wide = MediaQuery.sizeOf(context).width >= 900;
          final account = _Section(
            title: t('Compte', 'Account'),
            flat: isDesktop,
            children: [
              if (anilist.viewer != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(width: 52, height: 52, child: CoverImage(anilist.viewer!.avatar, radius: 26)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(anilist.viewer!.name, style: Nami.body.copyWith(fontWeight: FontWeight.w700)),
                            Text(t('Connecté', 'Logged in'), style: Nami.caption),
                          ],
                        ),
                      ),
                      FocusOutline(
                        child: OutlinedButton(onPressed: anilist.logout, child: Text(t('Se déconnecter', 'Log out'))),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(
                          'Connecte ton compte pour reprendre tes animes et cocher les épisodes vus.',
                          'Log in to resume your anime and tick off watched episodes.',
                        ),
                        style: Nami.meta,
                      ),
                      const SizedBox(height: 12),
                      FocusOutline(
                        child: FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                          icon: const Icon(Icons.login),
                          label: Text(t('Se connecter à AniList', 'Log in to AniList')),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
          final language = _Section(
            title: t('Langue', 'Language'),
            flat: isDesktop,
            children: [
              _Setting(
                label: t("Langue de l'app", 'App language'),
                control: _Segments<AppLanguage>(
                  value: settings.language,
                  onChanged: (v) => settings.language = v,
                  items: {for (final l in AppLanguage.values) l: Text(l.label)},
                ),
              ),
              _Setting(
                label: t('Titres des animes', 'Anime titles'),
                control: _Segments<TitleLanguage>(
                  value: settings.titleLanguage,
                  onChanged: (v) => settings.titleLanguage = v,
                  items: {for (final l in TitleLanguage.values) l: Text(l.label)},
                ),
              ),
            ],
          );
          final playback = _Section(
            title: t('Lecture', 'Playback'),
            flat: isDesktop,
            children: [
              _Setting(
                label: t('Qualité préférée', 'Preferred quality'),
                detail: t('La source recommandée la privilégie.', 'The recommended source favours it.'),
                warning: switch (settings.resolution) {
                  '2160' || '1440' => t(
                    'Peu de releases existent dans cette qualité, et un épisode pèse souvent 4 à 10 Go : '
                        'lancement plus lent, forfait vite consommé en 4G/5G.',
                    'Few releases exist in this quality, and an episode often weighs 4 to 10 GB: '
                        'slower to start, and mobile data goes fast.',
                  ),
                  _ => null,
                },
                control: _Segments<String>(
                  value: settings.resolution,
                  onChanged: (v) => settings.resolution = v,
                  items: {
                    for (final r in ['480', '720', '1080', '1440', '2160']) r: Text('${r}p'),
                  },
                ),
              ),
              _Setting(
                label: t("Passer l'intro et le générique", 'Skip openings and endings'),
                detail: t(
                  'Automatiquement, quand AniSkip connaît leurs horaires.',
                  'Automatically, when AniSkip knows where they are.',
                ),
                control: Switch(value: settings.autoSkip, onChanged: (v) => settings.autoSkip = v),
                inline: true,
              ),
              _Setting(
                label: t("Enchaîner l'épisode suivant", 'Play the next episode'),
                detail: t('Après un compte à rebours de 10 secondes.', 'After a 10 second countdown.'),
                control: Switch(value: settings.autoNext, onChanged: (v) => settings.autoNext = v),
                inline: true,
              ),
              if (isDesktop) const _Shortcuts(),
            ],
          );
          final subtitles = _Section(
            title: t('Sous-titres', 'Subtitles'),
            flat: isDesktop,
            children: [
              _Setting(
                label: t('Langue des sous-titres', 'Subtitle language'),
                detail: t('Langue choisie au début de chaque épisode.', 'Language picked when an episode starts.'),
                control: _Segments<SubtitleLanguage>(
                  value: settings.subtitleLanguage,
                  onChanged: (v) => settings.subtitleLanguage = v,
                  items: {for (final l in SubtitleLanguage.values) l: Text(l.label)},
                ),
              ),
              _Setting(
                label: t('Taille des sous-titres', 'Subtitle size'),
                // Each choice shows its size, so the right one is picked at a glance.
                control: _Segments<int>(
                  value: settings.subtitleSize,
                  onChanged: (v) => settings.subtitleSize = v,
                  items: {
                    for (final (size, font, label) in [
                      (80, 12.0, t('Petite', 'Small')),
                      (100, 15.0, t('Normale', 'Normal')),
                      (125, 18.0, t('Grande', 'Large')),
                      (150, 21.0, t('Très grande', 'Extra large')),
                    ])
                      size: Semantics(
                        label: label,
                        excludeSemantics: true,
                        child: Text(
                          'Aa',
                          style: TextStyle(fontSize: font, fontWeight: FontWeight.w600),
                        ),
                      ),
                  },
                ),
              ),
            ],
          );
          final extensions = _Section(
            title: t('Sources et extensions', 'Sources and extensions'),
            flat: isDesktop,
            footer: t(
              "Même format que les extensions Hayase : colle l'URL de l'index.json du dépôt.",
              "Same format as Hayase extensions: paste the repository's index.json URL.",
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _repo,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        decoration: InputDecoration(
                          labelText: t('URL du dépôt', 'Repository URL'),
                          hintText: 'https://…/index.json',
                        ),
                        onSubmitted: (_) => _addRepo(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : FocusOutline(
                              child: FilledButton(onPressed: _addRepo, child: Text(t('Ajouter', 'Add'))),
                            ),
                    ),
                  ],
                ),
              ),
              for (final repo in store.repos)
                FocusOutline(
                  radius: 0,
                  gap: -2,
                  child: ListTile(
                    leading: const Icon(Icons.extension_outlined),
                    title: Text(ExtensionStore.repoLabel(repo)),
                    subtitle: Text(_repoSummary(store, repo), maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: t('Retirer ce dépôt', 'Remove this repository'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmRemove(repo),
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RepoScreen(repo: repo))),
                  ),
                ),
              if (store.repos.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(t('Aucun dépôt pour le moment.', 'No repository yet.'), style: Nami.meta),
                ),
            ],
          );
          final about = _Section(
            title: t('À propos', 'About'),
            flat: isDesktop,
            children: [
              ListTile(
                title: Text(t('Créée par', 'Made by')),
                trailing: Text('raph559', style: Nami.body.copyWith(fontWeight: FontWeight.w700)),
              ),
              FocusOutline(
                radius: 0,
                gap: -2,
                child: ListTile(
                  title: Text(t('Code source', 'Source code')),
                  subtitle: const Text('github.com/raph559/Nami'),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => launchUrl(Uri.parse(sourceUrl), mode: LaunchMode.externalApplication),
                ),
              ),
              ListTile(
                title: const Text('Version'),
                trailing: Text(version, style: Nami.meta),
              ),
              FocusOutline(
                radius: 0,
                gap: -2,
                child: ListTile(
                  title: Text(t('Licence et logiciels tiers', 'License and third-party software')),
                  subtitle: Text(
                    t('GPL-3.0 · mpv, FFmpeg, anacrolix/torrent…', 'GPL-3.0 · mpv, FFmpeg, anacrolix/torrent…'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Nami',
                    applicationVersion: version,
                    applicationLegalese: t(
                      '© raph559 · Logiciel libre sous GPL-3.0\n$sourceUrl',
                      '© raph559 · Free software under GPL-3.0\n$sourceUrl',
                    ),
                  ),
                ),
              ),
            ],
          );
          final all = [account, playback, subtitles, extensions, language, about];
          if (isDesktop) {
            // Sections on the left, the chosen one on the right.
            final left = MediaQuery.paddingOf(context).left;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: left + 260,
                  padding: EdgeInsets.fromLTRB(left + 28, top + 26, 16, 16),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: Nami.line)),
                  ),
                  // Scrolls when the window is short or the text large.
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      Semantics(header: true, child: Text(t('Réglages', 'Settings'), style: Nami.pageTitle)),
                      const SizedBox(height: 18),
                      for (var i = 0; i < all.length; i++)
                        _NavEntry(
                          label: all[i].title,
                          selected: i == section,
                          onTap: () => setState(() => section = i),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(40, top + 14, 40, 32),
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: all[section]),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          final side = wide ? 48.0 : 20.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(side, top + (wide ? 32 : 20), side, 32),
            children: [
              Semantics(header: true, child: Text(t('Réglages', 'Settings'), style: Nami.pageTitle)),
              const SizedBox(height: 8),
              if (wide)
                // Two columns on a wide window: account and preferences, then sources and app.
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: [account, language, playback, subtitles])),
                        const SizedBox(width: 32),
                        Expanded(child: Column(children: [extensions, about])),
                      ],
                    ),
                  ),
                )
              else
                ContentWidth(child: Column(children: all)),
            ],
          );
        },
      ),
    );
  }
}

class RepoScreen extends StatelessWidget {
  const RepoScreen({super.key, required this.repo});
  final String repo;

  @override
  Widget build(BuildContext context) {
    final store = ExtensionStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(ExtensionStore.repoLabel(repo))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          children: [
            for (final ext in store.installed.where((e) => e.repo == repo)) ...[
              FocusOutline(
                radius: 0,
                gap: -2,
                child: SwitchListTile(
                  value: ext.enabled,
                  onChanged: ext.manifest.isSupported ? (v) => store.setEnabled(ext, v) : null,
                  secondary: SizedBox(width: 28, height: 28, child: CoverImage(ext.manifest.icon, radius: 6)),
                  title: Text(ext.manifest.name),
                  subtitle: Text(
                    [
                      if (ext.manifest.version != null) 'v${ext.manifest.version}',
                      if (ext.manifest.media == 'sub') t('sous-titré', 'subtitled'),
                      if (ext.manifest.media == 'dub') t('doublé', 'dubbed'),
                      if (!ext.manifest.isSupported) t('non supportée', 'unsupported'),
                    ].join(' · '),
                  ),
                ),
              ),
              for (final opt in ext.manifest.options.entries)
                if ((opt.value as Map)['type'] == 'boolean')
                  FocusOutline(
                    radius: 0,
                    gap: -2,
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.only(left: 56, right: 16),
                      value: (ext.options[opt.key] ?? (opt.value as Map)['default'] ?? false) == true,
                      onChanged: (v) => store.setOption(ext, opt.key, v),
                      title: Text(opt.key),
                      subtitle: Text((opt.value as Map)['description']?.toString() ?? ''),
                    ),
                  ),
              const Divider(),
            ],
          ],
        ),
      ),
    );
  }
}

/// AniList login in an embedded browser; the implicit-grant redirect to
/// nami://auth is intercepted here, so it works the same on every platform.
/// WebView2 on Windows only reports network requests to
/// shouldOverrideUrlLoading, so the redirect is also caught when the page
/// starts loading or fails to.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _handled = false;

  /// True when [url] is the redirect; logs in and closes the screen once.
  bool _catch(Uri? url) {
    if (url == null || url.scheme != 'nami') return false;
    if (_handled) return true;
    _handled = true;
    AniList.instance.completeLogin(url).then((ok) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(t('Connexion refusée', 'Login refused'))));
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Connexion AniList', 'AniList login'))),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri.uri(aniListAuthorizeUrl)),
        initialSettings: InAppWebViewSettings(useShouldOverrideUrlLoading: !Platform.isWindows),
        shouldOverrideUrlLoading: (controller, action) async =>
            _catch(action.request.url) ? NavigationActionPolicy.CANCEL : NavigationActionPolicy.ALLOW,
        onLoadStart: (controller, url) {
          if (_catch(url)) controller.stopLoading();
        },
        onUpdateVisitedHistory: (controller, url, _) => _catch(url),
        onReceivedError: (controller, request, error) => _catch(request.url),
      ),
    );
  }
}

/// A labelled dropdown that wraps under its label when the text is large.
/// A titled group of settings on its own card.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.footer, this.flat = false});
  final String title;
  final List<Widget> children;
  final String? footer;

  /// Desktop pane: rows on lines, no card around them.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    if (flat) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6, top: 12),
            child: Semantics(header: true, child: Text(title, style: Nami.section.copyWith(fontSize: 20))),
          ),
          Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children) ...[child, Divider(height: 1, thickness: 1, color: Nami.line)],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(footer!, style: Nami.caption),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Semantics(header: true, child: Text(title, style: Nami.section.copyWith(fontSize: 17))),
          ),
          // A Material surface, so the rows' touch ripples show on the card.
          Material(
            color: const Color(0xFF131315),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Nami.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: Nami.line),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(footer!, style: Nami.caption),
            ),
        ],
      ),
    );
  }
}

/// One setting: its name and what it does, then its control. Choices go
/// under the text when the card is narrow, beside it when there is room;
/// switches always sit at the end of the line.
class _Setting extends StatelessWidget {
  const _Setting({required this.label, required this.control, this.detail, this.warning, this.inline = false});
  final String label;
  final String? detail;

  /// Shown in amber with an icon, under the text: the icon and words carry it, not the color alone.
  final String? warning;
  final Widget control;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Nami.body),
        if (detail != null) ...[const SizedBox(height: 2), Text(detail!, style: Nami.caption)],
        if (warning != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Nami.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(warning!, style: Nami.caption.copyWith(color: Nami.warning)),
              ),
            ],
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, box) {
          if (inline) {
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 12),
                control,
              ],
            );
          }
          if (box.maxWidth >= 560) {
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                control,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [text, const SizedBox(height: 10), control],
          );
        },
      ),
    );
  }
}

/// Segmented choice: every option visible at once, the chosen one filled.
class _Segments<T> extends StatelessWidget {
  const _Segments({required this.value, required this.onChanged, required this.items});
  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, Widget> items;

  @override
  Widget build(BuildContext context) {
    return FocusOutline(
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [for (final e in items.entries) ButtonSegment(value: e.key, label: e.value)],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nami.radiusButton))),
          side: WidgetStatePropertyAll(BorderSide(color: Nami.border)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Nami.text : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Nami.ground : Nami.text,
          ),
          // Semi-bold when chosen: thin dark strokes on off-white read lighter than they are.
          textStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontFamily: Nami.sans,
              fontSize: 14,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// One section in the desktop settings list.
class _NavEntry extends StatelessWidget {
  const _NavEntry({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: FocusOutline(
        child: Material(
          type: MaterialType.transparency,
          child: QuietTap(
            onTap: onTap,
            builder: (context, hovered) => AnimatedContainer(
              duration: motion.fast,
              curve: Motion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Nami.text.withValues(alpha: selected ? 0.08 : (hovered ? 0.04 : 0)),
                borderRadius: BorderRadius.circular(Nami.radiusButton),
              ),
              child: AnimatedDefaultTextStyle(
                duration: motion.fast,
                style: Nami.body.copyWith(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected || hovered ? Nami.text : Nami.textSecondary,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The player's keyboard shortcuts, so they can be found (desktop only).
class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    final keys = [
      ('Espace', t('Lecture / pause', 'Play / pause')),
      ('K', t('Lecture / pause', 'Play / pause')),
      // Words, not arrows: the app font has no arrow glyphs.
      (t('Flèches', 'Arrows'), t('Reculer / avancer de 10 s', 'Back / forward 10 s')),
      ('S', t("Passer l'intro", 'Skip the opening')),
      ('F', t("Remplir l'écran", 'Fill the screen')),
      ('Z X', t('Décaler les sous-titres', 'Shift the subtitles')),
      ('F11', t('Plein écran', 'Full screen')),
      ('Échap', t('Réduire le lecteur', 'Shrink the player')),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Raccourcis du lecteur', 'Player shortcuts'), style: Nami.body),
          const SizedBox(height: 10),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              for (final (key, action) in keys)
                SizedBox(
                  width: 220,
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Nami.border),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          child: Text(key, style: Nami.caption.copyWith(color: Nami.text)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(action, style: Nami.caption)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
