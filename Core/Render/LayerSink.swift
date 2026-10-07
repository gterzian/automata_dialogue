import Foundation
import Metal
import QuartzCore

/// A `FrameClock` over `CAMetalDisplayLink` (design doc §6). It is added to the
/// render actor's run loop, so ticks and the `LayerSink` draw happen on the
/// thread that owns the Metal objects. `preferredFrameLatency = 2` keeps two
/// frames in flight, matching the three frame slots.
@available(macOS 26.0, *)
public final class DisplayLinkClock: NSObject, FrameClock, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    private let link: CAMetalDisplayLink
    private var tick: (@Sendable (TimeInterval) -> Void)?
    private var lastTimestamp: CFTimeInterval = 0

    /// Called on each update with the drawable to render into. Set by the sink
    /// that owns this clock.
    var onDrawable: (@Sendable (any CAMetalDrawable, CFTimeInterval) -> Void)?

    public init(layer: CAMetalLayer) {
        self.link = CAMetalDisplayLink(metalLayer: layer)
        super.init()
        link.delegate = self
        link.preferredFrameLatency = 2
    }

    /// Frames kept in flight; two matches the three frame slots (design doc §6).
    public var preferredFrameLatency: Float {
        get { link.preferredFrameLatency }
        set { link.preferredFrameLatency = newValue }
    }

    public func start(_ tick: @escaping @Sendable (TimeInterval) -> Void) {
        self.tick = tick
        lastTimestamp = 0
        link.add(to: .current, forMode: .common)
        link.isPaused = false
    }

    public func stop() {
        link.isPaused = true
        link.remove(from: .current, forMode: .common)
        tick = nil
    }

    public func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let delta = lastTimestamp == 0 ? 0 : update.targetTimestamp - lastTimestamp
        lastTimestamp = update.targetTimestamp
        tick?(delta)
        onDrawable?(update.drawable, update.targetTimestamp)
    }
}

/// Presents the latest delivered `RenderFrame` through a `CAMetalLayer` as the
/// display link ticks (design doc §6). It is a `FrameSink`, so the render actor
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
        // about it (design doc §11.11).
        context.queue.addResidencySet(layer.residencySet)
        clock.onDrawable = { [weak self] drawable, _ in self?.render(drawable) }
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
        guard !done, let frame, let spec = Catalog.spec(id: frame.specID) else { return }
        do {
            try renderer.render(grid: frame.grid, palette: spec.display.palette, into: drawable.texture)
        } catch {
            lock.lock()
            lastError = error.localizedDescription
            lock.unlock()
            return
        }
        drawable.present()
    }
}
