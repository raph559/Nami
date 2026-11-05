import SwiftUI

/// How the viewer rates anime on AniList. Nami keeps scores out of 100 and shows
/// them in this format. Same rules as mobile/lib/profile.dart.
enum ScoreFormat: String {
    case point100 = "POINT_100", point10Decimal = "POINT_10_DECIMAL", point10 = "POINT_10", point5 = "POINT_5", point3 = "POINT_3"

    /// A score out of 100, the way AniList shows it in this format.
    func show(_ outOf100: Double) -> String {
        switch self {
        case .point100: return "\(Int(outOf100.rounded()))"
        case .point10Decimal: return ListEditorSheet.format((outOf100).rounded() / 10)
        case .point10: return "\(Int((outOf100 / 10).rounded()))"
        case .point5: return String(repeating: "★", count: min(max(Int((outOf100 / 20).rounded()), 1), 5))
        case .point3: return outOf100 >= 61 ? "🙂" : (outOf100 >= 36 ? "😐" : "🙁")
        }
    }

    /// AniList gives the score distribution in the viewer's format, apart from
    /// "10 with decimals", which comes out of 100.
    func distributionToOutOf100(_ score: Int) -> Double {
        switch self {
        case .point100, .point10Decimal: Double(score)
        case .point10: Double(score) * 10
        case .point5: Double(score) * 20
        case .point3: score == 1 ? 35 : (score == 2 ? 60 : 85)
        }
    }
}

/// A piece of an AniList bio, as Nami shows it.
enum BioPart: Hashable {
    case text(String)
    case link(String, URL)
    case spoiler(String)
}

private func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: options)
}

private let media = regex(#"(img\d*%?|youtube|webm)\([^)]*\)|<(img|video|iframe|source)\b[^>]*>|</(video|iframe)>"#)
private let lineBreak = regex(#"<br\s*/?>"#)
private let pieces = regex(#"~!(.*?)!~|<a\b[^>]*?\bhref="([^"]+)"[^>]*>(.*?)</a>|\[([^\]]*)\]\((https?://[^)\s]+)\)|(https?://[^\s<>"')\]]+)"#,
                           [.caseInsensitive, .dotMatchesLineSeparators])
private let tags = regex(#"<[^>]+>"#)
private let marks = regex(#"__|\*\*|~~~"#)
private let headers = regex(#"^#+\s*"#, [.anchorsMatchLines])
private let spaces = regex(#"[ \t]{2,}"#)
private let blankLines = regex(#"\n{3,}"#)
private let strike = regex(#"~~(.+?)~~"#)
// Single * or _ around words; an underscore inside a word (snake_case) stays.
private let italics = regex(#"(?<![\w*])[*_](?=\S)(.+?)(?<=\S)[*_](?![\w*])"#)
private let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
private let entity = regex(#"&(amp|lt|gt|quot|apos|nbsp|#39);|&#(\d+);"#)

/// A link Nami can open: a web address that parses.
private func web(_ href: String) -> URL? {
    guard let url = URL(string: href), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          url.host?.isEmpty == false else { return nil }
    return url
}

private func decodeEntities(_ s: String) -> String {
    let ns = s as NSString
    var out = ""
    var at = 0
    for m in entity.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: at, length: m.range.location - at))
        let whole = ns.substring(with: m.range)
        if m.range(at: 2).location != NSNotFound, let code = Int(ns.substring(with: m.range(at: 2))), let scalar = Unicode.Scalar(code) {
            out += String(Character(scalar))
        } else {
            out += entities[whole] ?? whole
        }
        at = m.range.location + m.range.length
    }
    return out + ns.substring(from: at)
}

private extension String {
    func replacing(_ re: NSRegularExpression, with template: String) -> String {
        re.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: template)
    }
}

/// An AniList bio (Markdown, some HTML and AniList's own codes) as plain text,
/// links and spoilers. Images and videos are left out.
func parseBio(_ about: String?) -> [BioPart] {
    guard let about, !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
    let source = about.replacing(media, with: "").replacing(lineBreak, with: "\n")
    func clean(_ s: String) -> String {
        decodeEntities(s.replacing(tags, with: "").replacing(marks, with: "").replacing(headers, with: "")
            .replacing(strike, with: "$1").replacing(italics, with: "$1"))
            .replacing(spaces, with: " ").replacing(blankLines, with: "\n\n")
    }
    var parts: [BioPart] = []
    func addText(_ s: String) {
        let text = clean(s)
        guard !text.isEmpty else { return }
        if case .text(let before) = parts.last { parts[parts.count - 1] = .text(before + text) } else { parts.append(.text(text)) }
    }
    let ns = source as NSString
    var at = 0
    for m in pieces.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
        addText(ns.substring(with: NSRange(location: at, length: m.range.location - at)))
        at = m.range.location + m.range.length
        func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        if let hidden = group(1) {
            let text = clean(hidden).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append(.spoiler(text)) }
        } else if let href = group(2) {
            // A link around nothing left (an image) is dropped.
            let text = clean(group(3) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { if let url = web(href) { parts.append(.link(text, url)) } else { addText(text) } }
        } else if let label = group(4), let href = group(5) {
            let text = clean(label).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { if let url = web(href) { parts.append(.link(text, url)) } else { addText(text) } }
        } else if let href = group(6) {
            if let url = web(href) {
                parts.append(.link(href.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression), url))
            } else {
                addText(href)
            }
        }
    }
    addText(ns.substring(from: at))
    func blank(_ p: BioPart?) -> Bool { if case .text(let s) = p { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } else { false } }
    while blank(parts.first) { parts.removeFirst() }
    while blank(parts.last) { parts.removeLast() }
    if case .text(let s) = parts.first { parts[0] = .text(String(s.drop(while: \.isWhitespace))) }
    if case .text(let s) = parts.last {
        parts[parts.count - 1] = .text(String(s.reversed().drop(while: \.isWhitespace).reversed()))
    }
    return parts
}

/// The colour the viewer picked for their AniList profile: one of AniList's seven,
/// or a hex colour (donators). Blue, AniList's own, when there is none.
func profileAccent(_ name: String?) -> Color {
    let named: [String: UInt32] = ["blue": 0x3DB4F2, "purple": 0xC063FF, "pink": 0xFC9DD6, "orange": 0xEF881A,
                                   "red": 0xE13333, "green": 0x4CCA51, "gray": 0x677B94]
    var rgb = named[name ?? ""] ?? named["blue"]!
    if let name, name.count == 7, name.hasPrefix("#"), let v = UInt32(name.dropFirst(), radix: 16) { rgb = v }
    return Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
}

/// A score's colour, from red to green, as on AniList. Most scores are between 60
/// and 100, so red starts at 30 to spread them over the whole range.
func scoreColor(_ outOf100: Double) -> Color {
    Color(hue: min(max((outOf100 - 30) / 70, 0), 1) * 120 / 360, saturation: 0.7, brightness: 0.9)
}

/// Each list status in its own colour, the same ones as on AniList.
func statusColor(_ status: String) -> Color {
    switch status {
    case "CURRENT": profileAccent("green")
    case "COMPLETED": profileAccent("blue")
    case "PAUSED": profileAccent("orange")
    case "DROPPED": profileAccent("red")
    case "PLANNING": profileAccent("#9FADBD")
    case "REPEATING": profileAccent("purple")
    default: Nami.textSecondary
    }
}

/// AniList's format names, as Nami writes them.
func formatLabel(_ format: String) -> String {
    switch format {
    case "TV_SHORT": t("TV court", "TV short")
    case "MOVIE": t("Film", "Movie")
    case "SPECIAL": t("Spécial", "Special")
    case "MUSIC": "Clip"
    default: format
    }
}

/// AniList's list statuses, as Nami writes them.
func statusLabel(_ status: String) -> String {
    switch status {
    case "CURRENT": t("En cours", "Watching")
    case "COMPLETED": t("Terminé", "Completed")
    case "PAUSED": t("En pause", "Paused")
    case "DROPPED": t("Abandonné", "Dropped")
    case "PLANNING": t("À voir", "Planning")
    case "REPEATING": t("Revu", "Rewatching")
    default: status
    }
}

/// The bio, cut to 3 lines until "Plus". Spoilers stay hidden until tapped.
struct BioView: View {
    let parts: [BioPart]
    @State private var open = false
    @State private var shown: Set<Int> = []
    /// Heights of the text cut to 3 lines and in full, measured at the real width.
    @State private var cutHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    /// More than 3 lines: "Plus" is needed.
    private var long: Bool { fullHeight > cutHeight + 1 }

    /// Links open in the browser; a hidden spoiler is a link to itself, caught below.
    private var attributed: AttributedString {
        var out = AttributedString()
        for (i, part) in parts.enumerated() {
            switch part {
            case .text(let s):
                out += AttributedString(s)
            case .link(let s, let url):
                var a = AttributedString(s)
                a.link = url
                a.underlineStyle = .single
                out += a
            case .spoiler(let s):
                if shown.contains(i) {
                    out += AttributedString(s)
                } else {
                    var a = AttributedString(" Spoiler ")
                    a.link = URL(string: "nami-spoiler:\(i)")
                    a.backgroundColor = Nami.border
                    a.foregroundColor = Nami.textSecondary
                    out += a
                }
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(attributed)
                .lineLimit(open || !long ? nil : 3)
                .tint(Nami.text)
                .background {
                    // Two hidden copies, one cut and one whole, to know whether the text is cut.
                    ZStack {
                        Text(attributed).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { g in Color.clear.task(id: g.size.height) { cutHeight = g.size.height } })
                        Text(attributed).fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { g in Color.clear.task(id: g.size.height) { fullHeight = g.size.height } })
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "nami-spoiler", let i = Int(url.absoluteString.dropFirst("nami-spoiler:".count)) else {
                        return .systemAction
                    }
                    shown.insert(i)
                    return .handled
                })
            if long {
                Button(open ? t("Moins", "Less") : t("Plus", "More")) { withAnimation { open.toggle() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Nami.text)
            }
        }
    }
}

/// The viewer's anime statistics: the main numbers, what they watch most, how
/// they rate and which years their anime come from.
struct ProfileStatsView: View {
    let viewer: Viewer

    private func number(_ v: Double) -> String { ListEditorSheet.format((v * 10).rounded() / 10) }

    var body: some View {
        let a = viewer.statistics?.anime
        let format = viewer.scoreFormat
        let days = Double(a?.minutesWatched ?? 0) / 60 / 24
        var facts = [
            (t("Animes", "Anime"), "\(a?.count ?? 0)"),
            (t("Épisodes vus", "Episodes watched"), "\(a?.episodesWatched ?? 0)"),
            (t("Jours", "Days"), number(days)),
        ]
        if let mean = a?.meanScore, mean > 0 { facts.append((t("Note moyenne", "Mean score"), format.show(mean))) }
        if let sd = a?.standardDeviation, sd > 0 { facts.append((t("Écart type", "Standard deviation"), "± \(number(sd))")) }
        let genres = (a?.genres ?? []).map { ($0.genre ?? "", $0.count ?? 0) }
        let studios = (a?.studios ?? []).map { ($0.studio?.name ?? "", $0.count ?? 0) }
        let formats = (a?.formats ?? []).map { (formatLabel($0.format ?? ""), $0.count ?? 0) }
        let statuses = (a?.statuses ?? []).map { (statusLabel($0.status ?? ""), $0.count ?? 0, statusColor($0.status ?? "")) }
        let accent = profileAccent(viewer.options?.profileColor)
        // The most-watched first in full colour, the others fading a little.
        func fading(_ items: [(String, Int)]) -> [(String, Int, Color)] {
            items.enumerated().map { i, item in
                (item.0, item.1, accent.opacity(items.count < 2 ? 1 : 1 - 0.5 * Double(i) / Double(items.count - 1)))
            }
        }
        // Entries that end up on the same number add up; 0 (not rated, no year) is left out.
        let scores = Dictionary((a?.scores ?? []).filter { ($0.score ?? 0) > 0 }
            .map { (format.distributionToOutOf100($0.score ?? 0), $0.count ?? 0) }, uniquingKeysWith: +)
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        let years = Dictionary((a?.releaseYears ?? []).filter { ($0.releaseYear ?? 0) > 0 }
            .map { ($0.releaseYear ?? 0, $0.count ?? 0) }, uniquingKeysWith: +)
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                heading(t("En bref", "In brief"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 14) {
                    ForEach(facts, id: \.0) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.1).font(.title3.bold()).foregroundStyle(accent)
                            Text(fact.0).font(.caption).foregroundStyle(Nami.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if !genres.isEmpty { heading("Genres"); bars(fading(genres)) }
                if !studios.isEmpty { heading("Studios"); bars(fading(studios)) }
                if !formats.isEmpty { heading("Formats"); bars(fading(formats)) }
                if !statuses.isEmpty { heading(t("Statuts", "Statuses")); bars(statuses) }
                if !scores.isEmpty {
                    heading(t("Notes", "Scores"))
                    columns(scores.map { (format.show($0.0), $0.1, scoreColor($0.0)) }, label: t("Répartition des notes", "Score distribution"))
                }
                if !years.isEmpty {
                    heading(t("Années de sortie", "Release years"))
                    columns(years.map { ($0.0 % 5 == 0 ? "\($0.0)" : "", $0.1, accent) }, label: t("Animes par année de sortie", "Anime by release year"))
                }
            }
            .padding()
        }
        .navigationTitle(t("Statistiques", "Statistics"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.headline).padding(.top, 18).accessibilityAddTraits(.isHeader)
    }

    /// Names with a bar for their count, the longest for the largest.
    private func bars(_ items: [(String, Int, Color)]) -> some View {
        let most = max(items.map(\.1).max() ?? 1, 1)
        return VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Text(item.0).lineLimit(1).frame(width: 120, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3).fill(item.2)
                            .frame(width: 4 + (geo.size.width - 4) * CGFloat(item.1) / CGFloat(most), height: 10)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 20)
                    Text("\(item.1)").font(.subheadline).foregroundStyle(Nami.textSecondary).frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.0) : \(item.1)")
            }
        }
    }

    /// Columns with a label under each, like the anime page's score chart.
    private func columns(_ entries: [(String, Int, Color)], label: String) -> some View {
        let most = max(entries.map(\.1).max() ?? 1, 1)
        // Many columns (one per year) get thin gaps, and the labels float under them
        // without taking width, so the chart always fits the screen.
        return HStack(alignment: .bottom, spacing: entries.count > 20 ? 1 : 4) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3).fill(e.2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 2 + 90 * CGFloat(e.1) / CGFloat(most))
                    .overlay(alignment: .bottom) {
                        Text(e.0).font(.caption2).foregroundStyle(Nami.textSecondary)
                            .fixedSize()
                            .alignmentGuide(.bottom) { $0[.top] - 4 }
                    }
            }
        }
        .frame(height: 112, alignment: .bottom)
        .padding(.bottom, 18)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

enum FavouriteKind {
    case anime, character, staff, studio

    var argument: String {
        switch self {
        case .anime: "animeId"
        case .character: "characterId"
        case .staff: "staffId"
        case .studio: "studioId"
        }
    }
}

/// The viewer's favourites, the first 25 of each kind. Characters, staff and
/// studios open on AniList, as Nami has no page for them.
struct Favourites: Codable, Hashable {
    struct Item: Codable, Hashable, Identifiable {
        struct Name: Codable, Hashable { var full: String? }
        struct Picture: Codable, Hashable { var large: String? }
        var id: Int
        var name: Name?
        var image: Picture?
        var siteUrl: String?
        var title: String { name?.full ?? "" }
        var url: URL? { siteUrl.flatMap(URL.init(string:)) }
    }

    struct Studio: Codable, Hashable, Identifiable {
        var id: Int
        var name: String
        var siteUrl: String?
        var url: URL? { siteUrl.flatMap(URL.init(string:)) }
    }

    struct Page<T: Codable & Hashable>: Codable, Hashable { var nodes: [T]? }

    var anime: Page<Media>?
    var characters: Page<Item>?
    var staff: Page<Item>?
    var studios: Page<Studio>?

    var isEmpty: Bool {
        (anime?.nodes ?? []).isEmpty && (characters?.nodes ?? []).isEmpty && (staff?.nodes ?? []).isEmpty
            && (studios?.nodes ?? []).isEmpty
    }
}

/// The heart of a favourite on AniList. It changes at once; AniList is told after,
/// one request at a time, and the heart goes back if AniList refuses.
struct FavouriteButton: View {
    let kind: FavouriteKind
    let id: Int
    let initial: Bool
    var compact = false

    static let red = Color(red: 0xE8 / 255, green: 0x5D / 255, blue: 0x75 / 255)

    /// What AniList confirmed during this session, by kind and id. Pages keep the
    /// details they loaded, so a heart built again (another tab, the same anime
    /// opened twice) starts from here; a toggle flips, so starting wrong would undo it.
    @MainActor static var confirmed: [String: Bool] = [:]
    /// Favourites whose last change failed without AniList saying what it has: the
    /// change may have gone through with only the answer lost. They are checked
    /// before anything else is sent.
    @MainActor static var unsure: Set<String> = []

    private var key: String { "\(kind):\(id)" }
    private var known: Bool { Self.confirmed[key] ?? initial }

    /// What the heart shows: what the viewer asked for last.
    @State private var on: Bool?
    /// What AniList has.
    @State private var sent: Bool?
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        let shown = on ?? known
        let label = shown ? t("Retirer des favoris", "Remove from favourites") : t("Ajouter aux favoris", "Add to favourites")
        let heart = Image(systemName: shown ? "heart.fill" : "heart")
            .foregroundStyle(shown ? Self.red : Nami.text)
            .contentTransition(.symbolEffect(.replace))
        Group {
            if compact {
                Button(action: tap) { heart.font(.title3).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                Button(action: tap) { heart.font(.headline).padding(.vertical, 6) }
                    .buttonStyle(.bordered)
                    .tint(Nami.text)
                    .fixedSize()
            }
        }
        .accessibilityLabel(label)
        .alert(t("Les favoris n'ont pas pu être modifiés.", "Favourites could not be changed."), isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func tap() {
        on = !(on ?? known)
        guard !busy else { return }
        busy = true
        Task {
            /// Reads what AniList has and takes it as the truth.
            @MainActor func ask() async throws {
                let now = try await AniList.shared.isFavourite(kind, id: id)
                sent = now
                Self.confirmed[key] = now
                Self.unsure.remove(key)
            }
            // Taps during a request only change what is wanted; it is sent once that request ends.
            do {
                if Self.unsure.contains(key) { try await ask() }
                while (on ?? known) != (sent ?? known) {
                    Self.unsure.insert(key)
                    try await AniList.shared.toggleFavourite(kind, id: id)
                    let now = !(sent ?? known)
                    sent = now
                    Self.confirmed[key] = now
                    Self.unsure.remove(key)
                }
            } catch {
                // The change may have reached AniList with only its answer lost: ask before going back.
                try? await ask()
                let done = !Self.unsure.contains(key) && (sent ?? known) == (on ?? known)
                on = sent ?? known
                failed = !done
            }
            busy = false
        }
    }
}

/// The viewer's favourites on the profile, a row per kind.
struct FavouritesView: View {
    let favourites: Favourites
    /// For the zoom into an anime's page, as from the list below.
    let ns: Namespace.ID
    @Environment(\.openURL) private var openURL

    private func heading(_ text: String, big: Bool = false) -> some View {
        Text(text).font(big ? .title3.bold() : .subheadline.weight(.semibold))
            .foregroundStyle(big ? Nami.text : Nami.textSecondary)
            .padding(.top, big ? 10 : 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func people(_ items: [Favourites.Item]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(items) { p in
                    Button { if let url = p.url { openURL(url) } } label: {
                        VStack(spacing: 6) {
                            CoverImageView(url: p.image?.large, corner: 32).frame(width: 64, height: 64)
                            Text(p.title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(width: 76)
                    }
                    .buttonStyle(.plain)
                    .disabled(p.url == nil)
                }
            }
        }
    }

    var body: some View {
        let anime = favourites.anime?.nodes ?? []
        let characters = (favourites.characters?.nodes ?? []).filter { !$0.title.isEmpty }
        let staff = (favourites.staff?.nodes ?? []).filter { !$0.title.isEmpty }
        let studios = favourites.studios?.nodes ?? []
        VStack(alignment: .leading, spacing: 8) {
            heading(t("Favoris", "Favourites"), big: true)
            if !anime.isEmpty {
                heading(t("Animes", "Anime"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(anime) { m in
                            let route = MediaRoute(media: m, source: "favourite-\(m.id)")
                            NavigationLink(value: route) {
                                MediaCard(media: m, width: 104).zoomSource(route.source, in: ns)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !characters.isEmpty { heading(t("Personnages", "Characters")); people(characters) }
            if !staff.isEmpty { heading(t("Équipe", "Staff")); people(staff) }
            if !studios.isEmpty {
                heading("Studios")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(studios) { s in
                            Button(s.name) { if let url = s.url { openURL(url) } }
                                .buttonStyle(.bordered).tint(Nami.text)
                                .disabled(s.url == nil)
                        }
                    }
                }
            }
        }
    }
}
