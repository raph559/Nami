import MobileVLCKit
import SwiftUI

struct Track: Identifiable, Hashable {
    var id: Int32
    var name: String
}

@MainActor
final class PlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()

    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var timeMs: Int32 = 0
    @Published var lengthMs: Int32 = 0
    @Published var audioTracks: [Track] = []
    @Published var subtitleTracks: [Track] = []
    @Published var audioTrack: Int32 = -1
    @Published var subtitleTrack: Int32 = -1
    @Published var fill = false
    @Published var ended = false

    override init() {
        super.init()
        player.delegate = self
    }

    func play(url: URL) {
        let media = VLCMedia(url: url)
        media.addOptions([
            "network-caching": 5000,
            "http-reconnect": true,
        ])
        player.media = media
        player.play()
    }

    func stop() {
        player.stop()
        player.media = nil
    }

    func togglePause() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func jump(_ seconds: Int32) {
        if seconds >= 0 { player.jumpForward(seconds) } else { player.jumpBackward(-seconds) }
    }

    func seek(fraction: Double) {
        player.position = Float(min(max(fraction, 0), 1))
    }

    func setAudio(_ id: Int32) { player.currentAudioTrackIndex = id; audioTrack = id }
    func setSubtitle(_ id: Int32) { player.currentVideoSubTitleIndex = id; subtitleTrack = id }

    func toggleFill(size: CGSize) {
        fill.toggle()
        if fill, size.width > 0, size.height > 0 {
            let w = Int(size.width.rounded()), h = Int(size.height.rounded())
            "\(w):\(h)".withCString { player.videoCropGeometry = UnsafeMutablePointer(mutating: $0) }
        } else {
            player.videoCropGeometry = nil
        }
    }

    private func refreshTracks() {
        func tracks(_ names: [Any]?, _ ids: [Any]?) -> [Track] {
            let n = names as? [String] ?? []
            let i = (ids as? [NSNumber] ?? []).map(\.int32Value)
            return zip(i, n).map { Track(id: $0, name: $1) }
        }
        audioTracks = tracks(player.audioTrackNames, player.audioTrackIndexes)
        subtitleTracks = tracks(player.videoSubTitlesNames, player.videoSubTitlesIndexes)
        audioTrack = player.currentAudioTrackIndex
        subtitleTrack = player.currentVideoSubTitleIndex
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            let state = player.state
            isPlaying = player.isPlaying
            isBuffering = state == .buffering || state == .opening
            if state == .ended { ended = true }
            if state == .playing || state == .esAdded { refreshTracks() }
            lengthMs = player.media?.length.intValue ?? 0
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            timeMs = player.time.intValue
            isBuffering = false
            isPlaying = player.isPlaying
            if lengthMs <= 0 { lengthMs = player.media?.length.intValue ?? 0 }
            if audioTracks.isEmpty { refreshTracks() }
        }
    }
}

struct VLCSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        player.drawable = v
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Resolves a source into a stream and plays it.
struct PlayerView: View {
    let media: Media
    let episode: Int
    let result: TorrentResult
    var onNext: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerModel()
    @State private var phase: Phase = .connecting
    @State private var torrent: Engine.Torrent?
    @State private var stats: Engine.Stats?
    @State private var speed: Double = 0
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrub: Double?
    @State private var markedWatched = false

    enum Phase: Equatable {
        case connecting, chooseFile, playing
        case failed(String)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                VLCSurface(player: model.player)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }

                switch phase {
                case .connecting:
                    status(icon: nil, text: t("Connexion aux pairs…", "Connecting to peers…"), detail: result.title)
                case .failed(let message):
                    status(icon: "exclamationmark.triangle", text: t("Impossible de lire", "Cannot play"), detail: message)
                case .chooseFile:
                    fileChooser
                case .playing:
                    if model.isBuffering || model.timeMs == 0 {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white).controlSize(.large)
                            Text(statsLine).font(.caption).foregroundStyle(.white.opacity(0.8))
                        }
                        .allowsHitTesting(false)
                    }
                    if controls { overlay(size: geo.size).transition(.opacity) }
                }

                if phase != .playing || !controls {
                    VStack {
                        HStack {
                            if phase != .playing { closeButton }
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding()
                }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .task(id: torrent?.hash) { await pollStats() }
        .onChange(of: model.timeMs) { _, _ in checkWatched() }
        .onChange(of: model.ended) { _, ended in if ended { checkWatched(force: true) } }
        .onAppear { Orientation.set(.landscape) }
        .onDisappear {
            model.stop()
            Orientation.set(.portrait)
            if let hash = torrent?.hash { Task { await Engine.shared.drop(hash) } }
        }
    }

    // MARK: Flow

    private func start() async {
        do {
            let t = try await Engine.shared.add(result.link)
            torrent = t
            if let file = Engine.pick(t.files, episode: episode) {
                play(file)
            } else {
                phase = .chooseFile
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func play(_ file: Engine.File) {
        guard let torrent else { return }
        phase = .playing
        model.play(url: Engine.shared.streamURL(hash: torrent.hash, file: file))
        scheduleHide()
    }

    private func pollStats() async {
        guard let hash = torrent?.hash else { return }
        var last: Int64 = 0
        while !Task.isCancelled {
            if let s = await Engine.shared.stats(hash) {
                if last > 0 { speed = max(Double(s.downloaded - last), 0) }
                last = s.downloaded
                stats = s
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func checkWatched(force: Bool = false) {
        guard !markedWatched, model.lengthMs > 0 else { return }
        if force || Double(model.timeMs) / Double(model.lengthMs) >= 0.85 {
            markedWatched = true
            Task { try? await AniList.shared.setProgress(media: media, episode: episode) }
        }
    }

    // MARK: UI

    private var statsLine: String {
        guard let stats else { return t("Mise en mémoire tampon…", "Buffering…") }
        return t("\(stats.peers) pairs", "\(stats.peers) peers") + " · \(Self.bytes(speed))/s"
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
        }
    }

    private func status(icon: String?, text: String, detail: String) -> some View {
        VStack(spacing: 14) {
            if let icon { Image(systemName: icon).font(.largeTitle).foregroundStyle(.yellow) } else { ProgressView().tint(.white).controlSize(.large) }
            Text(text).font(.headline).foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).lineLimit(3)
            if phase == .connecting, let stats { Text(t("\(stats.peers) pairs", "\(stats.peers) peers")).font(.caption2).foregroundStyle(.white.opacity(0.6)) }
        }
        .padding(32)
        .frame(maxWidth: 480)
    }

    private var fileChooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t("Choisis le fichier de l'épisode \(episode)", "Pick the file for episode \(episode)")).font(.headline).foregroundStyle(.white).padding()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach((torrent?.files ?? []).filter(\.isVideo), id: \.index) { file in
                        Button { play(file) } label: {
                            HStack {
                                Text(file.name).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer()
                                Text(Self.bytes(Double(file.length))).font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                        }
                        Divider().background(.white.opacity(0.2))
                    }
                }
            }
        }
        .frame(maxWidth: 600, maxHeight: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func overlay(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack(spacing: 14) {
                    closeButton
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.title.display).font(.headline).lineLimit(1)
                        Text(media.isMovie ? statsLine : t("Épisode \(episode)", "Episode \(episode)") + " · \(statsLine)").font(.caption).opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    Spacer()
                    trackMenu
                    Button { model.toggleFill(size: size); scheduleHide() } label: {
                        Image(systemName: model.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.title3).foregroundStyle(.white).frame(width: 44, height: 44)
                    }
                }
                Spacer()
                HStack(spacing: 56) {
                    roundButton("gobackward.10", size: 30) { model.jump(-10) }
                    roundButton(model.isPlaying ? "pause.fill" : "play.fill", size: 44) { model.togglePause() }
                    roundButton("goforward.10", size: 30) { model.jump(10) }
                }
                Spacer()
                VStack(spacing: 6) {
                    HStack {
                        Button("+85 s") { model.jump(85); scheduleHide() }
                            .buttonStyle(.bordered).tint(.white)
                        Spacer()
                        if let onNext, !media.isMovie, episode < media.availableEpisodes {
                            Button { dismiss(); onNext() } label: { Label(t("Épisode suivant", "Next episode"), systemImage: "forward.end.fill") }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    Slider(value: Binding(
                        get: { scrub ?? (model.lengthMs > 0 ? Double(model.timeMs) / Double(model.lengthMs) : 0) },
                        set: { scrub = $0 }
                    ), onEditingChanged: { editing in
                        if !editing, let s = scrub { model.seek(fraction: s); scrub = nil }
                        scheduleHide()
                    })
                    .tint(media.accent)
                    HStack {
                        Text(Self.clock(scrub.map { Int32($0 * Double(model.lengthMs)) } ?? model.timeMs))
                        Spacer()
                        Text(Self.clock(model.lengthMs))
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
    }

    private var trackMenu: some View {
        Menu {
            Section(t("Sous-titres", "Subtitles")) {
                ForEach(model.subtitleTracks) { t in
                    Button { model.setSubtitle(t.id) } label: {
                        if t.id == model.subtitleTrack { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                    }
                }
            }
            Section("Audio") {
                ForEach(model.audioTracks) { t in
                    Button { model.setAudio(t.id) } label: {
                        if t.id == model.audioTrack { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble").font(.title3).foregroundStyle(.white).frame(width: 44, height: 44)
        }
    }

    private func roundButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button { action(); scheduleHide() } label: {
            Image(systemName: icon).font(.system(size: size, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size * 1.8, height: size * 1.8)
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controls.toggle() }
        if controls { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, model.isPlaying, scrub == nil else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controls = false }
        }
    }

    static func clock(_ ms: Int32) -> String {
        let s = max(Int(ms) / 1000, 0)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func bytes(_ v: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file)
    }
}
