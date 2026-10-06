import AppKit
import Core
import CoreGraphics
import SwiftUI

/// Draws an automaton `ColorGrid` image. The image is produced by the CPU
/// incremental renderer on the main actor; a Metal-backed view replaces this
/// when the layer sink lands.
struct AutomatonView: NSViewRepresentable {
    let image: CGImage?

    func makeNSView(context: Context) -> AutomatonNSView {
        AutomatonNSView()
    }

    func updateNSView(_ nsView: AutomatonNSView, context: Context) {
        nsView.image = image
    }
}

final class AutomatonNSView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor(calibratedWhite: 0.11, alpha: 1).cgColor)
        context.fill(bounds)
        guard let image else { return }

        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        let rect = CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        context.interpolationQuality = .none
        context.draw(image, in: rect)
    }
}
