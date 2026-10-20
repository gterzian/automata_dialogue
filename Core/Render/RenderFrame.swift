import Metal

/// The simulation's GPU color buffer (one palette index per display cell,
/// row-major). It belongs to the live `MetalSimulation`; a sink may read it only
/// on the render actor, and a reconfigured run replaces it.
public struct GPUColorGrid: @unchecked Sendable {
    public let buffer: any MTLBuffer
    public let cols: Int
    public let rows: Int

    public init(buffer: any MTLBuffer, cols: Int, rows: Int) {
        self.buffer = buffer
        self.cols = cols
        self.rows = rows
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
    /// Row the twin branches share, or nil for a single layout.
    public let horizonRow: Int?

    public init(specID: String, gpu: GPUColorGrid, horizonRow: Int? = nil) {
        self.specID = specID
        self.gpu = gpu
        self.horizonRow = horizonRow
    }
}
