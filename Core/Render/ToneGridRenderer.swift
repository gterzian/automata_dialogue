import Foundation
import Metal

/// Draws a grid whose cells are already colours: the below-floor minification
/// the fit writes once one display cell covers several source cells. A toned
/// cell has no palette index to compact into a span, and dithering its coverage
/// back into indices would cost a span per ink cell, so the grid goes out as one
/// textured quad instead and the surface samples the cells directly.
@available(macOS 26.0, *)
final class ToneGridRenderer {
    /// Mirrors the `ToneUniforms` struct in `ShaderSource.tone`.
    private struct Uniforms {
        var background: SIMD4<Float>
        var left: Float
        var top: Float
        var right: Float
        var bottom: Float
        var wobble: Float
        var phase: Float
    }

    private let context: GPUContext
    private let pipeline: any MTLRenderPipelineState
    private let submitter: FrameSubmitter
    private let table: any MTL4ArgumentTable
    private let uniforms: any MTLBuffer
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
        tableDescriptor.maxTextureBindCount = 1
        self.table = try context.device.makeArgumentTable(descriptor: tableDescriptor)
        guard let uniformBuffer = context.device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride, options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("tone uniforms")
        }
        self.uniforms = uniformBuffer
        table.setAddress(uniformBuffer.gpuAddress, index: 0)
        context.makeResident([uniformBuffer])
    }

    /// Draws the grid into `surface` and returns once the GPU has finished, so
    /// the caller may read the surface back. `mask` is what the reveal's ending
    /// leaves visible; `.full` draws the whole picture, and a masked cell draws
    /// the page, so the picture is eaten in place rather than rescaled.
    func render(
        gpu: GPUColorGrid,
        mask: RevealMask = .full,
        background: PaletteColor,
        into surface: MTLTexture
    ) throws {
        let texture = try cellsTexture(for: gpu)
        table.setTexture(texture.gpuResourceID, index: 0)
        var uniforms = Uniforms(
            background: background.simd,
            left: mask.left, top: mask.top, right: mask.right, bottom: mask.bottom,
            wobble: mask.wobble, phase: mask.phase)
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
}
