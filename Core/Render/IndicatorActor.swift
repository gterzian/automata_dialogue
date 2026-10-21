import Foundation
import QuartzCore

/// Owns the Metal objects for the submission beat and the collapse intro on a
/// dedicated run loop, the way `RenderActor` does for a run. `playSubmission`
/// creates the GPU context on the render thread, and the display link, draw,
/// and `present` all stay off the main thread.
@available(macOS 26.0, *)
public actor IndicatorActor {
    public nonisolated let executor = RenderExecutor()

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    private var context: GPUContext?
    private var indicator: WorkingIndicator?

    public init() {}

    /// Plays the submission beat for `image` on `layer`, then the intro. The
    /// context, renderer, and clock are reused across runs, so the pipelines
    /// compile once. `lineHalfThickness` is the automaton horizon row's
    /// half-height in screen-height units.
    public func playSubmission(
        _ image: RasterImage,
        layer: CAMetalLayer,
        lineHalfThickness: Float
    ) throws {
        let indicator = try ensureIndicator(layer: layer)
        try indicator.playSubmission(image, lineHalfThickness: lineHalfThickness)
    }

    /// Starts the intro on `layer` without a submission beat, creating the GPU
    /// context on first use. Reusing the same layer only restarts the clock, so
    /// the pipeline is not recompiled for every run. `lineHalfThickness` is the
    /// automaton horizon row's half-height in screen-height units.
    public func start(layer: CAMetalLayer, lineHalfThickness: Float) throws {
        let indicator = try ensureIndicator(layer: layer)
        indicator.start(lineHalfThickness: lineHalfThickness)
    }

    private func ensureIndicator(layer: CAMetalLayer) throws -> WorkingIndicator {
        let context: GPUContext
        if let existing = self.context {
            context = existing
        } else {
            let made = try GPUContext()
            self.context = made
            context = made
        }
        if let indicator, indicator.layer === layer { return indicator }
        indicator?.finish()
        let made = try WorkingIndicator(layer: layer, context: context)
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
