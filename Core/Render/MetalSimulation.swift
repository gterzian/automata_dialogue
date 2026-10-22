import Foundation
import Metal

/// The GPU simulation core, sink-independent. It owns the history buffer, the
/// GPU-side `head` counter, and the `seed`/`step`/`fit` kernels, and advances a
/// caller-sized chunk of source rows so a caller can animate instead of running
/// the whole board in one commit.
///
/// The run is a window over a board much wider than the display: the history
/// ring grows to hold every source row the run has produced, and `fit` maps a
/// display cell to the block of source cells it covers, at a sampling stride
/// that grows past the
/// display floor, so a short board grows into the grid and the whole history
/// stays visible without an end. A twin run maps one history into two mirrored
/// branches around a shared horizon row instead. `setZoom` resizes the display
/// grid and the viewport, reusing the color buffer.
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

    /// Mirrors `ViewParams` in `ShaderSource.simulation`; a field added here has
    /// to be added there first, and the buffer is sized from this type.
    private struct ViewParams {
        var boardWidth: UInt32
        var displayCols: UInt32
        var displayRows: UInt32
        var capacity: UInt32
        var currentStep: UInt32
        var topRows: UInt32
        var centreColumn: Float
        var sourceStride: Float
        /// Palette entries a cell can hold, which bounds the fit's reduction.
        var colors: UInt32
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
    /// Board column the window's left edge samples. Negative once the whole
    /// board is narrower than the window and sits centred in it.
    public private(set) var viewportOrigin: Int
    /// Board columns the window spans; grows with the reveal's sampling stride.
    private var sourceSpan: Int
    /// Display cells per board cell; see `ViewportGeometry.zoomFloor`. Past the
    /// floor the grid stops growing and the fit's sampling stride carries the
    /// zoom, so this value can fall below `minimumZoom`.
    public private(set) var zoom = 1.0
    /// The widest zoom-out the display grid shows one-to-one.
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

    /// Board column at the display's centre; the window grows symmetrically
    /// around it as the sampling stride rises.
    private var centreColumn: Double

    private let context: GPUContext
    private let width: Int
    /// The board the run simulates. Wider than the catalog board when the
    /// review window needs room to pan; see `ViewportGeometry.boardWidth`.
    private let board: Board
    /// Source rows the history ring holds. The ring grows with the run so the
    /// fit can keep sampling from the seed row; a source row indexes it modulo
    /// this.
    private var capacity: Int
    private var history: any MTLBuffer
    private let colorBuffer: any MTLBuffer
    private let stepBuffer: any MTLBuffer
    private let viewBuffer: any MTLBuffer
    private let seedBuffer: any MTLBuffer
    private let blockBuffer: any MTLBuffer
    private let headBuffer: any MTLBuffer
    private var stepTable: any MTL4ArgumentTable
    private let bumpTable: any MTL4ArgumentTable
    private var fitTable: any MTL4ArgumentTable
    private var seedTable: any MTL4ArgumentTable
    private let stepPipeline: any MTLComputePipelineState
    private let submitter: FrameSubmitter
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
        self.submitter = try FrameSubmitter(context: context)

        self.stepTable = try Self.makeTable(device: device, history: history, second: stepBuffer, third: headBuffer)
        self.bumpTable = try Self.makeTable(device: device, history: headBuffer, second: nil, third: nil)
        self.fitTable = try Self.makeTable(device: device, history: history, second: colorBuffer, third: viewBuffer)
        self.seedTable = try Self.makeTable(device: device, history: history, second: seedBuffer, third: blockBuffer)

        let startOrigin = ViewportGeometry.initialOrigin(
            boardWidth: width, cols: displayCols, start: runBoard.start,
            pinRight: spec.display.pinRight)
        self.viewportOrigin = startOrigin
        self.sourceSpan = displayCols
        self.centreColumn = Double(startOrigin) + Double(displayCols) / 2

        self.stepParams = StepParams(
            width: UInt32(width), rule: rule, colors: colors, capacity: UInt32(capacity),
            inject: runBoard.injection == nil ? 0 : 1,
            injectSeed: runBoard.injection?.seed ?? 0)
        self.viewParams = ViewParams(
            boardWidth: UInt32(width),
            displayCols: UInt32(displayCols),
            displayRows: UInt32(displayRows),
            capacity: UInt32(capacity),
            currentStep: 0,
            topRows: UInt32(halfRows),
            centreColumn: Float(centreColumn),
            sourceStride: 1,
            colors: UInt32(spec.stateCount))

        try reseed()
    }

    /// Shifts the window `delta` source columns, clamped to the board. A manual
    /// pan also aborts the entry's follow for the rest of the run; the caller
    /// re-fits (`renderGPU(chunk: 0)`) to show the new window.
    public func pan(by delta: Int) {
        userPanned = true
        centreColumn = clampedCentre(centreColumn + Double(delta), span: Double(sourceSpan))
    }

    /// Resizes the display grid for `value`, keeping the board column at the
    /// display's centre fixed. The grid is clamped to this run's display floor;
    /// a smaller `value` keeps the grid there and the fit reduces a wider block
    /// of the history per cell instead. The caller re-fits (`renderGPU(chunk: 0)`)
    /// to show the new view.
    public func setZoom(_ value: Double) {
        let clamped = min(max(value, Double.leastNormalMagnitude), ViewportGeometry.maximumZoom)
        zoom = clamped
        let gridZoom = max(clamped, minimumZoom)
        let newCols = ViewportGeometry.zoomedColumns(baseCols: baseCols, zoom: gridZoom)
        let newRows = twin
            ? ViewportGeometry.twinRows(baseRows: baseRows, zoom: gridZoom)
            : ViewportGeometry.zoomedRows(baseRows: baseRows, zoom: gridZoom)
        guard newCols != cols || newRows != rows else { return }
        cols = newCols
        rows = newRows
        twinHalfRows = twin ? ViewportGeometry.twinHalfRows(rows: rows) : 0
        centreColumn = clampedCentre(centreColumn, span: Double(cols))
        viewportOrigin = Int((centreColumn - Double(cols) / 2).rounded())
        sourceSpan = cols
        viewParams.displayCols = UInt32(cols)
        viewParams.displayRows = UInt32(rows)
        viewParams.topRows = UInt32(twinHalfRows)
        viewParams.centreColumn = Float(centreColumn)
        viewParams.sourceStride = 1
        memcpy(viewBuffer.contents(), &viewParams, MemoryLayout<ViewParams>.stride)
    }

    /// Keeps the window's centre on the board, or centres the whole board once
    /// it is narrower than the window.
    private func clampedCentre(_ centre: Double, span: Double) -> Double {
        guard span < Double(width) else { return Double(width) / 2 }
        return min(max(span / 2, centre), Double(width) - span / 2)
    }

    /// Scrolls the viewport as the pattern's leading edge advances, but only
    /// once that edge would leave the window: while the edge is still inside,
    /// the centre does not move. The edge is `leadAnchor` moved by the entry's
    /// signed rate, so a left-growing pattern is not pushed off the right. The
    /// window widens with the reveal's sampling stride, so the edge moves only
    /// once the pattern outruns that wider view.
    private func follow(to currentStep: Int) {
        let rate = spec.display.follow.columnsPerStep
        guard rate != 0, !userPanned else { return }
        let windowSpan = Double(cols) * sourceStride(steps: currentStep)
        let lead = leadAnchor + rate * Double(currentStep)
        if rate > 0 {
            let right = centreColumn + windowSpan / 2
            if lead > right - 1 { centreColumn = lead - windowSpan / 2 + 1 }
        } else {
            let left = centreColumn - windowSpan / 2
            if lead < left { centreColumn = lead + windowSpan / 2 }
        }
        centreColumn = clampedCentre(centreColumn, span: windowSpan)
    }

    /// Source cells per display cell at `steps`; 1 until the history outgrows
    /// the displayed rows. See `ViewportGeometry.sourceStride`.
    private func sourceStride(steps: Int) -> Double {
        let span = twin ? twinHalfRows : max(1, rows - 1)
        return ViewportGeometry.sourceStride(steps: steps, span: span)
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
        let origin = ViewportGeometry.initialOrigin(
            boardWidth: width, cols: cols, start: start, pinRight: spec.display.pinRight)
        centreColumn = clampedCentre(
            Double(origin) + Double(cols) / 2, span: Double(cols))
        viewportOrigin = Int((centreColumn - Double(cols) / 2).rounded())
        sourceSpan = cols
        viewParams.currentStep = 0
        viewParams.displayCols = UInt32(cols)
        viewParams.displayRows = UInt32(rows)
        viewParams.centreColumn = Float(centreColumn)
        viewParams.sourceStride = 1
        viewParams.topRows = UInt32(twinHalfRows)
        memcpy(viewBuffer.contents(), &viewParams, MemoryLayout<ViewParams>.stride)

        try submitter.submit { command in
            guard let encoder = command.makeComputeCommandEncoder() else {
                throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
            }
            encoder.setArgumentTable(seedTable)
            encoder.setComputePipelineState(context.seedPipeline)
            encoder.dispatchThreads(
                threadsPerGrid: MTLSize(width: width, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(64, width), height: 1, depth: 1)
            )
            encoder.endEncoding()
        }

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
        try growHistory(to: target + 1)
        follow(to: target)

        try submitter.submit { command in
            guard let encoder = command.makeComputeCommandEncoder() else {
                throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
            }
            encodeSteps(from: step, to: target, encoder: encoder)
            encodeFit(target: target, encoder: encoder)
            encoder.endEncoding()
        }
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
        let stride = sourceStride(steps: target)
        let span = max(1, Int((Double(cols) * stride).rounded()))
        centreColumn = clampedCentre(centreColumn, span: Double(span))
        viewportOrigin = Int((centreColumn - Double(span) / 2).rounded())
        sourceSpan = span
        viewParams.currentStep = UInt32(clamping: target)
        viewParams.topRows = UInt32(twinHalfRows)
        viewParams.centreColumn = Float(centreColumn)
        viewParams.sourceStride = Float(stride)
        memcpy(viewBuffer.contents(), &viewParams, MemoryLayout<ViewParams>.stride)
        encoder.setArgumentTable(fitTable)
        encoder.setComputePipelineState(
            twin ? context.fitTwinPipeline : context.fitPipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: cols, height: rows, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(16, cols), height: min(16, rows), depth: 1)
        )
    }

    /// Grows the history ring so it can hold every source row the run has
    /// produced. The fit keeps sampling back to the seed, so the ring may not
    /// wrap and drop rows. The previous frame has completed on the GPU, so the
    /// shared buffer can be copied on this thread.
    private func growHistory(to rows: Int) throws {
        guard rows > capacity else { return }
        var grownCapacity = max(1, capacity)
        while grownCapacity < rows { grownCapacity += max(1, grownCapacity / 2) }
        guard let grown = context.device.makeBuffer(
            length: grownCapacity * width, options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("history ring")
        }
        let old = history.contents()
        let new = grown.contents()
        // SAFETY: the ring holds `capacity` rows and the run grows it before any
        // step could reach that capacity, so every stored source row is inside
        // the old buffer; the new ring is larger than `step`, and each row is
        // `width` bytes in both buffers.
        precondition(grownCapacity > step && capacity > step)
        for row in 0...step {
            memcpy(new + row * width, old + (row % capacity) * width, width)
        }
        let newStepTable = try Self.makeTable(
            device: context.device, history: grown, second: stepBuffer, third: headBuffer)
        let newFitTable = try Self.makeTable(
            device: context.device, history: grown, second: colorBuffer, third: viewBuffer)
        let newSeedTable = try Self.makeTable(
            device: context.device, history: grown, second: seedBuffer, third: blockBuffer)
        context.makeResident([grown])
        context.removeResident(history)
        history = grown
        capacity = grownCapacity
        stepTable = newStepTable
        fitTable = newFitTable
        seedTable = newSeedTable
        stepParams.capacity = UInt32(clamping: grownCapacity)
        memcpy(stepBuffer.contents(), &stepParams, MemoryLayout<StepParams>.stride)
        viewParams.capacity = UInt32(clamping: grownCapacity)
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
