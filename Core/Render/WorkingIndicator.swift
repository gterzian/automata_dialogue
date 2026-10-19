import Foundation
import Metal
import QuartzCore

/// Presents the intro the review window shows while the model runs on a
/// `CAMetalLayer`, driven by a `DisplayLinkClock`. The sequence is one
/// wall-clock timeline: it ends on the automaton's warm white after the last
/// point shrinks away, so the cut to the first automaton frame does not flash.
/// Like `LayerSink`, it is confined to a render actor's thread and shared with
/// the clock's non-isolated draw callback, so it is `@unchecked Sendable` and
/// lock-guards the state the callback reads.
@available(macOS 26.0, *)
public final class WorkingIndicator: @unchecked Sendable {
    public let layer: CAMetalLayer
    public let clock: DisplayLinkClock

    private let renderer: CollapseRenderer
    private let white: PaletteColor
    private let ink: PaletteColor
    private let lock = NSLock()
    private var startedAt: CFTimeInterval = 0
    private var variation = CollapseVariation.standard
    private var finished = false
    private var error: String?

    public init(
        layer: CAMetalLayer,
        context: GPUContext,
        white: PaletteColor = Palette.standard(stateCount: 2)[0],
        ink: PaletteColor = Palette.standard(stateCount: 2)[1]
    ) throws {
        layer.device = context.device
        self.layer = layer
        self.white = white
        self.ink = ink
        self.clock = DisplayLinkClock(layer: layer)
        self.renderer = try CollapseRenderer(context: context, pixelFormat: layer.pixelFormat)
        // The layer owns the residency of its drawables; the queue must know
        // about it.
        context.queue.addResidencySet(layer.residencySet)
        clock.onDrawable = { [weak self] drawable, timestamp in
            self?.render(drawable, timestamp: timestamp)
        }
    }

    /// Starts (or restarts) the sequence from its opening point, drawing a
    /// fresh look for this run. Safe to call after `stop()`.
    public func start() {
        lock.lock()
        startedAt = 0
        finished = false
        variation = .seeded(UInt64.random(in: .min ... .max))
        lock.unlock()
        clock.start { _ in }
    }

    /// Pauses the animation, keeping the clock for a later `start()`.
    public func stop() {
        clock.stop()
    }

    /// Stops and marks the indicator done; no further frames are drawn.
    public func finish() {
        clock.stop()
        lock.lock()
        finished = true
        lock.unlock()
    }

    /// The most recent render failure, if any. The display link has no place to
    /// throw, so a dropped frame is recorded here instead of silently lost.
    public var errorDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }

    private func render(_ drawable: any CAMetalDrawable, timestamp: CFTimeInterval) {
        lock.lock()
        let done = finished
        if startedAt == 0 { startedAt = timestamp }
        let elapsed = timestamp - startedAt
        let variation = variation
        lock.unlock()
        guard !done else { return }

        let frame = CollapseTimeline.frame(time: Float(elapsed), variation: variation)
        do {
            try renderer.render(
                into: drawable.texture, frame: frame, white: white, ink: ink)
        } catch {
            lock.lock()
            self.error = error.localizedDescription
            lock.unlock()
            return
        }
        drawable.present()
    }
}
