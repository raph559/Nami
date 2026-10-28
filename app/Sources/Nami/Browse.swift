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

struct MediaCard: View {
    let media: Media
    var badge: String?
    var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(url: media.coverImage?.large ?? media.coverImage?.extraLarge)
                .frame(width: width, height: width * 1.45)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule()).padding(6)
                    }
                }
            Text(media.title.display).font(.caption.weight(.semibold)).lineLimit(2)
                .frame(width: width, alignment: .leading)
        }
    }
}

/// Grid cell that sizes its cover from the column width.
struct MediaGridCell: View {
    let media: Media

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(url: media.coverImage?.large ?? media.coverImage?.extraLarge)
                .aspectRatio(1 / 1.45, contentMode: .fit)
            Text(media.title.display).font(.caption.weight(.semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MediaRow: View {
    let title: String
    let items: [Media]
    var badge: (Media) -> String? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { m in
                        NavigationLink(value: m) { MediaCard(media: m, badge: badge(m)) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var anilist: AniList
    @State private var watching: [WatchingEntry] = []
    @State private var seasonal: [Media] = []
    @State private var trending: [Media] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    if !watching.isEmpty {
                        MediaRow(title: t("Continuer", "Continue watching"), items: watching.map(\.media)) { m in
                            guard let e = watching.first(where: { $0.id == m.id }) else { return nil }
                            return e.hasNewEpisode ? t("Ép. \(e.progress + 1)", "Ep. \(e.progress + 1)") : nil
                        }
                    } else if !anilist.isLoggedIn {
                        loginHint
                    }
                    if !seasonal.isEmpty {
                        let (s, y) = AniList.currentSeason()
                        MediaRow(title: "\(Self.seasonName(s)) \(y)", items: seasonal)
                    }
                    if !trending.isEmpty { MediaRow(title: t("Tendances", "Trending"), items: trending) }
                }
                .padding(.vertical)
            }
            .navigationTitle("Nami")
            .navigationDestination(for: Media.self) { MediaDetailView(media: $0) }
            .refreshable { await load() }
            .task(id: anilist.viewer?.id) { await load() }
        }
    }

    private var loginHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus").font(.title2)
            Text(t("Connecte AniList dans Réglages pour retrouver ta liste et synchroniser ta progression.",
                   "Log in to AniList in Settings to see your list and sync your progress."))
                .font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.genres, id: \.self) { g in
                                Button { genre = genre == g ? nil : g } label: {
                                    Text(g).font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(genre == g ? Color.accentColor : .white.opacity(0.08), in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    Text(heading).font(.title3.bold()).padding(.horizontal)
                    if loading && results.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(results) { m in
                            NavigationLink(value: m) { MediaGridCell(media: m) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(t("Recherche", "Search"))
            .searchable(text: $text, prompt: t("Titre d'un anime", "Anime title"))
            .navigationDestination(for: Media.self) { MediaDetailView(media: $0) }
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
