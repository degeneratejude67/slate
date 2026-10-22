import SwiftUI
import UIKit

struct RGBA: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func clamp(_ v: CGFloat) -> Double { Double(min(max(v, 0), 1)) }
        self.init(clamp(r), clamp(g), clamp(b), clamp(a))
    }

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(uiColor: uiColor) }
}

enum ItemFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono, hand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sans"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .hand: return "Handwritten"
        }
    }

    func font(size: CGFloat, bold: Bool) -> UIFont {
        if self == .hand {
            let name = bold ? "Noteworthy-Bold" : "Noteworthy-Light"
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        default: design = .default
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

enum TextFill: String, Codable, CaseIterable, Identifiable {
    case none, yellow, blue, green, pink

    var id: String { rawValue }
    var label: String { self == .none ? "No Fill" : rawValue.capitalized + " Note" }

    var rgba: RGBA? {
        switch self {
        case .none: return nil
        case .yellow: return RGBA(1.0, 0.95, 0.62)
        case .blue: return RGBA(0.82, 0.90, 1.0)
        case .green: return RGBA(0.84, 0.95, 0.80)
        case .pink: return RGBA(1.0, 0.86, 0.90)
        }
    }
}

struct TextStyle: Codable, Equatable {
    var font: ItemFont = .system
    var size: Double = 18
    var bold = false
    var fill: TextFill = .none

    static let sizes: [Double] = [12, 14, 16, 18, 22, 28, 36, 48]
}

/// Something placed on a page besides ink: a text box, a picture or a sticker.
/// Frames are in page coordinates (points, origin top left of the page).
struct PageItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case text, image, sticker }

    var id: UUID
    var kind: Kind
    var frame: CGRect
    var text: String?
    var style: TextStyle?
    var color: RGBA?
    var image: String?
    var sticker: String?

    init(id: UUID = UUID(), kind: Kind, frame: CGRect, text: String? = nil, style: TextStyle? = nil,
         color: RGBA? = nil, image: String? = nil, sticker: String? = nil) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.text = text
        self.style = style
        self.color = color
        self.image = image
        self.sticker = sticker
    }

    static let textInset: CGFloat = 6

    var uiFont: UIFont {
        let s = style ?? TextStyle()
        return s.font.font(size: CGFloat(s.size), bold: s.bold)
    }

    /// Height a text box needs at its current width.
    func fittedTextHeight() -> CGFloat {
        let width = max(frame.width - 2 * Self.textInset, 10)
        let text = (self.text?.isEmpty ?? true) ? "M" : self.text!
        let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   attributes: [.font: uiFont], context: nil)
        return ceil(rect.height) + 2 * Self.textInset
    }
}
