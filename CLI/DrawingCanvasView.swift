import AppKit
import Core

/// The black drawing page of the carousel. Pointer input fills a `Drawing` in
/// normalized top-left coordinates; any other source can fill the same value,
/// so the export and submission paths do not depend on this view.
@MainActor
final class DrawingCanvasView: NSView {
    private let pageColor = Palette.standard(stateCount: 2)[1]
    private let inkColor = Palette.standard(stateCount: 2)[0]
    private(set) var drawing: Drawing

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
        needsDisplay = true
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

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if drawing.isBlank { drawing.reset(aspect: Self.aspect(of: bounds.size)) }
        drawing.beginStroke(at: normalizedPoint(for: event))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        drawing.extendStroke(to: normalizedPoint(for: event))
        needsDisplay = true
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
