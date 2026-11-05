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
        let statuses = (a?.statuses ?? []).map { (statusLabel($0.status ?? ""), $0.count ?? 0) }
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
                            Text(fact.1).font(.title3.bold())
                            Text(fact.0).font(.caption).foregroundStyle(Nami.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if !genres.isEmpty { heading("Genres"); bars(genres) }
                if !studios.isEmpty { heading("Studios"); bars(studios) }
                if !formats.isEmpty { heading("Formats"); bars(formats) }
                if !statuses.isEmpty { heading(t("Statuts", "Statuses")); bars(statuses) }
                if !scores.isEmpty {
                    heading(t("Notes", "Scores"))
                    columns(scores.map { (format.show($0.0), $0.1) }, label: t("Répartition des notes", "Score distribution"))
                }
                if !years.isEmpty {
                    heading(t("Années de sortie", "Release years"))
                    columns(years.map { ($0.0 % 5 == 0 ? "\($0.0)" : "", $0.1) }, label: t("Animes par année de sortie", "Anime by release year"))
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
    private func bars(_ items: [(String, Int)]) -> some View {
        let most = max(items.map(\.1).max() ?? 1, 1)
        return VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 10) {
                    Text(item.0).lineLimit(1).frame(width: 120, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3).fill(Nami.textSecondary)
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
    private func columns(_ entries: [(String, Int)], label: String) -> some View {
        let most = max(entries.map(\.1).max() ?? 1, 1)
        // Many columns (one per year) get thin gaps, and the labels float under them
        // without taking width, so the chart always fits the screen.
        return HStack(alignment: .bottom, spacing: entries.count > 20 ? 1 : 4) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                Rectangle().fill(Nami.textSecondary)
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
