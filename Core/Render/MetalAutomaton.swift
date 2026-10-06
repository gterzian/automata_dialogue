import Foundation
import Metal

/// Runs one catalog entry to completion on the Metal 4 compute path and reads
/// the result back. The GPU `step`/`fit` kernels must produce the same grid as
/// `CPUAutomatonRenderer`; the readback tests assert that. A later
/// `MetalLayerSink` uses the same kernels and hands the grid to a drawable
/// instead of the CPU.
@available(macOS 26.0, *)
public enum MetalAutomaton {
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
    }

    public static func colorGrid(
        spec: ProgramSpec,
        cols: Int,
        rows: Int,
        steps: Int? = nil,
        context: GPUContext
    ) throws -> ColorGrid {
        let displayCols = max(1, cols)
        let displayRows = max(1, rows)
        let totalSteps = max(1, steps ?? min(spec.board.height, spec.display.stepLimit))
        let width = spec.board.width
        let device = context.device

        guard let history = device.makeBuffer(length: max(1, totalSteps * width), options: .storageModeShared),
              let colorBuffer = device.makeBuffer(length: displayCols * displayRows, options: .storageModeShared),
              let stepBuffer = device.makeBuffer(length: MemoryLayout<StepParams>.stride, options: .storageModeShared),
              let fitBuffer = device.makeBuffer(length: MemoryLayout<FitParams>.stride, options: .storageModeShared),
              let headBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let allocator = device.makeCommandAllocator(),
              let command = device.makeCommandBuffer() else {
            throw GPUContext.GPUError.resource("simulation buffers")
        }
        context.makeResident([history, colorBuffer, stepBuffer, fitBuffer, headBuffer])

        // Seed row 0 from the CPU reference (shared storage is written in place).
        let seed = spec.makeProgram().row()
        seed.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { memcpy(history.contents(), base, width) }
        }
        var head: UInt32 = 0
        memcpy(headBuffer.contents(), &head, MemoryLayout<UInt32>.stride)

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
        var stepParams = StepParams(width: UInt32(width), rule: rule, colors: colors)
        memcpy(stepBuffer.contents(), &stepParams, MemoryLayout<StepParams>.stride)

        let fit = Fit(boardWidth: width, displayCols: displayCols, pinRight: spec.display.pinRight)
        var fitParams = FitParams(
            boardWidth: UInt32(width),
            displayCols: UInt32(displayCols),
            displayRows: UInt32(displayRows),
            totalSteps: UInt32(totalSteps),
            block: UInt32(fit.block),
            sourceOrigin: UInt32(fit.sourceOrigin),
            padLeft: UInt32(fit.padLeft)
        )
        memcpy(fitBuffer.contents(), &fitParams, MemoryLayout<FitParams>.stride)

        // Three argument tables, each with constant bindings. The head counter
        // advances on the GPU, so nothing is rebound between dispatches.
        let stepTable = try makeTable(device: device, history: history, second: stepBuffer, third: headBuffer)
        let bumpTable = try makeTable(device: device, history: headBuffer, second: nil, third: nil)
        let fitTable = try makeTable(device: device, history: history, second: colorBuffer, third: fitBuffer)

        command.beginCommandBuffer(allocator: allocator)
        command.useResidencySet(context.residency)
        guard let encoder = command.makeComputeCommandEncoder() else {
            throw GPUContext.GPUError.resource("MTL4ComputeCommandEncoder")
        }

        let stepThreads = MTLSize(width: min(64, width), height: 1, depth: 1)
        for _ in 1..<totalSteps {
            encoder.setArgumentTable(stepTable)
            encoder.setComputePipelineState(pipeline)
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

        encoder.setArgumentTable(fitTable)
        encoder.setComputePipelineState(context.fitPipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: displayCols, height: displayRows, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(16, displayCols), height: min(16, displayRows), depth: 1
            )
        )
        encoder.endEncoding()
        command.endCommandBuffer()

        let semaphore = DispatchSemaphore(value: 0)
        let options = MTL4CommitOptions()
        options.addFeedbackHandler { _ in semaphore.signal() }
        context.queue.commit([command], options: options)
        semaphore.wait()
        allocator.reset()

        let pointer = colorBuffer.contents().bindMemory(to: UInt8.self, capacity: displayCols * displayRows)
        // SAFETY: the commit feedback handler has fired, so the GPU is done
        // writing `colorBuffer`; the buffer is `.storageModeShared` and was
        // allocated with exactly `displayCols * displayRows` bytes, so the
        // typed pointer and the count below both stay in bounds.
        let cells = Array(UnsafeBufferPointer(start: pointer, count: displayCols * displayRows))
        return ColorGrid(cols: displayCols, rows: displayRows, cells: cells)
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
