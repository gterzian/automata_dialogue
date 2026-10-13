import Foundation
import Metal

/// A reusable per-frame command allocator and command buffer. `FrameSlotRing`
/// rotates three of them so frame N+1/N+2 could be encoded while the GPU runs
/// N. `MetalSimulation.commit` waits after every commit today, so the rotation
/// is structural until that wait is dropped (see `README.md`).
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

/// The GPU simulation core, sink-independent. It owns the
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
        var capacity: UInt32
        var inject: UInt32
        var injectSeed: UInt64
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
        var capacity: UInt32
        var viewportStart: UInt32
        var currentStep: UInt32
        var scrolling: UInt32
    }

    public let spec: ProgramSpec
    public let cols: Int
    public let rows: Int
    /// Total source rows in the run, including the seed (`min(board.height,
    /// stepLimit)` unless overridden). `Int.max` in scrolling mode, where the
    /// run has no end.
    public let totalSteps: Int
    /// A scrolling run keeps only the newest `rows + 2` source rows and maps
    /// display row `d` to source step `step - (rows - 1) + d`, so the newest
    /// row stays at the bottom. A non-scrolling run stretches its whole history
    /// across the display and stops at `totalSteps`.
    public let scrolling: Bool
    /// Which column mapping the grid uses; see `ColumnMapping`.
    public let mapping: ColumnMapping
    /// First source column shown by a `.window` mapping, clamped to
    /// `maxViewportOrigin`.
    public private(set) var viewportOrigin: Int
    /// True once the caller pans by hand; the entry's follow then stops for the
    /// rest of the run (a `reset` clears it).
    public private(set) var userPanned = false
    /// Fractional columns carried between frames while following a drifting
    /// pattern, so a sub-column rate does not round to zero.
    private var followCarry = 0.0
    /// Source row currently computed (0 is the seed).
    public private(set) var step = 0
    /// Index of the frame slot that produced the last `render` call.
    public private(set) var lastSlot = 0

    /// The origin a `reset()` returns to (rightmost for a right-pinned entry).
    private let startOrigin: Int

    private let context: GPUContext
    private let width: Int
    /// The board the run simulates. Wider than the catalog board when the
    /// review window needs room to pan; see `ViewportGeometry.boardWidth`.
    private let board: Board
    /// Rows the history buffer holds; the source step indexes it modulo this.
    private let capacity: Int
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
        context: GPUContext,
        scrolling: Bool = false,
        mapping: ColumnMapping = .fit,
        board: Board? = nil
    ) throws {
        let displayCols = max(1, cols)
        let displayRows = max(1, rows)
        let runBoard = board ?? spec.board
        let nominalSteps = max(1, steps ?? min(runBoard.height, spec.display.stepLimit))
        let width = runBoard.width
        let device = context.device
        // A scrolling run only ever reads the last `rows` rows, so its history
        // is a ring of that size; a stretched run needs the whole history.
        let capacity = scrolling ? displayRows + 2 : nominalSteps

        guard let history = device.makeBuffer(length: max(1, capacity * width), options: .storageModeShared),
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
        case .k2r2(let codeValue):
            pipeline = context.stepK2R2
            rule = UInt32(codeValue)
            colors = 0
        }

        self.spec = spec
        self.cols = displayCols
        self.rows = displayRows
        self.totalSteps = scrolling ? Int.max : nominalSteps
        self.scrolling = scrolling
        self.mapping = mapping
        self.context = context
        self.width = width
        self.board = runBoard
        self.capacity = capacity
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
        // A `.window` mapping shows one cell per column at a movable origin, so
        // a board wider than the display pans instead of being downsampled.
        let startOrigin = mapping == .window
            ? ViewportGeometry.initialOrigin(
                boardWidth: width, cols: displayCols, start: runBoard.start,
                pinRight: spec.display.pinRight)
            : fit.sourceOrigin
        self.startOrigin = startOrigin
        self.viewportOrigin = startOrigin

        var stepParams = StepParams(
            width: UInt32(width), rule: rule, colors: colors, capacity: UInt32(capacity),
            inject: runBoard.injection == nil ? 0 : 1,
            injectSeed: runBoard.injection?.seed ?? 0)
        memcpy(stepBuffer.contents(), &stepParams, MemoryLayout<StepParams>.stride)
        self.fitParams = FitParams(
            boardWidth: UInt32(width),
            displayCols: UInt32(displayCols),
            displayRows: UInt32(displayRows),
            totalSteps: UInt32(clamping: nominalSteps),
            block: UInt32(mapping == .window ? 1 : fit.block),
            sourceOrigin: UInt32(startOrigin),
            padLeft: UInt32(mapping == .window ? 0 : fit.padLeft),
            rowOffset: 0,
            capacity: UInt32(capacity),
            viewportStart: 0,
            currentStep: 0,
            scrolling: scrolling ? 1 : 0
        )
        memcpy(fitBuffer.contents(), &fitParams, MemoryLayout<FitParams>.stride)

        reseed()
    }

    /// Largest `viewportOrigin` a `.window` mapping can pan to; 0 for `.fit`.
    public var maxViewportOrigin: Int {
        mapping == .window ? max(0, width - cols) : 0
    }

    /// Shifts a `.window` mapping `delta` source columns, clamped to the board.
    /// A manual pan also aborts the entry's follow for the rest of the run; the
    /// caller re-fits (`advance(chunk: 0)`) to show the new window.
    public func pan(by delta: Int) {
        guard mapping == .window else { return }
        userPanned = true
        moveOrigin(by: delta)
    }

    private func moveOrigin(by delta: Int) {
        let origin = min(max(0, viewportOrigin + delta), maxViewportOrigin)
        guard origin != viewportOrigin else { return }
        viewportOrigin = origin
        fitParams.sourceOrigin = UInt32(origin)
        memcpy(fitBuffer.contents(), &fitParams, MemoryLayout<FitParams>.stride)
    }

    /// Pans the viewport by the entry's follow rate for `steps` source steps.
    /// A manual pan, a `.fit` mapping, or a zero rate leaves the view fixed.
    private func follow(by steps: Int) {
        let rate = spec.display.follow.columnsPerStep
        guard rate != 0, mapping == .window, !userPanned else { return }
        followCarry += rate * Double(steps)
        let whole = Int(followCarry.rounded(.towardZero))
        guard whole != 0 else { return }
        followCarry -= Double(whole)
        moveOrigin(by: whole)
    }

    /// Returns the simulation to the seed row (step 0), resets the horizontal
    /// origin, and clears the grid. `program` supplies a different seed row (a
    /// `.rand` replay); the buffers are reused.
    public func reset(program: (any RowProgram)? = nil) {
        userPanned = false
        followCarry = 0
        viewportOrigin = startOrigin
        fitParams.sourceOrigin = UInt32(startOrigin)
        memcpy(fitBuffer.contents(), &fitParams, MemoryLayout<FitParams>.stride)
        reseed(program: program)
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
    /// the buffer directly and compacts only the new rows.
    @discardableResult
    public func renderGPU(chunk: Int) throws -> GPUColorGrid {
        // A scrolling frame refits every display row (the window moves), so it
        // always starts at row 0 and a sink must recompact the whole grid. A
        // stretched frame only fits the rows that just became ready.
        let firstRow = scrolling ? 0 : fittedRows
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
    /// the number of display rows fitted by this frame.
    @discardableResult
    func advance(chunk: Int) throws -> Int {
        let requested = max(0, chunk)
        let target = scrolling
            ? step + requested
            : min(totalSteps - 1, step + requested)
        if scrolling { follow(by: target - step) }
        let (index, slot) = ring.borrow()
        lastSlot = index

        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        guard let encoder = slot.command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }
        encodeSteps(from: step, to: target, encoder: encoder)
        if scrolling {
            fitParams.viewportStart = UInt32(max(0, target - (rows - 1)))
            fitParams.currentStep = UInt32(clamping: target)
            encodeFit(from: 0, to: rows, encoder: encoder)
            fittedRows = rows
        } else {
            let ready = readyRowCount(at: target)
            encodeFit(from: fittedRows, to: ready, encoder: encoder)
            fittedRows = ready
        }
        encoder.endEncoding()
        slot.command.endCommandBuffer()

        try commit(slot)
        step = target
        return fittedRows
    }

    // MARK: - Private

    private func reseed(program: (any RowProgram)? = nil) {
        step = 0
        fittedRows = 0
        let seed = (program ?? spec.reference(board)).row()
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
