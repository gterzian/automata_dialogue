import Foundation
import Metal

/// Encodes a GPU-resident frame into a render target: a `runs` kernel compacts
/// each non-background run of same-coloured cells into a `Span`, an
/// `encode_draw` kernel writes the indirect draw arguments on the GPU, and a
/// render pass clears to the background colour and draws one quad per span.
/// Draw cost therefore follows the structure, not the grid area. The same code
/// path serves a `CAMetalLayer` drawable and the offscreen test texture.
///
/// The window refits every display row each frame, so every frame recompacts
/// the whole grid.
@available(macOS 26.0, *)
final class LayerRenderer {
    /// Mirrors the `Span` struct in `ShaderSource.layer`.
    struct Span {
        var row: UInt32
        var start: UInt32
        var length: UInt32
        var color: UInt32
    }

    private struct LayerUniforms {
        var cols: UInt32
        var rows: UInt32
    }

    private struct DrawArguments {
        var vertexCount: UInt32
        var instanceCount: UInt32
        var vertexStart: UInt32
        var baseInstance: UInt32
    }

    private struct Buffers {
        let cells: any MTLBuffer
        let spans: any MTLBuffer
        /// Spans the buffer holds; a larger grid is only allocated when needed.
        let spansCapacity: Int
        let counter: any MTLBuffer
        let arguments: any MTLBuffer
        let uniforms: any MTLBuffer
        let palette: any MTLBuffer
        let clearTable: any MTL4ArgumentTable
        let runsTable: any MTL4ArgumentTable
        let encodeTable: any MTL4ArgumentTable
        let renderTable: any MTL4ArgumentTable
    }

    private let context: GPUContext
    private let clearPipeline: any MTLComputePipelineState
    private let runsPipeline: any MTLComputePipelineState
    private let encodePipeline: any MTLComputePipelineState
    private let layerPipeline: any MTLRenderPipelineState
    private let ring: FrameSlotRing
    private var buffers: Buffers?

    init(context: GPUContext, pixelFormat: MTLPixelFormat) throws {
        self.context = context
        self.ring = try FrameSlotRing(device: context.device)

        let libraryDescriptor = MTL4LibraryDescriptor()
        libraryDescriptor.source = ShaderSource.layer
        let library: any MTLLibrary
        do {
            library = try context.compiler.makeLibrary(descriptor: libraryDescriptor)
        } catch {
            throw GPUContext.GPUError.compile("layer library: \(error)")
        }

        self.clearPipeline = try Self.computePipeline(
            compiler: context.compiler, library: library, name: "clear_counter"
        )
        self.runsPipeline = try Self.computePipeline(
            compiler: context.compiler, library: library, name: "runs"
        )
        self.encodePipeline = try Self.computePipeline(
            compiler: context.compiler, library: library, name: "encode_draw"
        )
        self.layerPipeline = try Self.renderPipeline(
            compiler: context.compiler, library: library, pixelFormat: pixelFormat
        )
    }

    /// Renders a GPU-resident frame. When `wait` is true the call blocks until
    /// the GPU finishes (tests).
    func render(
        gpu: GPUColorGrid,
        palette: Palette,
        into texture: MTLTexture,
        wait: Bool = false
    ) throws {
        let buffers = try prepare(cols: gpu.cols, rows: gpu.rows, cells: gpu.buffer)
        writePalette(palette, into: buffers)
        writeUniforms(cols: gpu.cols, rows: gpu.rows, into: buffers)

        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        guard let compute = slot.command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }
        encodeRuns(buffers, cols: gpu.cols, rows: gpu.rows, encoder: compute)
        encodeDraw(buffers, encoder: compute)
        // Publish the spans and draw arguments to the render encoder that
        // follows in the same command buffer.
        compute.barrier(afterStages: .dispatch, beforeQueueStages: .vertex, visibilityOptions: .device)
        compute.endEncoding()

        let pass = MTL4RenderPassDescriptor()
        guard let attachment = pass.colorAttachments[0] else {
            throw GPUContext.GPUError.resource("render pass color attachment")
        }
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        let background = palette[0]
        attachment.clearColor = MTLClearColor(
            red: Double(background.r),
            green: Double(background.g),
            blue: Double(background.b),
            alpha: Double(background.a)
        )
        guard let render = slot.command.makeRenderCommandEncoder(descriptor: pass) else {
            throw GPUContext.GPUError.resource("MTL4RenderCommandEncoder")
        }
        render.setRenderPipelineState(layerPipeline)
        render.setArgumentTable(buffers.renderTable, stages: .vertex)
        render.drawPrimitives(primitiveType: .triangle, indirectBuffer: buffers.arguments.gpuAddress)
        render.endEncoding()
        slot.command.endCommandBuffer()

        let done = wait ? DispatchSemaphore(value: 0) : nil
        let options = MTL4CommitOptions()
        options.addFeedbackHandler { _ in
            slot.allocator.reset()
            slot.release()
            done?.signal()
        }
        context.queue.commit([slot.command], options: options)
        done?.wait()
    }

    // MARK: - Private

    private func prepare(cols: Int, rows: Int, cells: any MTLBuffer) throws -> Buffers {
        let spanCapacity = max(1, cols * rows)
        // The reveal zooms continuously, so the grid grows a little each frame.
        // Grow geometrically when it outgrows the buffer, so a run reallocates
        // a handful of times instead of every frame.
        if let buffers, sameBuffer(buffers.cells, cells), buffers.spansCapacity >= spanCapacity {
            return buffers
        }
        let device = context.device
        let capacity = max(spanCapacity, (buffers?.spansCapacity ?? 0) * 3 / 2)
        var owned: [any MTLBuffer] = []
        guard let spans = device.makeBuffer(
                length: capacity * MemoryLayout<Span>.stride, options: .storageModeShared
              ),
              let counter = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let arguments = device.makeBuffer(
                length: MemoryLayout<DrawArguments>.stride, options: .storageModeShared
              ),
              let uniforms = device.makeBuffer(
                length: MemoryLayout<LayerUniforms>.stride, options: .storageModeShared
              ),
              let palette = device.makeBuffer(
                length: 16 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared
              ) else {
            throw GPUContext.GPUError.resource("layer buffers")
        }
        owned.append(contentsOf: [spans, counter, arguments, uniforms, palette])
        context.makeResident(owned)

        let buffers = Buffers(
            cells: cells,
            spans: spans,
            spansCapacity: capacity,
            counter: counter,
            arguments: arguments,
            uniforms: uniforms,
            palette: palette,
            clearTable: try makeTable(device: device, addresses: [counter], count: 1),
            runsTable: try makeTable(device: device, addresses: [cells, spans, counter, uniforms], count: 4),
            encodeTable: try makeTable(device: device, addresses: [counter, arguments], count: 2),
            renderTable: try makeTable(device: device, addresses: [spans, uniforms, palette], count: 3)
        )
        self.buffers = buffers
        return buffers
    }

    private func writePalette(_ palette: Palette, into buffers: Buffers) {
        var colors = [SIMD4<Float>](repeating: .zero, count: 16)
        for index in 0..<palette.count { colors[index] = palette[index].simd }
        colors.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                memcpy(buffers.palette.contents(), base, 16 * MemoryLayout<SIMD4<Float>>.stride)
            }
        }
    }

    private func writeUniforms(cols: Int, rows: Int, into buffers: Buffers) {
        var uniforms = LayerUniforms(cols: UInt32(cols), rows: UInt32(rows))
        memcpy(buffers.uniforms.contents(), &uniforms, MemoryLayout<LayerUniforms>.stride)
    }

    private func encodeRuns(
        _ buffers: Buffers,
        cols: Int,
        rows: Int,
        encoder: any MTL4ComputeCommandEncoder
    ) {
        let one = MTLSize(width: 1, height: 1, depth: 1)
        encoder.setArgumentTable(buffers.clearTable)
        encoder.setComputePipelineState(clearPipeline)
        encoder.dispatchThreads(threadsPerGrid: one, threadsPerThreadgroup: one)
        encoder.barrier(
            afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch, visibilityOptions: .device
        )
        encoder.setArgumentTable(buffers.runsTable)
        encoder.setComputePipelineState(runsPipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: cols, height: rows, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(16, cols), height: min(16, rows), depth: 1)
        )
        encoder.barrier(
            afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch, visibilityOptions: .device
        )
    }

    private func encodeDraw(_ buffers: Buffers, encoder: any MTL4ComputeCommandEncoder) {
        encoder.setArgumentTable(buffers.encodeTable)
        encoder.setComputePipelineState(encodePipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
    }

    private func sameBuffer(_ a: any MTLBuffer, _ b: any MTLBuffer) -> Bool {
        (a as AnyObject) === (b as AnyObject)
    }

    private func makeTable(device: any MTLDevice, addresses: [any MTLBuffer], count: Int) throws -> any MTL4ArgumentTable {
        let descriptor = MTL4ArgumentTableDescriptor()
        descriptor.maxBufferBindCount = count
        let table = try device.makeArgumentTable(descriptor: descriptor)
        for (index, buffer) in addresses.enumerated() {
            table.setAddress(buffer.gpuAddress, index: index)
        }
        return table
    }

    private static func computePipeline(
        compiler: any MTL4Compiler,
        library: any MTLLibrary,
        name: String
    ) throws -> any MTLComputePipelineState {
        let function = MTL4LibraryFunctionDescriptor()
        function.library = library
        function.name = name
        let descriptor = MTL4ComputePipelineDescriptor()
        descriptor.computeFunctionDescriptor = function
        do {
            return try compiler.makeComputePipelineState(descriptor: descriptor)
        } catch {
            throw GPUContext.GPUError.compile("\(name): \(error)")
        }
    }

    private static func renderPipeline(
        compiler: any MTL4Compiler,
        library: any MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> any MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "layer_vertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "layer_fragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        guard let attachment = descriptor.colorAttachments[0] else {
            throw GPUContext.GPUError.resource("layer pipeline color attachment")
        }
        attachment.pixelFormat = pixelFormat
        do {
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw GPUContext.GPUError.compile("layer pipeline: \(error)")
        }
    }
}
