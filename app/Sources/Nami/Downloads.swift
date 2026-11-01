import Network
import SwiftUI

enum DownloadState: String, Codable { case queued, running, paused, failed, done }

/// One episode kept on the device. File names are relative to the downloads
/// folder, whose full path changes when the app is reinstalled.
struct DownloadEntry: Codable, Identifiable {
    var media: Media
    var episode: Int
    var state: DownloadState = .queued
    var link: String?
    var hash: String?
    var fileIndex: Int?
    var file: String?
    var done: Int64 = 0
    var total: Int64 = 0
    /// The quality asked for; nil when a source was picked by hand.
    var resolution: String?
    /// Live figures of a running download.
    var speed: Double?
    var peers: Int?
    /// Seconds since the last new data.
    var quiet: Int?

    /// Unknown until data comes in.
    var remaining: Int? {
        guard let speed, speed >= 1024, total > done else { return nil }
        return Int((Double(total - done) / speed).rounded(.up))
    }

    var id: String { "\(media.id)-\(episode)" }
    var fraction: Double { total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0 }

    /// What the download is doing, in words.
    @MainActor var label: String {
        switch state {
        case .running:
            let percent = Int(fraction * 100)
            var parts = [t("Téléchargement · \(percent) %", "Downloading · \(percent) %")]
            if (quiet ?? 0) >= 15 {
                parts.append(t("En attente de pairs", "Waiting for peers"))
            } else if let remaining {
                parts.append(t("\(Self.time(remaining)) restantes", "\(Self.time(remaining)) left"))
                parts.append("\(ByteCountFormatter.string(fromByteCount: Int64(speed ?? 0), countStyle: .file))/s")
            }
            return parts.joined(separator: " · ")
        case .queued:
            return Downloads.shared.heldForWifi ? t("En attente du Wi-Fi", "Waiting for Wi-Fi") : t("En attente", "Waiting")
        case .paused:
            let percent = Int(fraction * 100)
            return t("En pause · \(percent) %", "Paused · \(percent) %")
        case .failed: return t("Téléchargement bloqué", "Download stuck")
        case .done: return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }
    }

    /// "12 min", "1 h 05", "< 1 min".
    private static func time(_ seconds: Int) -> String {
        if seconds < 60 { return "< 1 min" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h \(String(format: "%02d", seconds % 3600 / 60))"
    }
}

/// A question put to the viewer before something costly happens.
struct DownloadQuestion: Identifiable {
    enum Kind {
        case start(episode: Int)
        case season(count: Int)
        case remove(DownloadEntry)
        case change(DownloadEntry)
    }

    var media: Media
    var kind: Kind

    var id: String { title }

    /// Questions answered with a quality rather than a yes.
    var asksQuality: Bool {
        if case .remove = kind { return false }
        return true
    }

    var title: String {
        switch kind {
        case .start(let episode): t("Télécharger l'épisode \(episode) ?", "Download episode \(episode)?")
        case .season(let count): t("Télécharger \(count) épisodes ?", "Download \(count) episodes?")
        case .change: t("Changer la qualité ?", "Change the quality?")
        case .remove(let e):
            e.state == .done ? t("Supprimer cet épisode ?", "Delete this episode?") : t("Annuler le téléchargement ?", "Cancel the download?")
        }
    }

    var message: String {
        switch kind {
        case .start:
            t("Nami prend la meilleure source dans cette qualité et garde cet épisode sur cet appareil. Laisse l'app ouverte pendant le téléchargement.",
              "Nami takes the best source in this quality and keeps this episode on this device. Keep the app open while it downloads.")
        case .season:
            t("Ils s'ajoutent à la file et se téléchargent l'un après l'autre. Laisse l'app ouverte pendant le téléchargement.",
              "They join the queue and download one after the other. Keep the app open while they download.")
        case .change:
            t("Ce qui a été téléchargé sera supprimé, puis Nami téléchargera cet épisode dans la nouvelle qualité.",
              "What was downloaded will be deleted, then Nami will download this episode in the new quality.")
        case .remove(let e):
            e.state == .done ? t("Il faudra le télécharger à nouveau pour le regarder hors ligne.", "You will have to download it again to watch it offline.")
                : t("Ce qui a déjà été récupéré sera perdu.", "What was already fetched will be lost.")
        }
    }

    var accept: String {
        guard case .remove(let e) = kind else { return "" }
        return e.state == .done ? t("Supprimer", "Delete") : t("Annuler le téléchargement", "Cancel download")
    }

    var refuse: String {
        guard case .remove(let e) = kind else { return t("Annuler", "Cancel") }
        return e.state == .done ? t("Garder", "Keep") : t("Continuer", "Keep going")
    }
}

extension View {
    /// Asks the store's pending question. Only the topmost screen may present it:
    /// a screen cannot show an alert over a sheet, and giving up would clear the
    /// question under the sheet's own alert.
    func downloadQuestions(_ store: Downloads, level: Int) -> some View {
        let shown = Binding(
            get: { store.question != nil && store.topLevel == level },
            set: { if !$0 { store.question = nil } })
        return alert(store.question?.title ?? "", isPresented: shown, presenting: store.question) { q in
            if q.asksQuality {
                ForEach(Downloads.qualities, id: \.self) { quality in
                    Button("\(quality)p") { store.confirm(q, quality: quality) }
                }
                if case .start(let episode) = q.kind {
                    Button(t("Choisir la source", "Choose source")) {
                        PlayerCenter.shared.openSources(q.media, episode: episode, forDownload: true)
                    }
                }
                Button(q.refuse, role: .cancel) {}
            } else {
                Button(q.accept, role: .destructive) { store.confirm(q) }
                Button(q.refuse, role: .cancel) {}
            }
        } message: { q in
            Text(q.message)
        }
    }
}

/// Episodes kept on the device and the queue that fetches them, one at a time.
/// The store is the source of truth: the engine knows nothing of it, and the
/// queue is rebuilt from here at launch.
@MainActor
final class Downloads: ObservableObject {
    static let shared = Downloads()

    /// A download with no new data for this many seconds gives up, so the queue moves on.
    private static let stallLimit = 600
    private static let sourceTries = 3
    private static let key = "downloads"

    @Published private(set) var entries: [DownloadEntry] = []
    /// The Downloads screen is open.
    @Published var screenShown = false
    @Published var question: DownloadQuestion?
    /// The download whose details are on screen.
    @Published var shown: DownloadEntry?
    /// Only mobile data is left.
    @Published private(set) var cellular = false

    /// The torrent the player has open: it cannot be moved or released yet.
    var playerHash: String?

    private var running: String?
    private var waitingForPlayer = Set<String>()
    private var releaseLater: [(hash: String, index: Int)] = []
    private var retrying = Set<String>()
    private var background: UIBackgroundTaskIdentifier = .invalid
    private let monitor = NWPathMonitor()

    let root: URL = {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("downloads")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    private var partial: URL { root.appendingPathComponent("partial") }

    var active: Bool { running != nil }

    /// The download to show at the bottom of every screen: the one running,
    /// or else the next in line, or else a paused one.
    var current: DownloadEntry? {
        for state in [DownloadState.running, .queued, .paused] {
            if let e = entries.first(where: { $0.state == state }) { return e }
        }
        return nil
    }

    /// How many more are in line behind `current`.
    var waiting: Int { entries.filter { $0.state == .queued && $0.id != current?.id }.count }

    func open() {
        shown = nil
        screenShown = true
    }

    /// Which screen is on top: 0 the app, 1 the Downloads screen, 2 the details.
    var topLevel: Int { shown != nil ? 2 : screenShown ? 1 : 0 }

    func askStart(_ media: Media, episode: Int) { question = DownloadQuestion(media: media, kind: .start(episode: episode)) }
    func askSeason(_ media: Media) { question = DownloadQuestion(media: media, kind: .season(count: missing(media).count)) }
    func askRemove(_ e: DownloadEntry) { question = DownloadQuestion(media: e.media, kind: .remove(e)) }
    func askChange(_ e: DownloadEntry) { question = DownloadQuestion(media: e.media, kind: .change(e)) }

    func confirm(_ q: DownloadQuestion, quality: String? = nil) {
        switch q.kind {
        case .start(let episode): start(q.media, episode: episode, resolution: quality)
        case .season: startSeason(q.media, resolution: quality)
        case .remove(let e):
            remove(e)
            shown = nil
        case .change(let e):
            remove(e)
            start(e.media, episode: e.episode, resolution: quality)
            shown = nil
        }
    }

    /// Qualities offered when downloading, the setting first.
    static var qualities: [String] {
        var list = [resolution]
        for q in ["1080", "720", "480"] where !list.contains(q) { list.append(q) }
        return list
    }

    private static var resolution: String {
        let d = UserDefaults.standard
        return d.string(forKey: "downloadResolution") ?? d.string(forKey: "resolution") ?? "1080"
    }

    /// Finished episodes on the device.
    var usedBytes: Int64 { entries.filter { $0.state == .done }.reduce(0) { $0 + $1.total } }

    var canPauseAll: Bool { entries.contains { $0.state == .running || $0.state == .queued } }
    var canResumeAll: Bool { entries.contains { $0.state == .paused } }
    func pauseAll() { for e in entries { pause(e) } }
    func resumeAll() { for e in entries { resume(e) } }

    /// Holding for Wi-Fi: the setting is on and only mobile data is there.
    var heldForWifi: Bool { cellular && UserDefaults.standard.bool(forKey: "downloadWifiOnly") }

    /// The Wi-Fi setting changed.
    func wifiSettingChanged() {
        objectWillChange.send()
        pump()
    }

    /// Applies the speed limit from the settings.
    func limitChanged() {
        let limit = UserDefaults.standard.integer(forKey: "downloadLimit")
        Task { try? await Engine.shared.limit(limit) }
    }

    /// Every aired episode that is not here or on its way.
    func missing(_ media: Media) -> [Int] {
        guard media.availableEpisodes > 0 else { return [] }
        return (1...media.availableEpisodes).filter { entry(media.id, $0) == nil }
    }

    func startSeason(_ media: Media, resolution: String?) {
        for n in missing(media) { start(media, episode: n, resolution: resolution) }
    }

    /// Waiting downloads, in the order they will start.
    var queue: [DownloadEntry] { entries.filter { $0.state == .queued } }

    /// Moves waiting downloads within `queue`; the others keep their places.
    func reorder(from: IndexSet, to: Int) {
        var line = queue
        let slots = entries.indices.filter { entries[$0].state == .queued }
        line.move(fromOffsets: from, toOffset: to)
        for (slot, e) in zip(slots, line) { entries[slot] = e }
        save()
    }

    /// Bytes per second from what was typed, in MB/s; 0 for no limit.
    static func parseLimit(_ text: String) -> Int {
        guard let mb = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), mb > 0 else { return 0 }
        return Int((mb * 1_000_000).rounded())
    }

    /// The limit as it is typed: 2.5, not 2500000.
    static func limitText(_ bytes: Int) -> String {
        guard bytes > 0 else { return "" }
        let mb = Double(bytes) / 1_000_000
        return mb == mb.rounded() ? String(Int(mb)) : String(mb)
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([DownloadEntry].self, from: data) {
            entries = saved
        }
        entries.removeAll { $0.state == .done && !FileManager.default.fileExists(atPath: url(of: $0).path) }
        for i in entries.indices where entries[i].state == .running { entries[i].state = .queued }
        sweepPartial()
        save()
        monitor.pathUpdateHandler = { path in
            let cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
            Task { @MainActor in Downloads.shared.networkChanged(cellular: cellular) }
        }
        monitor.start(queue: .global(qos: .utility))
        limitChanged()
        pump()
    }

    private func networkChanged(cellular: Bool) {
        self.cellular = cellular
        pump()
    }

    /// Partial data nothing needs any more.
    private func sweepPartial() {
        let wanted = Set(entries.compactMap(\.hash))
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: partial.path)) ?? []
        for dir in dirs where !wanted.contains(dir) && dir.count == 40 {
            try? FileManager.default.removeItem(at: partial.appendingPathComponent(dir))
        }
    }

    func entry(_ mediaID: Int, _ episode: Int) -> DownloadEntry? {
        entries.first { $0.media.id == mediaID && $0.episode == episode }
    }

    func url(of entry: DownloadEntry) -> URL { root.appendingPathComponent(entry.file ?? "") }
    func coverURL(_ mediaID: Int) -> URL { root.appendingPathComponent("\(mediaID).jpg") }

    /// Where a finished episode is, when it can be played.
    func localURL(_ mediaID: Int, _ episode: Int) -> URL? {
        guard let e = entry(mediaID, episode), e.state == .done else { return nil }
        return url(of: e)
    }

    /// With `link`, that source is used; otherwise the best one in `resolution`.
    func start(_ media: Media, episode: Int, resolution: String? = nil, link: String? = nil) {
        guard entry(media.id, episode) == nil else { return }
        let e = DownloadEntry(media: media, episode: episode, link: link, resolution: resolution)
        entries.append(e)
        if link != nil { retrying.insert(e.id) }
        save()
        if let cover = media.coverImage?.large, let url = URL(string: cover) {
            let dest = coverURL(media.id)
            Task.detached {
                if let (data, _) = try? await URLSession.shared.data(from: url) { try? data.write(to: dest) }
            }
        }
        pump()
    }

    /// What was fetched stays, and the queue moves on to the next episode.
    func pause(_ e: DownloadEntry) {
        guard e.state == .running || e.state == .queued else { return }
        update(e.id) { $0.state = .paused }
        waitingForPlayer.remove(e.id)
        if e.state == .running { pauseEngine(e.id) }
    }

    func resume(_ e: DownloadEntry) {
        guard e.state == .paused else { return }
        update(e.id) { $0.state = .queued }
        pump()
    }

    private func pauseEngine(_ id: String) {
        guard let e = current(id), let hash = e.hash, let index = e.fileIndex else { return }
        Task { try? await Engine.shared.pause(hash, index) }
    }

    /// Tries the same source first, so what was fetched is not lost.
    func retry(_ e: DownloadEntry) {
        guard e.state == .failed else { return }
        update(e.id) { $0.state = .queued }
        retrying.insert(e.id)
        pump()
    }

    /// Cancels a download or deletes a finished episode, and whatever it left.
    func remove(_ e: DownloadEntry) {
        entries.removeAll { $0.id == e.id }
        waitingForPlayer.remove(e.id)
        save()
        if e.state == .done {
            try? FileManager.default.removeItem(at: url(of: e))
        } else if let hash = e.hash, let index = e.fileIndex {
            if hash == playerHash {
                releaseLater.append((hash, index))
            } else {
                Task { await release(hash, index) }
            }
        }
        if !entries.contains(where: { $0.media.id == e.media.id }) {
            try? FileManager.default.removeItem(at: coverURL(e.media.id))
        }
    }

    /// The player opened or closed something: what waited for it can go on.
    func sessionChanged() {
        waitingForPlayer.removeAll()
        let later = releaseLater
        releaseLater = []
        Task {
            for (hash, index) in later { await release(hash, index) }
            pump()
        }
    }

    /// iOS gives a little time before suspending the app; the rest resumes on return.
    func enteredBackground() {
        guard active, background == .invalid else { return }
        background = UIApplication.shared.beginBackgroundTask { [weak self] in
            MainActor.assumeIsolated { self?.endBackground() }
        }
    }

    func endBackground() {
        guard background != .invalid else { return }
        UIApplication.shared.endBackgroundTask(background)
        background = .invalid
    }

    private func release(_ hash: String, _ index: Int) async {
        try? await Engine.shared.unkeep(hash, index)
        deletePartial(hash)
    }

    private func deletePartial(_ hash: String) {
        guard !entries.contains(where: { $0.hash == hash && $0.state != .done }) else { return }
        try? FileManager.default.removeItem(at: partial.appendingPathComponent(hash))
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
        KeepAwake.download = entries.contains { $0.state == .running }
    }

    private func update(_ id: String, _ change: (inout DownloadEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[i])
        save()
    }

    private func exists(_ id: String) -> Bool { entries.contains { $0.id == id } }
    private func current(_ id: String) -> DownloadEntry? { entries.first { $0.id == id } }

    private func pump() {
        guard running == nil, !heldForWifi else { return }
        guard let next = entries.first(where: { $0.state == .queued && !waitingForPlayer.contains($0.id) }) else { return }
        running = next.id
        Task {
            await run(next.id)
            running = nil
            pump()
        }
    }

    private func run(_ id: String) async {
        update(id) { $0.state = .running }
        let isRetry = retrying.remove(id) != nil
        do {
            let recovering = current(id)?.link != nil && !isRetry
            let attached = recovering ? try await reattach(id) : try await attach(id, stored: isRetry)
            // Paused while it was still looking for its torrent.
            if current(id)?.state == .paused { pauseEngine(id); return }
            guard attached else { update(id) { $0.state = .failed }; return }
            if await follow(id) { try await finish(id) }
        } catch let error as Engine.EngineError where error.busy {
            // The torrent is playing as a stream; this entry waits for the player to close.
            guard current(id)?.state != .paused else { return }
            update(id) { $0.state = .queued }
            waitingForPlayer.insert(id)
        } catch {
            if current(id)?.state != .paused { update(id) { $0.state = .failed } }
        }
    }

    /// After a restart, only the stored source: others would start from zero.
    /// With no network it fails, so it tries each minute up to the stall limit.
    private func reattach(_ id: String) async throws -> Bool {
        for _ in 0..<(Self.stallLimit / 60) {
            guard let e = current(id), let link = e.link else { return false }
            do {
                try await use(id, link)
                return true
            } catch let error as Engine.EngineError where error.busy {
                throw error
            } catch {
                try? await Task.sleep(for: .seconds(60))
            }
        }
        return false
    }

    private func attach(_ id: String, stored: Bool) async throws -> Bool {
        guard let e = current(id) else { return false }
        if stored, let link = e.link {
            do {
                try await use(id, link)
                return true
            } catch let error as Engine.EngineError where error.busy {
                throw error
            } catch {}
        }
        let resolution = e.resolution ?? Self.resolution
        let found = await SourceSearch.run(media: e.media, episode: e.episode, resolution: resolution)
        for release in ReleaseInfo.rank(found.results, resolution: resolution).prefix(Self.sourceTries) {
            do {
                try await use(id, release.result.link)
                return true
            } catch let error as Engine.EngineError where error.busy {
                throw error
            } catch {}
        }
        return false
    }

    private func use(_ id: String, _ link: String) async throws {
        guard let e = current(id) else { return }
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        let t = try await Engine.shared.addKept(link, dir: partial.path)
        guard let file = Engine.pick(t.files, episode: e.episode) else {
            await release(t.hash, -1)
            throw Engine.EngineError(message: "no file for this episode")
        }
        try await Engine.shared.keep(t.hash, file.index)
        let previous = e.hash
        let ext = (file.name as NSString).pathExtension
        update(id) {
            $0.link = link
            $0.hash = t.hash
            $0.fileIndex = file.index
            $0.total = file.length
            $0.file = "\(e.media.id)-\(e.episode)" + (ext.isEmpty ? "" : ".\(ext)")
        }
        if let previous, previous != t.hash { deletePartial(previous) }
    }

    /// Follows the file until it is complete; false if it stalled or was removed.
    /// Seconds are counted, not read from the clock: a suspended app must not stall.
    private func follow(_ id: String) async -> Bool {
        var quiet = 0
        var last: Int64 = -1
        while current(id)?.state == .running {
            try? await Task.sleep(for: .seconds(1))
            guard let e = current(id), e.state == .running, let hash = e.hash, let index = e.fileIndex else { return false }
            if heldForWifi {
                update(id) { $0.state = .queued }
                pauseEngine(id)
                return false
            }
            quiet += 1
            if let s = await Engine.shared.keepStats(hash, index) {
                guard exists(id) else { return false }
                if let i = entries.firstIndex(where: { $0.id == id }) {
                    // Smoothed, so the time left does not jump every second.
                    let now = last < 0 ? 0 : Double(max(s.done - last, 0))
                    entries[i].speed = (entries[i].speed ?? 0) == 0 ? now : entries[i].speed! * 0.8 + now * 0.2
                    entries[i].peers = s.peers
                    entries[i].done = s.done
                    entries[i].total = s.total
                }
                if s.total > 0, s.done == s.total { return true }
                if s.done > last {
                    last = s.done
                    quiet = 0
                }
                if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].quiet = quiet }
            }
            if quiet >= Self.stallLimit {
                update(id) { $0.state = .failed }
                return false
            }
        }
        return false
    }

    private func finish(_ id: String) async throws {
        while let e = current(id), e.hash == playerHash {
            try? await Task.sleep(for: .seconds(1))
        }
        guard let e = current(id), let hash = e.hash, let index = e.fileIndex else { return }
        try await Engine.shared.finish(hash, index, dest: url(of: e).path)
        update(id) { $0.state = .done }
        deletePartial(hash)
        endBackground()
    }
}

/// The screen stays on for the player and, on iPhone, for a running download.
@MainActor
enum KeepAwake {
    static var player = false { didSet { apply() } }
    static var download = false { didSet { apply() } }

    private static func apply() { UIApplication.shared.isIdleTimerDisabled = player || download }
}

/// Where a download stands and what can be done with it.
struct DownloadDetails: View {
    let id: String
    @ObservedObject private var store = Downloads.shared
    @EnvironmentObject private var center: PlayerCenter

    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    private func figures(_ e: DownloadEntry) -> String {
        var parts: [String] = []
        if e.total > 0 { parts.append("\(size(e.done)) / \(size(e.total))") }
        if e.state == .running {
            parts.append("\(size(Int64(e.speed ?? 0)))/s")
            parts.append(t("\(e.peers ?? 0) pairs", "\(e.peers ?? 0) peers"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if let e = store.entries.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.media.title.display).font(.title3.bold()).lineLimit(2)
                    Text("\(t("Épisode \(e.episode)", "Episode \(e.episode)")) · \(e.label)")
                        .font(.subheadline).foregroundStyle(Nami.textSecondary)
                }
                SmoothProgressLine(value: e.state == .done ? 1 : e.fraction)
                Text(figures(e)).font(.caption).foregroundStyle(Nami.textSecondary)
                HStack(spacing: 10) {
                    main(e)
                    Button(e.state == .done || e.state == .failed
                        ? t("Supprimer", "Delete") : t("Annuler", "Cancel"), role: .destructive) { store.askRemove(e) }
                        .buttonStyle(.bordered)
                }
                Button(t("Changer la qualité", "Change quality")) { store.askChange(e) }
                    .font(.footnote)
                if !store.screenShown {
                    Button(t("Tous les téléchargements", "All downloads")) { store.open() }
                        .font(.footnote)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.height(290)])
            .presentationBackground(Nami.sheet)
            .presentationDragIndicator(.visible)
            .foregroundStyle(Nami.text)
            .downloadQuestions(store, level: 2)
        }
    }

    @ViewBuilder
    private func main(_ e: DownloadEntry) -> some View {
        switch e.state {
        case .done:
            Button(t("Regarder", "Watch"), systemImage: "play.fill") {
                store.shown = nil
                center.openSources(e.media, episode: e.episode)
            }
            .buttonStyle(.borderedProminent).tint(Nami.text).foregroundStyle(Nami.ground)
        case .failed:
            Button(t("Réessayer", "Retry"), systemImage: "arrow.clockwise") { store.retry(e) }
                .buttonStyle(.borderedProminent).tint(Nami.text).foregroundStyle(Nami.ground)
        case .paused:
            Button(t("Reprendre", "Resume"), systemImage: "play.fill") { store.resume(e) }
                .buttonStyle(.borderedProminent).tint(Nami.text).foregroundStyle(Nami.ground)
        case .running, .queued:
            Button(t("Mettre en pause", "Pause"), systemImage: "pause.fill") { store.pause(e) }
                .buttonStyle(.borderedProminent).tint(Nami.text).foregroundStyle(Nami.ground)
        }
    }
}

/// Eases progress between two readings, a second apart, so it never jumps.
struct SmoothProgressLine: View {
    let value: Double
    var color: Color = Nami.text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ProgressLine(value: value, color: color)
            .animation(reduceMotion ? nil : .linear(duration: 1), value: value)
    }
}

/// The same around a button.
struct DownloadRing: View {
    let value: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: value).stroke(color, lineWidth: 2.5).rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: value)
        }
    }
}

/// Pauses what is going, resumes what is paused.
struct DownloadPauseButton: View {
    let entry: DownloadEntry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let paused = entry.state == .paused
        Button {
            if paused { Downloads.shared.resume(entry) } else { Downloads.shared.pause(entry) }
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: paused)
        }
        .accessibilityLabel(paused ? t("Reprendre", "Resume") : t("Mettre en pause", "Pause"))
    }
}

/// Above the tabs on every screen while something is downloading.
/// A tap opens the downloads.
struct DownloadBar: View {
    @ObservedObject private var store = Downloads.shared

    var body: some View {
        if let e = store.current {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { store.shown = e } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Nami.textSecondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(e.media.title.display) · \(t("Épisode \(e.episode)", "Episode \(e.episode)"))")
                                    .font(.footnote).lineLimit(1)
                                Text(detail(e)).font(.caption2).foregroundStyle(Nami.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    DownloadPauseButton(entry: e)
                }
                .padding(.leading, 12)
                SmoothProgressLine(value: e.fraction)
            }
            .foregroundStyle(Nami.text)
            .background(Nami.sheet, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func detail(_ e: DownloadEntry) -> String {
        let waiting = store.waiting
        return waiting > 0 ? "\(e.label) · \(t("\(waiting) en attente", "\(waiting) waiting"))" : e.label
    }
}

/// Leads to the Downloads screen, with what is in it.
struct DownloadsLink: View {
    @ObservedObject private var store = Downloads.shared

    private var detail: String {
        var parts: [String] = []
        let active = store.entries.filter { $0.state != .done }.count
        if active > 0 { parts.append(t("\(active) en cours", "\(active) active")) }
        if store.usedBytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: store.usedBytes, countStyle: .file)) }
        if store.entries.isEmpty { parts.append(t("Rien pour le moment", "Nothing yet")) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button { store.open() } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle").foregroundStyle(Nami.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t("Téléchargements", "Downloads"))
                    Text(detail).font(.caption).foregroundStyle(Nami.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Nami.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The download manager: what is going on, then what is kept, by anime.
struct DownloadsView: View {
    @ObservedObject private var store = Downloads.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: [DownloadEntry] { store.entries.filter { $0.state != .done && $0.state != .queued } }
    private var done: [DownloadEntry] { store.entries.filter { $0.state == .done } }

    private var animes: [Media] {
        var seen = Set<Int>()
        return done.map(\.media).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.entries.isEmpty {
                        Text(t("Sur la page d'un anime, la flèche à côté d'un épisode le garde sur cet appareil.",
                               "On an anime's page, the arrow beside an episode keeps it on this device."))
                            .foregroundStyle(Nami.textSecondary)
                    } else {
                        Text("\(t("\(store.entries.count) épisodes", "\(store.entries.count) episodes")) · \(ByteCountFormatter.string(fromByteCount: store.usedBytes, countStyle: .file))")
                            .font(.subheadline).foregroundStyle(Nami.textSecondary)
                    }
                    if store.active {
                        Text(t("Laisse l'app ouverte pendant le téléchargement.", "Keep the app open while it downloads."))
                            .font(.footnote).foregroundStyle(Nami.textSecondary)
                    }
                }
                .listRowBackground(Color.clear)
                if !active.isEmpty {
                    Section(t("En cours", "In progress")) {
                        ForEach(active) { DownloadRow(entry: $0) }
                    }
                }
                if !store.queue.isEmpty {
                    Section(t("File d'attente", "Queue")) {
                        ForEach(store.queue) { DownloadRow(entry: $0) }
                            .onMove { store.reorder(from: $0, to: $1) }
                    }
                }
                ForEach(animes) { media in
                    Section(media.title.display) {
                        ForEach(done.filter { $0.media.id == media.id }) { DownloadRow(entry: $0) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: store.entries.map { "\($0.id)-\($0.state)" })
            // Always on, so the drag handles of the queue always show.
            .environment(\.editMode, .constant(.active))
            .navigationTitle(t("Téléchargements", "Downloads"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("Fermer", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.canPauseAll {
                        Button(t("Tout en pause", "Pause all")) { store.pauseAll() }
                    } else if store.canResumeAll {
                        Button(t("Tout reprendre", "Resume all")) { store.resumeAll() }
                    }
                }
            }
        }
        .foregroundStyle(Nami.text)
        .sheet(item: $store.shown) { DownloadDetails(id: $0.id) }
        .downloadQuestions(store, level: 1)
    }
}

/// Everything downloaded, in one list. It needs no network, so the home shows
/// it when nothing else can load.
struct DownloadsSection: View {
    @ObservedObject private var store = Downloads.shared

    var body: some View {
        if !store.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.bold())
                ForEach(store.entries) { DownloadRow(entry: $0) }
            }
        }
    }

    private var title: String {
        let downloads = t("Téléchargements", "Downloads")
        return store.usedBytes > 0 ? "\(downloads) · \(ByteCountFormatter.string(fromByteCount: store.usedBytes, countStyle: .file))" : downloads
    }
}

private struct DownloadRow: View {
    let entry: DownloadEntry
    @ObservedObject private var store = Downloads.shared

    var body: some View {
        let e = entry
        HStack(spacing: 12) {
            Button {
                if e.state == .done {
                    store.screenShown = false
                    PlayerCenter.shared.openSources(e.media, episode: e.episode)
                } else {
                    store.shown = e
                }
            } label: {
                HStack(spacing: 12) {
                    cover(e).frame(width: 44, height: 62).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.media.title.display).font(.subheadline).lineLimit(1)
                        Text("\(t("Épisode \(e.episode)", "Episode \(e.episode)")) · \(e.label)")
                            .font(.caption).foregroundStyle(Nami.textSecondary).lineLimit(2)
                        if e.state == .running { SmoothProgressLine(value: e.fraction) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if e.state == .running || e.state == .queued || e.state == .paused {
                DownloadPauseButton(entry: e)
            }
            if e.state == .failed {
                Button { store.retry(e) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
                .accessibilityLabel(t("Réessayer", "Retry"))
            }
            Button { store.askRemove(e) } label: {
                Image(systemName: e.state == .done || e.state == .failed ? "trash" : "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel(e.state == .done || e.state == .failed
                ? t("Supprimer le téléchargement", "Delete download")
                : t("Annuler le téléchargement", "Cancel download"))
        }
        // In a list, a button without its own style would take the whole row.
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func cover(_ e: DownloadEntry) -> some View {
        if let image = UIImage(contentsOfFile: store.coverURL(e.media.id).path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            CoverImageView(url: e.media.coverImage?.large, corner: 6)
        }
    }
}
