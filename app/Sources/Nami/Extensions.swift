import Foundation
import WebKit

// Source extensions use the same format as Hayase's: a repository index.json
// lists manifests, each pointing at an ES module whose default export has
// single/batch/movie(query, options) methods returning torrent results.

enum JSONValue: Codable, Hashable {
    case bool(Bool), number(Double), string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        }
    }

    var any: Any {
        switch self {
        case .bool(let b): b
        case .number(let n): n
        case .string(let s): s
        }
    }
}

struct ExtensionOption: Codable, Hashable {
    var type: String
    var description: String?
    var `default`: JSONValue?
}

struct ExtensionManifest: Codable, Hashable {
    var manifestVersion: Int?
    var name: String
    var id: String
    var version: String?
    var type: String?
    var accuracy: String?
    var media: String?
    var languages: [String]?
    var icon: String?
    var update: String?
    var code: String
    var options: [String: ExtensionOption]?

    var isSupported: Bool { (type ?? "torrent") == "torrent" }
}

struct InstalledExtension: Codable, Identifiable, Hashable {
    var repo: String
    var manifest: ExtensionManifest
    var enabled: Bool
    var options: [String: JSONValue]

    var id: String { repo + "#" + manifest.id }

    var resolvedOptions: [String: Any] {
        var out: [String: Any] = [:]
        for (key, opt) in manifest.options ?? [:] {
            if let v = options[key] ?? opt.default { out[key] = v.any }
        }
        return out
    }
}

struct TorrentResult: Decodable, Identifiable, Hashable {
    var title: String
    var link: String
    var hash: String?
    var size: Double?
    var seeders: Int?
    var leechers: Int?
    var downloads: Int?
    var type: String?
    var date: String?
    var accuracy: String?
    var source: String?

    var id: String { (hash ?? link).lowercased() }
    var isBest: Bool { type == "best" }

    private enum CodingKeys: String, CodingKey {
        case title, link, hash, size, seeders, leechers, downloads, type, date, accuracy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)) ?? "Sans titre"
        link = try c.decode(String.self, forKey: .link)
        hash = try? c.decode(String.self, forKey: .hash)
        size = try? c.decode(Double.self, forKey: .size)
        seeders = (try? c.decode(Int.self, forKey: .seeders)) ?? (try? c.decode(Double.self, forKey: .seeders)).map(Int.init)
        leechers = (try? c.decode(Int.self, forKey: .leechers)) ?? (try? c.decode(Double.self, forKey: .leechers)).map(Int.init)
        downloads = try? c.decode(Int.self, forKey: .downloads)
        type = try? c.decode(String.self, forKey: .type)
        date = try? c.decode(String.self, forKey: .date)
        accuracy = try? c.decode(String.self, forKey: .accuracy)
    }
}

@MainActor
final class ExtensionStore: ObservableObject {
    static let shared = ExtensionStore()

    @Published private(set) var repos: [String] = []
    @Published private(set) var installed: [InstalledExtension] = []

    private let reposKey = "extensionRepos"
    private let installedKey = "installedExtensions"

    private init() {
        let d = UserDefaults.standard
        repos = d.stringArray(forKey: reposKey) ?? []
        if let data = d.data(forKey: installedKey),
           let list = try? JSONDecoder().decode([InstalledExtension].self, from: data) {
            installed = list
        }
    }

    private func save() {
        UserDefaults.standard.set(repos, forKey: reposKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(installed), forKey: installedKey)
    }

    var enabled: [InstalledExtension] { installed.filter { $0.enabled && $0.manifest.isSupported } }

    private func fetchIndex(_ repo: String) async throws -> [ExtensionManifest] {
        guard let url = URL(string: repo) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ExtensionManifest].self, from: data)
    }

    func addRepo(_ raw: String) async throws {
        let repo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifests = try await fetchIndex(repo)
        if !repos.contains(repo) { repos.append(repo) }
        merge(repo: repo, manifests: manifests)
    }

    func removeRepo(_ repo: String) {
        repos.removeAll { $0 == repo }
        installed.removeAll { $0.repo == repo }
        save()
    }

    /// Refreshes every repository so extensions pick up new versions.
    func refresh() async {
        for repo in repos {
            if let manifests = try? await fetchIndex(repo) { merge(repo: repo, manifests: manifests) }
        }
    }

    private func merge(repo: String, manifests: [ExtensionManifest]) {
        for m in manifests {
            if let i = installed.firstIndex(where: { $0.repo == repo && $0.manifest.id == m.id }) {
                installed[i].manifest = m
            } else {
                installed.append(InstalledExtension(repo: repo, manifest: m, enabled: m.isSupported, options: [:]))
            }
        }
        save()
    }

    func setEnabled(_ ext: InstalledExtension, _ on: Bool) {
        guard let i = installed.firstIndex(of: ext) else { return }
        installed[i].enabled = on
        save()
    }

    func setOption(_ ext: InstalledExtension, key: String, value: JSONValue) {
        guard let i = installed.firstIndex(where: { $0.id == ext.id }) else { return }
        installed[i].options[key] = value
        save()
    }
}

// MARK: - Runtime

/// Runs extension modules in a hidden WKWebView. `fetch` is routed through
/// URLSession so the extensions are not limited by CORS, like in Hayase.
@MainActor
final class ExtensionRuntime: NSObject, WKScriptMessageHandlerWithReply {
    static let shared = ExtensionRuntime()

    private var webView: WKWebView!
    private var ready: Task<Void, Never>?
    private var loaded: [String: String] = [:] // extension id -> code url

    private static let bootstrap = #"""
    (() => {
      const toB64 = (bytes) => { let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000)); return btoa(s) }
      const fromB64 = (s) => Uint8Array.from(atob(s), c => c.charCodeAt(0))
      const nativeFetch = async (input, init) => {
        const req = new Request(input, init)
        const headers = {}
        req.headers.forEach((v, k) => { headers[k] = v })
        const body = ['GET', 'HEAD'].includes(req.method) ? null : toB64(new Uint8Array(await req.arrayBuffer()))
        let r
        try {
          r = await window.webkit.messageHandlers.nfetch.postMessage({ url: req.url, method: req.method, headers, body })
        } catch (e) { throw new TypeError('Failed to fetch: ' + e) }
        const empty = r.status === 204 || r.status === 304 || req.method === 'HEAD'
        const resp = new Response(empty ? null : fromB64(r.body), { status: r.status, statusText: r.statusText || '', headers: r.headers })
        Object.defineProperty(resp, 'url', { value: r.url })
        return resp
      }
      window.fetch = nativeFetch
      const mods = {}
      window.__nami = {
        async load (id, code) {
          const url = URL.createObjectURL(new Blob([code], { type: 'text/javascript' }))
          try { mods[id] = (await import(url)).default } finally { URL.revokeObjectURL(url) }
          return true
        },
        async run (id, method, query, options, timeoutMs) {
          const mod = mods[id]
          if (!mod || typeof mod[method] !== 'function') return '[]'
          query.fetch = nativeFetch
          const timeout = new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), timeoutMs))
          const res = await Promise.race([mod[method](query, options), timeout])
          return JSON.stringify(Array.isArray(res) ? res : [])
        }
      }
    })()
    """#

    private override init() { super.init() }

    private func setUp() async {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.addScriptMessageHandler(self, contentWorld: .page, name: "nfetch")
        ucc.addUserScript(WKUserScript(source: Self.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = ucc
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        // Kept in the window (invisible) so WebKit does not throttle its timers.
        webView.alpha = 0
        webView.isUserInteractionEnabled = false
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.addSubview(webView)
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate
        await withCheckedContinuation { cont in
            delegate.done = { cont.resume() }
            webView.loadHTMLString("<!doctype html><title>nami</title>", baseURL: URL(string: "https://extensions.nami.local/"))
        }
        webView.navigationDelegate = nil
    }

    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        var done: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?(); done = nil }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { done?(); done = nil }
    }

    private func ensureReady() async {
        if ready == nil { ready = Task { await setUp() } }
        await ready?.value
    }

    private func ensureLoaded(_ ext: InstalledExtension) async throws {
        await ensureReady()
        let key = ext.id
        if loaded[key] == ext.manifest.code { return }
        guard let url = URL(string: ext.manifest.code) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadRevalidatingCacheData
        let (data, _) = try await URLSession.shared.data(for: req)
        let code = String(decoding: data, as: UTF8.self)
        _ = try await webView.callAsyncJavaScript("return await __nami.load(id, code)", arguments: ["id": key, "code": code], contentWorld: .page)
        loaded[key] = ext.manifest.code
    }

    func run(_ ext: InstalledExtension, method: String, query: [String: Any]) async throws -> [TorrentResult] {
        try await ensureLoaded(ext)
        let raw = try await webView.callAsyncJavaScript(
            "return await __nami.run(id, method, query, options, 25000)",
            arguments: ["id": ext.id, "method": method, "query": query, "options": ext.resolvedOptions],
            contentWorld: .page
        )
        guard let json = raw as? String else { return [] }
        var results = try JSONDecoder().decode([TorrentResult].self, from: Data(json.utf8))
        for i in results.indices { results[i].source = ext.manifest.name }
        return results
    }

    // fetch() bridge
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let urlString = body["url"] as? String, let url = URL(string: urlString) else {
            replyHandler(nil, "bad request")
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = body["method"] as? String ?? "GET"
        for (k, v) in body["headers"] as? [String: String] ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
        if let b64 = body["body"] as? String { req.httpBody = Data(base64Encoded: b64) }
        Task {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let http = resp as? HTTPURLResponse
                var headers: [String: String] = [:]
                for (k, v) in http?.allHeaderFields ?? [:] { headers["\(k)"] = "\(v)" }
                replyHandler([
                    "status": http?.statusCode ?? 200,
                    "statusText": HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 200),
                    "headers": headers,
                    "body": data.base64EncodedString(),
                    "url": resp.url?.absoluteString ?? urlString,
                ], nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }
        }
    }
}

// MARK: - Search

struct SourceSearch {
    struct Failure: Identifiable { var id: String { name }; var name: String; var message: String }

    var results: [TorrentResult] = []
    var failures: [Failure] = []

    @MainActor
    static func run(media: Media, episode: Int, resolution: String) async -> SourceSearch {
        let maps = await Mappings.load(anilistID: media.id)
        let ep = maps?.episode(episode)
        var titles = media.title.all
        titles.append(contentsOf: media.synonyms ?? [])
        let mediaJSON = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(media))) ?? [:]

        var query: [String: Any] = [
            "anilistId": media.id,
            "titles": titles.uniqued(),
            "episode": episode,
            "episodeCount": media.episodes ?? media.availableEpisodes,
            "resolution": resolution,
            "exclusions": [String](),
            "media": mediaJSON,
        ]
        if let v = media.idMal { query["malId"] = v }
        if let v = maps?.mappings?.anidb_id { query["anidbAid"] = v }
        if let v = ep?.anidbEid { query["anidbEid"] = v }
        if let v = maps?.mappings?.thetvdb_id { query["tvdbId"] = v }
        if let v = ep?.tvdbId { query["tvdbEId"] = v }
        if let v = maps?.mappings?.themoviedb_id?.value { query["tmdbId"] = v }
        if let v = maps?.mappings?.imdb_id { query["imdbId"] = v }

        var methods = [media.isMovie ? "movie" : "single"]
        if !media.isMovie, media.status == "FINISHED", (media.episodes ?? 0) > 1 { methods.append("batch") }

        // Plain tasks rather than a TaskGroup: task groups built with this
        // toolchain abort in the iOS 27.2 concurrency runtime.
        var tasks: [(String, Task<[TorrentResult], Error>)] = []
        for ext in ExtensionStore.shared.enabled {
            for method in methods {
                tasks.append((ext.manifest.name, Task { @MainActor in
                    try await ExtensionRuntime.shared.run(ext, method: method, query: query)
                }))
            }
        }
        var out = SourceSearch()
        for (name, task) in tasks {
            do { out.results.append(contentsOf: try await task.value) }
            catch { out.failures.append(Failure(name: name, message: error.localizedDescription)) }
        }
        var seen = Set<String>()
        out.results = out.results.filter { seen.insert($0.id).inserted }.sorted {
            if $0.isBest != $1.isBest { return $0.isBest }
            return ($0.seeders ?? 0) > ($1.seeders ?? 0)
        }
        return out
    }
}
