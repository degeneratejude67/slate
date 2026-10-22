import UIKit
import PDFKit
import PencilKit

/// Draws paper templates. Template pages are stored as real PDF pages, so blank notebooks
/// and imported PDFs go through the same page pipeline.
enum TemplateRenderer {
    static func pdfData(paper: Paper, size: CGSize, count: Int = 1) -> Data {
        if let name = paper.custom, let page = TemplateStore.page(named: name) {
            return customPDFData(page: page, count: count)
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            for _ in 0..<max(1, count) {
                ctx.beginPage()
                draw(paper, in: ctx.cgContext, size: size)
            }
        }
    }

    /// The page size a paper produces: an imported template keeps its own size.
    static func pageSize(for paper: Paper, default size: CGSize) -> CGSize {
        if let name = paper.custom, let page = TemplateStore.page(named: name) {
            return PageGeometry.displaySize(page)
        }
        return size
    }

    static func previewImage(_ paper: Paper, size: CGSize, width: CGFloat) -> UIImage {
        if let name = paper.custom, let page = TemplateStore.page(named: name) {
            let pageSize = PageGeometry.displaySize(page)
            return Thumbnailer.image(page: page, pageSize: pageSize, drawing: .init(), width: width)
        }
        let scale = width / size.width
        let out = CGSize(width: width, height: (size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: out).image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            draw(paper, in: ctx.cgContext, size: size)
        }
    }

    private static func customPDFData(page: PDFPage, count: Int) -> Data {
        let size = PageGeometry.displaySize(page)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            for _ in 0..<max(1, count) {
                ctx.beginPage()
                guard let cg = page.pageRef else { continue }
                let c = ctx.cgContext
                c.saveGState()
                c.translateBy(x: 0, y: size.height)
                c.scaleBy(x: 1, y: -1)
                c.concatenate(cg.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                     rotate: 0, preserveAspectRatio: true))
                c.drawPDFPage(cg)
                c.restoreGState()
            }
        }
    }

    // MARK: Drawing (UIKit coordinates, origin top left)

    static func draw(_ paper: Paper, in c: CGContext, size: CGSize) {
        let tone = paper.tone
        let fill = paper.kind == .engineering && tone == .white
            ? UIColor(red: 0.93, green: 0.97, blue: 0.91, alpha: 1)
            : tone.fill
        c.setFillColor(fill.cgColor)
        c.fill(CGRect(origin: .zero, size: size))

        let s = size.width / 595.28          // spacing is set for A4 portrait
        let w = size.width, h = size.height
        let top = 72 * s
        let side = 36 * s
        c.setLineWidth(0.6)
        c.setStrokeColor(tone.line.cgColor)

        switch paper.kind {
        case .blank:
            break

        case .ruled:
            hLines(c, x0: 0, x1: w, from: top, to: h - 36 * s, step: 24 * s)
            vLine(c, x: 64 * s, from: 0, to: h, color: tone.accent, width: 0.8)

        case .narrowRuled:
            hLines(c, x0: 0, x1: w, from: top, to: h - 30 * s, step: 18 * s)
            vLine(c, x: 56 * s, from: 0, to: h, color: tone.accent, width: 0.8)

        case .grid:
            grid(c, size: size, step: 17 * s)

        case .smallGrid:
            grid(c, size: size, step: 14.17 * s)

        case .dotted:
            dots(c, size: size, step: 17 * s, radius: 0.9 * s, color: tone.line)

        case .cornell:
            let summaryTop = h - 150 * s
            hLines(c, x0: 0, x1: w, from: top, to: summaryTop, step: 24 * s)
            c.setLineWidth(1.2)
            c.setStrokeColor(tone.accent.cgColor)
            line(c, 0, top, w, top)
            line(c, 160 * s, top, 160 * s, summaryTop)
            line(c, 0, summaryTop, w, summaryTop)
            c.strokePath()
            label(c, "CUES", at: CGPoint(x: side * 0.6, y: top + 6 * s), size: 8 * s, color: tone.label2)
            label(c, "SUMMARY", at: CGPoint(x: side * 0.6, y: summaryTop + 6 * s), size: 8 * s, color: tone.label2)

        case .lecture:
            header(c, fields: [("COURSE", 0.0), ("DATE", 0.62)], y: 40 * s, size: size, s: s, tone: tone)
            header(c, fields: [("TOPIC", 0.0)], y: 78 * s, size: size, s: s, tone: tone)
            hLines(c, x0: side, x1: w - side, from: 124 * s, to: h - 36 * s, step: 24 * s)

        case .problem:
            header(c, fields: [("PROBLEM", 0.0), ("SOURCE", 0.55)], y: 40 * s, size: size, s: s, tone: tone)
            let boxTop = 66 * s, boxH = 120 * s, mid = w / 2
            box(c, CGRect(x: side, y: boxTop, width: mid - side - 6 * s, height: boxH), title: "GIVEN", s: s, tone: tone)
            box(c, CGRect(x: mid + 6 * s, y: boxTop, width: mid - side - 6 * s, height: boxH), title: "FIND", s: s, tone: tone)
            let diagramTop = boxTop + boxH + 12 * s
            box(c, CGRect(x: side, y: diagramTop, width: w - 2 * side, height: 170 * s), title: "DIAGRAM", s: s, tone: tone)
            let solutionTop = diagramTop + 182 * s
            box(c, CGRect(x: side, y: solutionTop, width: w - 2 * side, height: h - solutionTop - 30 * s),
                title: "SOLUTION", s: s, tone: tone)
            c.saveGState()
            c.clip(to: CGRect(x: side, y: solutionTop + 18 * s, width: w - 2 * side, height: h - solutionTop - 48 * s))
            c.setStrokeColor(tone.line.withAlphaComponent(0.55).cgColor)
            grid(c, size: size, step: 14.17 * s)
            c.restoreGState()

        case .twoColumn:
            header(c, fields: [("TITLE", 0.0)], y: 40 * s, size: size, s: s, tone: tone)
            hLines(c, x0: side, x1: w - side, from: 96 * s, to: h - 36 * s, step: 24 * s)
            c.setStrokeColor(tone.accent.cgColor)
            c.setLineWidth(1)
            line(c, w / 2, 80 * s, w / 2, h - 30 * s)
            c.strokePath()

        case .engineering:
            let green = UIColor(red: 0.47, green: 0.69, blue: 0.47, alpha: tone == .dark ? 0.5 : 0.45)
            c.setStrokeColor(green.cgColor)
            c.saveGState()
            c.clip(to: CGRect(x: side, y: 80 * s, width: w - 2 * side, height: h - 110 * s))
            grid(c, size: size, step: 14.17 * s)
            c.restoreGState()
            c.setLineWidth(1.2)
            c.setStrokeColor(green.withAlphaComponent(0.9).cgColor)
            c.stroke(CGRect(x: side, y: 80 * s, width: w - 2 * side, height: h - 110 * s))
            let fields: [(String, CGFloat)] = [("NAME", 0.0), ("COURSE", 0.38), ("DATE", 0.68), ("PAGE", 0.86)]
            header(c, fields: fields, y: 50 * s, size: size, s: s, tone: tone, color: green.withAlphaComponent(0.9))

        case .graph:
            let mm = 2.8346 * s
            let base = UIColor(red: 0.90, green: 0.52, blue: 0.32, alpha: 1)
            let alpha: CGFloat = tone == .dark ? 0.55 : 1
            var i = 0
            var x: CGFloat = 0
            while x <= w {
                let weight = i % 10 == 0 ? 0.9 : (i % 5 == 0 ? 0.55 : 0.25)
                c.setStrokeColor(base.withAlphaComponent(weight * alpha * 0.8).cgColor)
                c.setLineWidth(i % 10 == 0 ? 0.8 : 0.35)
                line(c, x, 0, x, h); c.strokePath()
                x += mm; i += 1
            }
            i = 0
            var y: CGFloat = 0
            while y <= h {
                let weight = i % 10 == 0 ? 0.9 : (i % 5 == 0 ? 0.55 : 0.25)
                c.setStrokeColor(base.withAlphaComponent(weight * alpha * 0.8).cgColor)
                c.setLineWidth(i % 10 == 0 ? 0.8 : 0.35)
                line(c, 0, y, w, y); c.strokePath()
                y += mm; i += 1
            }

        case .isometric:
            let step = 20 * s
            let rowH = step * sqrt(3) / 2
            c.setFillColor(tone.line.cgColor)
            var row = 0
            var y: CGFloat = rowH
            while y < h {
                var x: CGFloat = row % 2 == 0 ? step / 2 : step
                while x < w {
                    c.fillEllipse(in: CGRect(x: x - 1.4 * s, y: y - 1.4 * s, width: 2.8 * s, height: 2.8 * s))
                    x += step
                }
                y += rowH; row += 1
            }

        case .todo:
            label(c, "TO DO", at: CGPoint(x: side, y: 34 * s), size: 20 * s, color: tone.label2, bold: true)
            header(c, fields: [("DATE", 0.6)], y: 50 * s, size: size, s: s, tone: tone)
            let rowStep = 32 * s
            var y = 100 * s
            while y < h - 40 * s {
                c.setStrokeColor(tone.line.cgColor)
                c.setLineWidth(0.6)
                line(c, side + 26 * s, y, w - side, y); c.strokePath()
                c.setStrokeColor(tone.label2.cgColor)
                c.setLineWidth(1)
                c.stroke(CGRect(x: side, y: y - 16 * s, width: 13 * s, height: 13 * s))
                y += rowStep
            }

        case .weekly:
            label(c, "WEEK OF", at: CGPoint(x: side, y: 34 * s), size: 11 * s, color: tone.label2, bold: true)
            c.setStrokeColor(tone.line.cgColor)
            line(c, side + 62 * s, 46 * s, w * 0.6, 46 * s); c.strokePath()
            let names = ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY", "NOTES"]
            let gridTop = 70 * s
            let cellW = (w - 2 * side - 10 * s) / 2
            let cellH = (h - gridTop - 30 * s - 30 * s) / 4
            for (i, name) in names.enumerated() {
                let col = CGFloat(i % 2), rowIndex = CGFloat(i / 2)
                let rect = CGRect(x: side + col * (cellW + 10 * s), y: gridTop + rowIndex * (cellH + 10 * s),
                                  width: cellW, height: cellH)
                box(c, rect, title: name, s: s, tone: tone)
                c.setStrokeColor(tone.line.withAlphaComponent(0.6).cgColor)
                c.setLineWidth(0.5)
                hLines(c, x0: rect.minX + 8 * s, x1: rect.maxX - 8 * s, from: rect.minY + 44 * s,
                       to: rect.maxY - 8 * s, step: 22 * s)
            }

        case .music:
            let lineGap = 7 * s
            let staveGap = 46 * s
            var y = top
            c.setStrokeColor(tone.label2.withAlphaComponent(0.7).cgColor)
            c.setLineWidth(0.7)
            while y + 4 * lineGap < h - 30 * s {
                for k in 0..<5 { line(c, side, y + CGFloat(k) * lineGap, w - side, y + CGFloat(k) * lineGap) }
                c.strokePath()
                y += 4 * lineGap + staveGap
            }
        }
    }

    // MARK: Helpers

    private static func line(_ c: CGContext, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
        c.move(to: CGPoint(x: x0, y: y0))
        c.addLine(to: CGPoint(x: x1, y: y1))
    }

    private static func hLines(_ c: CGContext, x0: CGFloat, x1: CGFloat, from top: CGFloat, to bottom: CGFloat, step: CGFloat) {
        var y = top
        while y <= bottom {
            line(c, x0, y, x1, y)
            y += step
        }
        c.strokePath()
    }

    private static func vLine(_ c: CGContext, x: CGFloat, from top: CGFloat, to bottom: CGFloat, color: UIColor, width: CGFloat) {
        c.saveGState()
        c.setStrokeColor(color.cgColor)
        c.setLineWidth(width)
        line(c, x, top, x, bottom)
        c.strokePath()
        c.restoreGState()
    }

    private static func grid(_ c: CGContext, size: CGSize, step: CGFloat) {
        var x = step
        while x < size.width { line(c, x, 0, x, size.height); x += step }
        var y = step
        while y < size.height { line(c, 0, y, size.width, y); y += step }
        c.strokePath()
    }

    private static func dots(_ c: CGContext, size: CGSize, step: CGFloat, radius r: CGFloat, color: UIColor) {
        c.setFillColor(color.cgColor)
        var y = step
        while y < size.height {
            var x = step
            while x < size.width {
                c.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                x += step
            }
            y += step
        }
    }

    private static func label(_ c: CGContext, _ text: String, at p: CGPoint, size: CGFloat, color: UIColor, bold: Bool = false) {
        UIGraphicsPushContext(c)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold),
            .foregroundColor: color,
            .kern: size * 0.12,
        ]
        (text as NSString).draw(at: p, withAttributes: attrs)
        UIGraphicsPopContext()
    }

    /// A row of "LABEL ________" fields; `fields` holds each label and its start as a
    /// fraction of the usable width.
    private static func header(_ c: CGContext, fields: [(String, CGFloat)], y: CGFloat, size: CGSize, s: CGFloat,
                               tone: PaperTone, color: UIColor? = nil) {
        let side = 36 * s
        let usable = size.width - 2 * side
        for (i, field) in fields.enumerated() {
            let x0 = side + usable * field.1
            let x1 = i + 1 < fields.count ? side + usable * fields[i + 1].1 - 14 * s : size.width - side
            label(c, field.0, at: CGPoint(x: x0, y: y - 11 * s), size: 7.5 * s, color: color ?? tone.label2)
            c.setStrokeColor((color ?? tone.line).cgColor)
            c.setLineWidth(0.8)
            let textWidth = CGFloat(field.0.count) * 6.2 * s + 6 * s
            line(c, x0 + textWidth, y, x1, y)
            c.strokePath()
        }
    }

    private static func box(_ c: CGContext, _ rect: CGRect, title: String, s: CGFloat, tone: PaperTone) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6 * s)
        c.setStrokeColor(tone.line.cgColor)
        c.setLineWidth(0.9)
        c.addPath(path.cgPath)
        c.strokePath()
        label(c, title, at: CGPoint(x: rect.minX + 8 * s, y: rect.minY + 6 * s), size: 7.5 * s, color: tone.label2)
    }
}

/// Templates the user imported (a PDF page or a picture), kept in Documents/Templates.
enum TemplateStore {
    static var folder: URL {
        let url = AppEnv.libraryRoot.deletingLastPathComponent().appendingPathComponent("Templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var cache: [String: PDFDocument] = [:]

    static func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.filter { $0.lowercased().hasSuffix(".pdf") }
            .map { String($0.dropLast(4)) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func page(named name: String) -> PDFPage? {
        if let doc = cache[name] { return doc.page(at: 0) }
        guard let doc = PDFDocument(url: folder.appendingPathComponent(name + ".pdf")) else { return nil }
        cache[name] = doc
        return doc.page(at: 0)
    }

    /// Copies the first page of a PDF, or a picture fitted to A4, in as a template.
    @discardableResult
    static func importFile(_ source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var name = source.deletingPathExtension().lastPathComponent
        var n = 2
        while names().contains(name) { name = source.deletingPathExtension().lastPathComponent + " \(n)"; n += 1 }
        let target = folder.appendingPathComponent(name + ".pdf")

        if let doc = PDFDocument(url: source), let first = doc.page(at: 0) {
            let single = PDFDocument()
            single.insert(first, at: 0)
            guard single.write(to: target) else { throw SlateError.writeFailed("the template") }
        } else if let image = UIImage(contentsOfFile: source.path) {
            let a4 = PageSizePreset.a4.size
            let size = image.size.width > image.size.height ? CGSize(width: a4.height, height: a4.width) : a4
            let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { ctx in
                ctx.beginPage()
                let scale = min(size.width / image.size.width, size.height / image.size.height)
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
            }
            try data.write(to: target, options: .atomic)
        } else {
            throw SlateError.unreadablePDF(source.lastPathComponent)
        }
        cache[name] = nil
        return name
    }

    static func delete(_ name: String) {
        cache[name] = nil
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".pdf"))
    }
}
