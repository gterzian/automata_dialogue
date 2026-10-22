import Foundation
import Metal

/// Delivers the simulation's GPU-resident frames into a `RenderTarget`. It
/// looks the entry up by id for its palette, asks the target for this frame's
/// surface, and draws the grid into it, so the target decides what the surface
/// is and how it reaches the viewer. It is a `FrameSink`, so the render actor
/// hands it frames on the render thread.
@available(macOS 26.0, *)
public final class CellGridSink: FrameSink, @unchecked Sendable {
    public let target: any RenderTarget
    private let renderer: CellGridRenderer
    private let toneRenderer: ToneGridRenderer
    private let lock = NSLock()
    private var finished = false
    private var lastError: String?

    public init(target: any RenderTarget, context: GPUContext) throws {
        target.attach(to: context)
        self.target = target
        self.renderer = try CellGridRenderer(
            context: context, pixelFormat: target.pixelFormat)
        self.toneRenderer = try ToneGridRenderer(
            context: context, pixelFormat: target.pixelFormat)
    }

    /// Draws the frame into the target's surface and presents it. A target with
    /// no surface for this frame skips the draw and keeps its last image.
    public func deliver(_ frame: RenderFrame) {
        lock.lock()
        let done = finished
        lock.unlock()
        guard !done else { return }
        guard let spec = Catalog.spec(id: frame.specID) else { return }
        guard let surface = target.acquire() else { return }
        do {
            switch frame.gpu.content {
            case .paletteIndices:
                try renderer.render(
                    gpu: frame.gpu, palette: spec.display.palette, into: surface.texture)
            case .colors:
                try toneRenderer.render(gpu: frame.gpu, into: surface.texture)
            }
        } catch {
            lock.lock()
            lastError = error.localizedDescription
            lock.unlock()
            return
        }
        surface.present()
    }

    public func finish() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    /// The most recent render failure, if any. The frame callback has no place
    /// to throw, so a dropped frame is recorded here instead of silently lost.
    public var errorDescription: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }
}
