import UIKit
import PDFKit

/// Draws paper templates. Template pages are stored as real PDF pages, so blank notebooks
/// and imported PDFs go through the same page pipeline.
enum TemplateRenderer {
    static func pdfData(paper: Paper, size: CGSize, count: Int = 1) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            for _ in 0..<max(1, count) {
                ctx.beginPage()
                draw(paper, in: ctx.cgContext, size: size)
            }
        }
    }

    static func previewImage(_ paper: Paper, size: CGSize, width: CGFloat) -> UIImage {
        let scale = width / size.width
        let out = CGSize(width: width, height: (size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: out).image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            draw(paper, in: ctx.cgContext, size: size)
        }
    }

    /// Draws in UIKit coordinates (origin top left).
    static func draw(_ paper: Paper, in c: CGContext, size: CGSize) {
        c.setFillColor(paper.tone.fill.cgColor)
        c.fill(CGRect(origin: .zero, size: size))

        // Spacing is set for A4 portrait and scales with the page width.
        let s = size.width / 595.28
        let top = 72 * s
        c.setLineWidth(0.6)
        c.setStrokeColor(paper.tone.line.cgColor)

        switch paper.kind {
        case .blank:
            break
        case .ruled:
            horizontalLines(c, size: size, from: top, to: size.height - 36 * s, spacing: 24 * s)
            verticalLine(c, x: 64 * s, from: 0, to: size.height, color: paper.tone.accent)
        case .grid:
            let step = 17 * s
            var x = step
            while x < size.width {
                c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: size.height)); x += step
            }
            var y = step
            while y < size.height {
                c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: size.width, y: y)); y += step
            }
            c.strokePath()
        case .dotted:
            let step = 17 * s
            let r = 0.9 * s
            c.setFillColor(paper.tone.line.cgColor)
            var y = step
            while y < size.height {
                var x = step
                while x < size.width {
                    c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)); x += step
                }
                y += step
            }
        case .cornell:
            let summaryTop = size.height - 150 * s
            horizontalLines(c, size: size, from: top, to: summaryTop, spacing: 24 * s)
            c.setLineWidth(1.2)
            c.setStrokeColor(paper.tone.accent.cgColor)
            c.move(to: CGPoint(x: 0, y: top)); c.addLine(to: CGPoint(x: size.width, y: top))
            c.move(to: CGPoint(x: 160 * s, y: top)); c.addLine(to: CGPoint(x: 160 * s, y: summaryTop))
            c.move(to: CGPoint(x: 0, y: summaryTop)); c.addLine(to: CGPoint(x: size.width, y: summaryTop))
            c.strokePath()
        }
    }

    private static func horizontalLines(_ c: CGContext, size: CGSize, from top: CGFloat, to bottom: CGFloat, spacing: CGFloat) {
        var y = top
        while y <= bottom {
            c.move(to: CGPoint(x: 0, y: y))
            c.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        c.strokePath()
    }

    private static func verticalLine(_ c: CGContext, x: CGFloat, from top: CGFloat, to bottom: CGFloat, color: UIColor) {
        c.saveGState()
        c.setStrokeColor(color.cgColor)
        c.setLineWidth(0.8)
        c.move(to: CGPoint(x: x, y: top))
        c.addLine(to: CGPoint(x: x, y: bottom))
        c.strokePath()
        c.restoreGState()
    }
}
