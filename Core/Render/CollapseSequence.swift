import Foundation
import Metal

/// Public timing for the review window's intro.
public enum ReviewIntro {
    /// Seconds the intro animates before it rests on the frame the reveal
    /// continues from.
    public static let duration: TimeInterval = 6.8

    /// Seconds the settled line takes to retract onto the single centred cell
    /// an entry that starts there seeds from. The window plays this once the
    /// entry is chosen, so the reveal grows out of the intro's last image.
    public static let finaleDuration: TimeInterval = 0.45
}

/// One run's look for the intro: where the form sits, and which colour,
/// texture, and grain it takes. `WorkingIndicator.start()` draws a fresh seed
/// per run, so two runs never paint the same sequence, and one seed always
/// reproduces one run's sequence.
struct CollapseVariation {
    /// Seconds the cycle leads or lags. The skew tapers to zero before the rest
    /// frame, so every run rests on the same last image.
    var timeSkew: Float
    /// 0 keeps the field violet, 1 makes it the reference film's rose.
    var warmth: Float
    /// Slice of the noise volume the mass and the edges read.
    var noiseOrigin: SIMD3<Float>
    var smokeScale: Float
    var smokeStrength: Float
    var dotScale: Float
    var grainSeed: Float
    /// Edge undulation as a fraction of the radius.
    var wobble: Float
    /// Peak radius of the halo layer as a fraction of the covering radius.
    var haloScale: Float

    /// The unskewed baseline.
    static let standard = CollapseVariation(
        timeSkew: 0,
        warmth: 0.7,
        noiseOrigin: SIMD3(0.25, 0.5, 0.75),
        smokeScale: 0.2,
        smokeStrength: 0.9,
        dotScale: 1,
        grainSeed: 0,
        wobble: 0.03,
        haloScale: 0.9)

    static func seeded(_ seed: UInt64) -> CollapseVariation {
        var draw = SplitMix64(seed: seed)
        return CollapseVariation(
            timeSkew: draw.float(-0.1...0.1),
            warmth: draw.float(0.35...1.0),
            noiseOrigin: SIMD3(draw.unit(), draw.unit(), draw.unit()),
            smokeScale: draw.float(0.16...0.26),
            smokeStrength: draw.float(0.75...1.0),
            dotScale: draw.float(0.8...1.2),
            grainSeed: draw.float(0...256),
            wobble: draw.float(0.015...0.04),
            haloScale: draw.float(0.82...1.0))
    }
}

/// The draw sequence behind `CollapseVariation.seeded`, so a run is
/// reproducible from its seed.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1, from the high 24 bits so the float is exact.
    mutating func unit() -> Float {
        Float(next() >> 40) * (1.0 / 16_777_216.0)
    }

    mutating func float(_ range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }
}

/// The intro the review window shows while the model's turn is prepared. One
/// wall-clock time drives the cycle, so it stays in step with the display link
/// even when a frame is dropped. The cycle lasts `ReviewIntro.duration` and
/// rests on its final frame, where the window stops drawing. A
/// `CollapseVariation` decides how this run is drawn and paced.
enum CollapseTimeline {
    static let duration = Float(ReviewIntro.duration)

    struct Frame {
        /// Seconds into the cycle; the rest frame holds `duration`.
        var time: Float
        var noiseScale: Float
        var smokeStrength: Float
        /// Noise slice the mass, the edges, and the flicker read.
        var noiseX: Float
        var noiseY: Float
        var noiseZ: Float
        var warmth: Float
        var grainSeed: Float
        /// Multiplier on the one-cell dot the cycle starts from.
        var dotScale: Float
        /// 0 until the dot has faded in; the dot, the circles, and the line all
        /// draw at this opacity.
        var endAlpha: Float
        /// Edge undulation as a fraction of the radius.
        var wobble: Float
        /// Peak radius of the halo layer as a fraction of the covering radius.
        var haloScale: Float
        /// 0 keeps the dot; 1 has stretched it into the horizon line.
        var stretch: Float
        /// Growth of the four circle layers. For L0 and the white hole this is
        /// an exponent; for the rings it is a radius fraction.
        var grow: SIMD4<Float>
        /// 0 keeps the horizon line; 1 retracts it onto the single centred cell
        /// an entry that starts there seeds from.
        var settle: Float
    }

    /// The intro's one cycle. It rests on the horizon line the reveal's two
    /// branches share.
    static func frame(time rawTime: Float, variation: CollapseVariation = .standard) -> Frame {
        let time = min(max(rawTime, 0), duration)
        // The cycle leads or lags per run, but the skew is gone before the rest
        // frame, so every run stops on the same last image.
        let skew = variation.timeSkew * (1 - smoothstep(3.0, duration, time))
        let t = min(max(time + skew, 0), duration)

        let endAlpha = smoothstep(0, 0.2, t)

        // L0: slow growth, a tiny pause, an inhale, then the burst.
        let bloom = 0.44 * smoothstep(0.3, 1.6, t)
                  + 0.56 * smoothstep(1.6, 2.5, t)
                  - 0.03 * bump(1.2, 1.5, t)
        let grow = SIMD4<Float>(
            bloom * fall(t, 4.2, 4.6),
            smoothstep(3.2, 4.8, t) * fall(t, 5.9, 6.8),
            smoothstep(5.0, 6.1, t) * fallSmooth(t, 6.1, 6.8),
            smoothstep(5.1, 6.15, t) * fallSmooth(t, 6.1, 6.75))

        let stretch = smoothstep(5.9, 6.6, t)

        return Frame(
            time: time,
            noiseScale: variation.smokeScale,
            smokeStrength: variation.smokeStrength,
            noiseX: variation.noiseOrigin.x,
            noiseY: variation.noiseOrigin.y,
            noiseZ: variation.noiseOrigin.z,
            warmth: variation.warmth,
            grainSeed: variation.grainSeed,
            dotScale: variation.dotScale,
            endAlpha: endAlpha,
            wobble: variation.wobble,
            haloScale: variation.haloScale,
            stretch: stretch,
            grow: grow,
            settle: 0)
    }

    /// The frame the sequence rests on, with `settle` retracting the horizon
    /// line onto the centred seed cell. `settle` 0 is exactly the last frame of
    /// `frame(time:)`, so the window can freeze there without a jump.
    static func rested(settle: Float, variation: CollapseVariation) -> Frame {
        var frame = frame(time: duration, variation: variation)
        frame.settle = min(max(settle, 0), 1)
        return frame
    }

    /// 1 until `start`, then accelerating down to exactly 0 at `end`.
    private static func fall(_ t: Float, _ start: Float, _ end: Float) -> Float {
        let c = min(max((t - start) / (end - start), 0), 1)
        return 1 - pow(c, 1.8)
    }

    /// 1 until `start`, then a smoothstep down to exactly 0 at `end`. The ring
    /// layers carry a radius fraction, so this eases their size rather than
    /// their exponent.
    private static func fallSmooth(_ t: Float, _ start: Float, _ end: Float) -> Float {
        1 - smoothstep(start, end, t)
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 0 at both ends of [a, b], 1 in the middle.
    private static func bump(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let s = min(max((x - a) / (b - a), 0), 1)
        return 4 * s * (1 - s)
    }
}

/// Encodes the intro into a drawable with one full-resolution render pass. The
/// fragment shader composites the dot, the bursting mass, and the horizon line;
/// only the uniforms cross the CPU.
///
/// The renderer serializes its frames: the uniform buffer is shared, so a frame
/// must finish before the next one rewrites it. That is the same trade the
/// automaton layer makes (see `Core/Render/README.md`).
@available(macOS 26.0, *)
final class CollapseRenderer {
    /// Mirrors the `CollapseUniforms` struct in `ShaderSource.collapse`.
    private struct Uniforms {
        var time: Float
        var aspect: Float
        var screenHeight: Float
        var noiseScale: Float
        var smokeStrength: Float
        var noiseX: Float
        var noiseY: Float
        var noiseZ: Float
        var warmth: Float
        var grainSeed: Float
        var dotScale: Float
        var endAlpha: Float
        var wobble: Float
        var haloScale: Float
        var stretch: Float
        var lineHalfThickness: Float
        var settle: Float
        var grow: SIMD4<Float>
        var white: SIMD4<Float>
        var ink: SIMD4<Float>
    }

    private let context: GPUContext
    private let ring: FrameSlotRing
    private let pipeline: any MTLRenderPipelineState
    private let uniforms: any MTLBuffer
    private let table: any MTL4ArgumentTable
    private let noise: MTLTexture

    init(context: GPUContext, pixelFormat: MTLPixelFormat) throws {
        self.context = context
        self.ring = try FrameSlotRing(device: context.device)

        let libraryDescriptor = MTL4LibraryDescriptor()
        libraryDescriptor.source = ShaderSource.collapse
        let library: any MTLLibrary
        do {
            library = try context.compiler.makeLibrary(descriptor: libraryDescriptor)
        } catch {
            throw GPUContext.GPUError.compile("collapse library: \(error)")
        }
        self.pipeline = try Self.makePipeline(
            compiler: context.compiler, library: library, pixelFormat: pixelFormat)

        guard let uniformBuffer = context.device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride, options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("collapse uniforms")
        }
        self.uniforms = uniformBuffer
        self.noise = try Self.makeNoiseVolume(context: context)

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 1
        tableDescriptor.maxTextureBindCount = 1
        let table = try context.device.makeArgumentTable(descriptor: tableDescriptor)
        table.setAddress(uniformBuffer.gpuAddress, index: 0)
        table.setTexture(noise.gpuResourceID, index: 0)
        self.table = table

        context.makeResident([uniformBuffer])
        context.makeResident([noise])
    }

    /// Renders one frame and blocks until the GPU finishes, so the drawable is
    /// complete (tests read the same texture back) and the next frame can
    /// safely rewrite the shared buffer. `lineHalfThickness` is the horizon
    /// row's half-height in screen-height units: the line the cycle ends on and
    /// the dot's radius at that rest frame.
    func render(
        into texture: MTLTexture,
        frame: CollapseTimeline.Frame,
        white: PaletteColor,
        ink: PaletteColor,
        lineHalfThickness: Float
    ) throws {
        write(
            frame: frame, into: texture, white: white, ink: ink,
            lineHalfThickness: lineHalfThickness)

        let (_, slot) = ring.borrow()
        slot.command.beginCommandBuffer(allocator: slot.allocator)
        slot.command.useResidencySet(context.residency)

        let pass = MTL4RenderPassDescriptor()
        guard let attachment = pass.colorAttachments[0] else {
            throw GPUContext.GPUError.resource("collapse render pass")
        }
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        attachment.clearColor = MTLClearColor(
            red: Double(white.r), green: Double(white.g), blue: Double(white.b),
            alpha: Double(white.a))
        guard let render = slot.command.makeRenderCommandEncoder(descriptor: pass) else {
            throw GPUContext.GPUError.resource("collapse render encoder")
        }
        render.setRenderPipelineState(pipeline)
        render.setArgumentTable(table, stages: .fragment)
        render.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
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
    }

    // MARK: - Uniforms and lists

    private func write(
        frame: CollapseTimeline.Frame,
        into texture: MTLTexture,
        white: PaletteColor,
        ink: PaletteColor,
        lineHalfThickness: Float
    ) {
        var uniforms = Uniforms(
            time: frame.time,
            aspect: Float(texture.width) / Float(max(1, texture.height)),
            screenHeight: Float(texture.height),
            noiseScale: frame.noiseScale,
            smokeStrength: frame.smokeStrength,
            noiseX: frame.noiseX,
            noiseY: frame.noiseY,
            noiseZ: frame.noiseZ,
            warmth: frame.warmth,
            grainSeed: frame.grainSeed,
            dotScale: frame.dotScale,
            endAlpha: frame.endAlpha,
            wobble: frame.wobble,
            haloScale: frame.haloScale,
            stretch: frame.stretch,
            lineHalfThickness: lineHalfThickness,
            settle: frame.settle,
            grow: frame.grow,
            white: white.simd,
            ink: ink.simd
        )
        memcpy(self.uniforms.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
    }

    // MARK: - Resource factories

    private static func makeNoiseVolume(context: GPUContext) throws -> MTLTexture {
        let size = 64
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r32Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: descriptor) else {
            throw GPUContext.GPUError.resource("collapse noise volume")
        }
        var values = [Float](repeating: 0, count: size * size * size)
        for index in values.indices { values[index] = Float.random(in: 0...1) }
        // The shader samples this volume with linear filtering, so a white-noise
        // volume creases the mass and its edges at every texel boundary.
        // Smoothing it first costs one startup pass and keeps both readings soft.
        for _ in 0..<2 { values = smoothed(values, size: size) }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 1e-5)
        for index in values.indices { values[index] = (values[index] - low) / span }
        values.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, size, size, size),
                mipmapLevel: 0,
                slice: 0,
                withBytes: base,
                bytesPerRow: size * MemoryLayout<Float>.size,
                bytesPerImage: size * size * MemoryLayout<Float>.size)
        }
        return texture
    }

    /// One wrapped box blur along each axis, so the cube's opposite faces join
    /// without a seam under the sampler's `repeat` address mode.
    private static func smoothed(_ values: [Float], size: Int) -> [Float] {
        let radius = 1
        let taps = Float(2 * radius + 1)
        var source = values
        var target = values
        for axis in 0..<3 {
            for z in 0..<size {
                for y in 0..<size {
                    for x in 0..<size {
                        var sum: Float = 0
                        for offset in -radius...radius {
                            let sx = axis == 0 ? (x + offset + size) % size : x
                            let sy = axis == 1 ? (y + offset + size) % size : y
                            let sz = axis == 2 ? (z + offset + size) % size : z
                            sum += source[(sz * size + sy) * size + sx]
                        }
                        target[(z * size + y) * size + x] = sum / taps
                    }
                }
            }
            swap(&source, &target)
        }
        return source
    }

    private static func makePipeline(
        compiler: any MTL4Compiler,
        library: any MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> any MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "collapse_vertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "collapse_fragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        do {
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw GPUContext.GPUError.compile("collapse pipeline: \(error)")
        }
    }
}
