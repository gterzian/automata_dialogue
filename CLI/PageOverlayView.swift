import AppKit

/// The text the review window draws over a page: the class an input drawing
/// illustrates, or the chosen automaton with the model's two reasons. The text
/// lives in AppKit only, so a reference drawing's pixels reach the model
/// without the label the window adds.
///
/// Neither style has a panel: the input class is white on the black page, and
/// the reveal's longer block is a light gray that sits under the picture
/// instead of competing with it.
@MainActor
final class PageOverlayView: NSView {
    enum Style: Equatable {
        /// The class of a reference drawing, white over the black page.
        case label
        /// The chosen entry and its reasons, light gray over the reveal.
        case detail
    }

    struct Content {
        var heading: String
        var subheading: String?
        var english: String?
        var chinese: String?
        var style: Style
    }

    /// Distance from the page's edges, shared with `LabeledPageView`.
    static let inset: CGFloat = 18
    private static let maximumTextWidth: CGFloat = 620

    private let content: Content

    init(_ content: Content) {
        self.content = content
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PageOverlayView is created in code") }

    override var isFlipped: Bool { true }

    /// The block's size for its sentences wrapped at the page's width, so the
    /// container can place it before drawing.
    func measuredSize(in available: CGSize) -> NSSize {
        let maximum = min(
            Self.maximumTextWidth, max(200, available.width - 2 * Self.inset))
        let bounds = attributedString().boundingRect(
            with: NSSize(width: maximum, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return NSSize(width: min(maximum, ceil(bounds.width)), height: ceil(bounds.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        attributedString().draw(
            with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private var textColor: NSColor {
        switch content.style {
        case .label: .white
        case .detail: NSColor(white: 0.58, alpha: 0.95)
        }
    }

    private func attributedString() -> NSAttributedString {
        let headingSize: CGFloat = content.style == .label ? 16 : 15
        let detailSize: CGFloat = 12
        var pieces: [(text: String, font: NSFont, color: NSColor)] = [
            (content.heading, .systemFont(ofSize: headingSize, weight: .medium), textColor),
        ]
        if let subheading = content.subheading, !subheading.isEmpty {
            pieces.append((
                subheading,
                .systemFont(ofSize: detailSize, weight: .medium),
                textColor.withAlphaComponent(0.9)))
        }
        if let english = content.english, !english.isEmpty {
            pieces.append((english, .systemFont(ofSize: detailSize), textColor))
        }
        if let chinese = content.chinese, !chinese.isEmpty {
            pieces.append((chinese, .systemFont(ofSize: detailSize), textColor))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 5
        let result = NSMutableAttributedString()
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(
                    string: "\n",
                    attributes: [.font: pieces[index - 1].font, .paragraphStyle: paragraph]))
            }
            result.append(NSAttributedString(
                string: piece.text,
                attributes: [
                    .font: piece.font,
                    .foregroundColor: piece.color,
                    .paragraphStyle: paragraph,
                ]))
        }
        return result
    }
}

/// A page plus its overlay. The container owns the frames so the text stays in
/// the top-left corner while the window resizes and the sentences rewrap.
@MainActor
final class LabeledPageView: NSView {
    private let page: NSView
    private let overlay: PageOverlayView

    init(page: NSView, overlay: PageOverlayView) {
        self.page = page
        self.overlay = overlay
        super.init(frame: page.frame)
        wantsLayer = true
        addSubview(page)
        addSubview(overlay)
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
        page.frame = bounds
        let size = overlay.measuredSize(in: bounds.size)
        overlay.frame = NSRect(
            x: PageOverlayView.inset, y: PageOverlayView.inset,
            width: size.width, height: size.height)
    }
}
