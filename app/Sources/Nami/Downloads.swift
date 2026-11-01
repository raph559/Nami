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
    /// Live figures of a running download.
    var speed: Int64?
    var peers: Int?

    var id: String { "\(media.id)-\(episode)" }
    var fraction: Double { total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0 }

    /// What the download is doing, in words.
    var label: String {
        switch state {
        case .running:
            let percent = Int(fraction * 100)
            return t("Téléchargement · \(percent) %", "Downloading · \(percent) %")
        case .queued: return t("En attente", "Waiting")
        case .paused:
            let percent = Int(fraction * 100)
            return t("En pause · \(percent) %", "Paused · \(percent) %")
        case .failed: return t("Téléchargement bloqué", "Download stuck")
        case .done: return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }
    }
}

/// A question put to the viewer before something costly happens.
struct DownloadQuestion: Identifiable {
    var media: Media
    var episode: Int
    /// What would be removed; nil when the question is about starting.
    var entry: DownloadEntry?

    var id: String { "\(media.id)-\(episode)" }
    private var done: Bool { entry?.state == .done }

    var title: String {
        if entry == nil { return t("Télécharger l'épisode \(episode) ?", "Download episode \(episode)?") }
        return done ? t("Supprimer cet épisode ?", "Delete this episode?") : t("Annuler le téléchargement ?", "Cancel the download?")
    }

    var message: String {
        if entry == nil {
            return t("Nami prend la meilleure source dans ta résolution et garde cet épisode sur cet appareil. Laisse l'app ouverte pendant le téléchargement.",
                     "Nami takes the best source for your resolution and keeps this episode on this device. Keep the app open while it downloads.")
        }
        return done ? t("Il faudra le télécharger à nouveau pour le regarder hors ligne.", "You will have to download it again to watch it offline.")
            : t("Ce qui a déjà été récupéré sera perdu.", "What was already fetched will be lost.")
    }

    var accept: String {
        if entry == nil { return t("Télécharger", "Download") }
        return done ? t("Supprimer", "Delete") : t("Annuler le téléchargement", "Cancel download")
    }

    var refuse: String {
        if entry == nil { return t("Annuler", "Cancel") }
        return done ? t("Garder", "Keep") : t("Continuer", "Keep going")
    }
}

extension View {
    /// Asks the store's pending question. Only the topmost screen may present it:
    /// the root cannot show an alert over the details sheet, and giving up would
    /// clear the question under the sheet's own alert.
    func downloadQuestions(_ store: Downloads, inSheet: Bool) -> some View {
        let shown = Binding(
            get: { store.question != nil && (store.shown != nil) == inSheet },
            set: { if !$0 { store.question = nil } })
        return alert(store.question?.title ?? "", isPresented: shown, presenting: store.question) { q in
            Button(q.accept, role: q.entry == nil ? nil : .destructive) { store.confirm(q) }
            Button(q.refuse, role: .cancel) {}
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
    /// Bumped to show the downloads section.
    @Published private(set) var opened = 0
    @Published var question: DownloadQuestion?
    /// The download whose details are on screen.
    @Published var shown: DownloadEntry?

    /// The torrent the player has open: it cannot be moved or released yet.
    var playerHash: String?

    private var running: String?
    private var waitingForPlayer = Set<String>()
    private var releaseLater: [(hash: String, index: Int)] = []
    private var retrying = Set<String>()
    private var background: UIBackgroundTaskIdentifier = .invalid

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

    func open() { opened += 1 }

    func askStart(_ media: Media, episode: Int) { question = DownloadQuestion(media: media, episode: episode) }
    func askRemove(_ e: DownloadEntry) { question = DownloadQuestion(media: e.media, episode: e.episode, entry: e) }

    func confirm(_ q: DownloadQuestion) {
        if let e = q.entry {
            remove(e)
            shown = nil
        } else {
            start(q.media, episode: q.episode)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([DownloadEntry].self, from: data) {
            entries = saved
        }
        entries.removeAll { $0.state == .done && !FileManager.default.fileExists(atPath: url(of: $0).path) }
        for i in entries.indices where entries[i].state == .running { entries[i].state = .queued }
        save()
        pump()
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

    func start(_ media: Media, episode: Int) {
        guard entry(media.id, episode) == nil else { return }
        entries.append(DownloadEntry(media: media, episode: episode))
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
        guard running == nil else { return }
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
        let resolution = UserDefaults.standard.string(forKey: "resolution") ?? "1080"
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
            quiet += 1
            if let s = await Engine.shared.keepStats(hash, index) {
                guard exists(id) else { return false }
                if let i = entries.firstIndex(where: { $0.id == id }) {
                    entries[i].speed = last < 0 ? 0 : max(s.done - last, 0)
                    entries[i].peers = s.peers
                    entries[i].done = s.done
                    entries[i].total = s.total
                }
                if s.total > 0, s.done == s.total { return true }
                if s.done > last {
                    last = s.done
                    quiet = 0
                }
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
            parts.append("\(size(e.speed ?? 0))/s")
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
                ProgressLine(value: e.state == .done ? 1 : e.fraction, color: Nami.text)
                Text(figures(e)).font(.caption).foregroundStyle(Nami.textSecondary)
                HStack(spacing: 10) {
                    main(e)
                    Button(e.state == .done || e.state == .failed
                        ? t("Supprimer", "Delete") : t("Annuler", "Cancel"), role: .destructive) { store.askRemove(e) }
                        .buttonStyle(.bordered)
                }
                Button(t("Tous les téléchargements", "All downloads")) {
                    store.shown = nil
                    store.open()
                }
                .font(.footnote)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.height(260)])
            .presentationBackground(Nami.sheet)
            .presentationDragIndicator(.visible)
            .foregroundStyle(Nami.text)
            .downloadQuestions(store, inSheet: true)
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

/// Pauses what is going, resumes what is paused.
struct DownloadPauseButton: View {
    let entry: DownloadEntry

    var body: some View {
        let paused = entry.state == .paused
        Button {
            if paused { Downloads.shared.resume(entry) } else { Downloads.shared.pause(entry) }
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
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
                ProgressLine(value: e.fraction, color: Nami.text)
            }
            .foregroundStyle(Nami.text)
            .background(Nami.sheet, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
        }
    }

    private func detail(_ e: DownloadEntry) -> String {
        let waiting = store.waiting
        return waiting > 0 ? "\(e.label) · \(t("\(waiting) en attente", "\(waiting) waiting"))" : e.label
    }
}

/// Everything kept on the device. It needs no network, so it shows above
/// whatever "Ma liste" can or cannot load.
struct DownloadsSection: View {
    @ObservedObject private var store = Downloads.shared
    @EnvironmentObject private var center: PlayerCenter

    var body: some View {
        if !store.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title3.bold())
                if store.active {
                    Text(t("Laisse l'app ouverte pendant le téléchargement.", "Keep the app open while it downloads."))
                        .font(.footnote).foregroundStyle(Nami.textSecondary)
                }
                ForEach(store.entries) { row($0) }
            }
        }
    }

    private var title: String {
        let total = store.entries.filter { $0.state == .done }.reduce(Int64(0)) { $0 + $1.total }
        let downloads = t("Téléchargements", "Downloads")
        return total > 0 ? "\(downloads) · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))" : downloads
    }

    private func row(_ e: DownloadEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                if e.state == .done { center.openSources(e.media, episode: e.episode) } else { store.shown = e }
            } label: {
                HStack(spacing: 12) {
                    cover(e).frame(width: 44, height: 62).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.media.title.display).font(.subheadline).lineLimit(1)
                        Text("\(t("Épisode \(e.episode)", "Episode \(e.episode)")) · \(e.label)")
                            .font(.caption).foregroundStyle(Nami.textSecondary)
                        if e.state == .running { ProgressLine(value: e.fraction, color: Nami.text) }
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
