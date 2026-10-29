import Foundation

enum SkipKind { case opening, ending }

/// One stretch of an episode to skip, from AniSkip (crowd-sourced timings).
struct SkipInterval: Equatable {
    var kind: SkipKind
    var startMs: Int32
    var endMs: Int32

    func contains(_ ms: Int32) -> Bool { ms >= startMs && ms < endMs }
}

enum AniSkip {
    /// Timings for one episode of the anime with MyAnimeList id `malId`.
    /// `lengthMs` is the file's duration: AniSkip keeps the timings submitted for
    /// a file of about that length, so another release's cut does not shift them.
    /// Returns an empty list when nothing is known or the service is unreachable.
    static func fetch(malId: Int, episode: Int, lengthMs: Int32) async -> [SkipInterval] {
        let length = String(format: "%.3f", Double(lengthMs) / 1000)
        guard let url = URL(string: "https://api.aniskip.com/v2/skip-times/\(malId)/\(episode)?types=op&types=ed&episodeLength=\(length)") else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [SkipInterval] {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              body["found"] as? Bool == true, let results = body["results"] as? [[String: Any]] else { return [] }
        var out: [SkipInterval] = []
        for r in results {
            let kind: SkipKind
            switch r["skipType"] as? String {
            case "op": kind = .opening
            case "ed": kind = .ending
            default: continue
            }
            // One interval per kind: AniSkip may return several votes for the same part.
            guard !out.contains(where: { $0.kind == kind }),
                  let interval = r["interval"] as? [String: Any],
                  let start = interval["startTime"] as? Double, let end = interval["endTime"] as? Double else { continue }
            out.append(SkipInterval(kind: kind, startMs: Int32(start * 1000), endMs: Int32(end * 1000)))
        }
        return out
    }
}
