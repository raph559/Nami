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
    /// `source` of the route to the calendar, which fits the same typed path; its media is ignored.
    static let calendar = "calendar"

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
    var badge: String?
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(url: media.coverImage?.large ?? media.coverImage?.extraLarge, corner: 6)
                .aspectRatio(1 / 1.45, contentMode: .fit)
            if let progress { ProgressLine(value: progress, color: Nami.accent(media.coverImage?.color)) }
            Text(media.title.display).font(.caption.weight(.semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let badge {
                Text(badge).font(.caption2).foregroundStyle(Nami.textSecondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
    /// Numbers the covers (1, 2, 3…), for "top" lists.
    var ranked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, m in
                        let route = MediaRoute(media: m, source: "\(title)-\(m.id)")
                        NavigationLink(value: route) {
                            MediaCard(media: m, badge: badge(m), progress: progress(m))
                                .overlay(alignment: .topLeading) {
                                    if ranked {
                                        Text("\(index + 1)").font(.footnote.weight(.heavy)).foregroundStyle(Nami.ground)
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Nami.text, in: RoundedRectangle(cornerRadius: 4))
                                            .padding(6)
                                    }
                                }
                                .zoomSource(route.source, in: ns)
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
/// The home banner: up to five anime, one at a time. It moves on every 8 s,
/// never by itself with Reduce Motion, and a swipe changes it.
struct HomeCarousel: View {
    let items: [HeroItem]
    let open: (HeroItem) -> Void
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                HeroSlide(item: item, count: items.count, index: i) { open(item) }.tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 460)
        .onChange(of: items.count) { _, count in
            if index >= count { index = 0 }
        }
        // Restarts the wait after every change, so a slide just swiped to stays.
        .task(id: "\(index)-\(reduceMotion)-\(scenePhase == .active)") {
            guard items.count > 1, !reduceMotion, scenePhase == .active else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation { index = (index + 1) % items.count }
        }
    }
}

private struct HeroSlide: View {
    let item: HeroItem
    let count: Int
    let index: Int
    let open: () -> Void
    @EnvironmentObject private var anilist: AniList

    private var media: Media { item.media }

    private var kicker: String {
        switch item.reason {
        case .resume: t("Reprendre · épisode \(item.episode)", "Resume · episode \(item.episode)")
        case .newEpisode: t("Nouvel épisode · \(item.episode)", "New episode · \(item.episode)")
        case .trending: t("Tendance", "Trending")
        }
    }

    private var meta: String {
        var parts: [String] = []
        if let y = media.seasonYear { parts.append(String(y)) }
        if let e = media.episodes { parts.append(t("\(e) épisodes", "\(e) episodes")) }
        if let s = media.averageScore { parts.append("\(s) %") }
        if let g = media.genres, !g.isEmpty { parts.append(g.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private var watchLabel: String {
        if item.reason == .resume { return t("Reprendre l'épisode \(item.episode)", "Resume episode \(item.episode)") }
        if media.isMovie { return t("Regarder", "Watch") }
        return t("Regarder l'épisode \(item.episode)", "Watch episode \(item.episode)")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImageView(url: media.bannerImage ?? media.coverImage?.extraLarge, corner: 0)
                .frame(height: 460)
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
                Text(kicker).font(.footnote.weight(.semibold)).foregroundStyle(Nami.accent(media.coverImage?.color))
                Text(media.title.display).font(.largeTitle.bold()).lineLimit(3)
                if !meta.isEmpty { Text(meta).font(.subheadline).foregroundStyle(Nami.textSecondary).lineLimit(2) }
                HStack(spacing: 10) {
                    Button { PlayerCenter.shared.openSources(media, episode: item.episode) } label: {
                        Label(watchLabel, systemImage: "play.fill")
                            .font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).tint(Nami.text).foregroundStyle(Nami.ground)
                    Button(action: open) {
                        Text(t("Voir la fiche", "See details")).font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered).tint(Nami.text)
                }
                .padding(.top, 6)
                if count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<count, id: \.self) { i in
                            Capsule().fill(i == index ? Nami.text : Nami.text.opacity(0.25))
                                .frame(width: i == index ? 30 : 18, height: 3)
                        }
                    }
                    .padding(.top, 10)
                    .accessibilityElement()
                    .accessibilityLabel(t("\(index + 1) sur \(count)", "\(index + 1) of \(count)"))
                }
            }
            .foregroundStyle(Nami.text)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
    }
}

/// Today's episodes in time order: small cover, time, title, episode, and a mark on the anime of your list.
struct AiringRow: View {
    let items: [AiringItem]
    let listIDs: Set<Int>
    let ns: Namespace.ID
    @Binding var path: [MediaRoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("Aujourd'hui", "Today")).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if let first = items.first {
                    Button(t("Calendrier complet", "Full calendar")) {
                        path.append(MediaRoute(media: first.media, source: MediaRoute.calendar))
                    }
                    .font(.subheadline).tint(Nami.textSecondary)
                }
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        let route = MediaRoute(media: item.media, source: "today-\(item.id)")
                        NavigationLink(value: route) { card(item).zoomSource(route.source, in: ns) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func card(_ item: AiringItem) -> some View {
        let time = item.airingAt.formatted(date: .omitted, time: .shortened)
        return HStack(spacing: 10) {
            CoverImageView(url: item.media.coverImage?.large, corner: 4).frame(width: 52, height: 74)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.aired ? t("\(time) · sorti", "\(time) · out") : time).font(.caption2.bold()).foregroundStyle(Nami.textSecondary)
                Text(item.media.title.display).font(.caption.weight(.semibold)).lineLimit(1)
                Text(t("Épisode \(item.episode)", "Episode \(item.episode)")).font(.caption2).foregroundStyle(Nami.textSecondary)
                if listIDs.contains(item.media.id) {
                    Text(t("Dans ta liste", "In your list")).font(.caption2.weight(.semibold))
                        .foregroundStyle(Nami.accent(item.media.coverImage?.color))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(width: 240)
        .background(Nami.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(Nami.text)
    }
}

struct HomeView: View {
    @EnvironmentObject private var anilist: AniList
    @ObservedObject private var store = HomeStore.shared
    @State private var path: [MediaRoute] = []
    @Namespace private var ns

    /// Without AniList, the anime played on this device that still have an episode to go.
    private var local: [Playback.Recent] {
        Playback.recent.filter { $0.episode <= ($0.media.isMovie ? 1 : $0.media.availableEpisodes) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !store.loaded {
                        skeleton
                    } else if let feed = store.feed {
                        sections(feed)
                    } else {
                        failure
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
                if r.source == MediaRoute.calendar {
                    CalendarView(listIDs: store.feed?.listIDs ?? [], ns: ns)
                } else {
                    MediaDetailView(media: r.media).zoomDestination(r.source, in: ns)
                }
            }
            .refreshable { await load() }
            .task(id: "\(anilist.viewer?.id ?? 0)-\(anilist.listRevision)") {
                // A list change only refreshes the rows that depend on the list.
                let sameAccount = store.loadedFor == anilist.viewer?.id && store.inputs != nil
                // Already up to date (the page was only rebuilt): nothing to ask for.
                if sameAccount, store.revision == anilist.listRevision { return }
                await load(accountOnly: sameAccount)
            }
        }
    }

    @ViewBuilder
    private func sections(_ feed: HomeFeed) -> some View {
        if !feed.hero.isEmpty {
            HomeCarousel(items: feed.hero) { item in
                path.append(MediaRoute(media: item.media, source: "hero-\(item.media.id)"))
            }
        }
        if !anilist.isLoggedIn { loginHint }
        continueRow(feed)
        if !feed.today.isEmpty { AiringRow(items: feed.today, listIDs: feed.listIDs, ns: ns, path: $path) }
        if !feed.planning.isEmpty {
            MediaRow(title: t("À voir dans ta liste", "Planned in your list"), items: feed.planning, ns: ns, path: $path)
        }
        if let because = feed.because {
            MediaRow(title: t("Parce que tu regardes \(because.source.title.display)", "Because you watch \(because.source.title.display)"),
                     items: because.items, ns: ns, path: $path)
        }
        if !feed.season.isEmpty {
            let (s, y) = AniList.currentSeason()
            MediaRow(title: "\(Self.seasonName(s)) \(y)", items: feed.season, ns: ns, path: $path)
        }
        if !feed.trending.isEmpty { MediaRow(title: t("Tendances", "Trending"), items: feed.trending, ns: ns, path: $path) }
        if !feed.topRated.isEmpty {
            MediaRow(title: t("Les mieux notés", "Top rated"), items: feed.topRated, ns: ns, path: $path, ranked: true)
        }
    }

    @ViewBuilder
    private func continueRow(_ feed: HomeFeed) -> some View {
        let shown = feed.continueWatching
        if !shown.isEmpty {
            MediaRow(title: t("Continuer", "Continue watching"), items: shown.map(\.media), ns: ns, path: $path) { m in
                guard let c = shown.first(where: { $0.id == m.id }) else { return nil }
                if c.fraction != nil { return t("Reprendre l'épisode \(c.nextEpisode)", "Resume episode \(c.nextEpisode)") }
                return c.available ? t("Épisode \(c.nextEpisode) dispo", "Episode \(c.nextEpisode) out")
                    : t("Épisode \(c.nextEpisode)", "Episode \(c.nextEpisode)")
            } progress: { m in
                // How far into the next episode you are, else how far into the series.
                guard let c = shown.first(where: { $0.id == m.id }) else { return nil }
                if let f = c.fraction { return f }
                let total = m.episodes ?? m.availableEpisodes
                return total > 0 ? Double(c.nextEpisode - 1) / Double(total) : nil
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
            LoadingShape(height: 460, corner: 0)
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

    private var failure: some View {
        VStack(spacing: 10) {
            Text(t("Rien à afficher pour le moment", "Nothing to show yet")).font(.headline)
            Text(t("Impossible de joindre AniList. Vérifie ta connexion, puis réessaie.",
                   "Can't reach AniList. Check your connection, then try again."))
                .font(.subheadline).foregroundStyle(Nami.textSecondary).multilineTextAlignment(.center)
            Button(t("Réessayer", "Try again")) { Task { await load() } }.buttonStyle(.bordered).tint(Nami.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 160)
        .padding(.horizontal, 32)
    }

    private var loginHint: some View {
        Text(t("Connecte AniList dans Réglages pour reprendre là où tu en es.",
               "Log in to AniList in Settings to pick up where you left off."))
            .font(.footnote).foregroundStyle(Nami.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    private func load(accountOnly: Bool = false) async {
        let account = anilist.viewer?.id
        let fresh = await HomeFeed.load(anilist, previous: account == store.loadedFor ? store.inputs : nil,
                                        accountOnly: accountOnly)
        // A newer load replaced this one: leave the screen to it.
        guard !Task.isCancelled else { return }
        store.loadedFor = account
        store.revision = anilist.listRevision
        if let fresh {
            store.inputs = fresh
            store.feed = fresh.feed(loggedIn: anilist.isLoggedIn)
            anilist.newEpisodes = fresh.watching.filter(\.hasNewEpisode).count
        }
        store.loaded = true
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
    @State private var genres: Set<String> = []
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
        if !genres.isEmpty { return genres.sorted().joined(separator: ", ") }
        return t("Les plus populaires", "Most popular")
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.genres, id: \.self) { g in
                                let on = genres.contains(g)
                                Button { if on { genres.remove(g) } else { genres.insert(g) } } label: {
                                    Text(g).font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(on ? Nami.text : .white.opacity(0.08), in: Capsule())
                                        .foregroundStyle(on ? Nami.ground : Nami.text)
                                }
                                .accessibilityAddTraits(on ? .isSelected : [])
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
            .task(id: "\(text)|\(genres.sorted().joined(separator: ","))") {
                let q = text.trimmingCharacters(in: .whitespaces)
                if q.count == 1 { return }
                if !q.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                loading = true
                if let found = try? await anilist.search(q, genres: Self.genres.filter(genres.contains)), !Task.isCancelled { results = found }
                loading = false
            }
        }
    }
}
