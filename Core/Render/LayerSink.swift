import Foundation
import Metal
import QuartzCore

// The layer is created on the main thread (as a view's backing layer) and then
// handed to `RenderActor.makeLayerSink(layer:)`, which uses it on the render
// thread to acquire and present drawables. `CAMetalLayer` is documented safe
// for `nextDrawable`/`present` across threads, and `LayerSink` already shares
// it with the render actor, so the cross-actor hand-off is accepted.
extension CAMetalLayer: @unchecked @retroactive Sendable {}

/// A `FrameClock` over `CAMetalDisplayLink`. It is added to the
/// render actor's run loop, so ticks and the `LayerSink` draw happen on the
/// thread that owns the Metal objects. `preferredFrameLatency = 1` matches the
/// serialized frame pipeline: the sink waits for each frame's GPU work, so a
/// second frame in flight would only alias the shared buffers.
@available(macOS 26.0, *)
public final class DisplayLinkClock: NSObject, FrameClock, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    private let link: CAMetalDisplayLink
    private var tick: (@Sendable (TimeInterval) -> Void)?
    private var lastTimestamp: CFTimeInterval = 0
    private var registered = false

    /// Called on each update with the drawable to render into. Set by the sink
    /// that owns this clock.
    var onDrawable: (@Sendable (any CAMetalDrawable, CFTimeInterval) -> Void)?

    public init(layer: CAMetalLayer) {
        self.link = CAMetalDisplayLink(metalLayer: layer)
        super.init()
        link.delegate = self
        link.preferredFrameLatency = 1
    }

    /// Frames kept in flight; one, because the sink serializes each frame.
    public var preferredFrameLatency: Float {
        get { link.preferredFrameLatency }
        set { link.preferredFrameLatency = newValue }
    }

    public func start(_ tick: @escaping @Sendable (TimeInterval) -> Void) {
        self.tick = tick
        lastTimestamp = 0
        if !registered {
            link.add(to: .current, forMode: .common)
            registered = true
        }
        link.isPaused = false
    }

    public func stop() {
        link.isPaused = true
        if registered {
            link.remove(from: .current, forMode: .common)
            registered = false
        }
        tick = nil
    }

    /// Stops delivering updates without leaving the run loop, so the layer
    /// keeps the last presented frame and the GPU is left to other work. A
    /// later `start` resumes. Unlike `stop` it is safe to call from the draw
    /// callback.
    public func freeze() {
        link.isPaused = true
    }

    public func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let delta = lastTimestamp == 0 ? 0 : update.targetTimestamp - lastTimestamp
        lastTimestamp = update.targetTimestamp
        tick?(delta)
        onDrawable?(update.drawable, update.targetTimestamp)
    }
}

/// Presents the latest delivered `RenderFrame` through a `CAMetalLayer` as the
/// display link ticks. It is a `FrameSink`, so the render actor
/// hands it frames; the `DisplayLinkClock` supplies the drawable and pacing.
/// The app starts the clock and advances the actor from its tick.
@available(macOS 26.0, *)
public final class LayerSink: FrameSink, @unchecked Sendable {
    public let layer: CAMetalLayer
    public let clock: DisplayLinkClock
    private let renderer: LayerRenderer
    private let lock = NSLock()
    private var latest: RenderFrame?
    private var finished = false
    private var lastError: String?

    public init(layer: CAMetalLayer, context: GPUContext) throws {
        layer.device = context.device
        self.layer = layer
        self.clock = DisplayLinkClock(layer: layer)
        self.renderer = try LayerRenderer(context: context, pixelFormat: layer.pixelFormat)
        // The layer owns the residency of its drawables; the queue must know
        // about it.
        context.queue.addResidencySet(layer.residencySet)
        clock.onDrawable = { [weak self] drawable, _ in
            self?.render(drawable)
        }
    }

    public func deliver(_ frame: RenderFrame) {
        lock.lock()
        latest = frame
        lock.unlock()
    }

    public func finish() {
        lock.lock()
        finished = true
        latest = nil
        lock.unlock()
    }

    /// The most recent render failure, if any. The display link has no place to
    /// throw, so a dropped frame is recorded here instead of silently lost.
    public var errorDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }

    private func render(_ drawable: any CAMetalDrawable) {
        lock.lock()
        let frame = latest
        let done = finished
        lock.unlock()
        guard !done, let frame else { return }
        do {
            try render(frame: frame, into: drawable.texture)
        } catch {
            lock.lock()
            lastError = error.localizedDescription
            lock.unlock()
            return
        }
        drawable.present()
    }

    /// Renders one delivered frame into `texture` and blocks until the GPU
    /// finishes. The on-screen path must serialize frames: the simulation
    /// reuses one color buffer, and this renderer reuses its span, counter,
    /// uniform, and palette buffers, so a frame that is still reading them must
    /// complete before the next frame writes them. Offscreen tests drive this
    /// directly; `render(_:)` adds the drawable and `present`.
    func render(frame: RenderFrame, into texture: MTLTexture) throws {
        guard let spec = Catalog.spec(id: frame.specID) else { return }
        try renderer.render(
            gpu: frame.gpu, palette: spec.display.palette, into: texture, wait: true)
    }
}
