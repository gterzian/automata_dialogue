import AppKit
import Core

/// The text the review window draws over a page: the class an input drawing
/// illustrates, or the submitted picture beside the model's reasons and the
/// chosen automaton. The text lives in AppKit only, so a reference drawing's
/// pixels reach the model without the label the window adds.
///
/// The input class is white text on the black reference page and needs no
/// panel. The reveal's block sits over the automaton's growth, so
/// `LabeledPageView` puts it in a liquid-glass panel to keep the text legible
/// against the pattern.
@MainActor
final class PageOverlayView: NSView {
    enum Style: Equatable {
        /// The class of a reference drawing, white over the black page.
        case label
        /// The submitted picture, the model's reasons, and the chosen entry.
        case detail
    }

    struct Content {
        var heading: String
        var subheading: String?
        var english: String?
        var chinese: String?
        /// Names what `heading` is, so the footer reads as the answer rather
        /// than as more commentary on the picture.
        var caption: String?
        /// The picture the reasons describe, drawn beside them.
        var input: NSImage?
        var style: Style
    }

    /// Distance from the page's edges, shared with `LabeledPageView`.
    static let inset: CGFloat = 18
    /// Padding between a panel's edge and its content. `NSGlassEffectView`
    /// stretches its content view over its own bounds, so the padding is drawn
    /// inside this view instead of being left to the panel's layout.
    static let glassPadding: CGFloat = 14
    static let glassCornerRadius: CGFloat = 18

    private static let maximumTextWidth: CGFloat = 620
    private static let thumbnailSide: CGFloat = 92
    private static let thumbnailGap: CGFloat = 16
    private static let thumbnailCornerRadius: CGFloat = 10
    private static let footerGap: CGFloat = 16

    private let content: Content

    var style: Style { content.style }

    init(_ content: Content) {
        self.content = content
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PageOverlayView is created in code") }

    override var isFlipped: Bool { true }

    /// One measured block: its text and the rect its top-left corner starts at.
    private struct Piece {
        var text: NSAttributedString
        var rect: NSRect
    }

    private struct Layout {
        var pieces: [Piece]
        var thumbnail: NSRect
        var height: CGFloat
    }

    private var padding: CGFloat {
        content.style == .detail ? Self.glassPadding : 0
    }

    /// The block's size for its sentences wrapped within the page, so the
    /// container can place it before drawing. The width is the widest the page
    /// allows and the height follows the wrapped text.
    func measuredSize(inPage page: CGSize) -> NSSize {
        let padding = self.padding
        let width = min(
            Self.maximumTextWidth,
            max(200, page.width - 2 * Self.inset - 2 * padding))
        let boundsWidth = width + 2 * padding
        return NSSize(
            width: boundsWidth, height: layout(boundsWidth: boundsWidth).height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let layout = layout(boundsWidth: bounds.width)
        if let input = content.input, !layout.thumbnail.isEmpty {
            draw(input, in: layout.thumbnail)
        }
        for piece in layout.pieces {
            piece.text.draw(
                with: piece.rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    private func layout(boundsWidth: CGFloat) -> Layout {
        let padding = self.padding
        let width = boundsWidth - 2 * padding
        var pieces: [Piece] = []
        var thumbnail = NSRect.zero
        var bottom = padding

        switch content.style {
        case .label:
            var y = padding
            for (text, gap) in [
                (headingText(), CGFloat(0)),
                (subheadingText(), 4),
                (reasonText(), 6),
            ] {
                guard !text.string.isEmpty else { continue }
                y += gap
                let piece = place(text, x: padding, y: y, width: width)
                pieces.append(piece)
                y = piece.rect.maxY
            }
            bottom = y

        case .detail:
            // The picture and the reasons share a row, so the reasons read as
            // commentary on the input; the footer below names the answer.
            let reason = reasonText()
            let hasThumbnail = content.input != nil
            let reasonWidth = hasThumbnail
                ? width - Self.thumbnailSide - Self.thumbnailGap
                : width
            let reasonX = hasThumbnail
                ? padding + Self.thumbnailSide + Self.thumbnailGap
                : padding
            let reasonPiece = place(reason, x: reasonX, y: padding, width: reasonWidth)
            if !reason.string.isEmpty {
                pieces.append(reasonPiece)
            }
            if hasThumbnail {
                thumbnail = NSRect(
                    x: padding, y: padding,
                    width: Self.thumbnailSide, height: Self.thumbnailSide)
            }
            var y = max(reasonPiece.rect.maxY, thumbnail.maxY) + Self.footerGap
            for (text, gap) in [
                (captionText(), CGFloat(0)),
                (headingText(), 2),
                (subheadingText(), 3),
            ] {
                guard !text.string.isEmpty else { continue }
                y += gap
                let piece = place(text, x: padding, y: y, width: width)
                pieces.append(piece)
                y = piece.rect.maxY
            }
            bottom = y
        }

        return Layout(
            pieces: pieces,
            thumbnail: thumbnail,
            height: bottom + padding)
    }

    /// Measures `text` wrapped at `width` and returns the rect it fills from
    /// (`x`, `y`) downward in this view's flipped coordinates.
    private func place(
        _ text: NSAttributedString, x: CGFloat, y: CGFloat, width: CGFloat
    ) -> Piece {
        let bounds = text.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return Piece(
            text: text,
            rect: NSRect(
                x: x, y: y, width: min(width, ceil(bounds.width)),
                height: ceil(bounds.height)))
    }

    private var textColor: NSColor {
        switch content.style {
        case .label: .white
        case .detail: .labelColor
        }
    }

    private func attributes(
        font: NSFont, color: NSColor
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private func headingText() -> NSAttributedString {
        let size: CGFloat = content.style == .label ? 16 : 15
        return NSAttributedString(
            string: content.heading,
            attributes: attributes(
                font: .systemFont(ofSize: size, weight: .medium), color: textColor))
    }

    private func subheadingText() -> NSAttributedString {
        guard let subheading = content.subheading, !subheading.isEmpty else {
            return NSAttributedString()
        }
        return NSAttributedString(
            string: subheading,
            attributes: attributes(
                font: .systemFont(ofSize: 12, weight: .medium),
                color: textColor.withAlphaComponent(0.9)))
    }

    private func captionText() -> NSAttributedString {
        guard let caption = content.caption, !caption.isEmpty else {
            return NSAttributedString()
        }
        return NSAttributedString(
            string: caption,
            attributes: attributes(
                font: .systemFont(ofSize: 11),
                color: textColor.withAlphaComponent(0.7)))
    }

    private func reasonText() -> NSAttributedString {
        let paragraphs = [content.english, content.chinese]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return NSAttributedString() }
        let font = NSFont.systemFont(ofSize: 12)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 5
        let result = NSMutableAttributedString()
        for (index, text) in paragraphs.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(
                    string: "\n",
                    attributes: [.font: font, .paragraphStyle: paragraph]))
            }
            result.append(NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph,
                ]))
        }
        return result
    }

    /// Draws the input picture aspect-fit in a rounded square, over black so a
    /// picture with transparent or letterboxed edges still reads as a page.
    private func draw(_ image: NSImage, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let frame = NSBezierPath(
            roundedRect: rect,
            xRadius: Self.thumbnailCornerRadius,
            yRadius: Self.thumbnailCornerRadius)
        frame.addClip()
        NSColor.black.setFill()
        rect.fill()

        let size = image.size
        if size.width > 0, size.height > 0 {
            let scale = min(rect.width / size.width, rect.height / size.height)
            let fitted = NSSize(
                width: (size.width * scale).rounded(.down),
                height: (size.height * scale).rounded(.down))
            image.draw(
                in: NSRect(
                    x: rect.midX - fitted.width / 2,
                    y: rect.midY - fitted.height / 2,
                    width: fitted.width, height: fitted.height),
                from: .zero, operation: .sourceOver, fraction: 1)
        }

        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: Self.thumbnailCornerRadius,
            yRadius: Self.thumbnailCornerRadius)
        NSColor.separatorColor.setStroke()
        border.lineWidth = 1
        border.stroke()
    }
}

/// A page plus its overlay. The container owns the frames so the text stays in
/// the top-left corner while the window resizes and the sentences rewrap.
@MainActor
final class LabeledPageView: NSView {
    private let page: NSView
    private let overlay: PageOverlayView
    private let glass: NSGlassEffectView?
    /// The page's height as a fraction of the container's. The reveal's ending
    /// lowers it to the horizon line and `layoutPages` keeps it there, because
    /// AppKit re-lays a view's frame out from this container's layout.
    private var pageHeightFraction: CGFloat = 1

    init(page: NSView, overlay: PageOverlayView) {
        self.page = page
        self.overlay = overlay
        if overlay.style == .detail {
            let panel = NSGlassEffectView()
            panel.contentView = overlay
            panel.cornerRadius = PageOverlayView.glassCornerRadius
            panel.style = .regular
            self.glass = panel
        } else {
            self.glass = nil
        }
        super.init(frame: page.frame)
        wantsLayer = true
        // The page fills this view, but the reveal's ending squashes the page
        // layer and leaves the page showing around it rather than the window's
        // own colour.
        layer?.backgroundColor = Palette.standard(stateCount: 2)[0].cgColor
        addSubview(page)
        addSubview(glass ?? overlay)
        layoutPages()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("LabeledPageView is created in code") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        layoutPages()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPages()
    }

    private func layoutPages() {
        page.frame = pageRect(fraction: pageHeightFraction)
        let size = overlay.measuredSize(inPage: bounds.size)
        let origin = NSPoint(x: PageOverlayView.inset, y: PageOverlayView.inset)
        if let glass {
            glass.frame = NSRect(origin: origin, size: size)
            // The panel stretches its content view over its bounds; the overlay
            // draws the panel's padding inside that frame.
            overlay.frame = NSRect(origin: .zero, size: size)
        } else {
            overlay.frame = NSRect(origin: origin, size: size)
        }
    }

    /// The page's frame for `fraction`, centred on the container's horizon row.
    private func pageRect(fraction: CGFloat) -> NSRect {
        let height = bounds.height * fraction
        return NSRect(
            x: bounds.minX, y: bounds.midY - height / 2,
            width: bounds.width, height: height)
    }

    /// Ends the reveal: the panel disappears and the page squashes onto its
    /// horizon row, the container's vertical centre, so the whole picture
    /// finishes as one line. `lineScale` is that line as a fraction of the
    /// page's height. Returns once the squash has finished.
    func collapseOntoHorizon(lineScale: CGFloat, duration: TimeInterval) async {
        (glass ?? overlay).isHidden = true
        pageHeightFraction = lineScale
        // The page's backing layer is AppKit's, so the squash animates the
        // view's frame: the layer stretches the presented picture to the
        // smaller bounds, and the container's page colour shows around it.
        NSAnimationContext.beginGrouping()
        let context = NSAnimationContext.current
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        page.animator().frame = pageRect(fraction: lineScale)
        NSAnimationContext.endGrouping()
        do {
            try await Task.sleep(for: .seconds(duration))
        } catch {
            return
        }
    }
}
