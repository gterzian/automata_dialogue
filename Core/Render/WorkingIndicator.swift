import Foundation
import Metal
import QuartzCore

/// Presents the submission beat and the intro the review window shows while the
/// model's turn is prepared. The submission separates the input image into a
/// double exposure — two copies a fraction of its height apart — then collapses
/// them onto the intro's opening dot, rejoining the copies as the image shrinks;
/// the intro then runs its one cycle and rests on the
/// horizon line the reveal's two branches grow from. The target freezes there if
/// the model outlasts the intro, so the surface keeps the last presented frame
/// and nothing is drawn. Both animations run at a reduced rate on a reduced
/// surface because they share the GPU with inference.
///
/// Like every presenter, it is confined to a render actor's thread and shared
/// with the target's frame callback, so it is `@unchecked Sendable` and
/// lock-guards the state the callback reads.
@available(macOS 26.0, *)
public final class WorkingIndicator: @unchecked Sendable {
    public let target: any RenderTarget

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
        target: any RenderTarget,
        context: GPUContext,
        white: PaletteColor = Palette.standard(stateCount: 2)[0],
        ink: PaletteColor = Palette.standard(stateCount: 2)[1]
    ) throws {
        target.attach(to: context)
        self.target = target
        self.white = white
        self.ink = ink
        self.renderer = try CollapseRenderer(
            context: context, pixelFormat: target.pixelFormat)
        self.submissionRenderer = try SubmissionRenderer(
            context: context, pixelFormat: target.pixelFormat)
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
        target.start { [weak self] _ in self?.draw() }
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
        target.start { [weak self] _ in self?.draw() }
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
        target.start { [weak self] _ in self?.draw() }
    }

    /// Pauses the animation, keeping the target for a later run.
    public func stop() {
        target.stop()
    }

    /// Stops and marks the indicator done; no further frames are drawn.
    public func finish() {
        target.stop()
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
    /// the target has stopped delivering, so nothing is being drawn. The reveal
    /// waits on this so its handoff has no jump, and the finale waits on it
    /// again after the retraction.
    public var isSettled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled
    }

    private func draw() {
        // The phase stamps come from the wall clock, so a dropped frame cannot
        // stretch the animation and a phase starts when it is first drawn.
        let now = CACurrentMediaTime()
        lock.lock()
        let done = finished
        if submissionStartedAt == 0 { submissionStartedAt = now }
        if introStartedAt == 0 { introStartedAt = now }
        if finaleStartedAt == 0 { finaleStartedAt = now }
        let submissionStart = submissionStartedAt
        let introStart = introStartedAt
        let finaleStart = finaleStartedAt
        let variation = variation
        let lineHalfThickness = lineHalfThickness
        let ink = finaleStart == nil ? self.ink : (finaleInk ?? self.ink)
        lock.unlock()

        let playing = finaleStart != nil || submissionStart != nil || introStart != nil
        guard !done, playing, let surface = target.acquire() else { return }

        var resting = false
        do {
            if let finaleStart {
                // The retraction's last frame is the rest frame, so freezing
                // there cannot jump.
                let progress = min(
                    max((now - finaleStart) / ReviewIntro.finaleDuration, 0), 1)
                let eased = progress * progress * (3 - 2 * progress)
                let frame = CollapseTimeline.rested(settle: Float(eased), variation: variation)
                try renderer.render(
                    into: surface.texture, frame: frame, white: white, ink: ink,
                    lineHalfThickness: lineHalfThickness)
                resting = progress >= 1
            } else if let submissionStart {
                let elapsed = now - submissionStart
                if elapsed < SubmissionIntro.duration {
                    try submissionRenderer.render(
                        into: surface.texture,
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
                    introStartedAt = now
                    lock.unlock()
                    try renderer.render(
                        into: surface.texture,
                        frame: CollapseTimeline.frame(
                            time: Float(ReviewIntro.openingTime), variation: variation),
                        white: white, ink: ink,
                        lineHalfThickness: lineHalfThickness)
                }
            } else if let introStart {
                let elapsed = now - introStart
                let introTime = ReviewIntro.openingTime + elapsed
                let frame = CollapseTimeline.frame(time: Float(introTime), variation: variation)
                try renderer.render(
                    into: surface.texture, frame: frame, white: white, ink: ink,
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
        surface.present()
        guard resting else { return }
        // The rest frame is static: stop drawing and leave the GPU to the model.
        target.freeze()
        lock.lock()
        settled = true
        lock.unlock()
    }
}
