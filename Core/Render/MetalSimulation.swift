import Foundation
import Metal

/// A reusable per-frame command allocator and command buffer. `FrameSlotRing`
/// rotates three of them so frame N+1/N+2 could be encoded while the GPU runs
/// N. `MetalSimulation` waits after every commit today, so the rotation is
/// structural until that wait is dropped (see `README.md`).
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

/// The GPU simulation core, sink-independent. It owns the history buffer, the
/// GPU-side `head` counter, and the `seed`/`step`/`fit` kernels, and advances a
/// caller-sized chunk of source rows so a caller can animate instead of running
/// the whole board in one commit.
///
/// The run is a window over a board much wider than the display: it keeps only
/// the newest `capacity` source rows in a ring and maps display row `d` to a
/// source step at or before the newest one, so a short board grows from the top
/// and then the window follows the newest row without an end. A twin run maps
/// one history into two mirrored branches around a shared horizon row instead.
/// `setZoom` resizes the display grid and the viewport, reusing the same ring
/// and color buffer.
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

    private struct ViewParams {
        var boardWidth: UInt32
        var displayCols: UInt32
        var displayRows: UInt32
        var capacity: UInt32
        var viewportStart: UInt32
        var viewportOrigin: UInt32
        var currentStep: UInt32
        var topRows: UInt32
    }

    private struct SeedParams {
        var width: UInt32
        var colors: UInt32
        var mode: UInt32
        var blockLength: UInt32
        var number: UInt32
        var density: Float
        var seed: UInt64
    }

    public let spec: ProgramSpec
    /// Current display grid, resized by `setZoom`.
    public private(set) var cols: Int
    public private(set) var rows: Int
    /// Grid at zoom 1; a zoom scales it.
    private let baseCols: Int
    private let baseRows: Int
    /// First source column the window shows, clamped to `maxViewportOrigin`.
    public private(set) var viewportOrigin: Int
    /// Display cells per board cell; see `ViewportGeometry.zoomFloor`.
    public private(set) var zoom = 1.0
    /// The widest zoom-out this run allows, chosen from the display.
    public let minimumZoom: Double
    /// The reveal's two-branch mapping: one shared horizon row, with the upper
    /// branch growing up and the lower growing down from it.
    public let twin: Bool
    /// Rows from the shared horizon to each outer edge.
    public private(set) var twinHalfRows = 0
    /// True once the caller pans by hand; the entry's follow then stops for the
    /// rest of the run.
    private var userPanned = false
    /// Source row currently computed (0 is the seed).
    private var step = 0

    /// Source rows computed so far; the reveal camera reads it to decide when
    /// to pull back.
    public var steppedRows: Int { step }

    /// The origin a `reseed` returns to (rightmost for a right-pinned entry).
    private var startOrigin: Int

    private let context: GPUContext
    private let width: Int
    /// The board the run simulates. Wider than the catalog board when the
    /// review window needs room to pan; see `ViewportGeometry.boardWidth`.
    private let board: Board
    /// Source rows the history ring holds; a step indexes it modulo this. Sized
    /// for the widest zoom-out so zooming never reallocates the ring.
    private let capacity: Int
    private let history: any MTLBuffer
    private let colorBuffer: any MTLBuffer
    private let stepBuffer: any MTLBuffer
    private let viewBuffer: any MTLBuffer
    private let seedBuffer: any MTLBuffer
    private let blockBuffer: any MTLBuffer
    private let headBuffer: any MTLBuffer
    private let stepTable: any MTL4ArgumentTable
    private let bumpTable: any MTL4ArgumentTable
    private let fitTable: any MTL4ArgumentTable
    private let seedTable: any MTL4ArgumentTable
    private let stepPipeline: any MTLComputePipelineState
    private let ring: FrameSlotRing
    /// Board column of the seed's leading edge in the follow direction. The
    /// viewport only scrolls once the growing edge reaches a viewport boundary,
    /// so the pattern is never pushed out of view.
    private var leadAnchor = 0.0
    private var stepParams: StepParams
    private var viewParams: ViewParams

    public init(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        context: GPUContext,
        board: Board? = nil,
        minimumZoom: Double = 1.0,
        twin: Bool = false
    ) throws {
        let displayCols = max(1, cols)
        // The twin layout needs an odd row count so exactly one row sits on the
        // horizon and both branches mirror around it.
        let displayRows = twin
            ? ViewportGeometry.twinRows(baseRows: max(1, rows), zoom: 1)
            : max(1, rows)
        let runBoard = board ?? spec.board
        let width = runBoard.width
        let device = context.device
        let runMinimumZoom = min(max(minimumZoom, ViewportGeometry.minimumZoomLimit), 1.0)
        // Size the ring and the grid for the widest zoom-out, so a zoom later
        // never reallocates the buffers or rebinds the fit table.
        let maxCols = ViewportGeometry.zoomedColumns(
            baseCols: displayCols, zoom: runMinimumZoom)
        let maxRows = twin
            ? ViewportGeometry.twinRows(baseRows: displayRows, zoom: runMinimumZoom)
            : ViewportGeometry.zoomedRows(baseRows: displayRows, zoom: runMinimumZoom)
        let capacity = maxRows + 2
        let halfRows = twin ? ViewportGeometry.twinHalfRows(rows: displayRows) : 0

        guard let history = device.makeBuffer(length: max(1, capacity * width), options: .storageModeShared),
              let colorBuffer = device.makeBuffer(length: max(1, maxCols * maxRows), options: .storageModeShared),
              let stepBuffer = device.makeBuffer(length: MemoryLayout<StepParams>.stride, options: .storageModeShared),
              let viewBuffer = device.makeBuffer(length: MemoryLayout<ViewParams>.stride, options: .storageModeShared),
              let seedBuffer = device.makeBuffer(length: MemoryLayout<SeedParams>.stride, options: .storageModeShared),
              let blockBuffer = device.makeBuffer(length: max(1, width), options: .storageModeShared),
              let headBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
            throw GPUContext.GPUError.resource("simulation buffers")
        }
        context.makeResident([history, colorBuffer, stepBuffer, viewBuffer, seedBuffer, blockBuffer, headBuffer])

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
        self.baseCols = displayCols
        self.baseRows = displayRows
        self.minimumZoom = runMinimumZoom
        self.twin = twin
        self.twinHalfRows = halfRows
        self.context = context
        self.width = width
        self.board = runBoard
        self.capacity = capacity
        self.history = history
        self.colorBuffer = colorBuffer
        self.stepBuffer = stepBuffer
        self.viewBuffer = viewBuffer
        self.seedBuffer = seedBuffer
        self.blockBuffer = blockBuffer
        self.headBuffer = headBuffer
        self.stepPipeline = pipeline
        self.ring = try FrameSlotRing(device: device)

        self.stepTable = try Self.makeTable(device: device, history: history, second: stepBuffer, third: headBuffer)
        self.bumpTable = try Self.makeTable(device: device, history: headBuffer, second: nil, third: nil)
        self.fitTable = try Self.makeTable(device: device, history: history, second: colorBuffer, third: viewBuffer)
        self.seedTable = try Self.makeTable(device: device, history: history, second: seedBuffer, third: blockBuffer)

        let startOrigin = ViewportGeometry.initialOrigin(
            boardWidth: width, cols: displayCols, start: runBoard.start,
            pinRight: spec.display.pinRight)
        self.startOrigin = startOrigin
        self.viewportOrigin = startOrigin

        self.stepParams = StepParams(
            width: UInt32(width), rule: rule, colors: colors, capacity: UInt32(capacity),
            inject: runBoard.injection == nil ? 0 : 1,
            injectSeed: runBoard.injection?.seed ?? 0)
        self.viewParams = ViewParams(
            boardWidth: UInt32(width),
            displayCols: UInt32(displayCols),
            displayRows: UInt32(displayRows),
            capacity: UInt32(capacity),
            viewportStart: 0,
            viewportOrigin: UInt32(startOrigin),
            currentStep: 0,
            topRows: UInt32(halfRows))

        try reseed()
    }

    /// Largest `viewportOrigin` the window can pan to.
    private var maxViewportOrigin: Int {
        max(0, width - cols)
    }

    /// Shifts the window `delta` source columns, clamped to the board. A manual
    /// pan also aborts the entry's follow for the rest of the run; the caller
    /// re-fits (`renderGPU(chunk: 0)`) to show the new window.
    public func pan(by delta: Int) {
        userPanned = true
        setOrigin(viewportOrigin + delta)
    }

    /// Resizes the display grid for `value`, keeping the board column at the
    /// viewport's centre fixed. Clamped to this run's floor; the caller re-fits
    /// (`renderGPU(chunk: 0)`) to show the new view.
    public func setZoom(_ value: Double) {
        let clamped = min(max(value, minimumZoom), ViewportGeometry.maximumZoom)
        guard clamped != zoom else { return }
        let centre = Double(viewportOrigin) + Double(cols) / 2
        zoom = clamped
        cols = ViewportGeometry.zoomedColumns(baseCols: baseCols, zoom: clamped)
        rows = twin
            ? ViewportGeometry.twinRows(baseRows: baseRows, zoom: clamped)
            : ViewportGeometry.zoomedRows(baseRows: baseRows, zoom: clamped)
        twinHalfRows = twin ? ViewportGeometry.twinHalfRows(rows: rows) : 0
        startOrigin = ViewportGeometry.initialOrigin(
            boardWidth: width, cols: cols, start: board.start, pinRight: spec.display.pinRight)
        viewportOrigin = min(
            max(0, Int((centre - Double(cols) / 2).rounded())), maxViewportOrigin)
        viewParams.displayCols = UInt32(cols)
        viewParams.displayRows = UInt32(rows)
        viewParams.viewportOrigin = UInt32(viewportOrigin)
        viewParams.topRows = UInt32(twinHalfRows)
        memcpy(viewBuffer.contents(), &viewParams, MemoryLayout<ViewParams>.stride)
    }

    private func setOrigin(_ origin: Int) {
        let clamped = min(max(0, origin), maxViewportOrigin)
        guard clamped != viewportOrigin else { return }
        viewportOrigin = clamped
        viewParams.viewportOrigin = UInt32(clamped)
        memcpy(viewBuffer.contents(), &viewParams, MemoryLayout<ViewParams>.stride)
    }

    /// Scrolls the viewport as the pattern's leading edge advances, but only
    /// once that edge would leave the viewport: while the edge is still inside,
    /// the origin does not move. The edge is `leadAnchor` moved by the entry's
    /// signed rate, so a left-growing pattern is not pushed off the right.
    private func follow(to currentStep: Int) {
        let rate = spec.display.follow.columnsPerStep
        guard rate != 0, !userPanned else { return }
        let lead = leadAnchor + rate * Double(currentStep)
        let raw = rate > 0
            ? max(Double(startOrigin), lead - Double(cols - 1))
            : min(Double(startOrigin), lead)
        setOrigin(Int(raw.rounded()))
    }

    /// Regenerates the seed row on the GPU, resets the head counter and grid,
    /// and clears any manual pan. `seed` reseeds a random start and injected
    /// randomness (a `.rand` replay); other starts ignore it.
    public func reseed(seed: UInt64? = nil) throws {
        var start = board.start
        var injectionSeed = board.injection?.seed
        if let seed {
            if case .random(_, let density) = start {
                start = .random(seed: seed, density: density)
            }
            if board.injection != nil { injectionSeed = seed }
        }

        stepParams.inject = board.injection == nil ? 0 : 1
        stepParams.injectSeed = injectionSeed ?? 0
        memcpy(stepBuffer.contents(), &stepParams, MemoryLayout<StepParams>.stride)

        var seedParams = Self.seedParams(start: start, width: width, colors: spec.stateCount)
        memcpy(seedBuffer.contents(), &seedParams.params, MemoryLayout<SeedParams>.stride)
        seedParams.block.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                memcpy(blockBuffer.contents(), base, min(width, seedParams.block.count))
            }
        }

        var head: UInt32 = 0
        memcpy(headBuffer.contents(), &head, MemoryLayout<UInt32>.stride)
        memset(colorBuffer.contents(), 0, cols * rows)
        step = 0
        userPanned = false
        startOrigin = ViewportGeometry.initialOrigin(
            boardWidth: width, cols: cols, start: start, pinRight: spec.display.pinRight)
        viewportOrigin = startOrigin
        viewParams.currentStep = 0
        viewParams.viewportStart = 0
        viewParams.displayCols = UInt32(cols)
        viewParams.displayRows = UInt32(rows)
        viewParams.viewportOrigin = UInt32(startOrigin)
        viewParams.topRows = UInt32(twinHalfRows)
        memcpy(viewBuffer.contents(), &viewParams, MemoryLayout<ViewParams>.stride)

        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        guard let encoder = slot.command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }
        encoder.setArgumentTable(seedTable)
        encoder.setComputePipelineState(context.seedPipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(64, width), height: 1, depth: 1)
        )
        encoder.endEncoding()
        slot.command.endCommandBuffer()
        try commit(slot)

        leadAnchor = Self.leadColumn(
            start: start, width: width, colors: spec.stateCount,
            rate: spec.display.follow.columnsPerStep)
    }

    /// Advances the run and returns the run's GPU color buffer. The window
    /// refits every display row, so a sink recompacts the whole grid each frame.
    @discardableResult
    public func renderGPU(chunk: Int) throws -> GPUColorGrid {
        try advance(chunk: chunk)
        return GPUColorGrid(buffer: colorBuffer, cols: cols, rows: rows)
    }

    /// Encodes the step and fit work for `chunk` rows and commits it.
    func advance(chunk: Int) throws {
        let target = step + max(0, chunk)
        follow(to: target)
        let (_, slot) = ring.borrow()

        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)
        guard let encoder = slot.command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }
        encodeSteps(from: step, to: target, encoder: encoder)
        encodeFit(target: target, encoder: encoder)
        encoder.endEncoding()
        slot.command.endCommandBuffer()

        try commit(slot)
        step = target
    }

    // MARK: - Private

    private static func seedParams(start: BoardStart, width: Int, colors: Int) -> (params: SeedParams, block: [UInt8]) {
        var p = SeedParams(
            width: UInt32(width), colors: UInt32(colors), mode: 0,
            blockLength: 0, number: 0, density: 0.5, seed: 0)
        var block: [UInt8] = [0]
        switch start {
        case .center:
            p.mode = 0
        case .rightmost:
            p.mode = 1
        case .random(let seed, let density):
            p.mode = 2
            p.seed = seed
            p.density = Float(density)
        case .randomBlocks(let seed):
            p.mode = 3
            p.seed = seed
        case .block(let bytes):
            p.mode = 4
            p.blockLength = UInt32(bytes.count)
            block = bytes
        case .seed(let number, let startColors):
            p.mode = 5
            p.number = UInt32(number)
            p.colors = UInt32(startColors)
        }
        return (p, block)
    }

    /// The seed's leading non-zero board column in the follow direction. It
    /// mirrors `seed_row` so the viewport can follow without reading the seed
    /// row back from the GPU.
    static func leadColumn(start: BoardStart, width: Int, colors: Int, rate: Double) -> Double {
        guard rate != 0 else { return 0 }
        var leading = 0
        for index in 0..<width where seedValue(start: start, index: index, width: width, colors: colors) != 0 {
            if rate > 0 {
                leading = index
            } else {
                return Double(index)
            }
        }
        return Double(leading)
    }

    private static func seedValue(start: BoardStart, index: Int, width: Int, colors: Int) -> UInt8 {
        switch start {
        case .center:
            return index == width / 2 ? 1 : 0
        case .rightmost:
            return index == width - 1 ? 1 : 0
        case .random(let seed, let density):
            let draw = splitMix(seed: seed, index: index + 1)
            if colors == 3 { return UInt8(draw % 3) }
            if density == 0.5 { return UInt8(draw & 1) }
            return Double(draw >> 11) * (1.0 / 9_007_199_254_740_992.0) < density ? 1 : 0
        case .randomBlocks(let seed):
            return UInt8(splitMix(seed: seed, index: index / 2 + 1) & 1)
        case .block(let block):
            return block.isEmpty ? 0 : block[index % block.count]
        case .seed(let number, let startColors):
            let origin = width / 2
            let count = digitCount(number: number, colors: startColors)
            guard index >= origin, index - origin < count else { return 0 }
            return UInt8(numberDigit(number: number, colors: startColors, index: index - origin, count: count))
        }
    }

    /// The `index`-th (1-based) SplitMix64 draw, matching `seed_row`.
    private static func splitMix(seed: UInt64, index: Int) -> UInt64 {
        var z = seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private static func digitCount(number: Int, colors: Int) -> Int {
        var count = 1
        var n = number
        while n >= colors { n /= colors; count += 1 }
        return count
    }

    private static func numberDigit(number: Int, colors: Int, index: Int, count: Int) -> Int {
        var power = 1
        for _ in 0..<(count - 1 - index) { power *= colors }
        return (number / power) % colors
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

    private func encodeFit(target: Int, encoder: any MTL4ComputeCommandEncoder) {
        // The twin layout pins the newest row to both outer edges around the
        // shared horizon; the single layout pins it to the grid's bottom.
        viewParams.viewportStart = UInt32(max(0, target - (twin ? twinHalfRows : rows - 1)))
        viewParams.currentStep = UInt32(clamping: target)
        viewParams.topRows = UInt32(twinHalfRows)
        memcpy(viewBuffer.contents(), &viewParams, MemoryLayout<ViewParams>.stride)
        encoder.setArgumentTable(fitTable)
        encoder.setComputePipelineState(
            twin ? context.fitTwinPipeline : context.fitPipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: cols, height: rows, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(16, cols), height: min(16, rows), depth: 1)
        )
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
