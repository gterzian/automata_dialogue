import Foundation
import QuartzCore

/// Owns the Metal objects for the "working" indicator on a dedicated run loop,
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

    /// Starts the animation on `layer`, creating the GPU context on first use.
    /// Reusing the same layer only restarts the clock, so the shader pipeline
    /// is not recompiled for every run.
    public func start(layer: CAMetalLayer) throws {
        if context == nil {
            context = try GPUContext()
        }
        guard let context else { throw GPUContext.GPUError.noMetal4Device }
        if let indicator, indicator.layer === layer {
            indicator.start()
            return
        }
        indicator?.finish()
        let made = try WorkingIndicator(layer: layer, context: context)
        made.start()
        indicator = made
    }

    /// Pauses the animation; the indicator is kept for the next `start`.
    public func stop() {
        indicator?.stop()
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
