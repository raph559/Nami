import Foundation

/// Keeps a copy of Nami's settings where a reinstall does not wipe them.
///
/// LiveContainer gives an app a new, empty data folder each time it is
/// installed again, so the repositories, extensions and AniList login would be
/// lost. Inside LiveContainer the copy goes to its shared Documents folder
/// (`Documents/Nami/settings.plist`), next to the apps; installed normally, it
/// stays in Application Support, which iOS keeps across updates anyway.
enum SettingsBackup {
    private static let keys = [
        "extensionRepos", "installedExtensions", "anilistToken",
        "appLanguage", "titleLanguage", "resolution",
        "autoSkip", "autoNext", "seekStep", "subtitleLanguage", "subtitleSize", "recent",
    ]

    private static var file: URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        // LiveContainer: <LiveContainer>/Documents/Data/Application/<uuid>
        let parts = home.pathComponents
        if parts.count > 3, parts[parts.count - 3] == "Data", parts[parts.count - 2] == "Application" {
            return home.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Nami/settings.plist")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nami/settings.plist")
    }

    /// Fills an empty data folder from the copy. Call before anything reads UserDefaults.
    static func restoreIfEmpty() {
        let d = UserDefaults.standard
        guard d.stringArray(forKey: "extensionRepos") == nil, d.string(forKey: "anilistToken") == nil,
              let data = try? Data(contentsOf: file),
              let saved = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        for key in keys { if let v = saved[key] { d.set(v, forKey: key) } }
    }

    private static var pending: DispatchWorkItem?

    /// Writes the copy whenever a setting changes, at most once a second.
    static func watch() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            pending?.cancel()
            let work = DispatchWorkItem { save() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
        save()
    }

    private static func save() {
        let d = UserDefaults.standard
        var out: [String: Any] = [:]
        for key in keys { if let v = d.object(forKey: key) { out[key] = v } }
        // Nothing worth keeping yet: do not replace a good copy with an empty one.
        guard out["extensionRepos"] != nil || out["anilistToken"] != nil,
              let data = try? PropertyListSerialization.data(fromPropertyList: out, format: .binary, options: 0) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
