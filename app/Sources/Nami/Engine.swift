import Foundation
import NamiEngine

/// Client for the embedded Go torrent engine's local HTTP API.
@MainActor
final class Engine {
    static let shared = Engine()

    struct File: Decodable, Hashable {
        var index: Int
        var path: String
        var length: Int64
        var name: String { (path as NSString).lastPathComponent }
        var isVideo: Bool { ["mkv", "mp4", "avi", "webm", "m4v", "mov", "ts"].contains((path as NSString).pathExtension.lowercased()) }
    }

    struct Torrent: Decodable {
        var hash: String
        var name: String
        var files: [File]
    }

    struct Stats: Decodable {
        var peers: Int
        var seeders: Int
        var downloaded: Int64
        var total: Int64
        var progress: Double
    }

    struct EngineError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private(set) var port: Int32 = -1
    private var base: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private init() {}

    func start() {
        guard port < 0 else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("torrents")
        // Nothing is kept between launches.
        try? FileManager.default.removeItem(at: dir)
        port = dir.path.withCString { NamiStart(UnsafeMutablePointer(mutating: $0)) }
    }

    private func call(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 30) async throws -> Data {
        start()
        guard port > 0 else { throw EngineError(message: t("Le moteur torrent n'a pas démarré", "The torrent engine did not start")) }
        var req = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: timeout)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "HTTP \(code)"
            throw EngineError(message: msg)
        }
        return data
    }

    func add(_ link: String) async throws -> Torrent {
        try JSONDecoder().decode(Torrent.self, from: await call("add", method: "POST", body: ["uri": link], timeout: 100))
    }

    func stats(_ hash: String) async -> Stats? {
        guard let data = try? await call("stats/\(hash)", timeout: 5) else { return nil }
        return try? JSONDecoder().decode(Stats.self, from: data)
    }

    func drop(_ hash: String) async {
        _ = try? await call("drop/\(hash)", method: "POST")
    }

    func streamURL(hash: String, file: File) -> URL {
        base.appendingPathComponent("stream/\(hash)/\(file.index)")
    }

    /// Picks the file for an episode: the only video, or the one whose name
    /// carries the episode number in a batch.
    static func pick(_ files: [File], episode: Int) -> File? {
        let videos = files.filter(\.isVideo)
        if videos.count <= 1 { return videos.first ?? files.max { $0.length < $1.length } }
        let matches = videos.filter { episodeNumber(in: $0.name) == episode }
        if matches.count >= 1 { return matches.max { $0.length < $1.length } }
        return nil
    }

    static func episodeNumber(in name: String) -> Int? {
        var s = (name as NSString).deletingPathExtension
        // Drop bracketed tags, resolutions, years and codecs before looking.
        for pattern in [#"\[[^\]]*\]"#, #"\([^)]*\)"#, #"\b\d{3,4}[pP]\b"#, #"\b(19|20)\d{2}\b"#, #"(?i)\b(x|h)\.?26[45]\b"#, #"(?i)\bS\d{1,2}\b"#] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let patterns = [#"(?i)S\d{1,2}E(\d{1,4})"#, #"(?i)\bE[Pp]?\.?\s?(\d{1,4})\b"#, #"\s-\s(\d{1,4})(v\d)?\b"#, #"\b(\d{1,4})(v\d)?\b"#]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p),
               let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let range = Range(m.range(at: 1), in: s) {
                return Int(s[range])
            }
        }
        return nil
    }
}
