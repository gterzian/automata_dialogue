import Foundation
import Metal

/// A reusable per-frame command allocator and command buffer. `FrameSlotRing`
/// rotates three of them so a sink that does not wait on readback can encode
/// frame N+1/N+2 while the GPU runs N (design doc §11.8). The readback path
/// waits after every commit, so the rotation is structural today; a
/// `LayerSink` returns from its drawable callback and lets the ring overlap.
@available(macOS 26.0, *)
final class FrameSlot: @unchecked Sendable {
    let allocator: any MTL4CommandAllocator
    let command: any MTL4CommandBuffer
    private let available = DispatchSemaphore(value: 1)

    init(device: any MTLDevice, label: String) throws {
        guard let allocator = device.makeCommandAllocator(),
              let command = device.makeCommandBuffer() else {
            throw GPUContext.GPUError.resource("frame slot \(label)")
        }
        self.allocator = allocator
        self.command = command
    }

    /// Waits until the slot's previous frame has finished on the GPU.
    func acquire() { available.wait() }

    /// Returns the slot to the ring. Called when the GPU finishes the frame.
    func release() { available.signal() }
}

@available(macOS 26.0, *)
final class FrameSlotRing {
    private let slots: [FrameSlot]
    private var next = 0

    init(device: any MTLDevice, count: Int = 3) throws {
        var slots: [FrameSlot] = []
        for index in 0..<max(1, count) {
            slots.append(try FrameSlot(device: device, label: "\(index)"))
        }
        self.slots = slots
    }

    func borrow() -> (index: Int, slot: FrameSlot) {
        let index = next
        let slot = slots[index]
        next = (next + 1) % slots.count
        slot.acquire()
        return (index, slot)
    }
}

/// The GPU simulation core, sink-independent (design doc §6). It owns the
/// history buffer, the GPU-side `head` counter, and the `step`/`fit` kernels,
/// and advances a caller-sized chunk of source rows so a caller can animate
/// instead of running the whole board in one commit. `render(chunk:)` produces
/// exactly the grid `IncrementalRenderer` would for the same step count;
/// `MetalTests` and `RenderActorTests` assert that.
@available(macOS 26.0, *)
public final class MetalSimulation {
    private struct StepParams {
        var width: UInt32
        var rule: UInt32
        var colors: UInt32
    }

    private struct FitParams {
        var boardWidth: UInt32
        var displayCols: UInt32
        var displayRows: UInt32
        var totalSteps: UInt32
        var block: UInt32
        var sourceOrigin: UInt32
        var padLeft: UInt32
        var rowOffset: UInt32
    }

    public let spec: ProgramSpec
    public let cols: Int
    public let rows: Int
    /// Total source rows in the run, including the seed (`min(board.height,
    /// stepLimit)` unless overridden).
    public let totalSteps: Int
    /// Source row currently computed (0 is the seed).
    public private(set) var step = 0
    /// Index of the frame slot that produced the last `render` call.
    public private(set) var lastSlot = 0

    private let context: GPUContext
    private let width: Int
    private let history: any MTLBuffer
    private let colorBuffer: any MTLBuffer
    private let stepBuffer: any MTLBuffer
    private let fitBuffer: any MTLBuffer
    private let headBuffer: any MTLBuffer
    private let stepTable: any MTL4ArgumentTable
    private let bumpTable: any MTL4ArgumentTable
    private let fitTable: any MTL4ArgumentTable
    private let stepPipeline: any MTLComputePipelineState
    private let ring: FrameSlotRing
    /// Display rows already written into `colorBuffer`; a frame only fits the
    /// rows that became ready since the last one.
    private var fittedRows = 0
    private var fitParams: FitParams

    public init(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        steps: Int? = nil,
        context: GPUContext
    ) throws {
        let displayCols = max(1, cols)
        let displayRows = max(1, rows)
        let totalSteps = max(1, steps ?? min(spec.board.height, spec.display.stepLimit))
        let width = spec.board.width
        let device = context.device

        guard let history = device.makeBuffer(length: max(1, totalSteps * width), options: .storageModeShared),
              let colorBuffer = device.makeBuffer(length: displayCols * displayRows, options: .storageModeShared),
              let stepBuffer = device.makeBuffer(length: MemoryLayout<StepParams>.stride, options: .storageModeShared),
              let fitBuffer = device.makeBuffer(length: MemoryLayout<FitParams>.stride, options: .storageModeShared),
              let headBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
            throw GPUContext.GPUError.resource("simulation buffers")
        }
        context.makeResident([history, colorBuffer, stepBuffer, fitBuffer, headBuffer])

        let pipeline: any MTLComputePipelineState
        let rule: UInt32
        let colors: UInt32
        switch spec.gpu {
        case .elementary(let ruleValue):
            pipeline = context.stepElementary
            rule = UInt32(ruleValue)
            colors = 0
        case .totalistic(let code, let colorCount):
            pipeline = context.stepTotalistic
            rule = code
            colors = UInt32(colorCount)
        }

        self.spec = spec
        self.cols = displayCols
        self.rows = displayRows
        self.totalSteps = totalSteps
        self.context = context
        self.width = width
        self.history = history
        self.colorBuffer = colorBuffer
        self.stepBuffer = stepBuffer
        self.fitBuffer = fitBuffer
        self.headBuffer = headBuffer
        self.stepPipeline = pipeline
        self.ring = try FrameSlotRing(device: device)

        self.stepTable = try Self.makeTable(device: device, history: history, second: stepBuffer, third: headBuffer)
        self.bumpTable = try Self.makeTable(device: device, history: headBuffer, second: nil, third: nil)
        self.fitTable = try Self.makeTable(device: device, history: history, second: colorBuffer, third: fitBuffer)

        let fit = Fit(boardWidth: width, displayCols: displayCols, pinRight: spec.display.pinRight)

        var stepParams = StepParams(width: UInt32(width), rule: rule, colors: colors)
        memcpy(stepBuffer.contents(), &stepParams, MemoryLayout<StepParams>.stride)
        self.fitParams = FitParams(
            boardWidth: UInt32(width),
            displayCols: UInt32(displayCols),
            displayRows: UInt32(displayRows),
            totalSteps: UInt32(totalSteps),
            block: UInt32(fit.block),
            sourceOrigin: UInt32(fit.sourceOrigin),
            padLeft: UInt32(fit.padLeft),
            rowOffset: 0
        )
        memcpy(fitBuffer.contents(), &fitParams, MemoryLayout<FitParams>.stride)

        reseed()
    }

    /// Returns the simulation to the seed row (step 0) and clears the grid.
    public func reset() {
        reseed()
    }

    /// Advances up to `count` source rows and returns the grid at the new
    /// position. Display rows whose target step has not been reached stay at
    /// the background palette index, matching `IncrementalRenderer`.
    @discardableResult
    public func render(chunk: Int) throws -> ColorGrid {
        try advance(chunk: chunk)
        return readColorGrid()
    }

    /// Advances without reading the grid back, returning the run's GPU color
    /// buffer and the display rows this call fitted. A GPU-resident sink binds
    /// the buffer directly and compacts only the new rows (design doc §7).
    @discardableResult
    public func renderGPU(chunk: Int) throws -> GPUColorGrid {
        let firstRow = fittedRows
        try advance(chunk: chunk)
        return GPUColorGrid(
            buffer: colorBuffer,
            cols: cols,
            rows: rows,
            firstRow: firstRow,
            rowCount: fittedRows - firstRow
        )
    }

    /// Encodes the step and fit work for `chunk` rows and commits it. Returns
    /// the number of display rows fitted so far.
    @discardableResult
    func advance(chunk: Int) throws -> Int {
        let target = min(totalSteps - 1, step + max(0, chunk))
        let (index, slot) = ring.borrow()
        lastSlot = index

        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        guard let encoder = slot.command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }
        encodeSteps(from: step, to: target, encoder: encoder)
        let ready = readyRowCount(at: target)
        encodeFit(from: fittedRows, to: ready, encoder: encoder)
        fittedRows = ready
        encoder.endEncoding()
        slot.command.endCommandBuffer()

        try commit(slot)
        step = target
        return ready
    }

    // MARK: - Private

    private func reseed() {
        step = 0
        fittedRows = 0
        let seed = spec.makeProgram().row()
        seed.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { memcpy(history.contents(), base, width) }
        }
        var head: UInt32 = 0
        memcpy(headBuffer.contents(), &head, MemoryLayout<UInt32>.stride)
        memset(colorBuffer.contents(), 0, cols * rows)
    }

    private func encodeSteps(from: Int, to: Int, encoder: any MTL4ComputeCommandEncoder) {
        guard to > from else { return }
        let stepThreads = MTLSize(width: min(64, width), height: 1, depth: 1)
        for _ in from..<to {
            encoder.setArgumentTable(stepTable)
            encoder.setComputePipelineState(stepPipeline)
            encoder.dispatchThreads(
                threadsPerGrid: MTLSize(width: width, height: 1, depth: 1),
                threadsPerThreadgroup: stepThreads
            )
            encoder.barrier(
                afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch, visibilityOptions: .device
            )
            encoder.setArgumentTable(bumpTable)
            encoder.setComputePipelineState(context.bumpHead)
            encoder.dispatchThreads(
                threadsPerGrid: MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
            )
            encoder.barrier(
                afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch, visibilityOptions: .device
            )
        }
    }

    private func encodeFit(from: Int, to: Int, encoder: any MTL4ComputeCommandEncoder) {
        guard to > from else { return }
        fitParams.rowOffset = UInt32(from)
        memcpy(fitBuffer.contents(), &fitParams, MemoryLayout<FitParams>.stride)
        encoder.setArgumentTable(fitTable)
        encoder.setComputePipelineState(context.fitPipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: cols, height: to - from, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(16, cols), height: min(16, to - from), depth: 1
            )
        )
    }

    /// Number of display rows whose target source step has been reached. The
    /// mapping matches `IncrementalRenderer.targetStep`.
    private func readyRowCount(at step: Int) -> Int {
        var ready = 0
        for displayRow in 0..<rows {
            let target = rows == 1 ? totalSteps - 1 : (displayRow * (totalSteps - 1)) / (rows - 1)
            if target > step { break }
            ready += 1
        }
        return ready
    }

    private func commit(_ slot: FrameSlot) throws {
        let done = DispatchSemaphore(value: 0)
        let options = MTL4CommitOptions()
        options.addFeedbackHandler { _ in done.signal() }
        context.queue.commit([slot.command], options: options)
        done.wait()
        slot.allocator.reset()
        slot.release()
    }

    private func readColorGrid() -> ColorGrid {
        let pointer = colorBuffer.contents().bindMemory(to: UInt8.self, capacity: cols * rows)
        // SAFETY: the commit feedback handler has fired, so the GPU is done
        // writing `colorBuffer`; the buffer is `.storageModeShared` and was
        // allocated with exactly `cols * rows` bytes, so the typed pointer and
        // the count stay in bounds.
        let cells = Array(UnsafeBufferPointer(start: pointer, count: cols * rows))
        return ColorGrid(cols: cols, rows: rows, cells: cells)
    }

    private static func makeTable(
        device: any MTLDevice,
        history: any MTLBuffer,
        second: (any MTLBuffer)?,
        third: (any MTLBuffer)?
    ) throws -> any MTL4ArgumentTable {
        let descriptor = MTL4ArgumentTableDescriptor()
        descriptor.maxBufferBindCount = 3
        let table = try device.makeArgumentTable(descriptor: descriptor)
        table.setAddress(history.gpuAddress, index: 0)
        if let second { table.setAddress(second.gpuAddress, index: 1) }
        if let third { table.setAddress(third.gpuAddress, index: 2) }
        return table
    }
}
