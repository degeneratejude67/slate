import UIKit

struct Sticker: Identifiable, Hashable {
    enum Art: Hashable {
        case symbol(String, [UIColor])
        case glyph(String, UIColor)
        case tag(String, UIColor)
        case tape(UIColor)
    }

    let id: String
    let art: Art

    /// Width over height of the rendered sticker.
    var aspect: CGFloat {
        switch art {
        case .symbol, .glyph: return 1
        case .tag(let text, _): return max(2.2, CGFloat(text.count) * 0.42 + 1.2)
        case .tape: return 4.2
        }
    }

    /// Size in page points when first placed.
    var defaultWidth: CGFloat {
        switch art {
        case .symbol, .glyph: return 64
        case .tag: return 150
        case .tape: return 170
        }
    }
}

struct StickerPack: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let stickers: [Sticker]
}

/// Built-in sticker packs, drawn at run time from SF Symbols and text, so they cost no
/// storage and stay sharp at any size.
enum StickerCatalog {
    static let defaultPacks = ["study", "labels", "arrows"]

    private static let ink = UIColor(red: 0.12, green: 0.20, blue: 0.36, alpha: 1)
    private static let red = UIColor(red: 0.85, green: 0.25, blue: 0.22, alpha: 1)
    private static let amber = UIColor(red: 0.96, green: 0.66, blue: 0.14, alpha: 1)
    private static let green = UIColor(red: 0.20, green: 0.62, blue: 0.38, alpha: 1)
    private static let blue = UIColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1)
    private static let purple = UIColor(red: 0.52, green: 0.33, blue: 0.78, alpha: 1)
    private static let teal = UIColor(red: 0.12, green: 0.55, blue: 0.58, alpha: 1)

    static let packs: [StickerPack] = [
        StickerPack(id: "study", name: "Study Marks", blurb: "Stars, flags and bulbs to mark what matters.", stickers: [
            symbol("star.fill", amber), symbol("exclamationmark.triangle.fill", amber), symbol("questionmark.circle.fill", blue),
            symbol("lightbulb.fill", amber), symbol("checkmark.seal.fill", green), symbol("flag.fill", red),
            symbol("bookmark.fill", red), symbol("pin.fill", red), symbol("target", red), symbol("flame.fill", UIColor.orange),
            symbol("heart.fill", red), symbol("graduationcap.fill", ink), symbol("brain.head.profile", purple),
            symbol("trophy.fill", amber), symbol("sparkles", amber), symbol("clock.fill", ink),
        ]),
        StickerPack(id: "labels", name: "Exam Labels", blurb: "Tags for formulas, definitions and past-paper questions.", stickers: [
            tag("Important", red), tag("Exam!", red), tag("Formula", blue), tag("Definition", purple),
            tag("Example", green), tag("Derivation", teal), tag("Revise", amber), tag("Asked in TF", ink),
            tag("Note", ink), tag("Remember", purple), tag("Doubt", UIColor.systemOrange), tag("Done", green),
        ]),
        StickerPack(id: "arrows", name: "Arrows", blurb: "Point things out and link ideas.", stickers: [
            symbol("arrow.right", ink), symbol("arrow.left", ink), symbol("arrow.up", ink), symbol("arrow.down", ink),
            symbol("arrow.up.right", ink), symbol("arrow.turn.down.right", ink), symbol("arrow.uturn.left", ink),
            symbol("arrow.left.and.right", ink), symbol("arrow.triangle.2.circlepath", ink), symbol("arrowshape.turn.up.right.fill", blue),
            symbol("arrow.clockwise", ink), symbol("arrow.right.circle.fill", red),
        ]),
        StickerPack(id: "maths", name: "Maths Symbols", blurb: "Clean symbols for quick formulas.", stickers: [
            glyph("∫"), glyph("∑"), glyph("√"), glyph("π"), glyph("Δ"), glyph("∂"), glyph("∞"), glyph("≈"),
            glyph("≠"), glyph("≤"), glyph("≥"), glyph("θ"), glyph("ω"), glyph("α"), glyph("β"), glyph("λ"),
            glyph("μ"), glyph("σ"), glyph("∇"), glyph("∝"),
        ]),
        StickerPack(id: "engineering", name: "Engineering", blurb: "Gears, flows and gauges for mechanical notes.", stickers: [
            symbol("gearshape.fill", ink), symbol("gearshape.2.fill", ink), symbol("bolt.fill", amber), symbol("wind", teal),
            symbol("drop.fill", blue), symbol("fanblades.fill", teal), symbol("flame.fill", red), symbol("speedometer", ink),
            symbol("ruler.fill", amber), symbol("wrench.and.screwdriver.fill", ink), symbol("hammer.fill", ink),
            symbol("cube.fill", purple), symbol("function", ink), symbol("waveform.path", blue), symbol("atom", purple),
            symbol("thermometer", red),
        ]),
        StickerPack(id: "tape", name: "Washi Tape", blurb: "Soft paper tape to frame a box or a heading.", stickers: [
            tape(UIColor(red: 0.98, green: 0.80, blue: 0.40, alpha: 0.75)), tape(UIColor(red: 0.60, green: 0.80, blue: 0.95, alpha: 0.75)),
            tape(UIColor(red: 0.98, green: 0.65, blue: 0.70, alpha: 0.75)), tape(UIColor(red: 0.66, green: 0.88, blue: 0.66, alpha: 0.75)),
            tape(UIColor(red: 0.80, green: 0.72, blue: 0.95, alpha: 0.75)), tape(UIColor(red: 0.85, green: 0.85, blue: 0.82, alpha: 0.8)),
        ]),
    ]

    private static func symbol(_ name: String, _ color: UIColor) -> Sticker {
        Sticker(id: "sym:" + name, art: .symbol(name, [color]))
    }

    private static func glyph(_ text: String) -> Sticker {
        Sticker(id: "glyph:" + text, art: .glyph(text, ink))
    }

    private static func tag(_ text: String, _ color: UIColor) -> Sticker {
        Sticker(id: "tag:" + text, art: .tag(text, color))
    }

    private static func tape(_ color: UIColor) -> Sticker {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hex = [r, g, b].map { String(Int($0 * 255), radix: 16) }.joined(separator: "-")
        return Sticker(id: "tape:" + hex, art: .tape(color))
    }

    private static let byID: [String: Sticker] = {
        var map: [String: Sticker] = [:]
        for pack in packs { for sticker in pack.stickers { map[sticker.id] = sticker } }
        return map
    }()

    static func sticker(_ id: String) -> Sticker? { byID[id] }

    private static let cache = NSCache<NSString, UIImage>()

    /// The sticker drawn `width` points wide (at 2x).
    static func image(for sticker: Sticker, width: CGFloat = 240) -> UIImage {
        let key = "\(sticker.id)#\(Int(width))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let size = CGSize(width: width, height: (width / sticker.aspect).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            switch sticker.art {
            case .symbol(let name, let colors):
                let config = UIImage.SymbolConfiguration(pointSize: size.height * 0.8, weight: .semibold)
                    .applying(UIImage.SymbolConfiguration(paletteColors: colors))
                if let symbol = UIImage(systemName: name, withConfiguration: config) {
                    let fit = aspectFit(symbol.size, in: rect.insetBy(dx: size.width * 0.06, dy: size.height * 0.06))
                    symbol.draw(in: fit)
                }
            case .glyph(let text, let color):
                let font = UIFont(name: "Georgia", size: size.height * 0.72) ?? .systemFont(ofSize: size.height * 0.72)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let textSize = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                                        withAttributes: attrs)
            case .tag(let text, let color):
                let inset = rect.insetBy(dx: 2, dy: 2)
                let path = UIBezierPath(roundedRect: inset, cornerRadius: inset.height / 2)
                color.withAlphaComponent(0.14).setFill()
                path.fill()
                color.setStroke()
                path.lineWidth = max(2, size.height * 0.05)
                path.stroke()
                let font = UIFont.systemFont(ofSize: size.height * 0.42, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let textSize = (text as NSString).size(withAttributes: attrs)
                (text as NSString).draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                                        withAttributes: attrs)
            case .tape(let color):
                let path = UIBezierPath()
                let teeth = 6
                let toothH = size.height / CGFloat(teeth)
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size.width, y: 0))
                for i in 0..<teeth {
                    let y = CGFloat(i) * toothH
                    path.addLine(to: CGPoint(x: size.width - (i % 2 == 0 ? 6 : 0), y: y + toothH / 2))
                    path.addLine(to: CGPoint(x: size.width, y: y + toothH))
                }
                path.addLine(to: CGPoint(x: 0, y: size.height))
                for i in (0..<teeth).reversed() {
                    let y = CGFloat(i) * toothH
                    path.addLine(to: CGPoint(x: i % 2 == 0 ? 6 : 0, y: y + toothH / 2))
                    path.addLine(to: CGPoint(x: 0, y: y))
                }
                path.close()
                color.setFill()
                path.fill()
                ctx.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
                var x: CGFloat = 8
                while x < size.width {
                    ctx.cgContext.fill(CGRect(x: x, y: 0, width: 5, height: size.height))
                    x += 16
                }
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
