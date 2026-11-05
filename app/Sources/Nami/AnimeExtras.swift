import SwiftUI
import WebKit

/// What only the anime page needs, apart from the fields every list uses.
struct AnimeDetails: Decodable {
    struct Trailer: Decodable, Identifiable {
        var id: String
        var site: String
        var thumbnail: String?

        var cleanID: String { id.trimmingCharacters(in: .whitespacesAndNewlines) }
        var isYouTube: Bool { site == "youtube" }

        /// The page that plays it, for an embedded player.
        var embedURL: String {
            isYouTube ? "https://www.youtube-nocookie.com/embed/\(cleanID)?autoplay=1&playsinline=1&rel=0"
                : "https://www.dailymotion.com/embed/video/\(cleanID)?autoplay=1"
        }

        /// Its own page on the site.
        var pageURL: URL? {
            URL(string: isYouTube ? "https://www.youtube.com/watch?v=\(cleanID)" : "https://www.dailymotion.com/video/\(cleanID)")
        }
    }

    struct Tag: Decodable, Identifiable {
        var name: String
        var rank: Int?
        var isMediaSpoiler: Bool?
        var isGeneralSpoiler: Bool?
        var id: String { name }
        var spoiler: Bool { isMediaSpoiler == true || isGeneralSpoiler == true }
    }

    struct Ranking: Decodable {
        var rank: Int
        var type: String
        var allTime: Bool?
        var season: String?
        var year: Int?

        var label: String? {
            let kind: String
            switch type {
            case "RATED": kind = t("mieux noté", "highest rated")
            case "POPULAR": kind = t("plus populaire", "most popular")
            default: return nil
            }
            if allTime == true { return "#\(rank) \(kind) \(t("de tous les temps", "of all time"))" }
            if let season, let year { return "#\(rank) \(kind) \(HomeView.seasonName(season)) \(year)" }
            if let year { return "#\(rank) \(kind) \(year)" }
            return nil
        }
    }

    struct Link: Decodable, Identifiable {
        var site: String?
        var url: String?
        var id: String { url ?? "" }
    }

    struct Stat: Decodable {
        var score: Int?
        var status: String?
        var amount: Int
    }

    struct Stats: Decodable {
        var scoreDistribution: [Stat]?
        var statusDistribution: [Stat]?
    }

    struct Person: Decodable {
        struct Name: Decodable { var full: String? }
        struct Picture: Decodable { var large: String? }
        var name: Name?
        var image: Picture?
        /// Only characters carry these: they can be favourites from the Characters tab.
        var id: Int?
        var isFavourite: Bool?
        var siteUrl: String?
    }

    struct Relations: Decodable {
        struct Edge: Decodable {
            var relationType: String?
            var node: Media
        }
        var edges: [Edge]
    }

    struct Characters: Decodable {
        struct Edge: Decodable {
            var role: String?
            var voiceActors: [Person]?
            var node: Person
        }
        var edges: [Edge]
    }

    struct Staff: Decodable {
        struct Edge: Decodable {
            var role: String?
            var node: Person
        }
        var edges: [Edge]
    }

    struct Recommendations: Decodable {
        struct Node: Decodable { var mediaRecommendation: Media? }
        var nodes: [Node]
    }

    /// One of the viewer's favourites (false when logged out).
    var isFavourite: Bool?
    var trailer: Trailer?
    var tags: [Tag]?
    var rankings: [Ranking]?
    var externalLinks: [Link]?
    var stats: Stats?
    var relations: Relations?
    var characters: Characters?
    var staff: Staff?
    var recommendations: Recommendations?

    /// Only anime: AniList also relates the manga and novels.
    var related: [Relations.Edge] { relations?.edges.filter { $0.node.type == "ANIME" } ?? [] }
    var similar: [Media] { recommendations?.nodes.compactMap(\.mediaRecommendation) ?? [] }
}

/// The seasons in order around an anime: what comes before it, oldest first, and
/// what comes after it; `around` holds what hangs off the other seasons (side
/// stories, spin-offs, films, specials).
struct AnimeChain {
    var before: [AnimeDetails.Relations.Edge]
    var after: [AnimeDetails.Relations.Edge]
    var around: [AnimeDetails.Relations.Edge] = []
}

extension AniList {
    /// AniList only gives an anime's direct prequel and sequel, so part 1 only knows
    /// part 2. This follows them step by step, several anime per request and at most
    /// 8 steps each way, to show the whole order. Same rules as mobile/lib/anime_details.dart.
    func chain(media: Media, details: AnimeDetails) async -> AnimeChain {
        struct Found: Decodable {
            struct Page: Decodable { var media: [Node] }
            struct Node: Decodable { var id: Int; var relations: AnimeDetails.Relations? }
            var Page: Page
        }
        let related = details.related
        var before = related.filter { AnimeRelation.isBefore($0.relationType) }
        var after = related.filter { $0.relationType == "SEQUEL" }
        var seen = Set([media.id] + related.map(\.node.id))
        var back = before.filter { $0.relationType == "PREQUEL" }.map(\.node.id)
        var forth = after.map(\.node.id)
        var around: [AnimeDetails.Relations.Edge] = []
        for _ in 0..<8 where !back.isEmpty || !forth.isEmpty {
            guard let found = try? await query("""
            query($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids, type: ANIME) { id
              relations { edges { relationType(version: 2) node { \(Self.cardFields) } } } } } }
            """, ["ids": back + forth], as: Found.self) else { break }
            let byID = Dictionary(found.Page.media.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            func next(_ from: [Int], _ relation: String) -> [AnimeDetails.Relations.Edge] {
                from.flatMap { id in
                    (byID[id]?.relations?.edges ?? []).filter {
                        $0.relationType == relation && $0.node.type == "ANIME" && seen.insert($0.node.id).inserted
                    }
                }
            }
            let older = next(back, "PREQUEL")
            let newer = next(forth, "SEQUEL")
            // The rest of each season's links, once the chain has taken its own.
            for m in found.Page.media {
                for e in m.relations?.edges ?? [] where e.relationType != "PREQUEL" && e.relationType != "SEQUEL"
                    && e.node.type == "ANIME" && seen.insert(e.node.id).inserted {
                    around.append(e)
                }
            }
            before.insert(contentsOf: older.reversed(), at: 0)
            after.append(contentsOf: newer)
            back = older.map(\.node.id)
            forth = newer.map(\.node.id)
        }
        return AnimeChain(before: before, after: after, around: around)
    }
}

enum AnimeRelation {
    static func label(_ relation: String?) -> String {
        switch relation {
        case "SEQUEL": t("Suite", "Sequel")
        case "PREQUEL": t("Préquelle", "Prequel")
        case "SIDE_STORY": t("Histoire parallèle", "Side story")
        case "SPIN_OFF": "Spin-off"
        case "ALTERNATIVE": t("Autre version", "Alternative")
        case "PARENT": t("Série principale", "Main story")
        case "SUMMARY": t("Résumé", "Summary")
        case "COMPILATION": "Compilation"
        case "CONTAINS": t("Contient", "Contains")
        default: t("Lié", "Related")
        }
    }

    static func isBefore(_ relation: String?) -> Bool { relation == "PREQUEL" || relation == "PARENT" }
}

extension AniList {
    static let cardFields = """
    id title { romaji english native userPreferred } coverImage { extraLarge large color }
    format type status episodes seasonYear averageScore nextAiringEpisode { episode airingAt }
    """

    func details(id: Int) async throws -> AnimeDetails {
        struct D: Decodable { var Media: AnimeDetails }
        return try await query("""
        query($id: Int) { Media(id: $id) {
        isFavourite
        trailer { id site thumbnail }
        tags { name rank isMediaSpoiler isGeneralSpoiler }
        rankings { rank type allTime season year }
        externalLinks { site url type }
        stats { scoreDistribution { score amount } statusDistribution { status amount } }
        relations { edges { relationType(version: 2) node { \(Self.cardFields) } } }
        characters(sort: [ROLE, RELEVANCE], perPage: 12) { edges { role
          voiceActors(language: JAPANESE, sort: [RELEVANCE]) { name { full } image { large } }
          node { id isFavourite siteUrl name { full } image { large } } } }
        staff(sort: [RELEVANCE], perPage: 8) { edges { role node { name { full } image { large } } } }
        recommendations(sort: [RATING_DESC], perPage: 12) { nodes { mediaRecommendation { \(Self.cardFields) } } }
        } }
        """, ["id": id], as: D.self).Media
    }
}

private struct TrailerWeb: UIViewRepresentable {
    let trailer: AnimeDetails.Trailer

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        // YouTube refuses an embed with no origin, so the page gets one.
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="\(trailer.embedURL)" allow="autoplay; encrypted-media; fullscreen" allowfullscreen></iframe></body></html>
        """, baseURL: URL(string: "https://github.com/raph559/Nami"))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// The trailer, played in the app. The site's own page stays one tap away.
struct TrailerView: View {
    let trailer: AnimeDetails.Trailer
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrailerWeb(trailer: trailer)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(t("Fermer", "Close")) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let page = trailer.pageURL {
                            Link(trailer.isYouTube ? "YouTube" : t("Le site", "The site"), destination: page)
                        }
                    }
                }
        }
    }
}

private struct Heading: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.title3.bold()).padding(.top, 14).accessibilityAddTraits(.isHeader)
    }
}

private struct PersonRow: View {
    let person: AnimeDetails.Person
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            CoverImageView(url: person.image?.large, corner: 6).frame(width: 44, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name?.full ?? "").font(.subheadline).lineLimit(2)
                if let detail { Text(detail).font(.caption).foregroundStyle(Nami.textSecondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AnimeDetailsTab: View {
    let media: Media
    let details: AnimeDetails
    let onTrailer: (AnimeDetails.Trailer) -> Void
    @State private var spoilers = false

    private var scores: [AnimeDetails.Stat] {
        (details.stats?.scoreDistribution ?? []).sorted { ($0.score ?? 0) < ($1.score ?? 0) }
    }

    private func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f M", Double(n) / 1_000_000) }
        return n >= 1000 ? "\(n / 1000) k" : "\(n)"
    }

    private func statusLabel(_ status: String?) -> String {
        switch status {
        case "CURRENT": t("regardent", "watching")
        case "PLANNING": t("prévoient de voir", "planning")
        case "COMPLETED": t("ont terminé", "completed")
        case "DROPPED": t("ont abandonné", "dropped")
        case "PAUSED": t("en pause", "paused")
        default: status?.lowercased() ?? ""
        }
    }

    private var chart: some View {
        let most = max(scores.map(\.amount).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(scores, id: \.score) { s in
                VStack(spacing: 4) {
                    Rectangle().fill(Nami.textSecondary)
                        .frame(height: 2 + 80 * CGFloat(s.amount) / CGFloat(most))
                    Text("\((s.score ?? 0) / 10)").font(.caption2).foregroundStyle(Nami.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(t("Répartition des notes", "Score distribution"))
    }

    var body: some View {
        let tags = details.tags ?? []
        let hidden = tags.filter(\.spoiler).count
        let statuses = (details.stats?.statusDistribution ?? []).sorted { $0.amount > $1.amount }
        let rankings = (details.rankings ?? []).compactMap(\.label).prefix(4)
        VStack(alignment: .leading, spacing: 8) {
            if let trailer = details.trailer {
                Heading(t("Bande-annonce", "Trailer"))
                Button { onTrailer(trailer) } label: {
                    CoverImageView(url: trailer.thumbnail ?? media.bannerImage, corner: 8)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            Image(systemName: "play.fill").font(.title).padding(16)
                                .background(Nami.ground.opacity(0.7), in: Circle())
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("Lire la bande-annonce", "Play the trailer"))
            }
            if !rankings.isEmpty {
                Heading(t("Classements", "Rankings"))
                ForEach(Array(rankings), id: \.self) { Text($0).font(.subheadline).foregroundStyle(Nami.textSecondary) }
            }
            if !scores.isEmpty {
                Heading(t("Notes", "Scores"))
                chart
            }
            if !statuses.isEmpty {
                Heading(t("Sur AniList", "On AniList"))
                Text(statuses.map { "\(short($0.amount)) \(statusLabel($0.status))" }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Nami.textSecondary)
            }
            if !tags.isEmpty {
                Heading("Tags")
                Text(tags.filter { spoilers || !$0.spoiler }.map { "\($0.name) \($0.rank ?? 0) %" }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(Nami.textSecondary)
                if hidden > 0, !spoilers {
                    Button(t("Montrer \(hidden) tags avec spoilers", "Show \(hidden) spoiler tags")) { spoilers = true }
                        .font(.footnote)
                }
            }
            if let staff = details.staff?.edges, !staff.isEmpty {
                Heading(t("Équipe", "Staff"))
                ForEach(staff.indices, id: \.self) { PersonRow(person: staff[$0].node, detail: staff[$0].role) }
            }
            if let links = details.externalLinks, !links.isEmpty {
                Heading(t("Liens", "Links"))
                ForEach(links) { link in
                    if let raw = link.url, let url = URL(string: raw) {
                        Link(link.site ?? raw, destination: url).font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnimeCastTab: View {
    let details: AnimeDetails

    var body: some View {
        let cast = details.characters?.edges ?? []
        VStack(alignment: .leading, spacing: 12) {
            if cast.isEmpty {
                Text(t("Aucun personnage connu", "No characters known")).foregroundStyle(Nami.textSecondary)
            }
            ForEach(cast.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    PersonRow(person: cast[i].node, detail: cast[i].role == "MAIN" ? t("Principal", "Main") : t("Secondaire", "Supporting"))
                    if AniList.shared.isLoggedIn, let id = cast[i].node.id {
                        FavouriteButton(kind: .character, id: id, initial: cast[i].node.isFavourite == true, compact: true)
                    }
                    if let voice = cast[i].voiceActors?.first {
                        PersonRow(person: voice, detail: t("Voix", "Voice"))
                    }
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What came before, this anime, what comes after; then everything else linked to it.
struct AnimeRelatedTab: View {
    let media: Media
    let details: AnimeDetails
    /// The whole order of seasons, once AniList has answered.
    @State private var chain: AnimeChain?

    private func link(_ m: Media, label: String?) -> some View {
        NavigationLink(value: MediaRoute(media: m, source: "related-\(m.id)")) {
            MediaCard(media: m, badge: label, width: 104)
        }
        .buttonStyle(.plain)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.footnote).foregroundStyle(Nami.textSecondary).padding(.top, 66)
    }

    var body: some View {
        let related = details.related
        // The direct prequels and sequels the page already has, until the whole order arrives.
        let before = chain?.before ?? related.filter { AnimeRelation.isBefore($0.relationType) }
        let after = chain?.after ?? related.filter { $0.relationType == "SEQUEL" }
        let others = related.filter { !AnimeRelation.isBefore($0.relationType) && $0.relationType != "SEQUEL" }
        let grid = [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)]
        VStack(alignment: .leading, spacing: 8) {
            if !before.isEmpty || !after.isEmpty {
                Heading(t("Dans quel ordre", "In order"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(before, id: \.node.id) { e in
                            link(e.node, label: AnimeRelation.label(e.relationType))
                            arrow
                        }
                        MediaCard(media: media, badge: t("Cet anime", "This anime"), width: 104)
                        ForEach(after, id: \.node.id) { e in
                            arrow
                            link(e.node, label: AnimeRelation.label(e.relationType))
                        }
                    }
                }
            }
            if !others.isEmpty {
                Heading(t("Aussi lié", "Also related"))
                LazyVGrid(columns: grid, alignment: .leading, spacing: 14) {
                    ForEach(others, id: \.node.id) { link($0.node, label: AnimeRelation.label($0.relationType)) }
                }
            }
            if let around = chain?.around, !around.isEmpty {
                Heading(t("Autour de la série", "Around the series"))
                LazyVGrid(columns: grid, alignment: .leading, spacing: 14) {
                    ForEach(around, id: \.node.id) { link($0.node, label: AnimeRelation.label($0.relationType)) }
                }
            }
            if !details.similar.isEmpty {
                Heading(t("Si tu as aimé", "If you liked this"))
                LazyVGrid(columns: grid, alignment: .leading, spacing: 14) {
                    ForEach(details.similar) { link($0, label: nil) }
                }
            }
            if related.isEmpty, details.similar.isEmpty {
                Text(t("Rien de lié pour le moment", "Nothing related yet")).foregroundStyle(Nami.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: media.id) {
            let found = await AniList.shared.chain(media: media, details: details)
            withAnimation { chain = found }
        }
    }
}
