import Foundation
import Metal
import QuartzCore

/// Presents the intro the review window shows while the model's turn is
/// prepared on a `CAMetalLayer`, driven by a `DisplayLinkClock`. The sequence
/// is one short cycle that ends on the horizon line the reveal's two branches
/// grow from; the clock freezes there, so the window draws nothing while
/// inference runs (see the window sequence in `AGENTS.md`).
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
    /// When the settled line started retracting onto the seed cell; 0 until the
    /// first frame of the retraction stamps it.
    private var finaleStartedAt: CFTimeInterval?
    private var variation = CollapseVariation.standard
    private var finished = false
    private var settled = false
    private var lineHalfThickness: Float = 0.00125
    /// The seed cell's colour, used for the retraction so the dot it lands on
    /// matches the entry's first frame.
    private var finaleInk: PaletteColor?
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

    /// Starts (or restarts) the sequence from its opening dot, drawing a fresh
    /// look for this run. `lineHalfThickness` is the automaton's horizon row
    /// half-height in screen-height units, which is both the line the cycle
    /// collapses into and the size of the dot it starts from. Safe to call
    /// after `stop()`.
    public func start(lineHalfThickness: Float) {
        lock.lock()
        startedAt = 0
        finaleStartedAt = nil
        finaleInk = nil
        finished = false
        settled = false
        variation = .seeded(UInt64.random(in: .min ... .max))
        self.lineHalfThickness = lineHalfThickness
        lock.unlock()
        clock.start { _ in }
    }

    /// Resumes the settled sequence for its last beat: the horizon line
    /// retracts onto the single centred cell an entry that starts there seeds
    /// from, drawn in `seedInk`, the palette colour of that cell. `isSettled`
    /// drops until that frame has been presented, and the clock freezes again
    /// there.
    public func collapseOntoSeedCell(seedInk: PaletteColor) {
        lock.lock()
        finaleStartedAt = 0
        finaleInk = seedInk
        settled = false
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

    /// True once the sequence rests on the frame the reveal continues from and
    /// the clock has stopped, so the window is drawing nothing. The window
    /// waits on this before starting inference, and again after the retraction.
    public var isSettled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled
    }

    private func render(_ drawable: any CAMetalDrawable, timestamp: CFTimeInterval) {
        lock.lock()
        let done = finished
        if startedAt == 0 { startedAt = timestamp }
        if finaleStartedAt == 0 { finaleStartedAt = timestamp }
        let finaleStart = finaleStartedAt
        let elapsed = timestamp - startedAt
        let variation = variation
        let lineHalfThickness = lineHalfThickness
        let ink = finaleStart == nil ? self.ink : (finaleInk ?? self.ink)
        lock.unlock()
        guard !done else { return }

        let frame: CollapseTimeline.Frame
        let isResting: Bool
        if let finaleStart {
            // The retraction's last frame is the rest frame, so freezing there
            // cannot jump.
            let progress = min(max((timestamp - finaleStart) / ReviewIntro.finaleDuration, 0), 1)
            let eased = progress * progress * (3 - 2 * progress)
            frame = CollapseTimeline.rested(settle: Float(eased), variation: variation)
            isResting = progress >= 1
        } else {
            frame = CollapseTimeline.frame(time: Float(elapsed), variation: variation)
            isResting = elapsed >= ReviewIntro.duration
        }
        do {
            try renderer.render(
                into: drawable.texture, frame: frame, white: white, ink: ink,
                lineHalfThickness: lineHalfThickness)
        } catch {
            lock.lock()
            self.error = error.localizedDescription
            lock.unlock()
            return
        }
        drawable.present()
        guard isResting else { return }
        // The rest frame is static: stop drawing and leave the GPU to the model.
        clock.freeze()
        lock.lock()
        settled = true
        lock.unlock()
    }
}
