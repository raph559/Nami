import Foundation

/// Subtitle track picked when an episode starts. `file` keeps the release's own default.
enum SubtitleLanguage: String, CaseIterable, Identifiable {
    case fr, en, file
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fr: "Français"
        case .en: "English"
        case .file: t("Celle du fichier", "The file's default")
        }
    }

    /// Words found in track names for this language: a title ("French") or the
    /// language code the player adds in brackets ("[fre]").
    var keys: [String] {
        switch self {
        case .fr: ["french", "français", "francais", "[fre]", "[fra]", "[fr]"]
        case .en: ["english", "[eng]", "[en]"]
        case .file: []
        }
    }
}

/// Playback preferences shared by the player and Settings (same keys as @AppStorage).
enum Playback {
    static var autoSkip: Bool { UserDefaults.standard.object(forKey: "autoSkip") as? Bool ?? true }
    static var autoNext: Bool { UserDefaults.standard.object(forKey: "autoNext") as? Bool ?? true }
    static var subtitleLanguage: SubtitleLanguage {
        SubtitleLanguage(rawValue: UserDefaults.standard.string(forKey: "subtitleLanguage") ?? "") ?? .fr
    }
    /// Percent, passed to mpv as sub-scale.
    static var subtitleSize: Int { UserDefaults.standard.object(forKey: "subtitleSize") as? Int ?? 100 }

    /// Where an episode was left, in milliseconds; nil once it was watched to the end.
    static func resumeAt(media: Int, episode: Int) -> Int32? {
        (UserDefaults.standard.object(forKey: "resume:\(media):\(episode)") as? Int).map { Int32($0) }
    }

    static func setResume(media: Int, episode: Int, ms: Int32?) {
        let key = "resume:\(media):\(episode)"
        if let ms { UserDefaults.standard.set(Int(ms), forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

extension ExtensionStore {
    /// Short name for a repository: host and path without `index.json`, so
    /// `…/dub/index.json` and `…/multi/index.json` on one host read apart.
    static func repoLabel(_ repo: String) -> String {
        guard let url = URL(string: repo), let host = url.host(), !host.isEmpty else { return repo }
        var path = url.path()
        if path.hasSuffix("index.json") { path.removeLast("index.json".count) }
        while path.hasSuffix("/") { path.removeLast() }
        return host + path
    }

    /// "2 of 3 on: NekoBT, AnimeTosho, …" so each repository says what it brings.
    func summary(_ repo: String) -> String {
        let exts = installed.filter { $0.repo == repo }
        if exts.isEmpty { return t("Aucune extension", "No extensions") }
        let on = exts.filter(\.enabled).count
        let names = exts.map(\.manifest.name).joined(separator: ", ")
        return t("\(on) sur \(exts.count) activées : \(names)", "\(on) of \(exts.count) on: \(names)")
    }
}
