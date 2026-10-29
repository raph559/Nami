import SwiftUI

/// Remote image that fills whatever frame it is given, without its own size
/// leaking into the layout.
struct CoverImageView: View {
    let url: String?
    var corner: CGFloat = 10

    var body: some View {
        Color.white.opacity(0.06)
            .overlay {
                AsyncImage(url: url.flatMap(URL.init(string:)), transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// Where a cover was tapped, so the anime page can grow out of it (iOS 18 zoom).
struct MediaRoute: Hashable {
    var media: Media
    var source: String
}

extension View {
    /// The cover a zoom transition starts from.
    @ViewBuilder
    func zoomSource(_ id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { matchedTransitionSource(id: id, in: ns) } else { self }
    }

    /// The page grows out of the cover it was opened from.
    @ViewBuilder
    func zoomDestination(_ id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { navigationTransition(.zoom(sourceID: id, in: ns)) } else { self }
    }

    /// Long press: a preview of the anime with the two things you can do.
    func mediaPreview(_ media: Media, open: @escaping () -> Void) -> some View {
        contextMenu {
            let next = media.isMovie ? 1 : min(max((media.mediaListEntry?.progress ?? 0) + 1, 1), max(media.availableEpisodes, 1))
            if media.isMovie || media.availableEpisodes > 0 {
                Button { PlayerCenter.shared.openSources(media, episode: next) } label: {
                    Label(media.isMovie ? t("Regarder", "Watch") : t("Regarder l'épisode \(next)", "Watch episode \(next)"),
                          systemImage: "play.fill")
                }
            }
            Button(action: open) { Label(t("Voir la fiche", "See details"), systemImage: "info.circle") }
        } preview: {
            MediaPreview(media: media)
        }
    }
}

/// What the long-press preview shows: cover, facts and the start of the summary.
struct MediaPreview: View {
    let media: Media

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImageView(url: media.coverImage?.large, corner: 6).frame(width: 96, height: 139)
            VStack(alignment: .leading, spacing: 6) {
                Text(media.title.display).font(.headline).lineLimit(3)
                Text(facts).font(.caption).foregroundStyle(Nami.textSecondary)
                if !media.plainDescription.isEmpty {
                    Text(media.plainDescription).font(.caption).foregroundStyle(Nami.textSecondary).lineLimit(5)
                }
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(Nami.card)
        .foregroundStyle(Nami.text)
    }

    private var facts: String {
        var parts: [String] = []
        if let f = media.format { parts.append(f.replacingOccurrences(of: "_", with: " ")) }
        if let y = media.seasonYear { parts.append(String(y)) }
        if let s = media.averageScore { parts.append("\(s) %") }
        if let g = media.genres, !g.isEmpty { parts.append(g.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

struct MediaCard: View {
    let media: Media
    var badge: String?
    var progress: Double?
    var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(url: media.coverImage?.large ?? media.coverImage?.extraLarge, corner: 6)
                .frame(width: width, height: width * 1.45)
            if let progress {
                ProgressLine(value: progress, color: Nami.accent(media.coverImage?.color)).frame(width: width)
            }
            Text(media.title.display).font(.caption.weight(.semibold)).lineLimit(2)
                .frame(width: width, alignment: .leading)
            if let badge {
                Text(badge).font(.caption2).foregroundStyle(Nami.textSecondary).lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
    }
}

/// Thin line showing how much is watched.
struct ProgressLine: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Nami.text.opacity(0.12))
                Rectangle().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 2)
    }
}

/// Grid cell that sizes its cover from the column width.
struct MediaGridCell: View {
    let media: Media

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(url: media.coverImage?.large ?? media.coverImage?.extraLarge, corner: 6)
                .aspectRatio(1 / 1.45, contentMode: .fit)
            Text(media.title.display).font(.caption.weight(.semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MediaRow: View {
    let title: String
    let items: [Media]
    let ns: Namespace.ID
    @Binding var path: [MediaRoute]
    var badge: (Media) -> String? = { _ in nil }
    var progress: (Media) -> Double? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { m in
                        let route = MediaRoute(media: m, source: "\(title)-\(m.id)")
                        NavigationLink(value: route) {
                            MediaCard(media: m, badge: badge(m), progress: progress(m)).zoomSource(route.source, in: ns)
                        }
                        .buttonStyle(.plain)
                        .mediaPreview(m) { path.append(route) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Grey shapes of the page while it loads; they breathe unless Reduce Motion is on.
struct LoadingShape: View {
    var width: CGFloat?
    var height: CGFloat
    var corner: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Nami.card)
            .frame(width: width, height: height)
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// The anime to resume (or the top trending one) across the top of the home screen.
struct HomeHero: View {
    let media: Media
    let episode: Int
    let resuming: Bool
    let open: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImageView(url: media.bannerImage ?? media.coverImage?.extraLarge, corner: 0)
                .frame(height: 440)
                .frame(maxWidth: .infinity)
                .clipped()
                // A long fade into the ground, then solid ground under the text (4.5:1 over any picture).
                .overlay(LinearGradient(stops: [
                    .init(color: Nami.ground.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: Nami.ground.opacity(0.55), location: 0.5),
                    .init(color: Nami.ground.opacity(0.9), location: 0.72),
                    .init(color: Nami.ground, location: 0.96),
                ], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 8) {
                Text(resuming ? t("À reprendre", "Up next") : t("En tendance", "Trending"))
                    .font(.footnote).foregroundStyle(Nami.textSecondary)
                Text(media.title.display).font(.largeTitle.bold()).lineLimit(3)
                if !media.isMovie {
                    Text(media.episodes.map { t("Épisode \(episode) sur \($0)", "Episode \(episode) of \($0)") }
                         ?? t("Épisode \(episode)", "Episode \(episode)"))
                        .font(.subheadline).foregroundStyle(Nami.textSecondary)
                }
                HStack(spacing: 10) {
                    Button { PlayerCenter.shared.openSources(media, episode: episode) } label: {
                        Label(media.isMovie ? t("Regarder", "Watch")
                              : resuming ? t("Reprendre l'épisode \(episode)", "Resume episode \(episode)")
                              : t("Regarder l'épisode \(episode)", "Watch episode \(episode)"),
                              systemImage: "play.fill")
                            .font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).tint(Nami.text).foregroundStyle(Nami.ground)
                    Button(action: open) {
                        Text(t("Voir la fiche", "See details")).font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered).tint(Nami.text)
                }
                .padding(.top, 6)
            }
            .foregroundStyle(Nami.text)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var anilist: AniList
    @State private var watching: [WatchingEntry] = []
    @State private var seasonal: [Media] = []
    @State private var trending: [Media] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var path: [MediaRoute] = []
    @Namespace private var ns

    /// The anime to resume (first with an aired, unwatched episode), else the top trending one.
    private var hero: (media: Media, episode: Int, resuming: Bool)? {
        if let w = watching.first(where: \.hasNewEpisode) { return (w.media, w.progress + 1, true) }
        if let m = trending.first { return (m, 1, false) }
        return nil
    }

    /// Without AniList, the anime played on this device that still have an episode to go.
    private var local: [Playback.Recent] {
        Playback.recent.filter { $0.episode <= ($0.media.isMovie ? 1 : $0.media.availableEpisodes) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !loaded {
                        skeleton
                    } else {
                        if let hero {
                            let route = MediaRoute(media: hero.media, source: "hero-\(hero.media.id)")
                            HomeHero(media: hero.media, episode: hero.episode, resuming: hero.resuming) { path.append(route) }
                                .zoomSource(route.source, in: ns)
                        }
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        continueRow
                        if !anilist.isLoggedIn { loginHint }
                        if !seasonal.isEmpty {
                            let (s, y) = AniList.currentSeason()
                            MediaRow(title: "\(Self.seasonName(s)) \(y)", items: seasonal, ns: ns, path: $path)
                        }
                        let rest = trending.filter { $0.id != hero?.media.id }
                        if !rest.isEmpty { MediaRow(title: t("Tendances", "Trending"), items: rest, ns: ns, path: $path) }
                    }
                }
                .padding(.bottom)
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                // The name over the banner, on a short fade so the status bar stays readable.
                Text("Nami").font(.title2.bold()).foregroundStyle(Nami.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 10)
                    .background(LinearGradient(colors: [Nami.ground.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top))
                    .allowsHitTesting(false)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MediaRoute.self) { r in
                MediaDetailView(media: r.media).zoomDestination(r.source, in: ns)
            }
            .refreshable { await load() }
            .task(id: anilist.viewer?.id) { await load() }
        }
    }

    @ViewBuilder
    private var continueRow: some View {
        let shown = watching.filter { $0.media.id != hero?.media.id }
        if !shown.isEmpty {
            MediaRow(title: t("Continuer", "Continue watching"), items: shown.map(\.media), ns: ns, path: $path) { m in
                guard let e = shown.first(where: { $0.id == m.id }) else { return nil }
                if Playback.resumeFraction(media: m.id, episode: e.progress + 1) != nil {
                    return t("Reprendre l'épisode \(e.progress + 1)", "Resume episode \(e.progress + 1)")
                }
                return e.hasNewEpisode ? t("Épisode \(e.progress + 1) dispo", "Episode \(e.progress + 1) out") : nil
            } progress: { m in
                // How far into the next episode you are, else how far into the series.
                guard let e = shown.first(where: { $0.id == m.id }) else { return nil }
                if let f = Playback.resumeFraction(media: m.id, episode: e.progress + 1) { return f }
                let total = m.episodes ?? m.availableEpisodes
                return total > 0 ? Double(e.progress) / Double(total) : nil
            }
        } else if !anilist.isLoggedIn, !local.isEmpty {
            let items = local
            MediaRow(title: t("Continuer", "Continue watching"), items: items.map(\.media), ns: ns, path: $path) { m in
                guard let e = items.first(where: { $0.media.id == m.id }), !m.isMovie else { return nil }
                return t("Épisode \(e.episode)", "Episode \(e.episode)")
            } progress: { m in
                guard let e = items.first(where: { $0.media.id == m.id }) else { return nil }
                return Playback.resumeFraction(media: m.id, episode: e.episode) ?? 0
            }
        }
    }

    /// The page's shape while it loads, so nothing jumps when it arrives.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 26) {
            LoadingShape(height: 440, corner: 0)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    LoadingShape(width: 150, height: 20).padding(.horizontal)
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in LoadingShape(width: 120, height: 174) }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(t("Chargement des animes…", "Loading anime…"))
    }

    private var loginHint: some View {
        Text(t("Connecte AniList dans Réglages pour reprendre là où tu en es.",
               "Log in to AniList in Settings to pick up where you left off."))
            .font(.footnote).foregroundStyle(Nami.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    private func load() async {
        do {
            async let w = anilist.watching()
            async let s = anilist.seasonal()
            async let tr = anilist.trending()
            (watching, seasonal, trending) = try await (w, s, tr)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    static func seasonName(_ s: String) -> String {
        switch s {
        case "WINTER": t("Hiver", "Winter")
        case "SPRING": t("Printemps", "Spring")
        case "SUMMER": t("Été", "Summer")
        case "FALL": t("Automne", "Fall")
        default: s
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var anilist: AniList
    @State private var text = ""
    @State private var genre: String?
    @State private var results: [Media] = []
    @State private var loading = false
    @State private var path: [MediaRoute] = []
    @Namespace private var ns

    private static let genres = ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mecha", "Music",
                                 "Mystery", "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports",
                                 "Supernatural", "Thriller"]

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    private var heading: String {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { return t("Résultats", "Results") }
        if let genre { return genre }
        return t("Les plus populaires", "Most popular")
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.genres, id: \.self) { g in
                                Button { genre = genre == g ? nil : g } label: {
                                    Text(g).font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(genre == g ? Nami.text : .white.opacity(0.08), in: Capsule())
                                        .foregroundStyle(genre == g ? Nami.ground : Nami.text)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    Text(heading).font(.title3.bold()).padding(.horizontal)
                    LazyVGrid(columns: columns, spacing: 16) {
                        if loading && results.isEmpty {
                            ForEach(0..<9, id: \.self) { _ in LoadingShape(height: 160) }
                        }
                        ForEach(results) { m in
                            let route = MediaRoute(media: m, source: "search-\(m.id)")
                            NavigationLink(value: route) { MediaGridCell(media: m).zoomSource(route.source, in: ns) }
                                .buttonStyle(.plain)
                                .mediaPreview(m) { path.append(route) }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(t("Recherche", "Search"))
            .searchable(text: $text, prompt: t("Titre d'un anime", "Anime title"))
            .navigationDestination(for: MediaRoute.self) { r in
                MediaDetailView(media: r.media).zoomDestination(r.source, in: ns)
            }
            .task(id: "\(text)|\(genre ?? "")") {
                let q = text.trimmingCharacters(in: .whitespaces)
                if q.count == 1 { return }
                if !q.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                loading = true
                if let found = try? await anilist.search(q, genre: genre), !Task.isCancelled { results = found }
                loading = false
            }
        }
    }
}
