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
            SnackBar(content: Text(t('Impossible de charger ce dépôt : ', 'Could not load this repository: ') + e.toString())));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(text, style: Nami.section.copyWith(fontSize: 22)),
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
        builder: (context, _) => ListView(
          children: [
            _header('AniList'),
            if (anilist.viewer != null)
              ListTile(
                leading: SizedBox(width: 40, height: 40, child: CoverImage(anilist.viewer!.avatar, radius: 20)),
                title: Text(anilist.viewer!.name),
                trailing: TextButton(onPressed: anilist.logout, child: Text(t('Déconnexion', 'Log out'))),
              )
            else
              ListTile(
                leading: const Icon(Icons.login),
                title: Text(t('Se connecter à AniList', 'Log in to AniList')),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              ),
            _header(t('Langue', 'Language')),
            ListTile(
              title: Text(t("Langue de l'app", 'App language')),
              trailing: DropdownButton<AppLanguage>(
                value: settings.language,
                onChanged: (v) => settings.language = v!,
                items: [for (final l in AppLanguage.values) DropdownMenuItem(value: l, child: Text(l.label))],
              ),
            ),
            ListTile(
              title: Text(t('Titres des animes', 'Anime titles')),
              trailing: DropdownButton<TitleLanguage>(
                value: settings.titleLanguage,
                onChanged: (v) => settings.titleLanguage = v!,
                items: [for (final l in TitleLanguage.values) DropdownMenuItem(value: l, child: Text(l.label))],
              ),
            ),
            _header(t('Lecture', 'Playback')),
            ListTile(
              title: Text(t('Qualité préférée', 'Preferred quality')),
              trailing: DropdownButton<String>(
                value: settings.resolution,
                onChanged: (v) => settings.resolution = v!,
                items: [for (final r in ['1080', '720', '480']) DropdownMenuItem(value: r, child: Text('${r}p'))],
              ),
            ),
            _header('Extensions'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _repo,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(hintText: t('URL du dépôt (index.json)', 'Repository URL (index.json)')),
                    onSubmitted: (_) => _addRepo(),
                  ),
                ),
                const SizedBox(width: 8),
                busy
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: _addRepo, child: Text(t('Ajouter', 'Add'))),
              ]),
            ),
            for (final repo in store.repos)
              ListTile(
                title: Text(Uri.tryParse(repo)?.host ?? repo),
                subtitle: Text(repo, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => store.removeRepo(repo)),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RepoScreen(repo: repo))),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                t("Même format que les extensions Hayase : colle l'URL de l'index.json du dépôt.",
                    "Same format as Hayase extensions: paste the repository's index.json URL."),
                style: Nami.caption,
              ),
            ),
            _header('Nami'),
            ListTile(title: const Text('Version'), trailing: Text(version)),
            const SizedBox(height: 24),
          ],
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
              SwitchListTile(
                value: ext.enabled,
                onChanged: ext.manifest.isSupported ? (v) => store.setEnabled(ext, v) : null,
                secondary: SizedBox(width: 28, height: 28, child: CoverImage(ext.manifest.icon, radius: 6)),
                title: Text(ext.manifest.name),
                subtitle: Text([
                  if (ext.manifest.version != null) 'v${ext.manifest.version}',
                  ?ext.manifest.media,
                  if (!ext.manifest.isSupported) t('non supportée', 'unsupported'),
                ].join(' · ')),
              ),
              for (final opt in ext.manifest.options.entries)
                if ((opt.value as Map)['type'] == 'boolean')
                  SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 56, right: 16),
                    value: (ext.options[opt.key] ?? (opt.value as Map)['default'] ?? false) == true,
                    onChanged: (v) => store.setOption(ext, opt.key, v),
                    title: Text(opt.key),
                    subtitle: Text((opt.value as Map)['description']?.toString() ?? ''),
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
