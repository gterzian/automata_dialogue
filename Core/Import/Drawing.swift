import CoreGraphics
import Foundation

/// A freehand drawing in normalized coordinates, so any pointer source can
/// produce one: the CLI's canvas is an adapter, and another input can fill the
/// same value. Points use a top-left origin; `aspect` is the surface's
/// width/height when the strokes were captured, so a render at a different
/// aspect keeps the shapes proportional.
public struct Drawing: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Stroke: Sendable, Equatable {
        public var points: [Point]
        /// Fraction of the drawing's smaller edge, so the stroke keeps its
        /// weight at any render size.
        public var width: Double

        public init(points: [Point], width: Double) {
            self.points = points
            self.width = width
        }
    }

    public private(set) var aspect: Double
    public private(set) var strokes: [Stroke]

    public init(aspect: Double = 1) {
        self.aspect = max(aspect, 1e-3)
        self.strokes = []
    }

    public var isBlank: Bool { strokes.isEmpty }

    public mutating func beginStroke(at point: Point, width: Double = 0.006) {
        strokes.append(Stroke(points: [point], width: max(width, 1e-4)))
    }

    public mutating func extendStroke(to point: Point) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].points.append(point)
    }

    public mutating func reset(aspect: Double? = nil) {
        if let aspect { self.aspect = max(aspect, 1e-3) }
        strokes.removeAll()
    }
}

/// Renders a `Drawing` in the review window's dark-page/light-ink look. The
/// prompt judges the drawn shapes rather than the page, so the submitted image
/// keeps the surface's colours.
public enum DrawingImage {
    /// The drawing is aspect-fit into `width × height` on the background
    /// colour, so a square model input never stretches the shapes.
    public static func raster(
        _ drawing: Drawing,
        width: Int,
        height: Int,
        background: PaletteColor = Palette.standard(stateCount: 2)[1],
        ink: PaletteColor = Palette.standard(stateCount: 2)[0]
    ) -> RasterImage? {
        guard width > 0, height > 0,
              let context = RasterImage.makeContext(width: width, height: height) else {
            return nil
        }
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let target = fitRect(aspect: drawing.aspect, width: width, height: height)
        context.setStrokeColor(ink.cgColor)
        context.setFillColor(ink.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in drawing.strokes {
            let points = stroke.points.map { point -> CGPoint in
                CGPoint(
                    x: target.minX + CGFloat(point.x) * target.width,
                    y: target.minY + (1 - CGFloat(point.y)) * target.height
                )
            }
            guard let first = points.first else { continue }
            let lineWidth = max(1, CGFloat(stroke.width) * min(target.width, target.height))
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
        guard let bytes = context.data else { return nil }
        // SAFETY: the context owns a width × height × 4 byte RGBA buffer that
        // stays alive until this function returns, and the copy is bounded by
        // that layout.
        return RasterImage(
            width: width, height: height,
            pixels: Data(bytes: bytes, count: width * height * 4))
    }

    /// The largest centred rectangle of `aspect` inside the target.
    static func fitRect(aspect: Double, width: Int, height: Int) -> CGRect {
        let targetAspect = Double(width) / Double(max(1, height))
        let fittedWidth: CGFloat
        let fittedHeight: CGFloat
        if max(aspect, 1e-3) >= targetAspect {
            fittedWidth = CGFloat(width)
            fittedHeight = CGFloat(Double(width) / max(aspect, 1e-3))
        } else {
            fittedHeight = CGFloat(height)
            fittedWidth = CGFloat(Double(height) * max(aspect, 1e-3))
        }
        return CGRect(
            x: (CGFloat(width) - fittedWidth) / 2,
            y: (CGFloat(height) - fittedHeight) / 2,
            width: fittedWidth,
            height: fittedHeight)
    }
}
