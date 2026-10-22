import Metal
@testable import Core

/// A `RenderTarget` over textures a test owns: each `acquire` hands out the next
/// texture (cycling) and `present` only counts, so a test reads the rendered
/// result back without a screen. `tick` delivers a frame by hand, which is how
/// the tests pump a run deterministically.
final class OffscreenTarget: RenderTarget, @unchecked Sendable {
    private let textures: [any MTLTexture]
    private let lock = NSLock()
    private var next = 0
    private var frame: (@Sendable (TimeInterval) -> Void)?
    private var paused = false
    private var presents = 0

    var pixelFormat: MTLPixelFormat { textures.first?.pixelFormat ?? .bgra8Unorm }

    /// One element per texture column, which is what a fixed-resolution surface
    /// resolves one-to-one.
    var displayLimits: DisplayLimits {
        DisplayLimits.elements(columns: textures.first?.width ?? 1)
    }

    init(textures: [any MTLTexture]) {
        self.textures = textures
    }

    func attach(to context: GPUContext) {
        context.makeResident(textures)
    }

    func start(_ frame: @escaping @Sendable (TimeInterval) -> Void) {
        lock.lock()
        self.frame = frame
        paused = false
        lock.unlock()
    }

    func stop() {
        lock.lock()
        frame = nil
        paused = false
        lock.unlock()
    }

    func freeze() {
        lock.lock()
        paused = true
        lock.unlock()
    }

    func acquire() -> (any RenderSurface)? {
        lock.lock()
        defer { lock.unlock() }
        guard !textures.isEmpty else { return nil }
        let texture = textures[next % textures.count]
        next += 1
        return OffscreenSurface(texture: texture) { [weak self] in
            self?.countPresent()
        }
    }

    /// Delivers one frame, as a surface with a fixed refresh would.
    func tick(_ delta: TimeInterval = 0) {
        lock.lock()
        let frame = self.frame
        let paused = self.paused
        lock.unlock()
        guard !paused else { return }
        frame?(delta)
    }

    /// Frames the target was asked to show.
    var presentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return presents
    }

    private func countPresent() {
        lock.lock()
        presents += 1
        lock.unlock()
    }
}

/// One of `OffscreenTarget`'s textures. Presenting it only reports back.
private final class OffscreenSurface: RenderSurface {
    let texture: any MTLTexture
    private let onPresent: () -> Void

    init(texture: any MTLTexture, onPresent: @escaping () -> Void) {
        self.texture = texture
        self.onPresent = onPresent
    }

    func present() { onPresent() }
}
