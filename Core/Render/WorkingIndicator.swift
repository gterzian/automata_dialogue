import Foundation
import Metal
import QuartzCore

/// Draws the animating "working" indicator into a texture: a full-screen
/// triangle whose fragment shader paints expanding rings from a time uniform.
/// No per-frame geometry is built on the CPU. The `LayerSink` and `MetalSimulation`
/// pairs stay untouched — the indicator is a self-contained draw.
@available(macOS 26.0, *)
final class IndicatorRenderer {
    /// Mirrors the `IndicatorUniforms` struct in `ShaderSource.indicator`.
    private struct Uniforms {
        var time: Float
        var aspect: Float
        var thickness: Float
        // Explicit padding keeps the constant buffer 16-byte aligned, matching
        // the MSL struct.
        var padding: Float = 0
        var background: SIMD4<Float>
        var ink: SIMD4<Float>
    }

    private let context: GPUContext
    private let pipeline: any MTLRenderPipelineState
    private let ring: FrameSlotRing
    private let uniformsBuffer: any MTLBuffer
    private let table: any MTL4ArgumentTable

    init(context: GPUContext, pixelFormat: MTLPixelFormat) throws {
        self.context = context
        self.ring = try FrameSlotRing(device: context.device)

        let libraryDescriptor = MTL4LibraryDescriptor()
        libraryDescriptor.source = ShaderSource.indicator
        let library: any MTLLibrary
        do {
            library = try context.compiler.makeLibrary(descriptor: libraryDescriptor)
        } catch {
            throw GPUContext.GPUError.compile("indicator library: \(error)")
        }

        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "indicator_vertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "indicator_fragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            self.pipeline = try context.compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw GPUContext.GPUError.compile("indicator pipeline: \(error)")
        }

        guard let uniforms = context.device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride, options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("indicator uniforms")
        }
        self.uniformsBuffer = uniforms
        context.makeResident([uniforms])

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 1
        let table = try context.device.makeArgumentTable(descriptor: tableDescriptor)
        table.setAddress(uniforms.gpuAddress, index: 0)
        self.table = table
    }

    /// Encodes one frame of the animation into `texture`. The caller presents
    /// the drawable; the GPU finishes after the commit. When `wait` is true the
    /// call blocks until the GPU finishes, so a test may read the texture back.
    func render(
        into texture: MTLTexture,
        time: Float,
        background: PaletteColor,
        ink: PaletteColor,
        wait: Bool = false
    ) throws {
        var uniforms = Uniforms(
            time: time,
            aspect: Float(texture.width) / Float(max(1, texture.height)),
            thickness: 0.075,
            background: background.simd,
            ink: ink.simd
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)

        let pass = MTL4RenderPassDescriptor()
        guard let attachment = pass.colorAttachments[0] else {
            throw GPUContext.GPUError.resource("indicator render pass")
        }
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        attachment.clearColor = MTLClearColor(
            red: Double(background.r),
            green: Double(background.g),
            blue: Double(background.b),
            alpha: Double(background.a)
        )
        guard let render = slot.command.makeRenderCommandEncoder(descriptor: pass) else {
            throw GPUContext.GPUError.resource("indicator render encoder")
        }
        render.setRenderPipelineState(pipeline)
        render.setArgumentTable(table, stages: .fragment)
        render.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
        slot.command.endCommandBuffer()

        let options = MTL4CommitOptions()
        let done = wait ? DispatchSemaphore(value: 0) : nil
        options.addFeedbackHandler { _ in
            slot.allocator.reset()
            slot.release()
            done?.signal()
        }
        context.queue.commit([slot.command], options: options)
        done?.wait()
    }
}

/// Presents the "working" indicator on a `CAMetalLayer`, driven by a
/// `DisplayLinkClock`. Like `LayerSink`, it is confined to a render actor's
/// thread and shared with the clock's non-isolated draw callback, so it is
/// `@unchecked Sendable` and lock-guards the state the callback reads.
@available(macOS 26.0, *)
public final class WorkingIndicator: @unchecked Sendable {
    public let layer: CAMetalLayer
    public let clock: DisplayLinkClock

    private let renderer: IndicatorRenderer
    private let background: PaletteColor
    private let ink: PaletteColor
    private let lock = NSLock()
    private var startedAt: CFTimeInterval = 0
    private var finished = false
    private var error: String?

    public init(
        layer: CAMetalLayer,
        context: GPUContext,
        background: PaletteColor = PaletteColor(0.07, 0.08, 0.10),
        ink: PaletteColor = PaletteColor(0.973, 0.969, 0.949)
    ) throws {
        layer.device = context.device
        self.layer = layer
        self.background = background
        self.ink = ink
        self.clock = DisplayLinkClock(layer: layer)
        self.renderer = try IndicatorRenderer(context: context, pixelFormat: layer.pixelFormat)
        // The layer owns the residency of its drawables; the queue must know
        // about it.
        context.queue.addResidencySet(layer.residencySet)
        clock.onDrawable = { [weak self] drawable, timestamp in
            self?.render(drawable, timestamp: timestamp)
        }
    }

    /// Starts (or restarts) the animation. Safe to call after `stop()`.
    public func start() {
        lock.lock()
        startedAt = 0
        finished = false
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
        let time = timestamp - startedAt
        lock.unlock()
        guard !done else { return }
        do {
            try renderer.render(
                into: drawable.texture, time: Float(time), background: background, ink: ink)
        } catch {
            lock.lock()
            self.error = error.localizedDescription
            lock.unlock()
            return
        }
        drawable.present()
    }
}
