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

    /// Fetches every section at once; a source that fails only empties its own section.
    /// Returns nil when every source failed.
    @MainActor
    static func load(_ anilist: AniList) async -> HomeFeed? {
        let loggedIn = anilist.isLoggedIn
        async let watchingR: [WatchingEntry]? = loggedIn ? try? await anilist.watching() : []
        async let libraryR: [ListStatus: [LibraryEntry]]? = loggedIn ? try? await anilist.library() : [:]
        async let todayR = try? await anilist.airingToday()
        async let seasonR = try? await anilist.seasonal()
        async let trendingR = try? await anilist.trending()
        async let topR = try? await anilist.topRated()
        let watching = await watchingR
        // Suggestions from the anime you watched most recently.
        let source = watching?.first?.media
        let recs: [Media]? = if let source { try? await anilist.recommendations(for: source.id) } else { [] }
        let (library, today, season, trending, top) = await (libraryR, todayR, seasonR, trendingR, topR)
        // Only the requests actually made count (logged out, the account ones are skipped).
        var results: [Any?] = [today, season, trending, top]
        if loggedIn { results += [watching, library] }
        if source != nil { results.append(recs) }
        if results.allSatisfy({ $0 == nil }) { return nil }
        var ids = Set((library ?? [:]).values.flatMap { $0.map(\.media.id) })
        ids.formUnion((watching ?? []).map(\.media.id))
        return build(loggedIn: loggedIn, watching: watching ?? [], planning: library?[.PLANNING] ?? [],
                     recommendations: recs ?? [], recommendationSource: source, today: today ?? [], season: season ?? [],
                     trending: trending ?? [], topRated: top ?? [],
                     resumeFraction: { Playback.resumeFraction(media: $0, episode: $1) }, listIDs: ids)
    }
}
