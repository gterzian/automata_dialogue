import AppKit
import Core

/// The black drawing page of the carousel. Pointer input fills a `Drawing` in
/// normalized top-left coordinates; any other source can fill the same value,
/// so the export and submission paths do not depend on this view.
///
/// A press starts a stroke, the drag extends it, and the release ends it, so
/// moving the pointer over the page without pressing draws nothing. Moving past
/// the page's edge ends the stroke there, so a drag that travels off the page
/// does not smear ink along the edge.
@MainActor
final class DrawingCanvasView: NSView {
    private let pageColor = Palette.standard(stateCount: 2)[1]
    private let inkColor = Palette.standard(stateCount: 2)[0]
    private(set) var drawing: Drawing

    /// True while a stroke is open, so consecutive moves extend one stroke and
    /// the pointer leaving then re-entering starts a new one instead of a line
    /// back to the exit point.
    private var isStrokeOpen = false
    /// The open stroke's last point, so a duplicated or coalesced event does not
    /// append the same point twice.
    private var lastPoint: Drawing.Point?

    override init(frame frameRect: NSRect) {
        drawing = Drawing(aspect: Self.aspect(of: frameRect.size))
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = pageColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DrawingCanvasView is created in code") }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Starts the page blank. The next stroke captures the page's current
    /// aspect, so a window resized between runs exports proportionally.
    func clear() {
        drawing.reset(aspect: Self.aspect(of: bounds.size))
        endStroke()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(pageColor.cgColor)
        context.fill(bounds)
        context.setStrokeColor(inkColor.cgColor)
        context.setFillColor(inkColor.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShouldAntialias(true)
        for stroke in drawing.strokes {
            let points = stroke.points.map { point in
                CGPoint(
                    x: CGFloat(point.x) * bounds.width,
                    y: bounds.height - CGFloat(point.y) * bounds.height)
            }
            guard let first = points.first else { continue }
            let lineWidth = max(1, CGFloat(stroke.width) * min(bounds.width, bounds.height))
            if points.count == 1 {
                let radius = lineWidth / 2
                context.fillEllipse(
                    in: CGRect(
                        x: first.x - radius, y: first.y - radius,
                        width: lineWidth, height: lineWidth))
                continue
            }
            context.setLineWidth(lineWidth)
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
    }

    /// The press is the pen down. It starts a stroke where the pointer is, so a
    /// press elsewhere does not connect to the previous stroke.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        extendStroke(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        extendStroke(with: event)
    }

    /// The release is the pen up.
    override func mouseUp(with event: NSEvent) {
        endStroke()
    }

    /// Leaving the page lifts the pen, and re-entering under a held button
    /// starts a new stroke instead of a line back to the exit point.
    override func mouseExited(with event: NSEvent) {
        endStroke()
    }

    private func extendStroke(with event: NSEvent) {
        let point = normalizedPoint(for: event)
        guard point != lastPoint else { return }
        if isStrokeOpen {
            drawing.extendStroke(to: point)
        } else {
            if drawing.isBlank { drawing.reset(aspect: Self.aspect(of: bounds.size)) }
            drawing.beginStroke(at: point)
            isStrokeOpen = true
        }
        lastPoint = point
        needsDisplay = true
    }

    private func endStroke() {
        isStrokeOpen = false
        lastPoint = nil
    }

    private func normalizedPoint(for event: NSEvent) -> Drawing.Point {
        let point = convert(event.locationInWindow, from: nil)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        return Drawing.Point(
            x: min(max(point.x / width, 0), 1),
            y: min(max(1 - point.y / height, 0), 1))
    }

    private static func aspect(of size: NSSize) -> Double {
        Double(max(size.width, 1) / max(size.height, 1))
    }
}
