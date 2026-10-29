import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../anilist.dart';
import '../extensions.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = TextEditingController();
  bool busy = false;
  String version = '';

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

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Semantics(header: true, child: Text(text, style: Nami.section.copyWith(fontSize: 18))),
  );

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final anilist = AniList.instance;
    final store = ExtensionStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(t('Réglages', 'Settings'))),
      body: ListenableBuilder(
        listenable: Listenable.merge([anilist, store]),
        builder: (context, _) => ContentWidth(
          child: ListView(
            children: [
              _header('AniList'),
              if (anilist.viewer != null)
                ListTile(
                  leading: SizedBox(width: 40, height: 40, child: CoverImage(anilist.viewer!.avatar, radius: 20)),
                  title: Text(anilist.viewer!.name),
                  trailing: FocusOutline(
                    child: TextButton(onPressed: anilist.logout, child: Text(t('Se déconnecter', 'Log out'))),
                  ),
                )
              else
                FocusOutline(
                  radius: 0,
                  gap: -2,
                  child: ListTile(
                    leading: const Icon(Icons.login),
                    title: Text(t('Se connecter à AniList', 'Log in to AniList')),
                    subtitle: Text(
                      t(
                        'Pour reprendre tes animes et cocher les épisodes vus.',
                        'To resume your anime and tick off watched episodes.',
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                  ),
                ),
              _header(t('Langue', 'Language')),
              _Choice<AppLanguage>(
                label: t("Langue de l'app", 'App language'),
                value: settings.language,
                onChanged: (v) => settings.language = v,
                items: {for (final l in AppLanguage.values) l: l.label},
              ),
              _Choice<TitleLanguage>(
                label: t('Titres des animes', 'Anime titles'),
                value: settings.titleLanguage,
                onChanged: (v) => settings.titleLanguage = v,
                items: {for (final l in TitleLanguage.values) l: l.label},
              ),
              _header(t('Lecture', 'Playback')),
              _Choice<String>(
                label: t('Qualité préférée', 'Preferred quality'),
                value: settings.resolution,
                onChanged: (v) => settings.resolution = v,
                items: {
                  for (final r in ['1080', '720', '480']) r: '${r}p',
                },
              ),
              _header('Extensions'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Field on its own line so the URL stays readable at any text size.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
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
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: busy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : FocusOutline(
                              child: OutlinedButton(
                                onPressed: _addRepo,
                                child: Text(t('Ajouter le dépôt', 'Add repository')),
                              ),
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
                    title: Text(Uri.tryParse(repo)?.host ?? repo),
                    subtitle: Text(repo, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: t('Retirer ce dépôt', 'Remove this repository'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmRemove(repo),
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RepoScreen(repo: repo))),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  t(
                    "Même format que les extensions Hayase : colle l'URL de l'index.json du dépôt.",
                    "Same format as Hayase extensions: paste the repository's index.json URL.",
                  ),
                  style: Nami.caption,
                ),
              ),
              _header('Nami'),
              ListTile(title: const Text('Version'), trailing: Text(version)),
              const SizedBox(height: 24),
            ],
          ),
        ),
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
      appBar: AppBar(title: Text(Uri.tryParse(repo)?.host ?? t('Dépôt', 'Repository'))),
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
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Connexion AniList', 'AniList login'))),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri.uri(aniListAuthorizeUrl)),
        initialSettings: InAppWebViewSettings(useShouldOverrideUrlLoading: true),
        shouldOverrideUrlLoading: (controller, action) async {
          final url = action.request.url;
          if (url != null && url.scheme == 'nami') {
            final ok = await AniList.instance.completeLogin(url);
            if (context.mounted) {
              Navigator.pop(context);
              if (!ok) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(t('Connexion refusée', 'Login refused'))));
              }
            }
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
      ),
    );
  }
}

/// A labelled dropdown that wraps under its label when the text is large.
class _Choice<T> extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.value, required this.onChanged, required this.items});
  final String label;
  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        children: [
          Text(label, style: Nami.body),
          FocusOutline(
            child: DropdownButton<T>(
              value: value,
              underline: Container(height: 1, color: Nami.border),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            ),
          ),
        ],
      ),
    );
  }
}
