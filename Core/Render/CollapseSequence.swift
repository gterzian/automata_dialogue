import Foundation
import Metal

/// Public timing for the review window's intro.
public enum ReviewIntro {
    /// Seconds the intro animates before it rests on its final frame: the dot
    /// ignites, bursts to cover the frame, holds, and collapses into the
    /// horizon line.
    public static let duration: TimeInterval = 3

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
    /// Where the form sits, in screen-height units from the frame's centre.
    var centerX: Float
    var centerY: Float
    /// 0 keeps the field violet, 1 makes it the reference film's rose.
    var warmth: Float
    /// Slice of the noise volume the mass and the silhouette read.
    var noiseOrigin: SIMD3<Float>
    var smokeScale: Float
    var smokeStrength: Float
    var dotScale: Float
    var grainSeed: Float

    /// The unskewed look tests pin, so the timeline's phase boundaries are
    /// exactly the constants `frame(time:)` states.
    static let standard = CollapseVariation(
        timeSkew: 0,
        centerX: 0,
        centerY: 0,
        warmth: 0.7,
        noiseOrigin: SIMD3(0.25, 0.5, 0.75),
        smokeScale: 0.2,
        smokeStrength: 0.9,
        dotScale: 1,
        grainSeed: 0)

    static func seeded(_ seed: UInt64) -> CollapseVariation {
        var draw = SplitMix64(seed: seed)
        return CollapseVariation(
            timeSkew: draw.float(-0.1...0.1),
            centerX: draw.float(-0.03...0.03),
            centerY: draw.float(-0.02...0.02),
            warmth: draw.float(0.35...1.0),
            noiseOrigin: SIMD3(draw.unit(), draw.unit(), draw.unit()),
            smokeScale: draw.float(0.16...0.26),
            smokeStrength: draw.float(0.75...1.0),
            dotScale: draw.float(0.8...1.2),
            grainSeed: draw.float(0...256))
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

/// The intro the review window shows before inference starts. A one-cell ink
/// dot ignites, bursts to cover the frame, flickers, and collapses into the
/// straight horizon row the two automaton branches share; the last beat
/// retracts that row onto the single cell an entry seeds from.
///
/// One wall-clock time drives the cycle, so it stays in step with the display
/// link even when a frame is dropped. The cycle lasts `ReviewIntro.duration`
/// and rests on its final frame, where the window stops drawing. A
/// `CollapseVariation` decides how this run's cycle is drawn and paced, so two
/// runs differ.
enum CollapseTimeline {
    static let duration = Float(ReviewIntro.duration)

    struct Frame {
        /// Seconds into the cycle; the rest frame holds `duration`.
        var time: Float
        var noiseScale: Float
        var smokeStrength: Float
        /// Centre of the whole form, in screen-height units from the frame's.
        var centerX: Float
        var centerY: Float
        /// Noise slice the mass, the silhouette, and the flicker read.
        var noiseX: Float
        var noiseY: Float
        var noiseZ: Float
        var warmth: Float
        var grainSeed: Float
        /// Multiplier on the one-cell dot the burst starts from.
        var dotScale: Float
        /// 0 until the dot has faded in; the dot, burst, and line all draw at
        /// this opacity.
        var endAlpha: Float
        /// Exponent of the radius growth: a slow ignition, an inhale, then the
        /// burst that covers the frame.
        var bloom: Float
        /// 0...1 progress from the covering mass into the horizon line.
        var collapse: Float
        /// 0...1 speed proxy of the moving front; widens the feather.
        var frontEnergy: Float
        /// Multiplier on the line's thickness; a damped rebound after the
        /// collapse.
        var lineSpring: Float
        /// 0 keeps the horizon line; 1 retracts it onto the single centred cell
        /// an entry that starts there seeds from.
        var settle: Float
    }

    /// The intro's one cycle: a one-cell dot ignites, an inhale tightens it, the
    /// burst covers the frame, holds and flickers, then collapses into the
    /// horizon line the reveal's two branches share.
    static func frame(time rawTime: Float, variation: CollapseVariation = .standard) -> Frame {
        let time = min(max(rawTime, 0), duration)
        // The cycle leads or lags per run, but the skew is gone before the rest
        // frame, so every run stops on the same last image.
        let skew = variation.timeSkew * (1 - smoothstep(2.2, duration, time))
        let t = min(max(time + skew, 0), duration)

        let endAlpha = smoothstep(0, 0.2, t)

        // Slow growth, a tiny pause where both smoothsteps have zero slope, an
        // inhale, then the burst. `bloom` is the exponent of the radius growth.
        let bloom = 0.44 * smoothstep(0.15, 0.75, t)
                  + 0.56 * smoothstep(0.75, 1.05, t)
                  - 0.03 * bump(0.55, 0.72, t)

        // The collapse accelerates into the line; the spring absorbs the
        // arrival and is damped to nothing before the rest frame, so the clock
        // can stop on a frame that is exactly the final line.
        let c = min(max((t - 1.45) / 0.55, 0), 1)
        let collapse = pow(c, 1.8)
        let since = max(t - 2.0, 0)
        let lineSpring = 1 + 0.8 * exp(-6 * since) * sin(16 * since)
                  * (1 - smoothstep(2.2, duration, t))

        let frontEnergy = max(bump(0.75, 1.05, t), bump(1.45, 2.0, t))

        return Frame(
            time: time,
            noiseScale: variation.smokeScale,
            smokeStrength: variation.smokeStrength,
            centerX: variation.centerX,
            centerY: variation.centerY,
            noiseX: variation.noiseOrigin.x,
            noiseY: variation.noiseOrigin.y,
            noiseZ: variation.noiseOrigin.z,
            warmth: variation.warmth,
            grainSeed: variation.grainSeed,
            dotScale: variation.dotScale,
            endAlpha: endAlpha,
            bloom: bloom,
            collapse: collapse,
            frontEnergy: frontEnergy,
            lineSpring: lineSpring,
            settle: 0
        )
    }

    /// The frame the sequence rests on, with `settle` retracting the horizon
    /// line onto the centred seed cell. `settle` 0 is exactly the last frame of
    /// `frame(time:)`, so the window can freeze there without a jump.
    static func rested(settle: Float, variation: CollapseVariation) -> Frame {
        var frame = frame(time: duration, variation: variation)
        frame.settle = min(max(settle, 0), 1)
        return frame
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
        var centerX: Float
        var centerY: Float
        var noiseX: Float
        var noiseY: Float
        var noiseZ: Float
        var warmth: Float
        var grainSeed: Float
        var dotScale: Float
        var endAlpha: Float
        var bloom: Float
        var collapse: Float
        var lineHalfThickness: Float
        var frontEnergy: Float
        var lineSpring: Float
        var settle: Float
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
    /// row's half-height in screen-height units, which is both the line the
    /// cycle collapses into and the seed dot's radius.
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
            centerX: frame.centerX,
            centerY: frame.centerY,
            noiseX: frame.noiseX,
            noiseY: frame.noiseY,
            noiseZ: frame.noiseZ,
            warmth: frame.warmth,
            grainSeed: frame.grainSeed,
            dotScale: frame.dotScale,
            endAlpha: frame.endAlpha,
            bloom: frame.bloom,
            collapse: frame.collapse,
            lineHalfThickness: lineHalfThickness,
            frontEnergy: frame.frontEnergy,
            lineSpring: frame.lineSpring,
            settle: frame.settle,
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
        // volume creases the mass and its silhouette at every texel boundary.
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
