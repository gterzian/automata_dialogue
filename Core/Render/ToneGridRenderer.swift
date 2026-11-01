import Foundation
import Metal

/// Draws a grid whose cells are already colours: the below-floor minification
/// the fit writes once one display cell covers several source cells. A toned
/// cell has no palette index to compact into a span, and dithering its coverage
/// back into indices would cost a span per ink cell, so the grid goes out as one
/// textured quad instead and the surface samples the cells directly. The same
/// quad carries the reveal's ending, which closes the sampled picture through
/// the intro's organic circle into a single ink dot.
@available(macOS 26.0, *)
final class ToneGridRenderer {
    /// Mirrors the `ToneUniforms` struct in `ShaderSource.tone`.
    private struct Uniforms {
        var background: SIMD4<Float>
        var ink: SIMD4<Float>
        var aspect: Float
        var screenHeight: Float
        var scale: Float
        var fall: Float
        var wobble: Float
        var phase: Float
        var time: Float
        var grain: Float
    }

    private let context: GPUContext
    private let pipeline: any MTLRenderPipelineState
    private let submitter: FrameSubmitter
    private let table: any MTL4ArgumentTable
    private let uniforms: any MTLBuffer
    /// The smooth field the ending's limb erodes along, so the picture is not
    /// eaten by a circle.
    private let noise: MTLTexture
    /// The texture view over the grid the last frame drew, so a run at a steady
    /// grid size does not build one per frame.
    private var cells: (texture: any MTLTexture, cols: Int, rows: Int, buffer: any MTLBuffer)?

    init(context: GPUContext, pixelFormat: MTLPixelFormat) throws {
        self.context = context
        self.submitter = try FrameSubmitter(context: context)

        let libraryDescriptor = MTL4LibraryDescriptor()
        libraryDescriptor.source = ShaderSource.tone
        let library: any MTLLibrary
        do {
            library = try context.compiler.makeLibrary(descriptor: libraryDescriptor)
        } catch {
            throw GPUContext.GPUError.compile("tone library: \(error)")
        }

        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "tone_vertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "tone_fragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        guard let attachment = descriptor.colorAttachments[0] else {
            throw GPUContext.GPUError.resource("tone pipeline color attachment")
        }
        attachment.pixelFormat = pixelFormat
        do {
            self.pipeline = try context.compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw GPUContext.GPUError.compile("tone pipeline: \(error)")
        }

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 1
        tableDescriptor.maxTextureBindCount = 2
        self.table = try context.device.makeArgumentTable(descriptor: tableDescriptor)
        guard let uniformBuffer = context.device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride, options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("tone uniforms")
        }
        self.uniforms = uniformBuffer
        self.noise = try Self.makeNoiseTexture(context: context)
        table.setAddress(uniformBuffer.gpuAddress, index: 0)
        table.setTexture(noise.gpuResourceID, index: 1)
        context.makeResident([uniformBuffer])
        context.makeResident([noise])
    }

    /// Draws the grid into `surface` and returns once the GPU has finished, so
    /// the caller may read the surface back. `mask` is the reveal's ending, and
    /// `.full` draws the whole picture unchanged; `ink` is the palette's darkest
    /// colour, which the falling picture and the final dot darken toward.
    func render(
        gpu: GPUColorGrid,
        mask: RevealMask = .full,
        background: PaletteColor,
        ink: PaletteColor,
        into surface: MTLTexture
    ) throws {
        let texture = try cellsTexture(for: gpu)
        table.setTexture(texture.gpuResourceID, index: 0)
        var uniforms = Uniforms(
            background: background.simd,
            ink: ink.simd,
            aspect: Float(surface.width) / Float(max(1, surface.height)),
            screenHeight: Float(surface.height),
            scale: mask.scale,
            fall: mask.fall,
            wobble: mask.wobble,
            phase: mask.phase,
            time: mask.time,
            grain: mask.grain)
        memcpy(self.uniforms.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        try submitter.submit { command in
            let pass = MTL4RenderPassDescriptor()
            guard let attachment = pass.colorAttachments[0] else {
                throw GPUContext.GPUError.resource("tone render pass")
            }
            attachment.texture = surface
            // The quad covers the surface, so there is nothing to clear.
            attachment.loadAction = .dontCare
            attachment.storeAction = .store
            guard let render = command.makeRenderCommandEncoder(descriptor: pass) else {
                throw GPUContext.GPUError.resource("MTL4RenderCommandEncoder")
            }
            render.setRenderPipelineState(pipeline)
            render.setArgumentTable(table, stages: .fragment)
            render.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
            render.endEncoding()
        }
    }

    // MARK: - Private

    /// A texture view over the grid's colours. The grid is the simulation's own
    /// buffer, so a new grid size or buffer means a new view; the view in use is
    /// resident with it.
    private func cellsTexture(for gpu: GPUColorGrid) throws -> any MTLTexture {
        if let cells, cells.cols == gpu.cols, cells.rows == gpu.rows,
           (cells.buffer as AnyObject) === (gpu.buffer as AnyObject) {
            return cells.texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: gpu.cols, height: gpu.rows, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = gpu.buffer.makeTexture(
            descriptor: descriptor, offset: 0, bytesPerRow: gpu.cols * 4
        ) else {
            throw GPUContext.GPUError.resource("tone grid texture")
        }
        if let cells { context.removeResident(cells.texture) }
        context.makeResident([texture])
        cells = (texture, gpu.cols, gpu.rows, gpu.buffer)
        return texture
    }

    /// A small wrapped noise field for the ending's limb. The shader traces a
    /// circle through it, so the edge erodes at more than one scale and drifts
    /// as the picture falls.
    private static func makeNoiseTexture(context: GPUContext) throws -> MTLTexture {
        let size = 96
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: descriptor) else {
            throw GPUContext.GPUError.resource("ending noise texture")
        }
        var values = [Float](repeating: 0, count: size * size)
        // A fixed field, so one ending's seed reproduces its limb; the run's own
        // phase and clock decide where it enters the field.
        var draw = SplitMix64(seed: 0x5EED_0F_7A11_1A9E)
        for index in values.indices { values[index] = draw.unit() }
        // The shader samples this field with linear filtering, so raw white noise
        // would crease the limb at every texel boundary. Smoothing it first keeps
        // the erosion soft.
        for _ in 0..<2 { values = smoothed(values, size: size) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 1e-5)
        for index in values.indices { values[index] = (values[index] - low) / span }
        values.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: size * MemoryLayout<Float>.size)
        }
        return texture
    }

    /// One wrapped box blur along each axis, so the field joins its opposite
    /// edges under the sampler's `repeat` address mode.
    private static func smoothed(_ values: [Float], size: Int) -> [Float] {
        let radius = 1
        let taps = Float(2 * radius + 1)
        var source = values
        var target = values
        for axis in 0..<2 {
            for y in 0..<size {
                for x in 0..<size {
                    var sum: Float = 0
                    for offset in -radius...radius {
                        let sx = axis == 0 ? (x + offset + size) % size : x
                        let sy = axis == 1 ? (y + offset + size) % size : y
                        sum += source[sy * size + sx]
                    }
                    target[y * size + x] = sum / taps
                }
            }
            swap(&source, &target)
        }
        return source
    }
}
