import SwiftUI

enum CoverPattern {
    case none, linen, kraft, grid, dots, stripes, terrazzo
}

enum CoverStyle: String, Codable, CaseIterable, Identifiable {
    case slate, navy, forest, maroon, sand, plum, teal, coral, mustard, charcoal, sky, rose
    case linen, kraft, blueprint, polka, stripes, terrazzo

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .slate: return Color(red: 0.24, green: 0.30, blue: 0.37)
        case .navy: return Color(red: 0.15, green: 0.24, blue: 0.40)
        case .forest: return Color(red: 0.19, green: 0.38, blue: 0.32)
        case .maroon: return Color(red: 0.49, green: 0.19, blue: 0.24)
        case .sand: return Color(red: 0.78, green: 0.70, blue: 0.54)
        case .plum: return Color(red: 0.37, green: 0.24, blue: 0.43)
        case .teal: return Color(red: 0.13, green: 0.45, blue: 0.48)
        case .coral: return Color(red: 0.86, green: 0.43, blue: 0.36)
        case .mustard: return Color(red: 0.83, green: 0.64, blue: 0.20)
        case .charcoal: return Color(red: 0.17, green: 0.17, blue: 0.19)
        case .sky: return Color(red: 0.45, green: 0.66, blue: 0.84)
        case .rose: return Color(red: 0.80, green: 0.52, blue: 0.58)
        case .linen: return Color(red: 0.86, green: 0.82, blue: 0.74)
        case .kraft: return Color(red: 0.69, green: 0.54, blue: 0.38)
        case .blueprint: return Color(red: 0.12, green: 0.30, blue: 0.55)
        case .polka: return Color(red: 0.95, green: 0.78, blue: 0.70)
        case .stripes: return Color(red: 0.26, green: 0.36, blue: 0.48)
        case .terrazzo: return Color(red: 0.93, green: 0.91, blue: 0.87)
        }
    }

    var pattern: CoverPattern {
        switch self {
        case .linen: return .linen
        case .kraft: return .kraft
        case .blueprint: return .grid
        case .polka: return .dots
        case .stripes: return .stripes
        case .terrazzo: return .terrazzo
        default: return .none
        }
    }

    /// Text on the cover label stays dark on light covers.
    var isLight: Bool {
        switch self {
        case .sand, .mustard, .linen, .polka, .terrazzo, .sky, .rose: return true
        default: return false
        }
    }
}

struct PageMeta: Codable, Equatable, Identifiable {
    var id: UUID
    /// The paper a template page was made with; nil for a page of an imported PDF.
    var paper: Paper?
    var items: [PageItem]

    init(id: UUID, paper: Paper?, items: [PageItem] = []) {
        self.id = id
        self.paper = paper
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        paper = (try? c.decodeIfPresent(Paper.self, forKey: .paper)) ?? nil
        items = (try? c.decodeIfPresent([PageItem].self, forKey: .items)) ?? []
    }
}

/// Contents of `notebook.json` inside a `<Title>.slate` folder.
struct NotebookMeta: Codable, Equatable {
    var version: Int
    var id: UUID
    var title: String
    var created: Date
    var modified: Date
    var cover: CoverStyle
    var pages: [PageMeta]
    var bookmarks: [UUID]
    var lastPage: Int
    var source: String?

    init(title: String, cover: CoverStyle, pages: [PageMeta], source: String? = nil) {
        let now = Date()
        version = 1
        id = UUID()
        self.title = title
        created = now
        modified = now
        self.cover = cover
        self.pages = pages
        bookmarks = []
        lastPage = 0
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
        cover = ((try? c.decodeIfPresent(CoverStyle.self, forKey: .cover)) ?? nil) ?? .slate
        pages = try c.decodeIfPresent([PageMeta].self, forKey: .pages) ?? []
        bookmarks = try c.decodeIfPresent([UUID].self, forKey: .bookmarks) ?? []
        lastPage = try c.decodeIfPresent(Int.self, forKey: .lastPage) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}

extension JSONEncoder {
    static var slate: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var slate: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
