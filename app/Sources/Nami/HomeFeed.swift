import Foundation

/// Why an anime is in the home banner.
enum HeroReason { case resume, newEpisode, trending }

struct HeroItem: Identifiable, Hashable {
    var media: Media
    var episode: Int
    var reason: HeroReason
    var id: Int { media.id }
}

struct ContinueItem: Identifiable, Hashable {
    var media: Media
    var nextEpisode: Int
    /// The next episode is out.
    var available: Bool
    /// How far into the next episode you are, when started.
    var fraction: Double?
    var id: Int { media.id }
}

/// What the home shows, worked out once (same rules as the Android and Windows app).
/// Sections with nothing in them are empty (or nil) and the view hides them.
struct HomeFeed {
    var hero: [HeroItem] = []
    var continueWatching: [ContinueItem] = []
    var today: [AiringItem] = []
    var planning: [Media] = []
    /// Suggestions drawn from one anime you watch, without anime already in your list.
    var because: (source: Media, items: [Media])?
    var season: [Media] = []
    var trending: [Media] = []
    var topRated: [Media] = []
    var listIDs: Set<Int> = []

    static let heroSize = 5

    static func build(loggedIn: Bool, watching: [WatchingEntry], planning: [LibraryEntry], recommendations: [Media],
                      recommendationSource: Media?, today: [AiringItem], season: [Media], trending: [Media],
                      topRated: [Media], resumeFraction: (Int, Int) -> Double?, listIDs: Set<Int>) -> HomeFeed {
        let watched = loggedIn ? watching : []
        var hero: [HeroItem] = []
        var seen = Set<Int>()
        func add(_ m: Media, _ episode: Int, _ reason: HeroReason) {
            if hero.count < heroSize, seen.insert(m.id).inserted { hero.append(HeroItem(media: m, episode: episode, reason: reason)) }
        }
        for w in watched where resumeFraction(w.media.id, w.progress + 1) != nil { add(w.media, w.progress + 1, .resume) }
        for w in watched where w.hasNewEpisode { add(w.media, w.progress + 1, .newEpisode) }
        for m in trending { add(m, 1, .trending) }

        let suggestions = recommendations.filter { !listIDs.contains($0.id) }
        var feed = HomeFeed()
        feed.hero = hero
        feed.continueWatching = watched.map {
            ContinueItem(media: $0.media, nextEpisode: $0.progress + 1, available: $0.hasNewEpisode,
                         fraction: resumeFraction($0.media.id, $0.progress + 1))
        }
        feed.today = today
        feed.planning = loggedIn ? planning.map(\.media) : []
        if loggedIn, let source = recommendationSource, !suggestions.isEmpty { feed.because = (source, suggestions) }
        feed.season = season
        feed.trending = trending.filter { !seen.contains($0.id) }
        feed.topRated = topRated
        feed.listIDs = listIDs
        return feed
    }

    /// Fetches the sources at once. A source that fails keeps what `previous` had, so one failed
    /// request never blanks a row that was on screen. With `accountOnly`, only the rows that depend
    /// on your list are fetched again. Returns nil when every request failed and there was nothing before.
    @MainActor
    static func load(_ anilist: AniList, previous: HomeInputs?, accountOnly: Bool = false) async -> HomeInputs? {
        let loggedIn = anilist.isLoggedIn
        let before = previous ?? HomeInputs()
        let reusePublic = accountOnly && previous != nil
        async let watchingR: [WatchingEntry]? = loggedIn ? try? await anilist.watching() : []
        async let libraryR: [ListStatus: [LibraryEntry]]? = loggedIn ? try? await anilist.library() : [:]
        async let todayR = reusePublic ? before.today : try? await anilist.airingToday()
        async let seasonR = reusePublic ? before.season : try? await anilist.seasonal()
        async let trendingR = reusePublic ? before.trending : try? await anilist.trending()
        async let topR = reusePublic ? before.topRated : try? await anilist.topRated()
        let watching = await watchingR
        // Suggestions from the anime you watched most recently.
        let source = (watching ?? before.watching).first?.media
        let recs: [Media]? = if let source { try? await anilist.recommendations(for: source.id) } else { [] }
        let (library, today, season, trending, top) = await (libraryR, todayR, seasonR, trendingR, topR)
        let all: [Any?] = [watching, library, today, season, trending, top, recs]
        if previous == nil, all.allSatisfy({ $0 == nil }) { return nil }
        return HomeInputs(watching: watching ?? before.watching, library: library ?? before.library,
                          recommendations: recs ?? before.recommendations, today: today ?? before.today,
                          season: season ?? before.season, trending: trending ?? before.trending,
                          topRated: top ?? before.topRated)
    }
}

/// The home's data, kept outside the view: rebuilding the page (language change)
/// shows it at once instead of asking AniList for everything again.
@MainActor
final class HomeStore: ObservableObject {
    static let shared = HomeStore()
    @Published var feed: HomeFeed?
    @Published var loaded = false
    var inputs: HomeInputs?
    var loadedFor: Int?
    var revision = -1
}

/// What the home was built from, kept so a refresh can reuse what it does not fetch again.
struct HomeInputs {
    var watching: [WatchingEntry] = []
    var library: [ListStatus: [LibraryEntry]] = [:]
    var recommendations: [Media] = []
    var today: [AiringItem] = []
    var season: [Media] = []
    var trending: [Media] = []
    var topRated: [Media] = []

    func feed(loggedIn: Bool) -> HomeFeed {
        var ids = Set(library.values.flatMap { $0.map(\.media.id) })
        ids.formUnion(watching.map(\.media.id))
        return HomeFeed.build(loggedIn: loggedIn, watching: watching, planning: library[.PLANNING] ?? [],
                              recommendations: recommendations, recommendationSource: watching.first?.media,
                              today: today, season: season, trending: trending, topRated: topRated,
                              resumeFraction: { Playback.resumeFraction(media: $0, episode: $1) }, listIDs: ids)
    }
}
