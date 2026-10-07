import Foundation
import Metal

/// Encodes a fitted `ColorGrid` into a render target: a `runs` kernel compacts
/// each non-background run of same-coloured cells into a `Span`, an
/// `encode_draw` kernel writes the indirect draw arguments on the GPU, and a
/// render pass clears to the background colour and draws one quad per span
/// (design doc §6). Draw cost therefore follows the structure, not the grid
/// area. The same code path serves a `CAMetalLayer` drawable and the offscreen
/// test texture.
///
/// Two entry points share the span buffer and its counter:
/// - `render(grid:)` uploads a CPU grid and recompacts every row (background
///   path, offscreen tests, a `LayerSink` fed a readback frame).
/// - `render(gpu:)` binds a `GPUColorGrid` directly and compacts only its new
///   rows, appending to the spans already accumulated. Display rows never
///   change once fitted, so the accumulated spans stay valid (design doc §7).
@available(macOS 26.0, *)
final class LayerRenderer {
    /// Mirrors the `Span` struct in `ShaderSource.layer`.
    struct Span: Equatable {
        var row: UInt32
        var start: UInt32
        var length: UInt32
        var color: UInt32
    }

    private struct LayerUniforms {
        var cols: UInt32
        var rows: UInt32
        var rowOffset: UInt32
        // Explicit padding keeps the constant buffer 16-byte aligned, matching
        // the MSL struct.
        var padding: UInt32 = 0
    }

    private struct DrawArguments {
        var vertexCount: UInt32
        var instanceCount: UInt32
        var vertexStart: UInt32
        var baseInstance: UInt32
    }

    private struct Buffers {
        let cells: any MTLBuffer
        /// True when `cells` is the caller's buffer (GPU-resident path) rather
        /// than one this renderer allocated.
        let cellsExternal: Bool
        let spans: any MTLBuffer
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
    private var size: (cols: Int, rows: Int)?

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

    /// Renders `grid` into `texture`. When `wait` is true the call blocks until
    /// the GPU finishes, so the caller may read the texture back (tests).
    func render(grid: ColorGrid, palette: Palette, into texture: MTLTexture, wait: Bool = false) throws {
        let buffers = try prepare(cols: grid.cols, rows: grid.rows, externalCells: nil)
        writeCells(grid, into: buffers)
        writePalette(palette, into: buffers)
        writeUniforms(cols: grid.cols, rows: grid.rows, rowOffset: 0, into: buffers)
        try render(
            buffers: buffers,
            cols: grid.cols,
            rowRange: 0..<grid.rows,
            reset: true,
            palette: palette,
            into: texture,
            wait: wait
        )
    }

    /// Renders a GPU-resident frame. Only `gpu.rowCount` rows starting at
    /// `gpu.firstRow` are compacted; the rest of the spans were accumulated by
    /// earlier frames. A frame that starts a run (`firstRow == 0`) resets the
    /// counter first. When `wait` is true the call blocks until the GPU
    /// finishes (tests).
    func render(gpu: GPUColorGrid, palette: Palette, into texture: MTLTexture, wait: Bool = false) throws {
        let buffers = try prepare(cols: gpu.cols, rows: gpu.rows, externalCells: gpu.buffer)
        writePalette(palette, into: buffers)
        writeUniforms(cols: gpu.cols, rows: gpu.rows, rowOffset: gpu.firstRow, into: buffers)
        try render(
            buffers: buffers,
            cols: gpu.cols,
            rowRange: gpu.firstRow..<(gpu.firstRow + gpu.rowCount),
            reset: gpu.startsRun,
            palette: palette,
            into: texture,
            wait: wait
        )
    }

    /// Runs the span compaction alone and reads the spans back. Used by tests to
    /// assert the kernel matches a CPU run-length pass.
    func spans(for grid: ColorGrid) throws -> [Span] {
        let buffers = try prepare(cols: grid.cols, rows: grid.rows, externalCells: nil)
        writeCells(grid, into: buffers)
        writeUniforms(cols: grid.cols, rows: grid.rows, rowOffset: 0, into: buffers)

        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        guard let compute = slot.command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }
        encodeRuns(buffers, cols: grid.cols, rowRange: 0..<grid.rows, reset: true, encoder: compute)
        compute.endEncoding()
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
        return readSpans(from: buffers)
    }

    /// The spans accumulated by the last frame, in GPU order. Test hook for the
    /// incremental path; the caller must have waited for the GPU.
    func accumulatedSpans() -> [Span] {
        guard let buffers else { return [] }
        return readSpans(from: buffers)
    }

    // MARK: - Private

    private func render(
        buffers: Buffers,
        cols: Int,
        rowRange: Range<Int>,
        reset: Bool,
        palette: Palette,
        into texture: MTLTexture,
        wait: Bool
    ) throws {
        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        guard let compute = slot.command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }
        encodeRuns(buffers, cols: cols, rowRange: rowRange, reset: reset, encoder: compute)
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

    private func prepare(cols: Int, rows: Int, externalCells: (any MTLBuffer)?) throws -> Buffers {
        if let buffers, let size, size == (cols, rows),
           buffers.cellsExternal == (externalCells != nil),
           externalCells == nil || sameBuffer(buffers.cells, externalCells) {
            return buffers
        }
        let device = context.device
        let spanCapacity = cols * rows
        let cells: any MTLBuffer
        var owned: [any MTLBuffer] = []
        if let externalCells {
            cells = externalCells
        } else {
            guard let made = device.makeBuffer(length: cols * rows, options: .storageModeShared) else {
                throw GPUContext.GPUError.resource("layer cells")
            }
            cells = made
            owned.append(made)
        }
        guard let spans = device.makeBuffer(
                length: max(1, spanCapacity) * MemoryLayout<Span>.stride, options: .storageModeShared
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
            cellsExternal: externalCells != nil,
            spans: spans,
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
        self.size = (cols, rows)
        return buffers
    }

    private func writeCells(_ grid: ColorGrid, into buffers: Buffers) {
        grid.cells.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { memcpy(buffers.cells.contents(), base, grid.cells.count) }
        }
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

    private func writeUniforms(cols: Int, rows: Int, rowOffset: Int, into buffers: Buffers) {
        var uniforms = LayerUniforms(cols: UInt32(cols), rows: UInt32(rows), rowOffset: UInt32(rowOffset))
        memcpy(buffers.uniforms.contents(), &uniforms, MemoryLayout<LayerUniforms>.stride)
    }

    private func encodeRuns(
        _ buffers: Buffers,
        cols: Int,
        rowRange: Range<Int>,
        reset: Bool,
        encoder: any MTL4ComputeCommandEncoder
    ) {
        if reset {
            let one = MTLSize(width: 1, height: 1, depth: 1)
            encoder.setArgumentTable(buffers.clearTable)
            encoder.setComputePipelineState(clearPipeline)
            encoder.dispatchThreads(threadsPerGrid: one, threadsPerThreadgroup: one)
            encoder.barrier(
                afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch, visibilityOptions: .device
            )
        }
        guard !rowRange.isEmpty else { return }
        encoder.setArgumentTable(buffers.runsTable)
        encoder.setComputePipelineState(runsPipeline)
        let rowCount = rowRange.count
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: cols, height: rowCount, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(16, cols), height: min(16, rowCount), depth: 1)
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

    private func readSpans(from buffers: Buffers) -> [Span] {
        let count = buffers.counter.contents().bindMemory(to: UInt32.self, capacity: 1).pointee
        let pointer = buffers.spans.contents().bindMemory(to: Span.self, capacity: Int(count))
        // SAFETY: `runs` wrote exactly `count` spans (the counter accumulates
        // one per run start) into a buffer sized for every cell, so the typed
        // pointer and count stay in bounds.
        return Array(UnsafeBufferPointer(start: pointer, count: Int(count)))
    }

    private func sameBuffer(_ a: any MTLBuffer, _ b: any MTLBuffer?) -> Bool {
        guard let b else { return false }
        return (a as AnyObject) === (b as AnyObject)
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
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw GPUContext.GPUError.compile("layer pipeline: \(error)")
        }
    }
}
