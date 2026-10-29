import AuthenticationServices
import Foundation
import SwiftUI

struct MediaTitle: Codable, Hashable {
    var romaji: String?
    var english: String?
    var native: String?
    var userPreferred: String?

    var display: String {
        let preferred: String? = switch TitleLanguage.current {
        case .romaji: romaji
        case .english: english
        case .native: native
        }
        return preferred ?? romaji ?? english ?? native ?? userPreferred ?? "?"
    }
    var all: [String] { [romaji, english, native, userPreferred].compactMap { $0 }.uniqued() }
}

struct CoverImage: Codable, Hashable {
    var extraLarge: String?
    var large: String?
    var color: String?
}

struct AiringEpisode: Codable, Hashable {
    var episode: Int
    var airingAt: Int
}

struct FuzzyDate: Codable, Hashable {
    var year: Int?
    var month: Int?
    var day: Int?

    var date: Date? {
        guard let year, let month, let day else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))
    }

    init(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        self.year = year; self.month = month; self.day = day
    }

    init(_ date: Date) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year, month: c.month, day: c.day)
    }

    var input: [String: Any] {
        ["year": year as Any? ?? NSNull(), "month": month as Any? ?? NSNull(), "day": day as Any? ?? NSNull()]
    }
}

/// The viewer's entry for a media in their AniList list.
struct ListEntry: Codable, Hashable {
    var id: Int?
    var progress: Int?
    var status: String?
    /// Score on a 0-100 scale, whatever the user's display format.
    var score: Double?
    var `repeat`: Int?
    var notes: String?
    var startedAt: FuzzyDate?
    var completedAt: FuzzyDate?
}

/// The states of an entry in the viewer's list, in the order AniList shows them.
enum ListStatus: String, CaseIterable, Identifiable {
    case CURRENT, PLANNING, COMPLETED, REPEATING, PAUSED, DROPPED
    var id: String { rawValue }

    var label: String {
        switch self {
        case .CURRENT: t("En cours", "Watching")
        case .PLANNING: t("À voir", "Planning")
        case .COMPLETED: t("Terminé", "Completed")
        case .PAUSED: t("En pause", "Paused")
        case .DROPPED: t("Abandonné", "Dropped")
        case .REPEATING: t("Revisionnage", "Rewatching")
        }
    }

    var icon: String {
        switch self {
        case .CURRENT: "play.circle.fill"
        case .PLANNING: "bookmark.fill"
        case .COMPLETED: "checkmark.circle.fill"
        case .PAUSED: "pause.circle.fill"
        case .DROPPED: "xmark.circle.fill"
        case .REPEATING: "arrow.counterclockwise.circle.fill"
        }
    }
}

struct Media: Codable, Identifiable, Hashable {
    var id: Int
    var idMal: Int?
    var title: MediaTitle
    var coverImage: CoverImage?
    var bannerImage: String?
    var description: String?
    var episodes: Int?
    var duration: Int?
    var format: String?
    var status: String?
    var season: String?
    var seasonYear: Int?
    var averageScore: Int?
    var genres: [String]?
    var synonyms: [String]?
    var nextAiringEpisode: AiringEpisode?
    var mediaListEntry: ListEntry?
    var startDate: FuzzyDate?

    /// Episodes that can be watched now (aired so far for ongoing shows).
    var availableEpisodes: Int {
        if let next = nextAiringEpisode { return max(next.episode - 1, 0) }
        return episodes ?? 0
    }

    var isMovie: Bool { format == "MOVIE" }

    var plainDescription: String {
        guard let description else { return "" }
        return description
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    var accent: Color { Color(hex: coverImage?.color) ?? .accentColor }
}

struct Viewer: Codable, Hashable {
    struct Options: Codable, Hashable {
        var titleLanguage: String?
        var displayAdultContent: Bool?
        var profileColor: String?
    }

    struct ListOptions: Codable, Hashable {
        var scoreFormat: String?
    }

    struct Statistics: Codable, Hashable {
        struct Anime: Codable, Hashable {
            var count: Int?
            var episodesWatched: Int?
            var minutesWatched: Int?
            var meanScore: Double?
        }
        var anime: Anime?
    }

    var id: Int
    var name: String
    var about: String?
    var avatar: CoverImage?
    var bannerImage: String?
    var siteUrl: String?
    var options: Options?
    var mediaListOptions: ListOptions?
    var statistics: Statistics?
}

/// One anime of the viewer's list with its entry.
struct LibraryEntry: Identifiable, Hashable {
    var media: Media
    var entry: ListEntry
    var id: Int { media.id }
}

struct WatchingEntry: Identifiable, Hashable {
    var media: Media
    var progress: Int
    var id: Int { media.id }
    var hasNewEpisode: Bool { media.availableEpisodes > progress }
}

enum AniListError: LocalizedError {
    case api(String)
    var errorDescription: String? {
        switch self { case .api(let m): return "AniList : \(m)" }
    }
}

let mediaFields = """
id idMal title { romaji english native userPreferred } coverImage { extraLarge large color }
bannerImage description(asHtml: false) episodes duration format status season seasonYear
averageScore genres synonyms nextAiringEpisode { episode airingAt } startDate { year month day }
mediaListEntry { \(entryFields) }
"""

let entryFields = """
id progress status score(format: POINT_100) repeat notes startedAt { year month day } completedAt { year month day }
"""

@MainActor
final class AniList: ObservableObject {
    static let shared = AniList()

    @AppStorage("anilistToken") private var token: String = ""
    /// AniList API client registered for Nami (redirect URL nami://auth).
    private let clientID = "55284"
    @Published var viewer: Viewer?
    /// Goes up each time Nami changes the viewer's list, so screens showing it reload.
    @Published var listRevision = 0

    var isLoggedIn: Bool { !token.isEmpty }

    private init() {}

    // MARK: Transport

    private struct GQLResponse<T: Decodable>: Decodable {
        var data: T?
        var errors: [GQLError]?
    }

    private struct GQLError: Decodable { var message: String }

    func query<T: Decodable>(_ query: String, _ variables: [String: Any] = [:], as: T.Type) async throws -> T {
        var req = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 { logout() }
        let decoded = try JSONDecoder().decode(GQLResponse<T>.self, from: data)
        if let err = decoded.errors?.first { throw AniListError.api(err.message) }
        guard let value = decoded.data else { throw AniListError.api("réponse vide") }
        return value
    }

    private struct PageData: Decodable {
        struct Page: Decodable { var media: [Media] }
        var Page: Page
    }

    // MARK: Browse

    func trending() async throws -> [Media] {
        try await query("query { Page(perPage: 30) { media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { \(mediaFields) } } }", as: PageData.self).Page.media
    }

    func seasonal() async throws -> [Media] {
        let (season, year) = Self.currentSeason()
        return try await query("""
        query($s: MediaSeason, $y: Int) { Page(perPage: 30) { media(type: ANIME, season: $s, seasonYear: $y, sort: POPULARITY_DESC, isAdult: false) { \(mediaFields) } } }
        """, ["s": season, "y": year], as: PageData.self).Page.media
    }

    /// Searches by text and/or genre; with neither, returns the most popular.
    func search(_ text: String, genre: String? = nil) async throws -> [Media] {
        var vars: [String: Any] = ["sort": [text.isEmpty ? "POPULARITY_DESC" : "SEARCH_MATCH"]]
        if !text.isEmpty { vars["q"] = text }
        if let genre { vars["g"] = genre }
        return try await query("""
        query($q: String, $g: String, $sort: [MediaSort]) { Page(perPage: 40) { media(type: ANIME, search: $q, genre: $g, sort: $sort, isAdult: false) { \(mediaFields) } } }
        """, vars, as: PageData.self).Page.media
    }

    func media(id: Int) async throws -> Media {
        struct D: Decodable { var Media: Media }
        return try await query("query($id: Int) { Media(id: $id) { \(mediaFields) } }", ["id": id], as: D.self).Media
    }

    static func currentSeason(_ date: Date = .now) -> (String, Int) {
        let c = Calendar(identifier: .gregorian).dateComponents([.month, .year], from: date)
        let season = switch c.month ?? 1 {
        case 1...3: "WINTER"
        case 4...6: "SPRING"
        case 7...9: "SUMMER"
        default: "FALL"
        }
        return (season, c.year ?? 2026)
    }

    // MARK: Account

    func loadViewer() async {
        guard isLoggedIn else { viewer = nil; return }
        struct D: Decodable { var Viewer: Viewer }
        viewer = try? await query("""
        query { Viewer { id name about avatar { large } bannerImage siteUrl
          options { titleLanguage displayAdultContent profileColor } mediaListOptions { scoreFormat }
          statistics { anime { count episodesWatched minutesWatched meanScore } } } }
        """, as: D.self).Viewer
    }

    func watching() async throws -> [WatchingEntry] {
        guard let viewer else { return [] }
        struct D: Decodable {
            struct Collection: Decodable { var lists: [List] }
            struct List: Decodable { var entries: [Entry] }
            struct Entry: Decodable { var progress: Int?; var media: Media }
            var MediaListCollection: Collection
        }
        let d = try await query("""
        query($u: Int) { MediaListCollection(userId: $u, type: ANIME, status_in: [CURRENT, REPEATING], sort: UPDATED_TIME_DESC) { lists { entries { progress media { \(mediaFields) } } } } }
        """, ["u": viewer.id], as: D.self)
        return d.MediaListCollection.lists.flatMap(\.entries).map { WatchingEntry(media: $0.media, progress: $0.progress ?? 0) }
    }

    /// Records an episode as watched; completes the entry on the last episode.
    func setProgress(media: Media, episode: Int) async throws {
        guard isLoggedIn else { return }
        if let current = media.mediaListEntry?.progress, current >= episode { return }
        let status = (media.episodes.map { episode >= $0 } ?? false) ? "COMPLETED" : "CURRENT"
        struct D: Decodable { struct E: Decodable { var progress: Int? }; var SaveMediaListEntry: E }
        _ = try await query("""
        mutation($id: Int, $p: Int, $s: MediaListStatus) { SaveMediaListEntry(mediaId: $id, progress: $p, status: $s) { progress } }
        """, ["id": media.id, "p": episode, "s": status], as: D.self)
        listChanged()
    }

    /// The viewer's whole anime list, grouped by status (custom lists left out).
    func library() async throws -> [ListStatus: [LibraryEntry]] {
        guard let viewer else { return [:] }
        struct D: Decodable {
            struct Collection: Decodable { var lists: [List] }
            struct List: Decodable { var isCustomList: Bool?; var entries: [Entry] }
            struct Entry: Decodable {
                var id: Int?; var progress: Int?; var status: String?; var score: Double?
                var media: Media
            }
            var MediaListCollection: Collection
        }
        let d = try await query("""
        query($u: Int) { MediaListCollection(userId: $u, type: ANIME, sort: UPDATED_TIME_DESC) { lists { isCustomList entries { id progress status score(format: POINT_100) media { \(mediaFields) } } } } }
        """, ["u": viewer.id], as: D.self)
        var byStatus: [ListStatus: [LibraryEntry]] = [:]
        for list in d.MediaListCollection.lists where list.isCustomList != true {
            for e in list.entries {
                let entry = ListEntry(id: e.id, progress: e.progress, status: e.status, score: e.score)
                byStatus[ListStatus(rawValue: e.status ?? "") ?? .CURRENT, default: []].append(LibraryEntry(media: e.media, entry: entry))
            }
        }
        return byStatus
    }

    /// Adds or updates the viewer's entry for a media. `score` is out of 100, 0 for none.
    func saveEntry(media: Media, status: ListStatus, progress: Int, score: Double) async throws -> ListEntry {
        struct D: Decodable { var SaveMediaListEntry: ListEntry }
        let d = try await query("""
        mutation($id: Int, $s: MediaListStatus, $p: Int, $r: Int) { SaveMediaListEntry(mediaId: $id, status: $s, progress: $p, scoreRaw: $r) { \(entryFields) } }
        """, ["id": media.id, "s": status.rawValue, "p": progress, "r": Int(score.rounded())], as: D.self)
        listChanged()
        return d.SaveMediaListEntry
    }

    func deleteEntry(id: Int) async throws {
        struct D: Decodable { struct R: Decodable { var deleted: Bool? }; var DeleteMediaListEntry: R }
        _ = try await query("mutation($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }", ["id": id], as: D.self)
        listChanged()
    }

    private func listChanged() {
        listRevision += 1
        // Episode and anime counts change with the list.
        Task { await loadViewer() }
    }

    func login() async throws {
        let url = URL(string: "https://anilist.co/api/v2/oauth/authorize?client_id=\(clientID)&response_type=token")!
        let callback = try await WebAuth.start(url: url, scheme: "nami")
        // Implicit grant: the token comes back in the fragment.
        let fragment = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.fragment ?? ""
        let params = URLComponents(string: "?" + fragment)?.queryItems ?? []
        guard let access = params.first(where: { $0.name == "access_token" })?.value else {
            throw AniListError.api(t("connexion refusée", "login refused"))
        }
        token = access
        await loadViewer()
    }

    func logout() {
        token = ""
        viewer = nil
    }
}

/// Runs ASWebAuthenticationSession and returns the callback URL.
@MainActor
enum WebAuth {
    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    private static let anchor = Anchor()

    static func start(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? AniListError.api(t("annulé", "cancelled"))) }
            }
            session.presentationContextProvider = anchor
            session.start()
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Color {
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
