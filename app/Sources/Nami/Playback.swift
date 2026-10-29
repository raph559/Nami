import Foundation

/// Subtitle track picked when an episode starts. `file` keeps the release's own default.
enum SubtitleLanguage: String, CaseIterable, Identifiable {
    case fr, en, file
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fr: "Français"
        case .en: "English"
        case .file: t("Du fichier", "From file")
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

    /// `lengthMs` lets screens draw how far into the episode you are; the anime
    /// also goes to the recent list, the "Continue" row of people not logged in.
    static func setResume(media: Media, episode: Int, ms: Int32?, lengthMs: Int32? = nil) {
        let d = UserDefaults.standard
        let key = "resume:\(media.id):\(episode)"
        if let ms {
            d.set(Int(ms), forKey: key)
            if let lengthMs, lengthMs > 0 { d.set(Int(lengthMs), forKey: "resumeLen:\(media.id):\(episode)") }
        } else {
            d.removeObject(forKey: key)
            d.removeObject(forKey: "resumeLen:\(media.id):\(episode)")
        }
        touchRecent(media, episode: ms == nil ? episode + 1 : episode)
    }

    /// How far into `episode` you stopped, from 0 to 1; nil if not started.
    static func resumeFraction(media: Int, episode: Int) -> Double? {
        let d = UserDefaults.standard
        guard let at = d.object(forKey: "resume:\(media):\(episode)") as? Int,
              let length = d.object(forKey: "resumeLen:\(media):\(episode)") as? Int, length > 0 else { return nil }
        return min(max(Double(at) / Double(length), 0), 1)
    }

    struct Recent: Codable {
        var media: Media
        var episode: Int
    }

    /// Anime played on this device, most recent first, with the episode to go on with.
    static var recent: [Recent] {
        guard let data = UserDefaults.standard.data(forKey: "recent"),
              let list = try? JSONDecoder().decode([Recent].self, from: data) else { return [] }
        return list
    }

    private static func touchRecent(_ media: Media, episode: Int) {
        var list = recent.filter { $0.media.id != media.id }
        list.insert(Recent(media: media, episode: episode), at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(list.prefix(20))), forKey: "recent")
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
