import Foundation

/// Cross-database ids and episode metadata from api.ani.zip, which the
/// source extensions need (AniDB, TVDB, TMDB ids).
struct Mappings: Decodable {
    struct Ids: Decodable {
        var anidb_id: Int?
        var thetvdb_id: Int?
        var themoviedb_id: FlexString?
        var imdb_id: String?
        var mal_id: Int?
    }

    struct Episode: Decodable {
        var title: [String: String]?
        var image: String?
        var overview: String?
        var summary: String?
        var airDate: String?
        var runtime: Int?
        var length: Int?
        var anidbEid: Int?
        var tvdbId: Int?
        var episodeNumber: Int?
        var absoluteEpisodeNumber: Int?

        func displayTitle(_ lang: String = "fr") -> String? {
            title?[lang] ?? title?["en"] ?? title?["x-jat"]
        }
    }

    var mappings: Ids?
    var episodes: [String: Episode]?

    func episode(_ n: Int) -> Episode? { episodes?[String(n)] }

    private static var cache: [Int: Mappings] = [:]

    @MainActor
    static func load(anilistID: Int) async -> Mappings? {
        if let cached = cache[anilistID] { return cached }
        guard let url = URL(string: "https://api.ani.zip/mappings?anilist_id=\(anilistID)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let m = try? JSONDecoder().decode(Mappings.self, from: data) else { return nil }
        cache[anilistID] = m
        return m
    }
}

/// Decodes a JSON value that may be either a string or a number.
struct FlexString: Decodable, Hashable {
    var value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s } else { value = String(try c.decode(Int.self)) }
    }
}
