import Metal

/// One frame's drawing destination, taken from a `RenderTarget` for the frame
/// being drawn.
public protocol RenderSurface: AnyObject {
    /// The texture the frame's render pass writes.
    var texture: any MTLTexture { get }

    /// Hands the drawn surface to the viewer. The target calls it once the
    /// frame has been encoded, so a surface that needs its own step after the
    /// draw owns that step here.
    func present()
}

/// What a finished frame lands in. The target is the only thing that knows the
/// pixel format the pipelines compile against, the elements its surface
/// resolves one-to-one, when frames are due, and how a drawn frame reaches the
/// viewer. The simulation, the timelines, and the renderers stay above it, so a
/// display's drawable and a panel's surface are interchangeable.
///
/// A target is created on the main thread and used on a render actor's thread;
/// implementations guard the state that crosses.
public protocol RenderTarget: AnyObject, Sendable {
    /// The format every render pipeline for this target compiles against.
    var pixelFormat: MTLPixelFormat { get }

    /// What this surface resolves one-to-one. The reveal's zoom floor derives
    /// from it, so a panel's element count stands in for a display's pixels.
    var displayLimits: DisplayLimits { get }

    /// Joins the context whose queue draws into this target. Called on the
    /// render actor before the first frame.
    func attach(to context: GPUContext)

    /// Starts delivering frames. `frame` receives the seconds since the
    /// previous frame, and `acquire` returns that frame's surface inside it.
    func start(_ frame: @escaping @Sendable (TimeInterval) -> Void)

    /// Stops delivering frames and leaves the target reusable by a later
    /// `start`.
    func stop()

    /// Stops delivering frames without leaving the target's loop, so the
    /// surface keeps its last drawn content. Safe to call from `frame`.
    func freeze()

    /// The surface to draw this frame into, or nil to skip the frame. Valid
    /// only inside `frame`, and at most one surface per frame.
    func acquire() -> (any RenderSurface)?
}
