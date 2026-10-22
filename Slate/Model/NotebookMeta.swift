import SwiftUI

enum CoverStyle: String, Codable, CaseIterable, Identifiable {
    case slate, navy, forest, maroon, sand, plum

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .slate: return Color(red: 0.24, green: 0.30, blue: 0.37)
        case .navy: return Color(red: 0.15, green: 0.24, blue: 0.40)
        case .forest: return Color(red: 0.19, green: 0.38, blue: 0.32)
        case .maroon: return Color(red: 0.49, green: 0.19, blue: 0.24)
        case .sand: return Color(red: 0.78, green: 0.70, blue: 0.54)
        case .plum: return Color(red: 0.37, green: 0.24, blue: 0.43)
        }
    }
}

struct PageMeta: Codable, Equatable, Identifiable {
    var id: UUID
    /// The paper a template page was made with; nil for a page of an imported PDF.
    var paper: Paper?
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
        cover = try c.decodeIfPresent(CoverStyle.self, forKey: .cover) ?? .slate
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
