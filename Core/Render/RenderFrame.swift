import Metal

/// What one grid cell holds.
public enum CellGridContent: Sendable, Equatable {
    /// A palette index, drawn as runs of equal cells. One cell is one source
    /// cell, so the grid is exact.
    case paletteIndices
    /// An RGBA colour. The cell covers several source cells, so the fit already
    /// holds its average and the draw shows it as tone.
    case colors
}

/// The simulation's GPU color buffer, row-major. Above the display floor a cell
/// is a palette index, which the sink compacts into spans; below it a cell is a
/// colour, which the sink draws as an image. It belongs to the live
/// `MetalSimulation`; a sink may read it only on the render actor, and a
/// reconfigured run replaces it.
public struct GPUColorGrid: @unchecked Sendable {
    public let buffer: any MTLBuffer
    public let cols: Int
    public let rows: Int
    public let content: CellGridContent

    public init(
        buffer: any MTLBuffer,
        cols: Int,
        rows: Int,
        content: CellGridContent = .paletteIndices
    ) {
        self.buffer = buffer
        self.cols = cols
        self.rows = rows
        self.content = content
    }
}

/// One delivered frame: the catalog id plus the GPU-resident grid. The sink
/// looks the `ProgramSpec` up from the catalog by `specID`, so a frame stays
/// small and `Sendable` across the render actor boundary.
public struct RenderFrame: Sendable {
    /// Catalog id of the entry that produced the frame.
    public let specID: String
    /// The simulation's GPU color buffer.
    public let gpu: GPUColorGrid

    public init(specID: String, gpu: GPUColorGrid) {
        self.specID = specID
        self.gpu = gpu
    }
}
