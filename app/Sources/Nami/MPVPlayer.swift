import Libmpv
import SwiftUI
import UIKit

/// The video engine: libmpv (from MPVKit), the same player as on Android and
/// Windows. mpv draws subtitles apart from the picture, so filling the screen
/// (panscan) crops the video without enlarging them, which VLC could not do.
@MainActor
final class PlayerModel: ObservableObject {
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
    @Published var subDelay: Double = 0

    /// The view mpv renders into; created first because mpv needs it at start.
    let view = MPVVideoView()
    private var mpv: OpaquePointer?
    private var subtitleChosen = false

    init() {
        guard let handle = mpv_create() else { return }
        mpv = handle
        var layer = view.metalLayer
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &layer)
        for (key, value) in [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            ("ytdl", "no"),
            ("keep-open", "yes"),
            ("cache", "yes"),
            ("demuxer-max-bytes", "64MiB"),
            ("network-timeout", "90"),
            // Subtitles keep their size on screen and stay inside it when the video
            // is cropped to fill the screen.
            ("sub-scale-with-window", "yes"),
            ("sub-ass-scale-with-window", "yes"),
            ("sub-use-margins", "yes"),
            ("sub-ass-force-margins", "yes"),
            ("sub-scale", String(Double(Playback.subtitleSize) / 100)),
        ] {
            mpv_set_option_string(handle, key, value)
        }
        guard mpv_initialize(handle) >= 0 else { return }
        for (name, format) in [
            ("time-pos", MPV_FORMAT_DOUBLE), ("duration", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG), ("paused-for-cache", MPV_FORMAT_FLAG),
            ("seeking", MPV_FORMAT_FLAG), ("eof-reached", MPV_FORMAT_FLAG),
            ("track-list/count", MPV_FORMAT_INT64),
            ("aid", MPV_FORMAT_STRING), ("sid", MPV_FORMAT_STRING),
        ] {
            mpv_observe_property(handle, 0, name, format)
        }
        // mpv calls this from its own thread; events are read on the main thread.
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let model = Unmanaged<PlayerModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { model.readEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: Commands

    private func command(_ args: [String]) {
        guard let mpv else { return }
        var cargs: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        cargs.append(nil)
        defer { for p in cargs where p != nil { free(UnsafeMutablePointer(mutating: p)) } }
        _ = cargs.withUnsafeMutableBufferPointer { mpv_command(mpv, $0.baseAddress) }
    }

    private func set(_ name: String, _ value: String) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, name, value)
    }

    private func get(_ name: String) -> String? {
        guard let mpv, let raw = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    func play(url: URL) {
        command(["loadfile", url.absoluteString])
        set("pause", "no")
    }

    func stop() {
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        // Tearing down mpv waits for its threads; keep that off the main thread.
        let address = Int(bitPattern: UnsafeRawPointer(handle))
        DispatchQueue.global(qos: .userInitiated).async {
            guard let raw = UnsafeRawPointer(bitPattern: address) else { return }
            mpv_terminate_destroy(OpaquePointer(raw))
        }
    }

    func togglePause() { set("pause", isPlaying ? "yes" : "no") }

    func jump(_ seconds: Int32) { command(["seek", String(seconds), "relative"]) }

    func seek(fraction: Double) { command(["seek", String(min(max(fraction, 0), 1) * 100), "absolute-percent"]) }

    func seek(ms: Int32) { command(["seek", String(Double(max(ms, 0)) / 1000), "absolute"]) }

    /// Positive when subtitles come too early.
    func setSubDelay(_ seconds: Double) {
        subDelay = (seconds * 100).rounded() / 100
        set("sub-delay", String(subDelay))
    }

    func setAudio(_ id: Int32) { set("aid", String(id)); audioTrack = id }

    func setSubtitle(_ id: Int32) { set("sid", id < 0 ? "no" : String(id)); subtitleTrack = id }

    /// Fills the screen by cropping the video to its shape (mpv's panscan).
    /// Subtitles are drawn on top at screen size, so they do not grow.
    func setFill(_ on: Bool, screen: CGSize) {
        fill = on
        set("panscan", on ? "1.0" : "0.0")
    }

    // MARK: Events

    private func readEvents() {
        while let mpv, let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE {
            switch event.pointee.event_id {
            case MPV_EVENT_PROPERTY_CHANGE:
                if let data = event.pointee.data {
                    changed(data.assumingMemoryBound(to: mpv_event_property.self).pointee)
                }
            case MPV_EVENT_FILE_LOADED:
                refreshTracks()
            case MPV_EVENT_SHUTDOWN:
                return
            default:
                break
            }
        }
    }

    private func changed(_ p: mpv_event_property) {
        let name = String(cString: p.name)
        func double() -> Double? { p.format == MPV_FORMAT_DOUBLE ? p.data?.assumingMemoryBound(to: Double.self).pointee : nil }
        func flag() -> Bool? { p.format == MPV_FORMAT_FLAG ? p.data.map { $0.assumingMemoryBound(to: Int32.self).pointee != 0 } : nil }
        switch name {
        case "time-pos":
            if let v = double() {
                timeMs = Int32(v * 1000)
                if v > 0 { isBuffering = false }
            }
        case "duration":
            if let v = double() { lengthMs = Int32(v * 1000) }
        case "pause":
            if let v = flag() { isPlaying = !v }
        case "paused-for-cache", "seeking":
            if let v = flag() { isBuffering = v }
        case "eof-reached":
            if flag() == true { ended = true }
        case "track-list/count":
            refreshTracks()
        case "aid":
            audioTrack = Int32(get("aid") ?? "") ?? -1
        case "sid":
            subtitleTrack = Int32(get("sid") ?? "") ?? -1
        default:
            break
        }
    }

    private func refreshTracks() {
        let count = Int(get("track-list/count") ?? "") ?? 0
        var audio: [Track] = [], subs: [Track] = [Track(id: -1, name: t("Aucun", "None"))]
        for i in 0..<count {
            guard let type = get("track-list/\(i)/type"), let id = Int32(get("track-list/\(i)/id") ?? "") else { continue }
            let title = get("track-list/\(i)/title")
            let lang = get("track-list/\(i)/lang")
            var name = title ?? (type == "sub" ? t("Piste \(id)", "Track \(id)") : "Audio \(id)")
            if let lang { name += " [\(lang)]" }
            if type == "audio" { audio.append(Track(id: id, name: name)) }
            if type == "sub" { subs.append(Track(id: id, name: name)) }
        }
        audioTracks = audio
        subtitleTracks = subs
        audioTrack = Int32(get("aid") ?? "") ?? -1
        subtitleTrack = Int32(get("sid") ?? "") ?? -1
        chooseSubtitle()
    }

    /// Picks the subtitle track in the user's language once the file's tracks are known.
    /// "Signs & Songs" tracks only translate on-screen text, so a full dialogue track comes first.
    private func chooseSubtitle() {
        let real = subtitleTracks.filter { $0.id >= 0 }
        guard !subtitleChosen, !real.isEmpty else { return }
        subtitleChosen = true
        let keys = Playback.subtitleLanguage.keys
        guard !keys.isEmpty else { return }
        let matches = real.filter { t in keys.contains { t.name.lowercased().contains($0) } }
        let partial = { (t: Track) in t.name.range(of: "sign|song|forced", options: [.regularExpression, .caseInsensitive]) != nil }
        if let pick = matches.first(where: { !partial($0) }) ?? matches.first { setSubtitle(pick.id) }
    }
}

/// Metal-backed view mpv renders into through MoltenVK.
final class MPVVideoView: UIView {
    override class var layerClass: AnyClass { MPVMetalLayer.self }
    var metalLayer: MPVMetalLayer { layer as! MPVMetalLayer }

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        contentScaleFactor = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        // Touches go to the SwiftUI layer above.
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// MoltenVK sets the drawable to 1×1 to finish a frame while resizing; ignoring
/// that avoids a black flash (same workaround as MPVKit's example).
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set { if newValue.width > 1, newValue.height > 1 { super.drawableSize = newValue } }
    }
}

struct MPVSurface: UIViewRepresentable {
    let model: PlayerModel
    func makeUIView(context: Context) -> MPVVideoView { model.view }
    func updateUIView(_ uiView: MPVVideoView, context: Context) {}
}
