import UIKit

enum TemplateCategory: String, CaseIterable, Identifiable {
    case essentials = "Essentials"
    case study = "Study"
    case engineering = "Engineering"
    case planners = "Planners & Lists"
    case creative = "Creative"

    var id: String { rawValue }
}

enum PaperKind: String, Codable, CaseIterable, Identifiable {
    case blank, ruled, narrowRuled, grid, smallGrid, dotted
    case cornell, lecture, problem, twoColumn
    case engineering, graph, isometric
    case todo, weekly
    case music

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blank: return "Blank"
        case .ruled: return "Ruled"
        case .narrowRuled: return "Narrow Ruled"
        case .grid: return "Grid"
        case .smallGrid: return "5 mm Grid"
        case .dotted: return "Dotted"
        case .cornell: return "Cornell"
        case .lecture: return "Lecture Notes"
        case .problem: return "Problem Sheet"
        case .twoColumn: return "Two Column"
        case .engineering: return "Engineering Pad"
        case .graph: return "Graph Paper"
        case .isometric: return "Isometric"
        case .todo: return "To-Do List"
        case .weekly: return "Weekly Planner"
        case .music: return "Music Staff"
        }
    }

    var blurb: String {
        switch self {
        case .blank: return "Nothing in the way."
        case .ruled: return "Wide lines with a margin."
        case .narrowRuled: return "Closer lines for small handwriting."
        case .grid: return "6 mm squares."
        case .smallGrid: return "5 mm squares for sketches and tables."
        case .dotted: return "Dots that guide without shouting."
        case .cornell: return "Cue column, notes and a summary box."
        case .lecture: return "Course, date and topic header over ruled lines."
        case .problem: return "Given, Find, Diagram and a gridded Solution area."
        case .twoColumn: return "Two ruled columns, for formulas or comparisons."
        case .engineering: return "Green engineering paper with a title block."
        case .graph: return "Millimetre graph paper with 5 and 10 mm lines."
        case .isometric: return "Triangular dot lattice for 3D sketches."
        case .todo: return "Checkbox rows with a date line."
        case .weekly: return "Seven day boxes and a notes box."
        case .music: return "Five-line staves."
        }
    }

    var category: TemplateCategory {
        switch self {
        case .blank, .ruled, .narrowRuled, .grid, .smallGrid, .dotted: return .essentials
        case .cornell, .lecture, .problem, .twoColumn: return .study
        case .engineering, .graph, .isometric: return .engineering
        case .todo, .weekly: return .planners
        case .music: return .creative
        }
    }

    /// The short list shown in quick pickers.
    static let quick: [PaperKind] = [.blank, .ruled, .grid, .dotted, .cornell, .problem, .engineering]
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

    /// Margin lines, dividers and header labels.
    var accent: UIColor {
        switch self {
        case .dark: return UIColor(red: 0.55, green: 0.30, blue: 0.33, alpha: 1)
        default: return UIColor(red: 0.91, green: 0.58, blue: 0.58, alpha: 1)
        }
    }

    var label2: UIColor {
        switch self {
        case .dark: return UIColor(white: 0.62, alpha: 1)
        default: return UIColor(red: 0.45, green: 0.52, blue: 0.60, alpha: 1)
        }
    }
}

struct Paper: Codable, Equatable, Hashable {
    var kind: PaperKind
    var tone: PaperTone
    /// Name of an imported template in Documents/Templates; overrides `kind` when set.
    var custom: String? = nil

    static let ruled = Paper(kind: .ruled, tone: .white)

    var label: String { custom ?? kind.label }
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
