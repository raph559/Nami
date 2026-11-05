import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var anilist: AniList
    @EnvironmentObject private var extensions: ExtensionStore
    @ObservedObject private var downloadsStore = Downloads.shared
    @State private var sourcesShown = 0
    @State private var flashSources = false

    /// The whole section lights up for a moment when a button brings you here.
    /// Font, colour, outline, background and height of the subtitles.
    @ViewBuilder
    private var subtitleStyle: some View {
        SegmentedSetting(label: t("Police", "Font"), selection: $subtitleFont,
                         options: SubtitleFont.allCases.map { ($0.rawValue, $0.label) })
        SegmentedSetting(label: t("Couleur", "Colour"), selection: $subtitleColor,
                         options: SubtitleColor.allCases.map { ($0.rawValue, $0.label) })
        SegmentedSetting(label: t("Contour", "Outline"),
                         detail: subtitleBox ? t("Remplacé par le fond sombre.", "Replaced by the dark background.") : nil,
                         selection: $subtitleOutline, options: SubtitleOutline.allCases.map { ($0.rawValue, $0.label) })
        Toggle(isOn: $subtitleBox) {
            VStack(alignment: .leading) {
                Text(t("Fond sombre", "Dark background"))
                Text(t("Un cadre derrière le texte.", "A box behind the text.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Text(t("Hauteur", "Height"))
            Text(t("Remonte les sous-titres, au-dessus des textes incrustés par exemple.",
                   "Raises the subtitles, above burned-in text for example."))
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(subtitleLift) }, set: { subtitleLift = Int($0.rounded()) }),
                   in: 0...Double(SubtitleStyle.maxLift), step: 10)
                .accessibilityLabel(t("Hauteur", "Height"))
                .accessibilityValue("\(subtitleLift) %")
        }
        .padding(.vertical, 4)
        Toggle(isOn: $subtitleForce) {
            VStack(alignment: .leading) {
                Text(t("Toujours utiliser mon style", "Always use my style"))
                Text(t("Remplace aussi le style des sous-titres déjà mis en forme. Les panneaux traduits peuvent mal s'afficher.",
                       "Also replaces the style of subtitles that bring their own. Translated signs may look wrong."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var sourcesBackground: some View {
        Rectangle().fill(flashSources ? Nami.text.opacity(0.22) : Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func showSources(_ proxy: ScrollViewProxy) {
        guard downloadsStore.sourcesOpened != sourcesShown else { return }
        sourcesShown = downloadsStore.sourcesOpened
        Task {
            // The tab appears first, then the list can move.
            try? await Task.sleep(for: .milliseconds(350))
            // In the middle of the screen, where the eye already is.
            withAnimation { proxy.scrollTo("sources", anchor: .center) }
            withAnimation(.easeOut(duration: 0.3)) { flashSources = true }
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(.easeOut(duration: 0.6)) { flashSources = false }
        }
    }
    @AppStorage("resolution") private var resolution = "1080"
    @AppStorage("downloadResolution") private var downloadResolution = "1080"
    @AppStorage("downloadWifiOnly") private var downloadWifiOnly = false
    @AppStorage("downloadLimit") private var downloadLimit = 0
    @State private var limitText = Downloads.limitText(UserDefaults.standard.integer(forKey: "downloadLimit"))
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.fr.rawValue
    @AppStorage("titleLanguage") private var titleLanguage = TitleLanguage.romaji.rawValue
    @AppStorage("autoSkip") private var autoSkip = true
    @AppStorage("autoNext") private var autoNext = true
    @AppStorage("seekStep") private var seekStep = 10
    @AppStorage("subtitleLanguage") private var subtitleLanguage = SubtitleLanguage.fr.rawValue
    @AppStorage("subtitleSize") private var subtitleSize = 100
    @AppStorage("subtitleFont") private var subtitleFont = SubtitleFont.standard.rawValue
    @AppStorage("subtitleColor") private var subtitleColor = SubtitleColor.white.rawValue
    @AppStorage("subtitleOutline") private var subtitleOutline = SubtitleOutline.thick.rawValue
    @AppStorage("subtitleBox") private var subtitleBox = false
    @AppStorage("subtitleLift") private var subtitleLift = 0
    @AppStorage("subtitleForce") private var subtitleForce = false
    @State private var repoURL = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section("AniList") {
                        if let viewer = anilist.viewer {
                            HStack(spacing: 12) {
                                CoverImageView(url: viewer.avatar?.large, corner: 20).frame(width: 40, height: 40)
                                Text(viewer.name).font(.headline)
                                Spacer()
                                Button(t("Déconnexion", "Log out"), role: .destructive) { anilist.logout() }
                            }
                        } else if anilist.isLoggedIn {
                            ProfileRetry()
                            Button(t("Déconnexion", "Log out"), role: .destructive) { anilist.logout() }
                        } else {
                            Button(t("Se connecter à AniList", "Log in to AniList")) {
                                Task {
                                    do { try await anilist.login() } catch { message = error.localizedDescription }
                                }
                            }
                        }
                    }

                    Section(t("Langue", "Language")) {
                        // Every option visible at once, as on Android and Windows.
                        SegmentedSetting(label: t("Langue de l'app", "App language"), selection: $appLanguage,
                                         options: AppLanguage.allCases.map { ($0.rawValue, $0.label) })
                        SegmentedSetting(label: t("Titres des animes", "Anime titles"), selection: $titleLanguage,
                                         options: TitleLanguage.allCases.map { ($0.rawValue, $0.label) })
                    }

                    Section(t("Lecture", "Playback")) {
                        SegmentedSetting(label: t("Qualité préférée", "Preferred quality"),
                                         detail: t("La source recommandée la privilégie.", "The recommended source favours it."),
                                         warning: ["2160", "1440"].contains(resolution)
                                             ? t("Peu de releases existent dans cette qualité, et un épisode pèse souvent 4 à 10 Go : lancement plus lent, forfait vite consommé en 4G/5G.",
                                                 "Few releases exist in this quality, and an episode often weighs 4 to 10 GB: slower to start, and mobile data goes fast.")
                                             : nil,
                                         selection: $resolution,
                                         options: ["480", "720", "1080", "1440", "2160"].map { ($0, "\($0)p") })
                        SegmentedSetting(label: t("Avancer et reculer de", "Seek by"),
                                         detail: t("Double appui à gauche ou à droite de l'image.",
                                                   "Double tap on the left or right of the picture."),
                                         selection: Binding(get: { String(seekStep) }, set: { seekStep = Int($0) ?? 10 }),
                                         options: ["5", "10", "15", "30"].map { ($0, "\($0) s") })
                        Toggle(isOn: $autoSkip) {
                            VStack(alignment: .leading) {
                                Text(t("Passer l'intro et le générique", "Skip openings and endings"))
                                Text(t("Automatiquement, quand AniSkip connaît leurs horaires.", "Automatically, when AniSkip knows where they are."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: $autoNext) {
                            VStack(alignment: .leading) {
                                Text(t("Enchaîner l'épisode suivant", "Play the next episode"))
                                Text(t("Après un compte à rebours de 10 secondes.", "After a 10 second countdown."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        SubtitlePreview(style: SubtitleStyle(
                            size: subtitleSize, font: SubtitleFont(rawValue: subtitleFont) ?? .standard,
                            color: SubtitleColor(rawValue: subtitleColor) ?? .white,
                            outline: SubtitleOutline(rawValue: subtitleOutline) ?? .thick,
                            box: subtitleBox, lift: subtitleLift, force: subtitleForce))
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        SegmentedSetting(label: t("Sous-titres", "Subtitles"),
                                         detail: t("Langue choisie au début de chaque épisode.", "Language picked when an episode starts."),
                                         selection: $subtitleLanguage, options: SubtitleLanguage.allCases.map { ($0.rawValue, $0.label) })
                        VStack(alignment: .leading, spacing: 10) {
                            Text(t("Taille des sous-titres", "Subtitle size"))
                            SubtitleSizeChoice(selection: $subtitleSize)
                        }
                        .padding(.vertical, 4)
                        subtitleStyle
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
                        // A row, not the section: a form scrolls to its rows.
                        .id("sources")
                        // Lit up for a moment when a button brings you here.
                        .listRowBackground(sourcesBackground)
                        ForEach(extensions.repos, id: \.self) { repo in
                            NavigationLink {
                                RepoView(repo: repo)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(ExtensionStore.repoLabel(repo))
                                    Text(extensions.summary(repo)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .onDelete { idx in idx.map { extensions.repos[$0] }.forEach(extensions.removeRepo) }
                        .listRowBackground(sourcesBackground)
                    } header: {
                        Text("Extensions").anchorPreference(key: SourcesBubble.self, value: .bounds) { [$0] }
                    } footer: {
                        Text(t("Colle l'URL de l'index.json du dépôt.",
                               "Paste the repository's index.json URL."))
                            .anchorPreference(key: SourcesBubble.self, value: .bounds) { [$0] }
                    }

                    Section(t("Téléchargements", "Downloads")) {
                        DownloadsLink()
                        SegmentedSetting(label: t("Qualité des téléchargements", "Download quality"),
                                         detail: t("À part de la lecture en streaming.", "Apart from streaming."),
                                         selection: Binding(get: { UserDefaults.standard.string(forKey: "downloadResolution") ?? resolution }, set: { downloadResolution = $0 }),
                                         options: ["480", "720", "1080", "1440", "2160", Downloads.best].map { ($0, Downloads.label($0)) })
                        Toggle(isOn: $downloadWifiOnly) {
                            VStack(alignment: .leading) {
                                Text(t("Wi-Fi uniquement", "Wi-Fi only"))
                                Text(t("Met les téléchargements en attente sur les données mobiles.", "Holds downloads while on mobile data."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: downloadWifiOnly) { _, _ in Downloads.shared.wifiSettingChanged() }
                        HStack {
                            VStack(alignment: .leading) {
                                Text(t("Limite de vitesse", "Speed limit"))
                                Text(t("Levée pendant la lecture d'un épisode en streaming.", "Lifted while an episode streams."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField(t("Aucune", "None"), text: $limitText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text("MB/s").foregroundStyle(.secondary)
                        }
                        .onChange(of: limitText) { _, text in
                            downloadLimit = Downloads.parseLimit(text)
                            Downloads.shared.limitChanged()
                        }
                    }

                    Section("Nami") {
                        LabeledContent(t("Créée par", "Made by")) { Text("raph559").bold() }
                        Link(destination: URL(string: "https://github.com/raph559/Nami")!) {
                            LabeledContent {
                                Image(systemName: "arrow.up.right.square")
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(t("Code source", "Source code")).foregroundStyle(Nami.text)
                                    Text("github.com/raph559/Nami").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                        NavigationLink {
                            ThirdPartyView()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(t("Licence et logiciels tiers", "License and third-party software"))
                                Text("GPL-3.0 · mpv, FFmpeg, anacrolix/torrent…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                // A bubble around the whole section, title included, while it is lit.
                .overlayPreferenceValue(SourcesBubble.self) { anchors in
                    GeometryReader { geo in
                        if flashSources, let top = anchors.first, let bottom = anchors.last, anchors.count == 2 {
                            let a = geo[top], b = geo[bottom]
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Nami.text, lineWidth: 2.5)
                                .frame(width: geo.size.width - 20, height: b.maxY - a.minY + 28)
                                .position(x: geo.size.width / 2, y: (a.minY + b.maxY) / 2)
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .navigationTitle(t("Réglages", "Settings"))
                .alert("Nami", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(message ?? "") }
                // The first time, the tab is built after the request: it asks on appearing too.
                .onAppear { showSources(proxy) }
                .onChange(of: downloadsStore.sourcesOpened) { _, _ in showSources(proxy) }
            }
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
        .navigationTitle(ExtensionStore.repoLabel(repo))
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

/// A setting whose options all show at once: name, what it does, then the choice.
struct SegmentedSetting: View {
    let label: String
    var detail: String?
    /// Shown in amber with an icon: the icon and words carry it, not the color alone.
    var warning: String?
    @Binding var selection: String
    let options: [(value: String, label: String)]
    /// What the control shows. The setting itself is written once the control has finished
    /// moving: saving redraws the whole page, which would stutter in the middle of its animation.
    @State private var shown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Nami.warning)
            }
            Picker(label, selection: Binding(get: { shown ?? selection }, set: { shown = $0 })) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .task(id: shown) {
            guard let shown, shown != selection else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            selection = shown
        }
    }
}

/// Subtitle sizes shown at their size, so the right one is picked at a glance.
struct SubtitleSizeChoice: View {
    @Binding var selection: Int

    private let sizes: [(value: Int, font: CGFloat, label: String)] = [
        (80, 12, t("Petite", "Small")), (100, 15, t("Normale", "Normal")),
        (125, 18, t("Grande", "Large")), (150, 21, t("Très grande", "Extra large")),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(sizes, id: \.value) { s in
                Button { selection = s.value } label: {
                    Text("Aa").font(.system(size: s.font, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selection == s.value ? Nami.ground : Nami.text)
                        .background(selection == s.value ? Nami.text : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.label)
                .accessibilityAddTraits(selection == s.value ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Nami.border))
    }
}

/// Nami's license and the main components it is built on (full list in
/// THIRD_PARTY_NOTICES.md in the repository).
struct ThirdPartyView: View {
    private let components: [(name: String, license: String, note: String)] = [
        ("mpv, FFmpeg, libass, libplacebo", "LGPL-2.1+", t("Lecture vidéo, via MPVKit", "Video playback, through MPVKit")),
        ("MPVKit", "LGPL-3.0", t("mpv et FFmpeg pour iOS", "mpv and FFmpeg for iOS")),
        ("Hanken Grotesk, Atkinson Hyperlegible, PT Serif", "OFL-1.1", t("Polices des sous-titres", "Subtitle fonts")),
        ("MoltenVK", "Apache-2.0", t("Vulkan sur Metal", "Vulkan on Metal")),
        ("anacrolix/torrent", "MPL-2.0", t("Moteur torrent", "Torrent engine")),
        ("Go", "BSD-3-Clause", t("Langage du moteur", "The engine's language")),
    ]

    var body: some View {
        List {
            Section {
                Text(t("Nami est un logiciel libre de raph559, sous licence GNU GPL 3.0 : tu peux l'utiliser, l'étudier, le modifier et le partager.",
                       "Nami is free software by raph559, under the GNU GPL 3.0: you can use, study, change and share it."))
                Link("github.com/raph559/Nami", destination: URL(string: "https://github.com/raph559/Nami")!)
            }
            Section {
                ForEach(components, id: \.name) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.name)
                            Spacer()
                            Text(c.license).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(c.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(t("Logiciels tiers", "Third-party software"))
            } footer: {
                Text(t("Liste complète, modules Go compris : THIRD_PARTY_NOTICES.md dans le dépôt.",
                       "Full list, Go modules included: THIRD_PARTY_NOTICES.md in the repository."))
            }
        }
        .navigationTitle(t("Licences", "Licenses"))
    }
}

/// Where the Extensions section starts and ends, to draw a bubble around it.
private struct SourcesBubble: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) { value += nextValue() }
}
