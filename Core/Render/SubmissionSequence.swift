import Foundation
import Metal

/// Public timing for the beat between Return on an input page and the intro.
public enum SubmissionIntro {
    /// Seconds the submitted image spends parting into two copies. The two
    /// clones move in opposite vertical directions and the page shows between
    /// them.
    public static let doublingDuration: TimeInterval = 2.0

    /// Seconds the doubled screen takes to fall into the intro's opening dot.
    public static let collapseDuration: TimeInterval = 0.5

    public static var duration: TimeInterval { doublingDuration + collapseDuration }
}

/// The submission beat: one wall-clock time drives both phases, so a dropped
/// frame cannot stretch the animation.
enum SubmissionTimeline {
    static var duration: Float { Float(SubmissionIntro.duration) }
    static var doublingDuration: Float { Float(SubmissionIntro.doublingDuration) }

    struct Frame {
        var time: Float
        /// 0 keeps the two copies on top of each other; 1 has fully parted them.
        var doubling: Float
        /// 0 keeps the parted screen; 1 has collapsed it onto the opening dot.
        var collapse: Float
    }

    static func frame(time rawTime: Float) -> Frame {
        let time = min(max(rawTime, 0), duration)
        return Frame(
            time: time,
            doubling: smoothstep(0, doublingDuration, time),
            collapse: smoothstep(doublingDuration, duration, time))
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Encodes the submission beat into the indicator's drawable. The same
/// drawable and display link then play the intro, so the opening dot is one
/// continuous image rather than a view swap.
@available(macOS 26.0, *)
final class SubmissionRenderer {
    /// Mirrors the `SubmissionUniforms` struct in `ShaderSource.submission`.
    private struct Uniforms {
        var aspect: Float
        var imageAspect: Float
        var doubling: Float
        var collapse: Float
        var dotScale: Float
        var lineHalfThickness: Float
        var screenHeight: Float
        var white: SIMD4<Float>
        var ink: SIMD4<Float>
    }

    private let context: GPUContext
    private let ring: FrameSlotRing
    private let pipeline: any MTLRenderPipelineState
    private let uniforms: any MTLBuffer
    private let table: any MTL4ArgumentTable
    private var texture: MTLTexture?
    private var imageAspect: Float = 1

    init(context: GPUContext, pixelFormat: MTLPixelFormat) throws {
        self.context = context
        self.ring = try FrameSlotRing(device: context.device)

        let libraryDescriptor = MTL4LibraryDescriptor()
        libraryDescriptor.source = ShaderSource.submission
        let library: any MTLLibrary
        do {
            library = try context.compiler.makeLibrary(descriptor: libraryDescriptor)
        } catch {
            throw GPUContext.GPUError.compile("submission library: \(error)")
        }
        self.pipeline = try Self.makePipeline(
            compiler: context.compiler, library: library, pixelFormat: pixelFormat)

        guard let uniformBuffer = context.device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride, options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("submission uniforms")
        }
        self.uniforms = uniformBuffer

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 1
        tableDescriptor.maxTextureBindCount = 1
        let table = try context.device.makeArgumentTable(descriptor: tableDescriptor)
        table.setAddress(uniformBuffer.gpuAddress, index: 0)
        self.table = table

        context.makeResident([uniformBuffer])
    }

    /// Uploads the image the beat will draw. A new size replaces the texture
    /// and releases the old one from the residency set.
    func setImage(_ image: RasterImage) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: image.width,
            height: image.height,
            mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: descriptor) else {
            throw GPUContext.GPUError.resource("submission texture")
        }
        image.pixels.withUnsafeBytes { bytes in
            // SAFETY: the texture is width × height, the raster's invariant
            // fixes its pixel data at width × height × 4 bytes, and the copy is
            // bounded by that layout.
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, image.width, image.height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: image.width * 4)
        }
        if let old = self.texture { context.removeResident(old) }
        context.makeResident([texture])
        self.texture = texture
        self.imageAspect = Float(image.width) / Float(max(1, image.height))
        table.setTexture(texture.gpuResourceID, index: 0)
    }

    /// Renders one beat frame and blocks until the GPU finishes, matching the
    /// intro's serialized shared-uniform pipeline.
    func render(
        into texture: MTLTexture,
        frame: SubmissionTimeline.Frame,
        dotScale: Float,
        lineHalfThickness: Float,
        white: PaletteColor,
        ink: PaletteColor
    ) throws {
        guard self.texture != nil else {
            throw GPUContext.GPUError.resource("submission image")
        }
        write(
            frame: frame, into: texture, dotScale: dotScale,
            lineHalfThickness: lineHalfThickness, white: white, ink: ink)

        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)

        let pass = MTL4RenderPassDescriptor()
        guard let attachment = pass.colorAttachments[0] else {
            throw GPUContext.GPUError.resource("submission render pass")
        }
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        attachment.clearColor = MTLClearColor(
            red: Double(white.r), green: Double(white.g), blue: Double(white.b),
            alpha: Double(white.a))
        guard let render = slot.command.makeRenderCommandEncoder(descriptor: pass) else {
            throw GPUContext.GPUError.resource("submission render encoder")
        }
        render.setRenderPipelineState(pipeline)
        render.setArgumentTable(table, stages: .fragment)
        render.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
        slot.command.endCommandBuffer()

        let done = DispatchSemaphore(value: 0)
        let options = MTL4CommitOptions()
        options.addFeedbackHandler { _ in
            slot.allocator.reset()
            slot.release()
            done.signal()
        }
        context.queue.commit([slot.command], options: options)
        done.wait()
    }

    private func write(
        frame: SubmissionTimeline.Frame,
        into texture: MTLTexture,
        dotScale: Float,
        lineHalfThickness: Float,
        white: PaletteColor,
        ink: PaletteColor
    ) {
        var uniforms = Uniforms(
            aspect: Float(texture.width) / Float(max(1, texture.height)),
            imageAspect: imageAspect,
            doubling: frame.doubling,
            collapse: frame.collapse,
            dotScale: dotScale,
            lineHalfThickness: lineHalfThickness,
            screenHeight: Float(texture.height),
            white: white.simd,
            ink: ink.simd
        )
        memcpy(self.uniforms.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
    }

    private static func makePipeline(
        compiler: any MTL4Compiler,
        library: any MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> any MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "submission_vertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "submission_fragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw GPUContext.GPUError.compile("submission pipeline: \(error)")
        }
    }
}
