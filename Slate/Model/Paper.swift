import UIKit

enum PaperKind: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, grid, dotted, cornell

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PaperTone: String, Codable, CaseIterable, Identifiable {
    case white, cream, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var fill: UIColor {
        switch self {
        case .white: return .white
        case .cream: return UIColor(red: 0.992, green: 0.973, blue: 0.925, alpha: 1)
        case .dark: return UIColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1)
        }
    }

    var line: UIColor {
        switch self {
        case .white: return UIColor(red: 0.72, green: 0.80, blue: 0.88, alpha: 1)
        case .cream: return UIColor(red: 0.80, green: 0.76, blue: 0.66, alpha: 1)
        case .dark: return UIColor(red: 0.32, green: 0.35, blue: 0.40, alpha: 1)
        }
    }

    /// Margin and Cornell divider lines.
    var accent: UIColor {
        switch self {
        case .dark: return UIColor(red: 0.55, green: 0.30, blue: 0.33, alpha: 1)
        default: return UIColor(red: 0.91, green: 0.58, blue: 0.58, alpha: 1)
        }
    }
}

struct Paper: Codable, Equatable, Hashable {
    var kind: PaperKind
    var tone: PaperTone

    static let ruled = Paper(kind: .ruled, tone: .white)
}

enum PageSizePreset: String, Codable, CaseIterable, Identifiable {
    case a4, letter, slide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .a4: return "A4"
        case .letter: return "Letter"
        case .slide: return "Slide 16:9"
        }
    }

    var size: CGSize {
        switch self {
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .letter: return CGSize(width: 612, height: 792)
        case .slide: return CGSize(width: 960, height: 540)
        }
    }
}
