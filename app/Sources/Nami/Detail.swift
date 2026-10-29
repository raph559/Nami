import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var anilist: AniList
    @State var media: Media
    @State private var mappings: Mappings?
    @State private var expanded = false
    /// Once the main button has scrolled away, the top bar offers it instead.
    @State private var showBarButton = false
    @State private var editingList = false
    @EnvironmentObject private var center: PlayerCenter

    private var progress: Int { media.mediaListEntry?.progress ?? 0 }
    private var nextEpisode: Int {
        let total = max(media.availableEpisodes, 1)
        return min(progress + 1, total)
    }

    private var canWatch: Bool { media.isMovie || media.availableEpisodes > 0 }

    private var watchLabel: String {
        if media.isMovie { return t("Regarder", "Watch") }
        if Playback.resumeFraction(media: media.id, episode: nextEpisode) != nil {
            return t("Reprendre l'épisode \(nextEpisode)", "Resume episode \(nextEpisode)")
        }
        return t("Regarder l'épisode \(nextEpisode)", "Watch episode \(nextEpisode)")
    }

    private func watch() { center.openSources(media, episode: media.isMovie ? 1 : nextEpisode) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button(action: watch) {
                            Label(watchLabel, systemImage: "play.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Nami.accent(media.coverImage?.color))
                        .foregroundStyle(Nami.ground)
                        .disabled(!canWatch)
                        if anilist.isLoggedIn { listButton }
                    }

                    if let genres = media.genres, !genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(genres, id: \.self) {
                                    Text($0).font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(.white.opacity(0.08), in: Capsule())
                                }
                            }
                        }
                    }
                    if !media.plainDescription.isEmpty {
                        Text(media.plainDescription).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(expanded ? nil : 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture { withAnimation { expanded.toggle() } }
                    }
                    if !media.isMovie { episodes }
                }
                .padding(.horizontal)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .onScrolledPast(300) { showBarButton = $0 }
        .toolbar {
            if showBarButton && canWatch {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: watch) {
                        Label(media.isMovie ? t("Regarder", "Watch") : t("Épisode \(nextEpisode)", "Episode \(nextEpisode)"),
                              systemImage: "play.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $editingList) {
            ListEditorSheet(media: media) { media = $0 }
        }
        .task {
            if let fresh = try? await anilist.media(id: media.id) { media = fresh }
            mappings = await Mappings.load(anilistID: media.id)
        }
        // The player may have moved the AniList progress.
        .onChange(of: center.finished) { _, _ in
            Task { if let fresh = try? await anilist.media(id: media.id) { media = fresh } }
        }
    }

    /// Opens the list editor; its label is where the anime stands in the list.
    private var listButton: some View {
        let status = ListStatus(rawValue: media.mediaListEntry?.status ?? "")
        return Button { editingList = true } label: {
            Label(status?.label ?? t("Ma liste", "My list"), systemImage: status == nil ? "bookmark" : "bookmark.fill")
                .font(.headline).padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(Nami.text)
        .fixedSize()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImageView(url: media.bannerImage ?? media.coverImage?.extraLarge, corner: 0)
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .overlay(LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom))
            HStack(alignment: .bottom, spacing: 14) {
                CoverImageView(url: media.coverImage?.extraLarge ?? media.coverImage?.large)
                    .frame(width: 104, height: 150)
                    .shadow(radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title.display).font(.title3.bold()).lineLimit(3)
                    Text(metaLine).font(.caption).foregroundStyle(.secondary)
                    if progress > 0 {
                        Text(t("Vu : \(progress)/\(media.episodes.map(String.init) ?? "?")", "Watched: \(progress)/\(media.episodes.map(String.init) ?? "?")"))
                            .font(.caption.bold()).foregroundStyle(media.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.top, -70)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let f = media.format { parts.append(f.replacingOccurrences(of: "_", with: " ")) }
        if let y = media.seasonYear { parts.append(String(y)) }
        if let e = media.episodes { parts.append(t("\(e) ép.", "\(e) ep.")) }
        if let s = media.averageScore { parts.append("\(s) %") }
        if let next = media.nextAiringEpisode {
            let d = Date(timeIntervalSince1970: TimeInterval(next.airingAt))
            let when = d.formatted(.relative(presentation: .named).locale(Locale(identifier: AppLanguage.current.rawValue)))
            parts.append(t("Ép. \(next.episode) \(when)", "Ep. \(next.episode) \(when)"))
        }
        return parts.joined(separator: " · ")
    }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Épisodes", "Episodes")).font(.title3.bold()).padding(.top, 6)
            if media.availableEpisodes == 0 {
                Text(t("Aucun épisode diffusé pour l'instant.", "No episode has aired yet.")).font(.footnote).foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(1...media.availableEpisodes, id: \.self) { n in
                        episodeRow(n)
                    }
                }
            }
        }
        .padding(.bottom, 30)
    }

    private func episodeRow(_ n: Int) -> some View {
        let ep = mappings?.episode(n)
        let resume = n > progress ? Playback.resumeFraction(media: media.id, episode: n) : nil
        let accent = Nami.accent(media.coverImage?.color)
        return Button { center.openSources(media, episode: n) } label: {
            HStack(spacing: 12) {
                CoverImageView(url: ep?.image ?? media.bannerImage ?? media.coverImage?.large, corner: 8)
                    .frame(width: 128, height: 72)
                    .overlay {
                        if n <= progress {
                            ZStack { Color.black.opacity(0.45); Image(systemName: "checkmark.circle.fill").font(.title2) }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    // How far into a started episode you are.
                    .overlay(alignment: .bottom) {
                        if let resume { ProgressLine(value: resume, color: accent).clipShape(RoundedRectangle(cornerRadius: 1)) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(resume != nil ? t("Épisode \(n) · En cours", "Episode \(n) · In progress") : t("Épisode \(n)", "Episode \(n)"))
                        .font(.caption.bold()).foregroundStyle(accent)
                    Text(ep?.displayTitle(AppLanguage.current.rawValue) ?? "").font(.subheadline).lineLimit(2)
                    if let len = ep?.runtime ?? ep?.length { Text("\(len) min").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Same layout as the Android and Windows sheet: a header, the recommended
/// source on its own card, then this episode and the season packs.
struct SourcesSheet: View {
    let media: Media
    let episode: Int
    var autoPick = false
    let onPick: (TorrentResult) -> Void

    @EnvironmentObject private var extensions: ExtensionStore
    @AppStorage("resolution") private var resolution = "1080"
    @State private var search: SourceSearch?
    @State private var releases: [ReleaseInfo] = []
    @State private var showFailures = false

    private var accent: Color { Nami.accent(media.coverImage?.color) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                content
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
        .foregroundStyle(Nami.text)
        .task {
            let found = await SourceSearch.run(media: media, episode: episode, resolution: resolution)
            releases = ReleaseInfo.rank(found.results, resolution: resolution)
            search = found
            if autoPick, let best = releases.first { onPick(best.result) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(media.isMovie ? media.title.display : t("Épisode \(episode)", "Episode \(episode)"))
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            let sub = [media.isMovie ? nil : media.title.display, releases.isEmpty ? nil : "\(releases.count) sources"]
                .compactMap { $0 }.joined(separator: " · ")
            if !sub.isEmpty {
                Text(sub).font(.subheadline).foregroundStyle(Nami.textSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if extensions.enabled.isEmpty {
            message(t("Aucune source installée", "No sources installed"),
                    t("Ajoute un dépôt d'extensions dans Réglages, puis reviens ici.", "Add an extension repository in Settings, then come back here."))
        } else if let search {
            if releases.isEmpty {
                message(t("Aucune source trouvée", "No source found"),
                        search.failures.isEmpty
                            ? t("Tes extensions n'ont rien pour cet épisode. Essaie une autre qualité dans Réglages.",
                                "Your extensions have nothing for this episode. Try another quality in Settings.")
                            : search.failures.map { "\($0.name) : \($0.message)" }.joined(separator: "\n"))
            } else {
                list(search)
            }
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(Nami.text)
                Text(autoPick ? t("Recherche de la meilleure source…", "Finding the best source…")
                              : t("Recherche des sources…", "Looking for sources…"))
                    .font(.subheadline).foregroundStyle(Nami.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }

    private func message(_ title: String, _ body: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(Nami.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32).padding(.top, 60)
    }

    private func list(_ search: SourceSearch) -> some View {
        let rest = releases.dropFirst()
        let single = rest.filter { !$0.batch }
        let packs = rest.filter(\.batch)
        return VStack(alignment: .leading, spacing: 0) {
            if let best = releases.first { recommended(best) }
            if !single.isEmpty {
                sectionLabel(t("Cet épisode", "This episode"))
                ForEach(single) { row($0) }
            }
            if !packs.isEmpty {
                sectionLabel(t("Saisons complètes", "Full seasons"))
                ForEach(packs) { row($0) }
            }
            if !search.failures.isEmpty {
                DisclosureGroup(isExpanded: $showFailures) {
                    Text(search.failures.map { "\($0.name) : \($0.message)" }.joined(separator: "\n"))
                        .font(.caption).foregroundStyle(Nami.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(t("\(search.failures.count) extension(s) n'ont pas répondu", "\(search.failures.count) extension(s) didn't answer"))
                        .font(.subheadline)
                }
                .tint(Nami.textSecondary)
                .padding(.horizontal, 20).padding(.top, 16)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.callout.bold())
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// The pick at the top: what it is, why it was chosen, and one button.
    /// Tinted by the anime's color, like its page.
    private func recommended(_ r: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t("Recommandée", "Recommended")).font(.caption).foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline) {
                Text(r.title).font(.headline)
                Spacer(minLength: 8)
                if let size = r.result.size, size > 0 { Text(Self.bytes(size)).font(.subheadline).foregroundStyle(Nami.textSecondary) }
            }
            .padding(.top, 6)
            FactTags(facts: r.facts).padding(.top, 6)
            HealthLine(release: r).padding(.top, 8)
            Text(r.reason(resolution)).font(.footnote).foregroundStyle(Nami.textSecondary).padding(.top, 4)
            Button { onPick(r.result) } label: {
                Label(t("Lire cette source", "Play this source"), systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Nami.ground)
                    .background(accent, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .background(Nami.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(0.6)))
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func row(_ r: ReleaseInfo) -> some View {
        Button { onPick(r.result) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(r.title).font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    if let size = r.result.size, size > 0 { Text(Self.bytes(size)).font(.subheadline).foregroundStyle(Nami.textSecondary) }
                }
                FactTags(facts: r.facts).padding(.top, 6)
                HStack(spacing: 8) {
                    HealthLine(release: r)
                    if let source = r.result.source { Text("·  \(source)").font(.caption).foregroundStyle(Nami.textSecondary).lineLimit(1) }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Long press: the native menu shows the full release name.
        .contextMenu {
            Text(r.result.title)
            Button { onPick(r.result) } label: { Label(t("Lire", "Play"), systemImage: "play.fill") }
        }
        .accessibilityHint(t("Appui long pour le nom complet", "Long press for the full name"))
    }

    static func bytes(_ v: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file) }
}

/// Facts as small outlined tags; they are real data from the release name.
struct FactTags: View {
    let facts: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(facts, id: \.self) { f in
                Text(f).font(.caption).foregroundStyle(Nami.text)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Nami.border))
            }
        }
    }
}

/// Seeders with a signal icon and a word, in a color that matches the level.
struct HealthLine: View {
    let release: ReleaseInfo

    var body: some View {
        let h = release.health
        HStack(spacing: 5) {
            Image(systemName: "cellularbars", variableValue: h.bars)
            Text("\(release.seeders) seeders, \(h.label)")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(h.color)
    }
}

/// Lays children out in rows, wrapping to the next line when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

extension View {
    /// Tells when the page has scrolled past `offset` points (iOS 18; earlier
    /// versions keep the button in the page only).
    @ViewBuilder
    func onScrolledPast(_ offset: CGFloat, _ action: @escaping (Bool) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > offset } action: { _, past in
                withAnimation(.easeInOut(duration: 0.2)) { action(past) }
            }
        } else {
            self
        }
    }
}
