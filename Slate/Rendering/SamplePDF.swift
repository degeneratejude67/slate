import UIKit
import PDFKit

/// A small lecture-like PDF for the UI tests: a 16:9 slide, an A4 page of text, and an
/// A4 page stored with /Rotate 90, the case that breaks naive PDF drawing.
enum SamplePDF {
    static func make() -> Data {
        let slide = CGRect(x: 0, y: 0, width: 960, height: 540)
        let a4 = CGRect(origin: .zero, size: PageSizePreset.a4.size)
        let renderer = UIGraphicsPDFRenderer(bounds: slide)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1).setFill()
            ctx.fill(slide)
            text("Lecture 3: Pelton Wheel", at: CGPoint(x: 60, y: 48), size: 40, weight: .bold)
            let bullets = ["Impulse turbine for high head, low flow",
                           "Jet velocity  V1 = Cv * sqrt(2 g H)",
                           "Bucket speed ratio  u / V1 ~ 0.46",
                           "Hydraulic efficiency peaks at u = V1 / 2"]
            for (i, line) in bullets.enumerated() {
                text("•  " + line, at: CGPoint(x: 70, y: 140 + CGFloat(i) * 52), size: 26, weight: .regular)
            }
            let c = ctx.cgContext
            c.setStrokeColor(UIColor(red: 0.2, green: 0.4, blue: 0.75, alpha: 1).cgColor)
            c.setLineWidth(4)
            c.strokeEllipse(in: CGRect(x: 680, y: 170, width: 220, height: 220))
            for k in 0..<12 {
                let a = CGFloat(k) / 12 * 2 * .pi
                c.move(to: CGPoint(x: 790 + cos(a) * 60, y: 280 + sin(a) * 60))
                c.addLine(to: CGPoint(x: 790 + cos(a) * 110, y: 280 + sin(a) * 110))
            }
            c.strokePath()

            ctx.beginPage(withBounds: a4, pageInfo: [:])
            text("Worked example", at: CGPoint(x: 56, y: 60), size: 24, weight: .semibold)
            for i in 0..<18 {
                text("Line \(i + 1): head H = \(40 + i * 5) m, flow Q = 0.\(i + 2) m^3/s",
                     at: CGPoint(x: 56, y: 110 + CGFloat(i) * 34), size: 15, weight: .regular)
            }

            ctx.beginPage(withBounds: a4, pageInfo: [:])
            text("Rotated page", at: CGPoint(x: 56, y: 60), size: 34, weight: .bold)
            text("This text reads upright when /Rotate is honoured.", at: CGPoint(x: 56, y: 120), size: 16, weight: .regular)
        }
        guard let doc = PDFDocument(data: data), let rotated = doc.page(at: 2) else { return data }
        rotated.rotation = 90
        return doc.dataRepresentation() ?? data
    }

    private static func text(_ s: String, at p: CGPoint, size: CGFloat, weight: UIFont.Weight) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor(white: 0.12, alpha: 1),
        ]
        (s as NSString).draw(at: p, withAttributes: attrs)
    }
}
