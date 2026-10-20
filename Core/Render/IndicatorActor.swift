import Foundation
import QuartzCore

/// Owns the Metal objects for the collapse intro on a dedicated run loop,
/// the way `RenderActor` does for a run. `start(layer:)` creates the GPU
/// context on the render thread and adds the display link there, so drawable
/// acquisition, the draw, and `present` all stay off the main thread.
@available(macOS 26.0, *)
public actor IndicatorActor {
    public nonisolated let executor = RenderExecutor()

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    private var context: GPUContext?
    private var indicator: WorkingIndicator?

    public init() {}

    /// Starts the intro on `layer`, creating the GPU context on first use.
    /// Reusing the same layer only restarts the clock, so the pipeline is not
    /// recompiled for every run. `lineHalfThickness` is the automaton horizon
    /// row's half-height in screen-height units.
    public func start(layer: CAMetalLayer, lineHalfThickness: Float) throws {
        if context == nil {
            context = try GPUContext()
        }
        guard let context else { throw GPUContext.GPUError.noMetal4Device }
        if let indicator, indicator.layer === layer {
            indicator.start(lineHalfThickness: lineHalfThickness)
            return
        }
        indicator?.finish()
        let made = try WorkingIndicator(layer: layer, context: context)
        made.start(lineHalfThickness: lineHalfThickness)
        indicator = made
    }

    /// Pauses the animation; the indicator is kept for the next `start`.
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
