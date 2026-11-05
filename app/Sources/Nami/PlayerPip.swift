import AVKit
import Combine
import CoreMedia
import Metal
import UIKit

/// Picture-in-Picture for mpv, with the system's own controls. iOS only floats video
/// it is handed frame by frame, so each picture mpv draws is copied into that window.
@MainActor
final class PlayerPip: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    private unowned let model: PlayerModel
    private let container: UIView
    private let display = AVSampleBufferDisplayLayer()
    private let tap: FrameTap?
    private var controller: AVPictureInPictureController?
    private var timebase: CMTimebase?
    private var timer: Timer?
    private var playing: AnyCancellable?
    /// The last picture copied, kept so the window can be filled again while mpv is
    /// paused and draws nothing new. It is Nami's own copy, not one of mpv's.
    private var last: CVPixelBuffer?
    private var tries = 0

    /// Why the window could not open, for the player to say.
    var onProblem: ((String) -> Void)?

    init(model: PlayerModel, container: UIView) {
        self.model = model
        self.container = container
        tap = FrameTap(layer: model.view.metalLayer)
        super.init()
        guard AVPictureInPictureController.isPictureInPictureSupported(), let tap else { return }
        tap.onFrame = { [weak self] buffer in
            self?.last = buffer
            self?.show(buffer)
        }
        // The pictures are read back, so the layer cannot keep them for the screen only.
        model.view.metalLayer.readable = true
        model.view.metalLayer.framebufferOnly = false
        display.videoGravity = .resizeAspect
        container.layer.insertSublayer(display, at: 0)
        // The window's progress bar follows this clock.
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
        if let timebase {
            display.controlTimebase = timebase
            self.timebase = timebase
        }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: display, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        self.controller = controller
        playing = model.$isPlaying.sink { [weak self] _ in
            Task { @MainActor in self?.controller?.invalidatePlaybackState() }
        }
        // A picture now and then, so the window has one if it opens on its own.
        feed(every: 1)
    }

    var supported: Bool { controller != nil }

    func start() {
        guard let controller else { return }
        if display.sampleBufferRenderer.status == .failed {
            let reason = display.sampleBufferRenderer.error?.localizedDescription ?? "?"
            onProblem?(t("L'image dans l'image n'affiche rien : \(reason)", "Picture-in-Picture shows nothing: \(reason)"))
            return
        }
        // iOS refuses to open a window that has no picture yet: wait for one first.
        guard last != nil, controller.isPictureInPicturePossible else {
            tries += 1
            if tries > 15 {
                tries = 0
                onProblem?(t(last == nil ? "L'image dans l'image n'a reçu aucune image de la vidéo. Lance la lecture puis réessaie."
                                         : "L'image dans l'image n'est pas encore prête. Réessaie dans un instant.",
                             last == nil ? "Picture-in-Picture got no picture from the video. Play it, then try again."
                                         : "Picture-in-Picture is not ready yet. Try again in a moment."))
                return
            }
            tap?.request(aspect: model.videoAspect)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.start() }
            return
        }
        tries = 0
        if let last { show(last) }
        controller.startPictureInPicture()
    }

    /// Puts a picture in the window, stamped with the window's own clock so iOS shows it.
    private func show(_ buffer: CVPixelBuffer) {
        let renderer = display.sampleBufferRenderer
        if renderer.requiresFlushToResumeDecoding { renderer.flush() }
        let now = timebase.map { CMTimebaseGetTime($0) } ?? CMClockGetTime(CMClockGetHostTimeClock())
        guard let sample = FrameTap.sample(buffer, at: now) else { return }
        renderer.enqueue(sample)
    }

    private func feed(every seconds: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if display.frame != container.bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            display.frame = container.bounds
            CATransaction.commit()
        }
        if let timebase {
            CMTimebaseSetTime(timebase, time: CMTime(value: CMTimeValue(model.timeMs), timescale: 1000))
            CMTimebaseSetRate(timebase, rate: model.isPlaying ? 1 : 0)
        }
        tap?.request(aspect: model.videoAspect)
    }

    // MARK: Window

    /// Closes the window and brings the video back into the app.
    func stop() { controller?.stopPictureInPicture() }

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            feed(every: 1 / 30)
            model.inPip = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            feed(every: 1)
            model.inPip = false
        }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated {
            feed(every: 1)
            model.inPip = false
            onProblem?(t("L'image dans l'image n'a pas pu s'ouvrir : \(error.localizedDescription)",
                         "Picture-in-Picture could not open: \(error.localizedDescription)"))
        }
    }

    // MARK: Controls

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated { model.setPaused(!playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            let length = model.lengthMs > 0 ? CMTime(value: CMTimeValue(model.lengthMs), timescale: 1000) : .positiveInfinity
            return CMTimeRange(start: .zero, duration: length)
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { !model.isPlaying }
    }

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) {
        MainActor.assumeIsolated { model.jump(Int32(skipInterval.seconds.rounded())) }
        completion()
    }
}

/// Copies a picture mpv drew, on the GPU, cropped to the video without the bars mpv
/// puts around it and shrunk to what the window needs. One copy per request, right
/// after it is shown. A small shader does the copy, so any format mpv draws in works.
final class FrameTap: @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private weak var layer: MPVMetalLayer?
    private var cache: CVMetalTextureCache?
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)
    private var library: MTLLibrary?
    private var pipelines: [MTLPixelFormat: MTLRenderPipelineState] = [:]
    private let lock = NSLock()
    private var wanted = false
    private var aspect: Double?
    private var linear = false

    @MainActor var onFrame: ((CVPixelBuffer) -> Void)?

    init?(layer: MPVMetalLayer) {
        guard let device = layer.device ?? MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.layer = layer
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        if cache == nil { return nil }
        layer.onPresent { [weak self] texture in self?.presented(texture) }
    }

    /// The next picture shown is copied.
    @MainActor func request(aspect: Double?) {
        // Half-float pictures hold linear light unless the layer says otherwise.
        let space = layer?.colorspace?.name as String?
        let linear = space?.contains("Linear") ?? true
        lock.withLock {
            wanted = true
            self.aspect = aspect
            self.linear = linear
        }
    }

    private func presented(_ source: MTLTexture) {
        let (go, aspect, linear) = lock.withLock { () -> (Bool, Double?, Bool) in
            defer { wanted = false }
            return (wanted, self.aspect, self.linear)
        }
        guard go, let cache else { return }
        if source.isFramebufferOnly { return }
        // The part of the picture that is video, without mpv's bars.
        let full = (width: Double(source.width), height: Double(source.height))
        let shape = aspect.flatMap { $0 > 0.2 ? $0 : nil } ?? full.width / full.height
        var crop = full
        if full.width / full.height > shape { crop.width = full.height * shape } else { crop.height = full.width / shape }
        let scale = min(1, 1280 / max(crop.width, crop.height))
        let width = Int(crop.width * scale) & ~1, height = Int(crop.height * scale) & ~1
        guard width > 1, height > 1, let buffer = makeBuffer(width: width, height: height) else { return }
        // Light stored linearly is turned back into ordinary sRGB by writing to an sRGB view.
        let written: MTLPixelFormat = Self.linearLight(source.pixelFormat, linear) ? .bgra8Unorm_srgb : .bgra8Unorm
        var target: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil, written, width, height, 0, &target)
        guard let target, let destination = CVMetalTextureGetTexture(target) else { return }
        guard let pipeline = pipeline(for: written) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let commands = queue.makeCommandBuffer(), let draw = commands.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        var region = SIMD4<Float>(Float((full.width - crop.width) / 2 / full.width), Float((full.height - crop.height) / 2 / full.height),
                                  Float(crop.width / full.width), Float(crop.height / full.height))
        draw.setRenderPipelineState(pipeline)
        draw.setVertexBytes(&region, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        draw.setFragmentTexture(source, index: 0)
        draw.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        draw.endEncoding()
        commands.addCompletedHandler { [weak self] done in
            withExtendedLifetime(target) {}
            if done.error != nil { return }
            nonisolated(unsafe) let buffer = buffer
            Task { @MainActor in self?.onFrame?(buffer) }
        }
        commands.commit()
    }

    private static func linearLight(_ format: MTLPixelFormat, _ linearFloat: Bool) -> Bool {
        switch format {
        case .bgra8Unorm_srgb, .rgba8Unorm_srgb: return true
        case .rgba16Float, .rgba32Float, .rg11b10Float, .rgb9e5Float: return linearFloat
        default: return false
        }
    }

    private func pipeline(for format: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let made = pipelines[format] { return made }
        do {
            if library == nil { library = try device.makeLibrary(source: Self.shader, options: nil) }
            let description = MTLRenderPipelineDescriptor()
            description.vertexFunction = library?.makeFunction(name: "crop_vertex")
            description.fragmentFunction = library?.makeFunction(name: "crop_fragment")
            description.colorAttachments[0].pixelFormat = format
            let made = try device.makeRenderPipelineState(descriptor: description)
            pipelines[format] = made
            return made
        } catch {
            return nil
        }
    }

    /// One triangle covering the target, reading the cropped part of mpv's picture.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Corner { float4 position [[position]]; float2 uv; };
    vertex Corner crop_vertex(uint id [[vertex_id]], constant float4 &region [[buffer(0)]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        Corner c;
        c.position = float4(p.x * 2 - 1, 1 - p.y * 2, 0, 1);
        c.uv = region.xy + p * region.zw;
        return c;
    }
    fragment float4 crop_fragment(Corner c [[stage_in]], texture2d<float> source [[texture(0)]]) {
        constexpr sampler linear_sampler(filter::linear, address::clamp_to_edge);
        return float4(source.sample(linear_sampler, c.uv).rgb, 1);
    }
    """

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolSize != (width, height) {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey: true,
            ]
            pool = nil
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
            poolSize = (width, height)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }

    static func sample(_ buffer: CVPixelBuffer, at time: CMTime) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return nil }
        // Shown as soon as it arrives, whatever the clock says.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
