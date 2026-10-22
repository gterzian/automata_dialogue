import Foundation
import Metal
import QuartzCore

// The layer is created on the main thread (as a view's backing layer) and then
// handed to `MetalLayerTarget`, which uses it on the render thread to acquire
// and present drawables. `CAMetalLayer` is documented safe for
// `nextDrawable`/`present` across threads, so the cross-actor hand-off is
// accepted.
extension CAMetalLayer: @unchecked @retroactive Sendable {}

/// A `FrameClock` over `CAMetalDisplayLink`. It is added to the
/// render actor's run loop, so ticks and the draw happen on the thread that
/// owns the Metal objects. `preferredFrameLatency = 1` matches the serialized
/// frame pipeline: every commit waits for the GPU, so a second frame in flight
/// would only alias the shared buffers.
@available(macOS 26.0, *)
public final class DisplayLinkClock: NSObject, FrameClock, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    private let link: CAMetalDisplayLink
    private var tick: (@Sendable (TimeInterval) -> Void)?
    private var lastTimestamp: CFTimeInterval = 0
    private var registered = false
    /// The surface of the update being delivered. The display link supplies one
    /// drawable per update, so it is taken at most once.
    private var drawable: (any CAMetalDrawable)?

    public init(layer: CAMetalLayer) {
        self.link = CAMetalDisplayLink(metalLayer: layer)
        super.init()
        link.delegate = self
        link.preferredFrameLatency = 1
    }

    /// The display-link rate. `MetalLayerTarget` sets it for a surface that
    /// shares the GPU with other work, without changing an animation's
    /// wall-clock timing.
    var preferredFrameRateRange: CAFrameRateRange {
        get { link.preferredFrameRateRange }
        set { link.preferredFrameRateRange = newValue }
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
        drawable = nil
    }

    /// Stops delivering updates without leaving the run loop, so the layer
    /// keeps the last presented frame and the GPU is left to other work. A
    /// later `start` resumes. Unlike `stop` it is safe to call from the frame
    /// callback.
    public func freeze() {
        link.isPaused = true
    }

    public func metalDisplayLink(
        _ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update
    ) {
        // Stash the surface before the tick, so a callback that draws finds it.
        drawable = update.drawable
        let delta = lastTimestamp == 0 ? 0 : update.targetTimestamp - lastTimestamp
        lastTimestamp = update.targetTimestamp
        tick?(delta)
    }

    /// The surface this update can draw into.
    func takeDrawable() -> (any CAMetalDrawable)? {
        defer { drawable = nil }
        return drawable
    }
}

/// A `RenderTarget` over a `CAMetalLayer`: the drawable of each display-link
/// update is the frame's surface, and presenting it shows it on screen.
/// `MetalHostView` sets the layer's format, contents scale, drawable size, and
/// magnification; this target attaches the device and the residency set and
/// never resizes the layer.
@available(macOS 26.0, *)
public final class MetalLayerTarget: RenderTarget, @unchecked Sendable {
    public let layer: CAMetalLayer
    public let displayLimits: DisplayLimits
    private let clock: DisplayLinkClock
    private var attached = false

    public var pixelFormat: MTLPixelFormat { layer.pixelFormat }

    /// `displayLimits` is what the surface behind the layer resolves
    /// one-to-one, which only the caller that sized it knows; `frameRate` caps
    /// the display link for a target that shares the GPU with other work.
    public init(
        layer: CAMetalLayer,
        displayLimits: DisplayLimits,
        frameRate: CAFrameRateRange? = nil
    ) {
        self.layer = layer
        self.displayLimits = displayLimits
        self.clock = DisplayLinkClock(layer: layer)
        if let frameRate { clock.preferredFrameRateRange = frameRate }
    }

    public func attach(to context: GPUContext) {
        guard !attached else { return }
        attached = true
        layer.device = context.device
        // The layer owns the residency of its drawables; the queue must know
        // about it.
        context.queue.addResidencySet(layer.residencySet)
    }

    public func start(_ frame: @escaping @Sendable (TimeInterval) -> Void) {
        clock.start(frame)
    }

    public func stop() { clock.stop() }

    public func freeze() { clock.freeze() }

    public func acquire() -> (any RenderSurface)? {
        guard let drawable = clock.takeDrawable() else { return nil }
        return LayerSurface(drawable: drawable)
    }
}

/// One drawable of a `CAMetalLayer`; presenting it shows the frame.
@available(macOS 26.0, *)
final class LayerSurface: RenderSurface, @unchecked Sendable {
    private let drawable: any CAMetalDrawable

    init(drawable: any CAMetalDrawable) {
        self.drawable = drawable
    }

    var texture: any MTLTexture { drawable.texture }

    func present() { drawable.present() }
}
