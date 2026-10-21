import Foundation
import Metal
import QuartzCore

/// Presents the submission beat and the intro the review window shows while the
/// model's turn is prepared on a `CAMetalLayer`, driven by a
/// `DisplayLinkClock`. The submission doubles the input image into two copies
/// that part vertically, then collapses them onto the intro's opening dot; the
/// intro then runs its one cycle and rests on the horizon line the reveal's two
/// branches grow from. The clock freezes there if the model outlasts the intro,
/// so the window keeps the last presented frame and stops drawing. Both
/// animations run at 30 fps on a reduced drawable because they share the GPU
/// with inference.
///
/// Like `LayerSink`, it is confined to a render actor's thread and shared with
/// the clock's non-isolated draw callback, so it is `@unchecked Sendable` and
/// lock-guards the state the callback reads.
@available(macOS 26.0, *)
public final class WorkingIndicator: @unchecked Sendable {
    public let layer: CAMetalLayer
    public let clock: DisplayLinkClock

    private let renderer: CollapseRenderer
    private let submissionRenderer: SubmissionRenderer
    private let white: PaletteColor
    private let ink: PaletteColor
    private let lock = NSLock()
    /// 0 until the first submission frame stamps it; nil when the beat is not
    /// playing.
    private var submissionStartedAt: CFTimeInterval?
    /// 0 until the first intro frame stamps it; nil before the intro begins.
    private var introStartedAt: CFTimeInterval?
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
        self.submissionRenderer = try SubmissionRenderer(
            context: context, pixelFormat: layer.pixelFormat)
        // The model runs while this animates, so 30 fps with the slow radial
        // motion leaves most of the GPU to inference.
        clock.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        // The layer owns the residency of its drawables; the queue must know
        // about it.
        context.queue.addResidencySet(layer.residencySet)
        clock.onDrawable = { [weak self] drawable, timestamp in
            self?.render(drawable, timestamp: timestamp)
        }
    }

    /// Plays the submission beat for `image`, then the intro. A fresh look is
    /// drawn for this run, so the dot the image collapses onto is the same dot
    /// the intro starts from. Safe to call after `stop()`.
    public func playSubmission(_ image: RasterImage, lineHalfThickness: Float) throws {
        lock.lock()
        submissionStartedAt = 0
        introStartedAt = nil
        finaleStartedAt = nil
        finaleInk = nil
        finished = false
        settled = false
        error = nil
        variation = .seeded(UInt64.random(in: .min ... .max))
        self.lineHalfThickness = lineHalfThickness
        lock.unlock()
        try submissionRenderer.setImage(image)
        clock.start { _ in }
    }

    /// Starts (or restarts) the intro from its opening dot without a
    /// submission beat, drawing a fresh look for this run.
    /// `lineHalfThickness` is the automaton's horizon row half-height in
    /// screen-height units: the shader scales the opening dot and the resting
    /// hairline from it, and the finale lands on one cell of that row. Safe to
    /// call after `stop()`.
    public func start(lineHalfThickness: Float) {
        lock.lock()
        submissionStartedAt = nil
        introStartedAt = 0
        finaleStartedAt = nil
        finaleInk = nil
        finished = false
        settled = false
        error = nil
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

    /// Pauses the animation, keeping the clock for a later run.
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
    /// the clock has stopped, so the window is drawing nothing. The reveal
    /// waits on this so its handoff has no jump, and the finale waits on it
    /// again after the retraction.
    public var isSettled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled
    }

    private func render(_ drawable: any CAMetalDrawable, timestamp: CFTimeInterval) {
        lock.lock()
        let done = finished
        if submissionStartedAt == 0 { submissionStartedAt = timestamp }
        if introStartedAt == 0 { introStartedAt = timestamp }
        if finaleStartedAt == 0 { finaleStartedAt = timestamp }
        let submissionStart = submissionStartedAt
        let introStart = introStartedAt
        let finaleStart = finaleStartedAt
        let variation = variation
        let lineHalfThickness = lineHalfThickness
        let ink = finaleStart == nil ? self.ink : (finaleInk ?? self.ink)
        lock.unlock()
        guard !done else { return }

        var resting = false
        do {
            if let finaleStart {
                // The retraction's last frame is the rest frame, so freezing
                // there cannot jump.
                let progress = min(
                    max((timestamp - finaleStart) / ReviewIntro.finaleDuration, 0), 1)
                let eased = progress * progress * (3 - 2 * progress)
                let frame = CollapseTimeline.rested(settle: Float(eased), variation: variation)
                try renderer.render(
                    into: drawable.texture, frame: frame, white: white, ink: ink,
                    lineHalfThickness: lineHalfThickness)
                resting = progress >= 1
            } else if let submissionStart {
                let elapsed = timestamp - submissionStart
                if elapsed < SubmissionIntro.duration {
                    try submissionRenderer.render(
                        into: drawable.texture,
                        frame: SubmissionTimeline.frame(time: Float(elapsed)),
                        dotScale: variation.dotScale,
                        lineHalfThickness: lineHalfThickness,
                        white: white,
                        ink: ink)
                } else {
                    // The beat's last frame is the intro's opening dot, so the
                    // switch draws the same image the intro starts from.
                    lock.lock()
                    submissionStartedAt = nil
                    introStartedAt = timestamp
                    lock.unlock()
                    try renderer.render(
                        into: drawable.texture,
                        frame: CollapseTimeline.frame(
                            time: Float(ReviewIntro.openingTime), variation: variation),
                        white: white, ink: ink,
                        lineHalfThickness: lineHalfThickness)
                }
            } else if let introStart {
                let elapsed = timestamp - introStart
                let introTime = ReviewIntro.openingTime + elapsed
                let frame = CollapseTimeline.frame(time: Float(introTime), variation: variation)
                try renderer.render(
                    into: drawable.texture, frame: frame, white: white, ink: ink,
                    lineHalfThickness: lineHalfThickness)
                resting = introTime >= ReviewIntro.duration
            } else {
                return
            }
        } catch {
            lock.lock()
            self.error = error.localizedDescription
            lock.unlock()
            return
        }
        drawable.present()
        guard resting else { return }
        // The rest frame is static: stop drawing and leave the GPU to the model.
        clock.freeze()
        lock.lock()
        settled = true
        lock.unlock()
    }
}
