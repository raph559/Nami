import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var anilist: AniList
    @EnvironmentObject private var extensions: ExtensionStore
    @AppStorage("resolution") private var resolution = "1080"
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.fr.rawValue
    @AppStorage("titleLanguage") private var titleLanguage = TitleLanguage.romaji.rawValue
    @State private var repoURL = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("AniList") {
                    if let viewer = anilist.viewer {
                        HStack(spacing: 12) {
                            CoverImageView(url: viewer.avatar?.large, corner: 20).frame(width: 40, height: 40)
                            Text(viewer.name).font(.headline)
                            Spacer()
                            Button(t("Déconnexion", "Log out"), role: .destructive) { anilist.logout() }
                        }
                    } else {
                        Button(t("Se connecter à AniList", "Log in to AniList")) {
                            Task {
                                do { try await anilist.login() } catch { message = error.localizedDescription }
                            }
                        }
                    }
                }

                Section(t("Langue", "Language")) {
                    Picker(t("Langue de l'app", "App language"), selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker(t("Titres des animes", "Anime titles"), selection: $titleLanguage) {
                        ForEach(TitleLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }

                Section(t("Lecture", "Playback")) {
                    Picker(t("Qualité préférée", "Preferred quality"), selection: $resolution) {
                        Text("1080p").tag("1080")
                        Text("720p").tag("720")
                        Text("480p").tag("480")
                    }
                }

                Section {
                    HStack {
                        TextField(t("URL du dépôt (index.json)", "Repository URL (index.json)"), text: $repoURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        if busy { ProgressView() } else {
                            Button(t("Ajouter", "Add")) { addRepo() }.disabled(repoURL.isEmpty)
                        }
                    }
                    ForEach(extensions.repos, id: \.self) { repo in
                        NavigationLink {
                            RepoView(repo: repo)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(URL(string: repo)?.host() ?? repo)
                                Text(repo).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { idx in idx.map { extensions.repos[$0] }.forEach(extensions.removeRepo) }
                } header: {
                    Text("Extensions")
                } footer: {
                    Text(t("Même format que les extensions Hayase : colle l'URL de l'index.json du dépôt.",
                           "Same format as Hayase extensions: paste the repository's index.json URL."))
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                }
            }
            .navigationTitle(t("Réglages", "Settings"))
            .alert("Nami", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private func addRepo() {
        busy = true
        Task {
            do {
                try await extensions.addRepo(repoURL)
                repoURL = ""
            } catch {
                message = t("Impossible de charger ce dépôt : ", "Could not load this repository: ") + error.localizedDescription
            }
            busy = false
        }
    }
}

struct RepoView: View {
    let repo: String
    @EnvironmentObject private var extensions: ExtensionStore

    var body: some View {
        List {
            ForEach(extensions.installed.filter { $0.repo == repo }) { ext in
                Section {
                    Toggle(isOn: Binding(get: { ext.enabled }, set: { extensions.setEnabled(ext, $0) })) {
                        HStack(spacing: 10) {
                            CoverImageView(url: ext.manifest.icon, corner: 6).frame(width: 28, height: 28)
                            VStack(alignment: .leading) {
                                Text(ext.manifest.name)
                                Text([ext.manifest.version.map { "v\($0)" }, ext.manifest.media,
                                      ext.manifest.isSupported ? nil : t("non supportée", "unsupported")]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!ext.manifest.isSupported)
                    ForEach((ext.manifest.options ?? [:]).sorted { $0.key < $1.key }, id: \.key) { key, opt in
                        option(ext, key: key, opt: opt)
                    }
                }
            }
        }
        .navigationTitle(URL(string: repo)?.host() ?? t("Dépôt", "Repository"))
    }

    @ViewBuilder
    private func option(_ ext: InstalledExtension, key: String, opt: ExtensionOption) -> some View {
        let current = ext.options[key] ?? opt.default
        switch opt.type {
        case "boolean":
            Toggle(isOn: Binding(
                get: { if case .bool(let b) = current { b } else { false } },
                set: { extensions.setOption(ext, key: key, value: .bool($0)) }
            )) {
                VStack(alignment: .leading) {
                    Text(key)
                    if let d = opt.description { Text(d).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        default:
            TextField(opt.description ?? key, text: Binding(
                get: { if case .string(let s) = current { s } else if case .number(let n) = current { String(n) } else { "" } },
                set: { extensions.setOption(ext, key: key, value: opt.type == "number" ? .number(Double($0) ?? 0) : .string($0)) }
            ))
        }
    }
}
