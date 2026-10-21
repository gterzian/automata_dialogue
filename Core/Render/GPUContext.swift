import Foundation
import Metal

/// One per app, created on the render actor.
@available(macOS 26.0, *)
public final class GPUContext {
    public enum GPUError: Error, LocalizedError {
        case noMetal4Device
        case resource(String)
        case compile(String)

        public var errorDescription: String? {
            switch self {
            case .noMetal4Device: "No Metal 4 device (macOS 26, Apple silicon required)."
            case .resource(let name): "Could not create Metal resource: \(name)."
            case .compile(let message): "Metal compile failed: \(message)."
            }
        }
    }

    public let device: any MTLDevice
    public let queue: any MTL4CommandQueue
    public let compiler: any MTL4Compiler
    private let library: any MTLLibrary
    public let stepElementary: any MTLComputePipelineState
    public let stepTotalistic: any MTLComputePipelineState
    public let stepK2R2: any MTLComputePipelineState
    public let bumpHead: any MTLComputePipelineState
    public let fitPipeline: any MTLComputePipelineState
    public let fitTwinPipeline: any MTLComputePipelineState
    public let seedPipeline: any MTLComputePipelineState
    public let residency: any MTLResidencySet

    public static var isAvailable: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsFamily(.metal4)
    }

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            throw GPUError.noMetal4Device
        }
        self.device = device

        guard let queue = device.makeMTL4CommandQueue() else {
            throw GPUError.resource("MTL4CommandQueue")
        }
        self.queue = queue

        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        self.compiler = compiler

        let libraryDescriptor = MTL4LibraryDescriptor()
        libraryDescriptor.source = ShaderSource.simulation
        let library: any MTLLibrary
        do {
            library = try compiler.makeLibrary(descriptor: libraryDescriptor)
        } catch {
            throw GPUError.compile(String(describing: error))
        }
        self.library = library

        self.stepElementary = try Self.makePipeline(
            compiler: compiler, library: library, name: "step_eca"
        )
        self.stepTotalistic = try Self.makePipeline(
            compiler: compiler, library: library, name: "step_totalistic"
        )
        self.stepK2R2 = try Self.makePipeline(
            compiler: compiler, library: library, name: "step_k2r2"
        )
        self.bumpHead = try Self.makePipeline(
            compiler: compiler, library: library, name: "bump_head"
        )
        self.fitPipeline = try Self.makePipeline(
            compiler: compiler, library: library, name: "fit"
        )
        self.fitTwinPipeline = try Self.makePipeline(
            compiler: compiler, library: library, name: "fit_twin"
        )
        self.seedPipeline = try Self.makePipeline(
            compiler: compiler, library: library, name: "seed_row"
        )

        let residencyDescriptor = MTLResidencySetDescriptor()
        residencyDescriptor.initialCapacity = 16
        do {
            self.residency = try device.makeResidencySet(descriptor: residencyDescriptor)
        } catch {
            throw GPUError.resource("MTLResidencySet: \(error)")
        }
        queue.addResidencySet(residency)
    }

    private static func makePipeline(
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
            throw GPUError.compile("\(name): \(error)")
        }
    }

    /// Residency sets are Metal 4's only residency mechanism.
    public func makeResident(_ buffers: [any MTLBuffer]) {
        for buffer in buffers { residency.addAllocation(buffer) }
        residency.commit()
    }

    /// Textures the renderer creates after its first frame (the intro's noise
    /// volume) join the same residency set.
    public func makeResident(_ textures: [any MTLTexture]) {
        for texture in textures { residency.addAllocation(texture) }
        residency.commit()
    }

    /// Releases a texture that a later submission replaced. The caller must
    /// have finished every command that reads it.
    public func removeResident(_ texture: any MTLTexture) {
        residency.removeAllocation(texture)
        residency.commit()
    }
}
