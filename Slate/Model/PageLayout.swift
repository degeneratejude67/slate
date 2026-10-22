import PDFKit
import PencilKit

enum PageGeometry {
    /// The page size as shown, with the PDF's own rotation applied.
    static func displaySize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        return rotation == 90 || rotation == 270
            ? CGSize(width: box.height, height: box.width)
            : box.size
    }
}

/// Where each page sits in the notebook's one long canvas (unzoomed points).
/// Vertical: pages stack top to bottom, centred on the widest page.
/// Horizontal: pages sit side by side, centred on the tallest page.
struct PageLayout {
    static let margin: CGFloat = 32
    static let gap: CGFloat = 32

    let axis: ScrollAxis
    let frames: [CGRect]
    let contentSize: CGSize

    init(sizes: [CGSize], axis: ScrollAxis = .vertical) {
        self.axis = axis
        let m = Self.margin
        var frames: [CGRect] = []
        switch axis {
        case .vertical:
            let maxWidth = sizes.map(\.width).max() ?? PageSizePreset.a4.size.width
            var y = m
            for size in sizes {
                frames.append(CGRect(x: m + (maxWidth - size.width) / 2, y: y, width: size.width, height: size.height))
                y += size.height + Self.gap
            }
            contentSize = CGSize(width: maxWidth + 2 * m, height: sizes.isEmpty ? 2 * m : y - Self.gap + m)
        case .horizontal:
            let maxHeight = sizes.map(\.height).max() ?? PageSizePreset.a4.size.height
            var x = m
            for size in sizes {
                frames.append(CGRect(x: x, y: m + (maxHeight - size.height) / 2, width: size.width, height: size.height))
                x += size.width + Self.gap
            }
            contentSize = CGSize(width: sizes.isEmpty ? 2 * m : x - Self.gap + m, height: maxHeight + 2 * m)
        }
        self.frames = frames
    }

    /// The page a position along the scroll axis belongs to; the gap after a page counts
    /// half to each side.
    func index(along value: CGFloat) -> Int {
        guard !frames.isEmpty else { return 0 }
        for (i, frame) in frames.enumerated() {
            let end = axis == .vertical ? frame.maxY : frame.maxX
            if value < end + Self.gap / 2 { return i }
        }
        return frames.count - 1
    }

    func index(atY y: CGFloat) -> Int { index(along: y) }

    func index(at point: CGPoint) -> Int {
        index(along: axis == .vertical ? point.y : point.x)
    }

    func index(for rect: CGRect) -> Int {
        index(at: CGPoint(x: rect.midX, y: rect.midY))
    }
}

/// Moves strokes between the notebook canvas (one drawing for all pages) and the
/// per-page drawings kept on disk in page coordinates.
enum InkLayout {
    static func translated(_ stroke: PKStroke, by offset: CGPoint) -> PKStroke {
        var moved = stroke
        moved.transform = stroke.transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))
        return moved
    }

    static func merge(_ drawings: [PKDrawing], origins: [CGPoint]) -> PKDrawing {
        var strokes: [PKStroke] = []
        for (drawing, origin) in zip(drawings, origins) {
            strokes += drawing.strokes.map { translated($0, by: origin) }
        }
        return PKDrawing(strokes: strokes)
    }

    static func split(_ drawing: PKDrawing, layout: PageLayout) -> [PKDrawing] {
        var buckets = Array(repeating: [PKStroke](), count: layout.frames.count)
        guard !buckets.isEmpty else { return [] }
        for stroke in drawing.strokes {
            let i = layout.index(for: stroke.renderBounds)
            let origin = layout.frames[i].origin
            buckets[i].append(translated(stroke, by: CGPoint(x: -origin.x, y: -origin.y)))
        }
        return buckets.map { PKDrawing(strokes: $0) }
    }
}
