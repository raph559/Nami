import SwiftUI

struct Track: Identifiable, Hashable {
    var id: Int32
    var name: String
}

/// What the player asks for when it closes on the way to the next episode.
struct PlayerExit {
    /// The countdown ran out: pick the recommended source without asking.
    var auto: Bool
    /// The torrent just played also holds the next episode (a season pack).
    var reuse: TorrentResult?
}

/// Resolves a source into a stream and plays it.
struct PlayerView: View {
    let media: Media
    let episode: Int
    let result: TorrentResult
    var onNext: ((PlayerExit) -> Void)?

    @EnvironmentObject private var center: PlayerCenter
    @StateObject private var model = PlayerModel()
    @State private var phase: Phase = .connecting
    @State private var torrent: Engine.Torrent?
    @State private var stats: Engine.Stats?
    @State private var speed: Double = 0
    @State private var controls = true
    @AppStorage("seekStep") private var seekStep = 10
    /// The signed seconds shown after a double tap; 0 when nothing is shown.
    @State private var flash = 0
    /// Goes up with each double tap, so each one turns the arrow.
    @State private var flashPulse = 0
    @State private var flashTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    @State private var scrub: Double?
    @State private var markedWatched = false
    // Resume
    @State private var lengthSeen = false
    @State private var lastSaved: Int32 = 0
    // AniSkip
    @State private var skips: [SkipInterval] = []
    @State private var skipped: Set<String> = []
    @State private var offered: SkipInterval?
    // Short message over the video, with an optional action ("Recommencer", "Revoir").
    @State private var notice: Notice?
    @State private var noticeTask: Task<Void, Never>?
    // Next episode
    @State private var countdown: Int?
    @State private var countdownCancelled = false
    @State private var countdownTask: Task<Void, Never>?

    struct Notice: Equatable {
        var text: String
        var action: String?
        var seekTo: Int32?
    }

    private var hasNext: Bool { onNext != nil && !media.isMovie && episode < media.availableEpisodes }

    enum Phase: Equatable {
        case connecting, chooseFile, playing
        case failed(String)
    }

    var body: some View {
        GeometryReader { geo in
            let mini = center.minimized
            ZStack(alignment: .bottom) {
                if !mini { Color.black.ignoresSafeArea() }

                // One video surface for both shapes, so mpv keeps playing while it shrinks.
                HStack(spacing: 12) {
                    Color.black
                        .frame(maxWidth: mini ? 112 : .infinity, maxHeight: mini ? 63 : .infinity)
                        .frame(width: mini ? 112 : nil, height: mini ? 63 : nil)
                        // mpv keeps drawing at the size it started with and MoltenVK shows that
                        // unscaled, so the surface stays full size and is only scaled down.
                        .overlay {
                            MPVSurface(model: model)
                                .frame(width: surfaceSize.width, height: surfaceSize.height)
                                .scaleEffect(mini ? 63 / surfaceSize.height : 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: mini ? 8 : 0))
                        .ignoresSafeArea(.all, edges: mini ? [] : .all)
                        .allowsHitTesting(false)
                    if mini { miniInfo }
                }
                .padding(mini ? 8 : 0)
                .background { if mini { miniBackground } }
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { if mini { expand() } }
                .padding(.horizontal, mini ? 12 : 0)
                // Just above the tab bar.
                .padding(.bottom, mini ? 62 : 0)
                .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                    guard mini else { return }
                    if v.translation.height < -30 { expand() } else if v.translation.height > 40 { center.close() }
                })

                if !mini {
                    ZStack {
                        // Catches the gestures over the video: tap for the controls, pinch to
                        // fill the screen, swipe down to shrink the player like YouTube.
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            // Double tap on a side jumps; the middle only shows the controls.
                            .onTapGesture(count: 2) { location in
                                seekFromDoubleTap(x: location.x, width: fullSize(geo).width)
                            }
                            .onTapGesture { toggleControls() }
                            .gesture(MagnifyGesture().onEnded { value in
                                if value.magnification > 1.05 { model.setFill(true, screen: fullSize(geo)) }
                                else if value.magnification < 0.95 { model.setFill(false, screen: fullSize(geo)) }
                            })
                            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
                                if v.translation.height > 110, abs(v.translation.width) < v.translation.height { minimize() }
                            })

                        if flash != 0 {
                            // A new view per direction, so changing side fades instead of sliding across.
                            SeekFeedback(seconds: flash, step: seekStep, pulse: flashPulse)
                                .id(flash > 0)
                                .transition(.opacity)
                        }

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
                            if controls { overlay(size: fullSize(geo)).transition(.opacity) }
                            floating
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .statusBarHidden(!center.minimized)
        .persistentSystemOverlays(center.minimized ? .automatic : .hidden)
        .task { await start() }
        .task(id: torrent?.hash) { await pollStats() }
        .onChange(of: model.timeMs) { _, ms in onTime(ms) }
        .onChange(of: model.lengthMs) { _, ms in onLength(ms) }
        .onChange(of: model.ended) { _, ended in
            guard ended else { return }
            checkWatched(force: true)
            if hasNext, Playback.autoNext { startCountdown() }
        }
        .onAppear { Orientation.set(.landscape) }
        .onDisappear {
            saveResume()
            countdownTask?.cancel()
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
            Playback.setResume(media: media, episode: episode, ms: nil)
            Task { try? await AniList.shared.setProgress(media: media, episode: episode) }
        }
    }

    private func onTime(_ ms: Int32) {
        checkWatched()
        if abs(ms - lastSaved) > 5000 { saveResume() }

        var inside: SkipInterval?
        for i in skips where i.contains(ms) {
            if i.kind == .ending, hasNext, Playback.autoNext, !countdownCancelled {
                startCountdown()
                return
            }
            let key = i.kind == .opening ? "op" : "ed"
            if Playback.autoSkip, !skipped.contains(key) {
                skipped.insert(key)
                model.seek(ms: i.endMs)
                show(Notice(text: i.kind == .opening ? t("Intro passée", "Opening skipped") : t("Générique passé", "Ending skipped"),
                            action: t("Revoir", "Watch it"), seekTo: i.startMs))
                return
            }
            inside = i
        }
        if inside != offered { offered = inside }
    }

    /// The first known length: AniSkip needs it, and so does resuming.
    private func onLength(_ ms: Int32) {
        guard !lengthSeen, ms > 0 else { return }
        lengthSeen = true
        if let at = Playback.resumeAt(media: media.id, episode: episode), at > 30_000, at < ms - 120_000 {
            model.seek(ms: at)
            lastSaved = at
            show(Notice(text: t("Reprise à \(Self.clock(at))", "Resumed at \(Self.clock(at))"), action: t("Recommencer", "Start over"), seekTo: 0))
        }
        if let malId = media.idMal {
            Task { skips = await AniSkip.fetch(malId: malId, episode: episode, lengthMs: ms) }
        }
    }

    private func saveResume() {
        guard !markedWatched, lengthSeen else { return }
        lastSaved = model.timeMs
        if model.timeMs > 30_000 { Playback.setResume(media: media, episode: episode, ms: model.timeMs, lengthMs: model.lengthMs) }
    }

    private func show(_ n: Notice) {
        noticeTask?.cancel()
        withAnimation { notice = n }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation { notice = nil }
        }
    }

    /// The floating skip button, or the fixed 85 s jump when AniSkip has nothing.
    private func skipNow() {
        if let i = offered {
            skipped.insert(i.kind == .opening ? "op" : "ed")
            model.seek(ms: i.endMs)
            offered = nil
        } else {
            model.jump(85)
        }
    }

    private func startCountdown() {
        guard countdown == nil, !countdownCancelled else { return }
        countdown = 10
        countdownTask = Task {
            while !Task.isCancelled, let c = countdown {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if c <= 1 { goNext(auto: true); return }
                countdown = c - 1
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdown = nil
        countdownCancelled = true
    }

    private func goNext(auto: Bool) {
        countdownTask?.cancel()
        let files = torrent?.files ?? []
        let packHasNext = files.filter(\.isVideo).count > 1 && Engine.pick(files, episode: episode + 1) != nil
        onNext?(PlayerExit(auto: auto, reuse: packHasNext ? result : nil))
    }

    // MARK: UI

    private var statsLine: String {
        guard let stats else { return t("Mise en mémoire tampon…", "Buffering…") }
        return t("\(stats.peers) pairs", "\(stats.peers) peers") + " · \(Self.bytes(speed))/s"
    }

    private var closeButton: some View {
        Button { center.close() } label: {
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
                    Button { model.setFill(!model.fill, screen: size); scheduleHide() } label: {
                        Image(systemName: model.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.title3).foregroundStyle(.white).frame(width: 44, height: 44)
                    }
                }
                Spacer()
                VStack(spacing: 6) {
                    HStack {
                        // Without AniSkip timings, a fixed jump over a typical 1:30 opening.
                        if !skips.contains(where: { $0.kind == .opening }) {
                            Button("+85 s") { model.jump(85); scheduleHide() }
                                .buttonStyle(.bordered).tint(.white)
                        }
                        Spacer()
                        // The countdown card offers the same action while it runs.
                        if hasNext, countdown == nil {
                            Button { goNext(auto: false) } label: { Label(t("Épisode suivant", "Next episode"), systemImage: "forward.end.fill") }
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
            // Like Netflix: wide side margins keep the controls clear of the rounded
            // corners, while the bar still spans most of the screen.
            .padding(.horizontal, 48).padding(.top, 20).padding(.bottom, 16)
            .ignoresSafeArea()

            // Centred on the screen itself, not between the top bar and the taller bottom block.
            HStack(spacing: 56) {
                roundButton("gobackward.\(seekStep)", size: 30) { model.jump(Int32(-seekStep)) }
                roundButton(model.isPlaying ? "pause.fill" : "play.fill", size: 44) { model.togglePause() }
                roundButton("goforward.\(seekStep)", size: 30) { model.jump(Int32(seekStep)) }
            }
            .ignoresSafeArea()
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
            Section(model.subDelay == 0 ? t("Décalage des sous-titres", "Subtitle delay")
                                        : t("Décalage : \(Self.signed(model.subDelay)) s", "Delay: \(Self.signed(model.subDelay)) s")) {
                Button { model.setSubDelay(model.subDelay + 0.25) } label: { Label(t("Plus tard (+0,25 s)", "Later (+0.25 s)"), systemImage: "plus") }
                Button { model.setSubDelay(model.subDelay - 0.25) } label: { Label(t("Plus tôt (−0,25 s)", "Earlier (−0.25 s)"), systemImage: "minus") }
                if model.subDelay != 0 { Button(t("Remettre à zéro", "Reset")) { model.setSubDelay(0) } }
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

    /// Several double taps in a row add up in the flash; changing direction starts again.
    private func seekFromDoubleTap(x: CGFloat, width: CGFloat) {
        guard case .playing = phase, x < width * 0.4 || x > width * 0.6 else { return toggleControls() }
        let seconds = x < width * 0.4 ? -seekStep : seekStep
        model.jump(Int32(seconds))
        flashPulse += 1
        withAnimation(.spring(duration: 0.3, bounce: 0.25)) {
            flash = flash * seconds > 0 ? flash + seconds : seconds
        }
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { flash = 0 }
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

    // MARK: Mini-player

    private func minimize() {
        model.setFill(false, screen: .zero)
        controls = false
        withAnimation(.spring(duration: 0.35)) { center.minimized = true }
        Orientation.set(.portrait)
    }

    private func expand() {
        withAnimation(.spring(duration: 0.35)) { center.minimized = false }
        Orientation.set(.landscape)
        controls = true
        scheduleHide()
    }

    private var miniInfo: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(media.title.display).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(miniStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { expand() }
            Button { model.togglePause() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.isPlaying ? t("Pause", "Pause") : t("Lecture", "Play"))
            Button { center.close() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(t("Fermer", "Close"))
        }
        .foregroundStyle(.primary)
    }

    private var miniStatus: String {
        let ep = media.isMovie ? nil : t("Épisode \(episode)", "Episode \(episode)")
        let state: String
        switch phase {
        case .connecting: state = t("Connexion…", "Connecting…")
        case .failed: state = t("Impossible de lire", "Cannot play")
        case .chooseFile: state = t("Choisis le fichier", "Pick the file")
        case .playing: state = "\(Self.clock(model.timeMs)) / \(Self.clock(model.lengthMs))"
        }
        return [ep, state].compactMap { $0 }.joined(separator: " · ")
    }

    /// Liquid Glass on iOS 26 and later, the regular material before.
    @ViewBuilder
    private var miniBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16).fill(.regularMaterial)
        }
    }

    // MARK: Floating

    /// Stays on screen while the controls are hidden: the skip button, a short
    /// notice and the next-episode countdown.
    private var floating: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                if let notice {
                    HStack(spacing: 10) {
                        Text(notice.text).foregroundStyle(.white)
                        if let action = notice.action {
                            Button(action) {
                                if let to = notice.seekTo { model.seek(ms: to) }
                                self.notice = nil
                            }
                            .foregroundStyle(.white).bold()
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Self.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
                if let countdown {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("Épisode \(episode + 1) dans \(countdown) s", "Episode \(episode + 1) in \(countdown) s"))
                            .font(.headline).foregroundStyle(.white)
                        HStack(spacing: 12) {
                            Button(t("Annuler", "Cancel")) { cancelCountdown() }.foregroundStyle(.white)
                            Button { goNext(auto: true) } label: { Label(t("Lire maintenant", "Play now"), systemImage: "forward.end.fill") }
                                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        }
                    }
                    .padding(14)
                    .background(Self.panel, in: RoundedRectangle(cornerRadius: 8))
                } else if let offered {
                    Button { skipNow() } label: {
                        Label(offered.kind == .opening ? t("Passer l'intro", "Skip opening") : t("Passer le générique", "Skip ending"),
                              systemImage: "forward.fill")
                            .font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                }
            }
        }
        // Same edges as the controls, above the progress bar while it shows.
        .padding(.horizontal, 48)
        .padding(.bottom, controls ? 108 : 24)
        .ignoresSafeArea()
    }

    /// Near-black panel: white text stays readable over any frame.
    private static let panel = Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x15 / 255).opacity(0.9)

    /// The landscape screen, whatever the phone's orientation right now.
    private var surfaceSize: CGSize {
        let screen = UIScreen.main.bounds.size
        return CGSize(width: max(screen.width, screen.height), height: min(screen.width, screen.height))
    }

    /// The whole screen, safe areas included: the video ignores them.
    private func fullSize(_ geo: GeometryProxy) -> CGSize {
        CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
               height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
    }

    static func signed(_ v: Double) -> String { (v > 0 ? "+" : "") + String(format: "%.2f", v) }

    static func clock(_ ms: Int32) -> String {
        let s = max(Int(ms) / 1000, 0)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func bytes(_ v: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file)
    }
}

/// The answer to a double tap: a circular arrow with the step inside gives a turn with each
/// jump and the total climbs under it. Nothing covers the picture.
private struct SeekFeedback: View {
    let seconds: Int
    let step: Int
    let pulse: Int

    @State private var turn = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var forward: Bool { seconds > 0 }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 6) {
                Image(systemName: "\(forward ? "goforward" : "gobackward").\(step)")
                    .font(.system(size: 52, weight: .light))
                    .rotationEffect(.degrees(turn))
                Text("\(forward ? "+" : "-")\(abs(seconds)) s")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(abs(seconds))))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 6)
            .position(x: geo.size.width * (forward ? 0.78 : 0.22), y: geo.size.height / 2)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: kick)
        .onChange(of: pulse) { kick() }
    }

    private func kick() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            turn = forward ? 35 : -35
        } completion: {
            withAnimation(.spring(duration: 0.4, bounce: 0.45)) { turn = 0 }
        }
    }
}
