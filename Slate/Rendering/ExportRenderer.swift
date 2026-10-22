import UIKit
import PDFKit
import PencilKit

/// Writes a notebook as a flat PDF: each page's background stays vector, items are drawn
/// on top, and ink is drawn as vector paths (not a picture), so it stays sharp when printed.
enum ExportRenderer {
    static func pdf(of document: NotebookDocument, drawings: [PKDrawing], pages: Range<Int>? = nil) -> Data {
        let range = pages ?? 0..<document.pageCount
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PageSizePreset.a4.size))
        return renderer.pdfData { ctx in
            for index in range {
                let size = document.pageSize(at: index)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                let c = ctx.cgContext
                if let page = document.pdf.page(at: index), let cg = page.pageRef {
                    c.saveGState()
                    c.translateBy(x: 0, y: size.height)
                    c.scaleBy(x: 1, y: -1)
                    c.concatenate(cg.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                         rotate: 0, preserveAspectRatio: true))
                    c.drawPDFPage(cg)
                    c.restoreGState()
                }
                for item in document.items(onPage: index) {
                    ItemRenderer.draw(item, imageLoader: { document.image(named: $0) })
                }
                if let drawing = drawings[safe: index] {
                    drawInk(drawing, in: c)
                }
            }
        }
    }

    /// Ink as vector paths: each stroke becomes short round-capped segments whose width
    /// follows the pen pressure. Highlighter strokes are drawn translucent with multiply.
    static func drawInk(_ drawing: PKDrawing, in c: CGContext) {
        for stroke in drawing.strokes {
            let points = Array(stroke.path.interpolatedPoints(by: .distance(1.5)))
            guard !points.isEmpty else { continue }
            c.saveGState()
            if let mask = stroke.mask {
                let clip = mask.copy() as! UIBezierPath
                clip.apply(stroke.transform)
                c.addPath(clip.cgPath)
                c.clip()
            }
            let isMarker = stroke.ink.inkType == .marker
            var color = stroke.ink.color
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                color = color.resolvedColor(with: .current)
            }
            if isMarker {
                c.setBlendMode(.multiply)
                color = color.withAlphaComponent(0.45)
            }
            c.setLineCap(isMarker ? .square : .round)
            c.setLineJoin(.round)
            if points.count == 1 {
                let p = points[0].location.applying(stroke.transform)
                let r = max(points[0].size.width, 0.5) / 2
                c.setFillColor(color.cgColor)
                c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            } else if isMarker {
                // One path keeps overlaps from darkening.
                c.setStrokeColor(color.cgColor)
                c.setLineWidth(points.map(\.size.width).max() ?? 10)
                c.addLines(between: points.map { $0.location.applying(stroke.transform) })
                c.strokePath()
            } else {
                for i in 1..<points.count {
                    let a = points[i - 1], b = points[i]
                    c.setStrokeColor(color.withAlphaComponent(color.cgColor.alpha * b.opacity).cgColor)
                    c.setLineWidth(max((a.size.width + b.size.width) / 2, 0.3))
                    c.move(to: a.location.applying(stroke.transform))
                    c.addLine(to: b.location.applying(stroke.transform))
                    c.strokePath()
                }
            }
            c.restoreGState()
        }
    }

    /// Zips a folder with the system's own archiver (the same one Files uses for "Compress").
    static func zip(folder: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinatorError) { zipped in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zipped, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
    }

    static var exportFolder: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
