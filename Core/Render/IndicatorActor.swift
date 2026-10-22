import Foundation
import QuartzCore

/// Owns the Metal objects for the submission beat and the collapse intro on a
/// dedicated run loop, the way `RenderActor` does for a run. The GPU context is
/// created on the render thread, and the target's frame callback, draw, and
/// present all stay off the main thread.
@available(macOS 26.0, *)
public actor IndicatorActor {
    public nonisolated let executor = RenderExecutor()

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    private var context: GPUContext?
    private var indicator: WorkingIndicator?

    public init() {}

    /// Plays the submission beat for `image` on `target`, then the intro. The
    /// context, renderer, and target are reused across runs, so the pipelines
    /// compile once. `lineHalfThickness` is the half-height of the row the
    /// cycle ends on in screen-height units, which the dot and the resting
    /// hairline are scaled from; `cellHalfHeight` is half the height of the
    /// cell the retraction lands on.
    public func playSubmission(
        _ image: RasterImage,
        target: any RenderTarget,
        lineHalfThickness: Float,
        cellHalfHeight: Float
    ) throws {
        let indicator = try ensureIndicator(target: target)
        try indicator.playSubmission(
            image, lineHalfThickness: lineHalfThickness, cellHalfHeight: cellHalfHeight)
    }

    /// Starts the intro on `target` without a submission beat, creating the GPU
    /// context on first use. Reusing the same target only restarts its frame
    /// loop, so the pipeline is not recompiled for every run.
    /// `lineHalfThickness` is the half-height of the row the cycle ends on in
    /// screen-height units; `cellHalfHeight` is half the height of the cell the
    /// retraction lands on.
    public func start(
        target: any RenderTarget,
        lineHalfThickness: Float,
        cellHalfHeight: Float
    ) throws {
        let indicator = try ensureIndicator(target: target)
        indicator.start(
            lineHalfThickness: lineHalfThickness, cellHalfHeight: cellHalfHeight)
    }

    private func ensureIndicator(target: any RenderTarget) throws -> WorkingIndicator {
        let context: GPUContext
        if let existing = self.context {
            context = existing
        } else {
            let made = try GPUContext()
            self.context = made
            context = made
        }
        if let indicator, indicator.target === target { return indicator }
        indicator?.finish()
        let made = try WorkingIndicator(target: target, context: context)
        indicator = made
        return made
    }

    /// Pauses the animation; the indicator is kept for the next run.
    public func stop() {
        indicator?.stop()
    }

    /// Plays the intro's last beat: the settled horizon line retracts onto the
    /// single centred cell an entry that starts there seeds from, drawn in the
    /// colour of that cell. A window with no indicator has nothing to retract.
    public func collapseOntoSeedCell(seedInk: PaletteColor) {
        indicator?.collapseOntoSeedCell(seedInk: seedInk)
    }

    /// True once the visible sequence rests on the frame the reveal continues
    /// from and has stopped drawing. No indicator means nothing is left to wait
    /// for.
    public var isSettled: Bool {
        indicator?.isSettled ?? true
    }

    /// The last render failure, if any.
    public var lastError: String? {
        indicator?.errorDescription
    }

    /// Stops the render thread. Status calls must not follow.
    public func shutdown() {
        indicator?.finish()
        indicator = nil
        context = nil
        executor.shutdown()
    }
}
