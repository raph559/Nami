import SwiftUI

struct PlayRequest: Identifiable {
    var episode: Int
    var result: TorrentResult
    var id: String { "\(episode)-\(result.id)" }
}

struct EpisodeRef: Identifiable {
    var episode: Int
    var id: Int { episode }
}

struct MediaDetailView: View {
    @EnvironmentObject private var anilist: AniList
    @State var media: Media
    @State private var mappings: Mappings?
    @State private var expanded = false
    @State private var sources: EpisodeRef?
    @State private var playing: PlayRequest?
    @State private var pendingPlay: PlayRequest?
    @State private var pendingSources: Int?

    private var progress: Int { media.mediaListEntry?.progress ?? 0 }
    private var nextEpisode: Int {
        let total = max(media.availableEpisodes, 1)
        return min(progress + 1, total)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    Button { sources = EpisodeRef(episode: media.isMovie ? 1 : nextEpisode) } label: {
                        Label(media.isMovie ? t("Regarder", "Watch") : t("Regarder l'épisode \(nextEpisode)", "Watch episode \(nextEpisode)"),
                              systemImage: "play.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(media.accent)
                    .disabled(media.availableEpisodes == 0 && !media.isMovie)

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
        .task {
            if let fresh = try? await anilist.media(id: media.id) { media = fresh }
            mappings = await Mappings.load(anilistID: media.id)
        }
        .sheet(item: $sources, onDismiss: {
            if let p = pendingPlay { pendingPlay = nil; playing = p }
        }) { ref in
            SourcesSheet(media: media, episode: ref.episode) { result in
                pendingPlay = PlayRequest(episode: ref.episode, result: result)
                sources = nil
            }
        }
        .fullScreenCover(item: $playing, onDismiss: {
            Task { if let fresh = try? await anilist.media(id: media.id) { media = fresh } }
            if let n = pendingSources { pendingSources = nil; sources = EpisodeRef(episode: n) }
        }) { req in
            PlayerView(media: media, episode: req.episode, result: req.result) {
                pendingSources = req.episode + 1
            }
        }
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
        return Button { sources = EpisodeRef(episode: n) } label: {
            HStack(spacing: 12) {
                CoverImageView(url: ep?.image ?? media.bannerImage ?? media.coverImage?.large, corner: 8)
                    .frame(width: 128, height: 72)
                    .overlay {
                        if n <= progress {
                            ZStack { Color.black.opacity(0.45); Image(systemName: "checkmark.circle.fill").font(.title2) }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Épisode \(n)", "Episode \(n)")).font(.caption.bold()).foregroundStyle(media.accent)
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

struct SourcesSheet: View {
    let media: Media
    let episode: Int
    let onPick: (TorrentResult) -> Void

    @EnvironmentObject private var extensions: ExtensionStore
    @AppStorage("resolution") private var resolution = "1080"
    @State private var search: SourceSearch?
    @State private var showFailures = false

    var body: some View {
        NavigationStack {
            Group {
                if extensions.enabled.isEmpty {
                    ContentUnavailableView(t("Aucune extension", "No extensions"), systemImage: "puzzlepiece.extension",
                                           description: Text(t("Ajoute un dépôt d'extensions dans Réglages.", "Add an extension repository in Settings.")))
                } else if let search {
                    if search.results.isEmpty {
                        ContentUnavailableView(t("Aucun résultat", "No results"), systemImage: "magnifyingglass",
                                               description: Text(search.failures.isEmpty
                                                                 ? t("Les extensions n'ont rien trouvé.", "The extensions found nothing.")
                                                                 : t("Certaines extensions ont échoué.", "Some extensions failed.")))
                    } else {
                        list(search)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(t("Recherche des sources…", "Looking for sources…")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(media.isMovie ? media.title.display : t("Épisode \(episode)", "Episode \(episode)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let failures = search?.failures, !failures.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showFailures = true } label: { Image(systemName: "exclamationmark.triangle") }
                    }
                }
            }
            .alert(t("Extensions en erreur", "Extension errors"), isPresented: $showFailures) {
                Button("OK", role: .cancel) {}
            } message: {
                Text((search?.failures ?? []).map { "\($0.name) : \($0.message)" }.joined(separator: "\n"))
            }
        }
        .presentationDetents([.medium, .large])
        .task { search = await SourceSearch.run(media: media, episode: episode, resolution: resolution) }
    }

    private func list(_ search: SourceSearch) -> some View {
        List {
            if let best = search.results.first {
                Section {
                    Button { onPick(best) } label: {
                        Label(t("Lire la meilleure source", "Play the best source"), systemImage: "bolt.fill").font(.headline)
                    }
                }
            }
            Section(t("\(search.results.count) sources", "\(search.results.count) sources")) {
                ForEach(search.results) { r in
                    Button { onPick(r) } label: { SourceRow(result: r) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SourceRow: View {
    let result: TorrentResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                if result.isBest { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                Text(result.title).font(.subheadline).lineLimit(3)
            }
            HStack(spacing: 10) {
                Label("\(result.seeders ?? 0)", systemImage: "arrow.up.circle").foregroundStyle((result.seeders ?? 0) > 0 ? .green : .secondary)
                if let size = result.size, size > 0 { Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
                if let source = result.source { Text(source) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
