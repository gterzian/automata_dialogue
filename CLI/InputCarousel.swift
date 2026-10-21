import Foundation

/// One page of the input carousel. The drawing page is first; the carousel
/// wraps, so it is also the page after the last image and sits at both ends.
enum InputPage: Equatable {
    case drawing
    case image(URL)

    var title: String {
        switch self {
        case .drawing: "Draw"
        case .image(let url): url.lastPathComponent
        }
    }

    static func carousel(for paths: [String]) -> [InputPage] {
        [.drawing] + paths.map { .image(URL(fileURLWithPath: $0)) }
    }
}

/// What the review loop should do next on an input page.
enum InputAction: Equatable {
    case submit
    case move(Int)
    case closed
}

/// The carousel index after stepping by `delta`, wrapping at both ends.
func wrappedIndex(_ index: Int, count: Int) -> Int {
    let count = max(1, count)
    return ((index % count) + count) % count
}
