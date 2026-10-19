import Foundation
import Metal

/// Public timing for the review window's intro.
public enum ReviewIntro {
    /// Seconds the intro runs before it holds its final frame.
    public static let duration: TimeInterval = 10
}

/// One disc or ring in the intro's world. The fragment shader composites these
/// large to small; `layer` splits the list around the rays so the center
/// bullseye stays on top of them.
struct CollapseDisc {
    /// Fill style: 0 white, 1 shaded, 2 ring only.
    var radius: Float
    var fillMode: Float
    var rimWidth: Float
    var rimDark: Float
    var penumbraWidth: Float
    var penumbraDark: Float
    var opacity: Float
    var layer: Float
    /// Colour at the edge of a shaded fill.
    var fillDark: Float
}

/// A ray is a soft wedge with its apex at the center.
struct CollapseRay {
    var angle: Float
    var halfWidth: Float
    /// Radius beyond which the ray fades out.
    var length: Float
    var darkness: Float
}

/// One run's look for the intro: where the form sits, how its contour wanders,
/// which way the rays lie, how the starburst is cut, and which colour and
/// texture it takes. `WorkingIndicator.start()` draws a fresh seed per run, so
/// two runs never paint the same sequence, and one seed always reproduces one
/// run's sequence.
struct CollapseVariation {
    /// Seconds the opening phases lead or lag; the ending stays anchored.
    var timeSkew: Float
    /// Where the form sits, in screen-height units from the frame's centre.
    var centerX: Float
    var centerY: Float
    /// 0 keeps the field violet, 1 makes it the reference film's rose.
    var warmth: Float
    /// How far the contour wanders from a circle, as a fraction of the radius.
    var warp: Float
    /// Slice of the noise volume the field and the contour read.
    var noiseOrigin: SIMD3<Float>
    var smokeScale: Float
    var smokeStrength: Float
    var rayAngles: [Float]
    var rayWidths: [Float]
    var rayDarknesses: [Float]
    /// Signed radians per second the ray fan turns.
    var raySpin: Float
    var burstSectors: Float
    var burstRotation: Float
    var burstWidth: Float
    var burstLight: Float
    var dotScale: Float
    /// Scale of the small center structure and of its ring.
    var centerScale: Float
    var innerRatio: Float
    var ringScale: Float
    var grainSeed: Float

    /// The look the reference sequence uses; tests pin one drawing with it.
    static let standard = CollapseVariation.seeded(0)

    static func seeded(_ seed: UInt64) -> CollapseVariation {
        var draw = SplitMix64(seed: seed)
        let rayCount = 4 + Int(draw.unit() * 5)
        let spacing = 2 * Float.pi / Float(rayCount)
        let phase = draw.float(0...(2 * Float.pi))
        var angles: [Float] = []
        var widths: [Float] = []
        var darknesses: [Float] = []
        for index in 0..<rayCount {
            angles.append(
                phase + Float(index) * spacing + draw.float(-0.3...0.3) * spacing)
            widths.append(draw.float(0.7...1.35))
            darknesses.append(draw.float(0.85...1.1))
        }
        return CollapseVariation(
            timeSkew: draw.float(-0.1...0.1),
            centerX: draw.float(-0.03...0.03),
            centerY: draw.float(-0.02...0.02),
            warmth: draw.float(0.35...1.0),
            warp: draw.float(0.03...0.075),
            noiseOrigin: SIMD3(draw.unit(), draw.unit(), draw.unit()),
            smokeScale: draw.float(0.16...0.26),
            smokeStrength: draw.float(0.75...1.0),
            rayAngles: angles,
            rayWidths: widths,
            rayDarknesses: darknesses,
            raySpin: draw.float(0.3...0.9) * (draw.unit() < 0.5 ? -1 : 1),
            burstSectors: Float(2 * (17 + Int(draw.unit() * 11))),
            burstRotation: draw.float(0...(2 * Float.pi)),
            burstWidth: draw.float(0.42...0.58),
            burstLight: draw.float(0.5...0.7),
            dotScale: draw.float(0.8...1.2),
            centerScale: draw.float(0.88...1.12),
            innerRatio: draw.float(0.7...0.8),
            ringScale: draw.float(0.85...1.15),
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

/// The expanding-and-collapsing intro the review window shows while the model
/// runs. A point grows into a shaded disc, the frame whites out, nested discs
/// and a ring open up, rays cross them, a starburst fills the frame, the frame
/// goes black, and that black field shrinks into a white page with a final
/// point that shrinks away.
///
/// One wall-clock time drives every layer, so the sequence stays in step with
/// the display link even when a frame is dropped. The timeline is 10 seconds
/// and freezes on its final frame. A `CollapseVariation` decides how this run's
/// sequence is drawn and paced, so two runs differ.
enum CollapseTimeline {
    static let duration = Float(ReviewIntro.duration)

    static let maxDiscs = 9
    static let maxRays = 8

    struct Frame {
        var time: Float
        var fieldAlpha: Float
        var burstAlpha: Float
        var burstRotation: Float
        var burstWidth: Float
        var burstLight: Float
        var burstSectors: Float
        var blackout: Float
        var shrinkMix: Float
        var shrinkRadius: Float
        var dotOpacity: Float
        /// Radius of the central ink point, in screen-height units.
        var dotRadius: Float
        var noiseScale: Float
        var smokeStrength: Float
        /// Centre of the whole form, in screen-height units from the frame's.
        var centerX: Float
        var centerY: Float
        /// Noise slice the field and the contour read, and the contour's wander.
        var noiseX: Float
        var noiseY: Float
        var noiseZ: Float
        var warp: Float
        var warmth: Float
        var grainSeed: Float
        var discs: [CollapseDisc]
        var rays: [CollapseRay]
    }

    static func frame(
        time rawTime: Float,
        variation: CollapseVariation = .standard
    ) -> Frame {
        let time = min(max(rawTime, 0), duration)
        // The opening phases lead or lag by a fraction of a second per run; the
        // ending stays on `time` so the freeze and the cut to the automaton do
        // not move.
        let t = max(time + variation.timeSkew, 0)

        let sphereGrow = smoothstep(1.8, 3.8, t)
        let sphereRadius = 0.02 + 1.5 * pow(sphereGrow, 2.5)
        let sphereOpacity = smoothstep(1.6, 2.4, t) * (1 - smoothstep(5.0, 5.4, t))

        let glowRadius = 0.02 + 0.12 * smoothstep(2.0, 4.0, t)
        let glowOpacity = smoothstep(1.8, 2.6, t) * (1 - smoothstep(4.0, 4.6, t))
        let whiteoutGrow = pow(smoothstep(4.0, 5.0, t), 3)
        let coreRadius = 0.02 + 0.09 * smoothstep(4.0, 4.6, t) + 1.5 * whiteoutGrow
        let coreOpacity = smoothstep(4.0, 4.5, t)

        let fieldAlpha = smoothstep(2.4, 3.8, t) * (1 - smoothstep(4.8, 5.4, t))

        let pageRadius = 0.40 + 0.80 * smoothstep(5.5, 8.5, t)
        let pageOpacity = smoothstep(5.2, 5.8, t)
        let largeShadeRadius = 0.45 * smoothstep(6.2, 7.4, t)
        let largeShadeOpacity = smoothstep(6.2, 7.0, t)
            * (1 - smoothstep(7.8, 8.3, t))

        let innerGrow = smoothstep(5.2, 5.8, t)
        let innerShrink = smoothstep(5.8, 8.2, t)
        let shadeRadius = (0.16 * variation.centerScale - 0.125 * innerShrink) * innerGrow
        let innerWhiteRadius = max(shadeRadius * variation.innerRatio, 0.008)
        let ringRadius = max(
            (0.08 * variation.ringScale - 0.06 * innerShrink) * innerGrow, 0.0)
        let centerRadius = max(shadeRadius * 0.35, 0.006)

        let rayProgress = smoothstep(7.5, 9.3, t)
        let rayGrow = smoothstep(6.0, 9.2, t)
        let rayCount = t < 6.0
            ? 0
            : 1 + Int(Float(variation.rayAngles.count - 1) * pow(rayProgress, 3))
        let raySpin = variation.raySpin * max(t - 6.2, 0)
        var rays: [CollapseRay] = []
        for index in 0..<min(rayCount, maxRays) {
            rays.append(CollapseRay(
                angle: variation.rayAngles[index] + raySpin,
                halfWidth: variation.rayWidths[index] * mix(0.012, 0.045, rayGrow),
                length: 2,
                darkness: variation.rayDarknesses[index] * (0.55 + 0.35 * rayGrow)
            ))
        }

        let burstAlpha = smoothstep(8.5, 9.2, time)
        let blackout = smoothstep(8.9, 9.25, time)
        let shrinkMix = smoothstep(9.4, 9.5, time)
        let shrinkProgress = min(max((time - 9.5) / (duration - 9.5), 0), 1)
        let shrinkRadius = 1.3 * pow(1 - shrinkProgress, 3)
        let dotShrink = smoothstep(8.9, 9.2, time)

        let earlyDot = mix(0.013, 0.024, smoothstep(0, 2.0, t)) * variation.dotScale
        let dotRadius = mix(earlyDot, 0.006 * variation.dotScale, smoothstep(2.0, 4.0, t))

        var discs: [CollapseDisc] = []
        // The first shaded sphere.
        discs.append(CollapseDisc(
            radius: sphereRadius,
            fillMode: 1,
            rimWidth: 0.015 + 0.03 * sphereRadius,
            rimDark: 0.8,
            penumbraWidth: 0.02 + 0.15 * sphereRadius,
            penumbraDark: 0.6,
            opacity: sphereOpacity,
            layer: 0,
            fillDark: 0.20))
        // The soft bright glow inside the shaded sphere.
        discs.append(CollapseDisc(
            radius: glowRadius,
            fillMode: 3,
            rimWidth: 0,
            rimDark: 0,
            penumbraWidth: 0,
            penumbraDark: 0,
            opacity: glowOpacity,
            layer: 0,
            fillDark: 0))
        // The hard white core that opens into the whiteout.
        discs.append(CollapseDisc(
            radius: coreRadius,
            fillMode: 0,
            rimWidth: 0,
            rimDark: 0,
            penumbraWidth: 0.25 * coreRadius + 0.01,
            penumbraDark: 0.45,
            opacity: coreOpacity,
            layer: 0,
            fillDark: 0))
        // The large white page with a mauve penumbra outside it.
        discs.append(CollapseDisc(
            radius: pageRadius,
            fillMode: 0,
            rimWidth: 0,
            rimDark: 0,
            penumbraWidth: 0.25 * pageRadius,
            penumbraDark: 0.5,
            opacity: pageOpacity,
            layer: 0,
            fillDark: 0))
        // The large shaded sphere that grows around the small white center.
        discs.append(CollapseDisc(
            radius: largeShadeRadius,
            fillMode: 1,
            rimWidth: 0.01 + 0.03 * largeShadeRadius,
            rimDark: 0.7,
            penumbraWidth: 0.05 + 0.10 * largeShadeRadius,
            penumbraDark: 0.5,
            opacity: largeShadeOpacity,
            layer: 0,
            fillDark: 0.32))
        // The small center structure after the whiteout.
        discs.append(CollapseDisc(
            radius: shadeRadius,
            fillMode: 1,
            rimWidth: 0.006 + 0.025 * shadeRadius,
            rimDark: 0.8,
            penumbraWidth: 0.02 + 0.10 * shadeRadius,
            penumbraDark: 0.4,
            opacity: innerGrow,
            layer: 1,
            fillDark: 0.58))
        discs.append(CollapseDisc(
            radius: innerWhiteRadius,
            fillMode: 0,
            rimWidth: 0,
            rimDark: 0,
            penumbraWidth: 0.006,
            penumbraDark: 0.25,
            opacity: innerGrow,
            layer: 1,
            fillDark: 0))
        discs.append(CollapseDisc(
            radius: ringRadius,
            fillMode: 2,
            rimWidth: 0.003 + 0.005 * innerGrow,
            rimDark: 0.75,
            penumbraWidth: 0,
            penumbraDark: 0,
            opacity: smoothstep(7.0, 7.8, time) * (1 - blackout),
            layer: 1,
            fillDark: 0))
        discs.append(CollapseDisc(
            radius: centerRadius,
            fillMode: 0,
            rimWidth: 0,
            rimDark: 0,
            penumbraWidth: 0.004,
            penumbraDark: 0.2,
            opacity: innerGrow,
            layer: 1,
            fillDark: 0))

        return Frame(
            time: time,
            fieldAlpha: fieldAlpha,
            burstAlpha: burstAlpha,
            burstRotation: variation.burstRotation + 0.6 * t,
            burstWidth: variation.burstWidth,
            burstLight: variation.burstLight,
            burstSectors: variation.burstSectors,
            blackout: blackout,
            shrinkMix: shrinkMix,
            shrinkRadius: shrinkRadius,
            dotOpacity: 1 - dotShrink,
            dotRadius: dotRadius,
            noiseScale: variation.smokeScale,
            smokeStrength: variation.smokeStrength,
            centerX: variation.centerX,
            centerY: variation.centerY,
            noiseX: variation.noiseOrigin.x,
            noiseY: variation.noiseOrigin.y,
            noiseZ: variation.noiseOrigin.z,
            warp: variation.warp,
            warmth: variation.warmth,
            grainSeed: variation.grainSeed,
            discs: discs,
            rays: rays
        )
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}

/// Encodes the intro into a drawable with one full-resolution render pass. The
/// fragment shader composites the field, discs, rays, starburst, blackout,
/// shrink, and final point; only the uniforms and the small disc/ray lists
/// cross the CPU.
///
/// The renderer serializes its frames: the uniform, disc, and ray buffers are
/// shared, so a frame must finish before the next one rewrites them. That is
/// the same trade the automaton layer makes (see `Core/Render/README.md`).
@available(macOS 26.0, *)
final class CollapseRenderer {
    /// Mirrors the `CollapseUniforms` struct in `ShaderSource.collapse`.
    private struct Uniforms {
        var time: Float
        var aspect: Float
        var screenHeight: Float
        var fieldAlpha: Float
        var burstAlpha: Float
        var burstRotation: Float
        var burstWidth: Float
        var burstLight: Float
        var blackout: Float
        var shrinkMix: Float
        var shrinkRadius: Float
        var dotRadius: Float
        var dotOpacity: Float
        var noiseScale: Float
        var smokeStrength: Float
        var discCount: Float
        var rayCount: Float
        var centerX: Float
        var centerY: Float
        var warp: Float
        var noiseX: Float
        var noiseY: Float
        var noiseZ: Float
        var warmth: Float
        var burstSectors: Float
        var grainSeed: Float
        var white: SIMD4<Float>
        var ink: SIMD4<Float>
    }

    private let context: GPUContext
    private let ring: FrameSlotRing
    private let pipeline: any MTLRenderPipelineState
    private let uniforms: any MTLBuffer
    private let discs: any MTLBuffer
    private let rays: any MTLBuffer
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
        guard let discBuffer = context.device.makeBuffer(
            length: CollapseTimeline.maxDiscs * MemoryLayout<CollapseDisc>.stride,
            options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("collapse discs")
        }
        self.discs = discBuffer
        guard let rayBuffer = context.device.makeBuffer(
            length: CollapseTimeline.maxRays * MemoryLayout<CollapseRay>.stride,
            options: .storageModeShared
        ) else {
            throw GPUContext.GPUError.resource("collapse rays")
        }
        self.rays = rayBuffer
        self.noise = try Self.makeNoiseVolume(context: context)

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 3
        tableDescriptor.maxTextureBindCount = 1
        let table = try context.device.makeArgumentTable(descriptor: tableDescriptor)
        table.setAddress(uniformBuffer.gpuAddress, index: 0)
        table.setAddress(discBuffer.gpuAddress, index: 1)
        table.setAddress(rayBuffer.gpuAddress, index: 2)
        table.setTexture(noise.gpuResourceID, index: 0)
        self.table = table

        context.makeResident([uniformBuffer, discBuffer, rayBuffer])
        context.makeResident([noise])
    }

    /// Renders one frame and blocks until the GPU finishes, so the drawable is
    /// complete (tests read the same texture back) and the next frame can
    /// safely rewrite the shared buffers.
    func render(
        into texture: MTLTexture,
        frame: CollapseTimeline.Frame,
        white: PaletteColor,
        ink: PaletteColor
    ) throws {
        write(frame: frame, into: texture, white: white, ink: ink)

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
        ink: PaletteColor
    ) {
        var uniforms = Uniforms(
            time: frame.time,
            aspect: Float(texture.width) / Float(max(1, texture.height)),
            screenHeight: Float(texture.height),
            fieldAlpha: frame.fieldAlpha,
            burstAlpha: frame.burstAlpha,
            burstRotation: frame.burstRotation,
            burstWidth: frame.burstWidth,
            burstLight: frame.burstLight,
            blackout: frame.blackout,
            shrinkMix: frame.shrinkMix,
            shrinkRadius: frame.shrinkRadius,
            dotRadius: frame.dotRadius,
            dotOpacity: frame.dotOpacity,
            noiseScale: frame.noiseScale,
            smokeStrength: frame.smokeStrength,
            discCount: Float(frame.discs.count),
            rayCount: Float(frame.rays.count),
            centerX: frame.centerX,
            centerY: frame.centerY,
            warp: frame.warp,
            noiseX: frame.noiseX,
            noiseY: frame.noiseY,
            noiseZ: frame.noiseZ,
            warmth: frame.warmth,
            burstSectors: frame.burstSectors,
            grainSeed: frame.grainSeed,
            white: white.simd,
            ink: ink.simd
        )
        memcpy(self.uniforms.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        frame.discs.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                memcpy(discs.contents(), base, bytes.count)
            }
        }
        frame.rays.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress {
                memcpy(rays.contents(), base, bytes.count)
            }
        }
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
        // volume creases the field and the contours at every texel boundary.
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
