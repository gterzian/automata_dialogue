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

/// The expanding-and-collapsing intro the review window shows while the model
/// runs. A point grows into a shaded disc, the frame whites out, nested discs
/// and a ring open up, rays cross them, a starburst fills the frame, the frame
/// goes black, and that black field shrinks into a white page with a final
/// point that shrinks away.
///
/// One wall-clock time drives every layer, so the sequence stays in step with
/// the display link even when a frame is dropped. The timeline is 10 seconds
/// and freezes on its final frame.
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
        var blackout: Float
        var shrinkMix: Float
        var shrinkRadius: Float
        var dotOpacity: Float
        /// Radius of the central ink point, in screen-height units.
        var dotRadius: Float
        var noiseScale: Float
        var smokeStrength: Float
        var discs: [CollapseDisc]
        var rays: [CollapseRay]
    }

    static func frame(time rawTime: Float) -> Frame {
        let time = min(max(rawTime, 0), duration)

        let sphereGrow = smoothstep(1.8, 3.8, time)
        let sphereRadius = 0.02 + 1.5 * pow(sphereGrow, 2.5)
        let sphereOpacity = smoothstep(1.6, 2.4, time) * (1 - smoothstep(5.0, 5.4, time))

        let glowRadius = 0.02 + 0.12 * smoothstep(2.0, 4.0, time)
        let glowOpacity = smoothstep(1.8, 2.6, time) * (1 - smoothstep(4.0, 4.6, time))
        let whiteoutGrow = pow(smoothstep(4.0, 5.0, time), 3)
        let coreRadius = 0.02 + 0.09 * smoothstep(4.0, 4.6, time) + 1.5 * whiteoutGrow
        let coreOpacity = smoothstep(4.0, 4.5, time)

        let fieldAlpha = smoothstep(2.4, 3.8, time) * (1 - smoothstep(4.8, 5.4, time))

        let pageRadius = 0.40 + 0.80 * smoothstep(5.5, 8.5, time)
        let pageOpacity = smoothstep(5.2, 5.8, time)
        let largeShadeRadius = 0.45 * smoothstep(6.2, 7.4, time)
        let largeShadeOpacity = smoothstep(6.2, 7.0, time)
            * (1 - smoothstep(7.8, 8.3, time))

        let innerGrow = smoothstep(5.2, 5.8, time)
        let innerShrink = smoothstep(5.8, 8.2, time)
        let shadeRadius = (0.16 - 0.125 * innerShrink) * innerGrow
        let innerWhiteRadius = max(shadeRadius * 0.75, 0.008)
        let ringRadius = max((0.08 - 0.06 * innerShrink) * innerGrow, 0.0)
        let centerRadius = max(shadeRadius * 0.35, 0.006)

        let rayProgress = smoothstep(7.5, 9.3, time)
        let rayGrow = smoothstep(6.0, 9.2, time)
        let rayCount = time < 6.0 ? 0 : 1 + Int(7 * pow(rayProgress, 3))
        let rayRotation = 0.8 * (time - 6.2)
        let rayAngles: [Float] = [0, .pi / 2, .pi / 4, 3 * .pi / 4, 0.12 * .pi, 0.62 * .pi, 0.37 * .pi, 0.87 * .pi]
        var rays: [CollapseRay] = []
        for index in 0..<min(rayCount, maxRays) {
            rays.append(CollapseRay(
                angle: rayAngles[index] + rayRotation,
                halfWidth: mix(0.012, 0.045, rayGrow),
                length: 2,
                darkness: 0.55 + 0.35 * rayGrow
            ))
        }

        let burstAlpha = smoothstep(8.5, 9.2, time)
        let blackout = smoothstep(8.9, 9.25, time)
        let shrinkMix = smoothstep(9.4, 9.5, time)
        let shrinkProgress = min(max((time - 9.5) / (duration - 9.5), 0), 1)
        let shrinkRadius = 1.3 * pow(1 - shrinkProgress, 3)
        let dotShrink = smoothstep(8.9, 9.2, time)

        let earlyDot = mix(0.004, 0.018, smoothstep(0, 2.0, time))
        let dotRadius = mix(earlyDot, 0.006, smoothstep(2.0, 4.0, time))

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
            rimWidth: 0.008 + 0.03 * shadeRadius,
            rimDark: 0.9,
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
            rimWidth: 0.004 + 0.006 * innerGrow,
            rimDark: 0.9,
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
            burstRotation: 0.6 * time,
            burstWidth: 0.5,
            burstLight: 0.6,
            blackout: blackout,
            shrinkMix: shrinkMix,
            shrinkRadius: shrinkRadius,
            dotOpacity: 1 - dotShrink,
            dotRadius: dotRadius,
            noiseScale: 0.28,
            smokeStrength: 0.9,
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
