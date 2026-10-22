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
/// Pages stack vertically and are centred on the widest page.
struct PageLayout {
    static let margin: CGFloat = 32
    static let gap: CGFloat = 32

    let frames: [CGRect]
    let contentSize: CGSize

    init(sizes: [CGSize]) {
        let maxWidth = sizes.map(\.width).max() ?? PageSizePreset.a4.size.width
        var y = Self.margin
        var frames: [CGRect] = []
        for size in sizes {
            frames.append(CGRect(x: Self.margin + (maxWidth - size.width) / 2, y: y,
                                 width: size.width, height: size.height))
            y += size.height + Self.gap
        }
        self.frames = frames
        contentSize = CGSize(width: maxWidth + 2 * Self.margin,
                             height: sizes.isEmpty ? 2 * Self.margin : y - Self.gap + Self.margin)
    }

    /// The page a vertical position belongs to; the gap below a page counts half to each side.
    func index(atY y: CGFloat) -> Int {
        guard !frames.isEmpty else { return 0 }
        for (i, frame) in frames.enumerated() where y < frame.maxY + Self.gap / 2 {
            return i
        }
        return frames.count - 1
    }

    func index(for rect: CGRect) -> Int {
        index(atY: rect.midY)
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
