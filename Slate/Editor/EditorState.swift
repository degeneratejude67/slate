import SwiftUI
import PencilKit

enum ToolKind: String, CaseIterable, Identifiable, Codable {
    case pen, pencil, highlighter, shape, eraser, lasso, text, select

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .shape: return "square.on.circle"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .text: return "textformat"
        case .select: return "hand.point.up.left"
        }
    }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        case .shape: return "Shapes"
        case .eraser: return "Eraser"
        case .lasso: return "Lasso"
        case .text: return "Text"
        case .select: return "Select"
        }
    }

    var usesColor: Bool { [.pen, .pencil, .highlighter, .shape, .text].contains(self) }
    var usesWidth: Bool { [.pen, .pencil, .highlighter, .shape].contains(self) }
    /// Tools that work on text boxes, pictures and stickers instead of ink.
    var editsItems: Bool { self == .text || self == .select }
}

enum PenStyle: String, CaseIterable, Identifiable, Codable {
    case ball, fountain, brush

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ball: return "Ballpoint"
        case .fountain: return "Fountain Pen"
        case .brush: return "Brush Pen"
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .ball: return .monoline
        case .fountain: return .fountainPen
        case .brush: return .pen
        }
    }
}

enum EraserMode: String, CaseIterable, Codable {
    case stroke, pixel
}

/// Pen settings, kept between notebooks like GoodNotes' favourite colours and widths.
struct ToolSettings: Codable, Equatable {
    static let penWidths: [CGFloat] = [1.6, 2.6, 4.2]
    static let pencilWidths: [CGFloat] = [1.8, 3.2, 5.2]
    static let highlightWidths: [CGFloat] = [10, 16, 24]

    var tool: ToolKind = .pen
    var penStyle: PenStyle = .ball
    var eraserMode: EraserMode = .stroke
    var inkColors: [RGBA] = [RGBA(0.11, 0.11, 0.13), RGBA(0.13, 0.33, 0.80), RGBA(0.80, 0.16, 0.16)]
    var highlightColors: [RGBA] = [RGBA(1.0, 0.86, 0.22), RGBA(0.55, 0.88, 0.45), RGBA(1.0, 0.56, 0.74)]
    var inkColorIndex = 0
    var highlightColorIndex = 0
    var penWidthIndex = 1
    var pencilWidthIndex = 1
    var highlightWidthIndex = 1
    var textStyle = TextStyle()

    var palette: [RGBA] { tool == .highlighter ? highlightColors : inkColors }

    var colorIndex: Int { tool == .highlighter ? highlightColorIndex : inkColorIndex }

    var widthIndex: Int {
        switch tool {
        case .pencil: return pencilWidthIndex
        case .highlighter: return highlightWidthIndex
        default: return penWidthIndex
        }
    }

    var currentColor: RGBA { palette[safe: colorIndex] ?? RGBA(0, 0, 0) }
    var inkColor: RGBA { inkColors[safe: inkColorIndex] ?? RGBA(0, 0, 0) }

    mutating func selectColor(_ i: Int) {
        if tool == .highlighter { highlightColorIndex = i } else { inkColorIndex = i }
    }

    mutating func setCurrentColor(_ color: RGBA) {
        if tool == .highlighter {
            if highlightColors.indices.contains(highlightColorIndex) { highlightColors[highlightColorIndex] = color }
        } else if inkColors.indices.contains(inkColorIndex) {
            inkColors[inkColorIndex] = color
        }
    }

    mutating func selectWidth(_ i: Int) {
        switch tool {
        case .pencil: pencilWidthIndex = i
        case .highlighter: highlightWidthIndex = i
        default: penWidthIndex = i
        }
    }

    var pkTool: PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(penStyle.inkType, color: currentColor.uiColor,
                                width: Self.penWidths[safe: penWidthIndex] ?? 2.6)
        case .shape:
            return PKInkingTool(.monoline, color: currentColor.uiColor,
                                width: Self.penWidths[safe: penWidthIndex] ?? 2.6)
        case .pencil:
            return PKInkingTool(.pencil, color: currentColor.uiColor,
                                width: Self.pencilWidths[safe: pencilWidthIndex] ?? 3.2)
        case .highlighter:
            return PKInkingTool(.marker, color: currentColor.uiColor,
                                width: Self.highlightWidths[safe: highlightWidthIndex] ?? 16)
        case .eraser:
            return PKEraserTool(eraserMode == .stroke ? .vector : .bitmap)
        case .lasso, .text, .select:
            return PKLassoTool()
        }
    }
}

final class EditorState: ObservableObject {
    @Published var settings: ToolSettings
    @Published var pageLabel = ""
    @Published var strokeCount = 0
    @Published var itemCount = 0
    @Published var showPages = false
    @Published var showStickers = false
    @Published var showPhotoPicker = false
    @Published var showImageImporter = false
    @Published var pagesRevision = 0
    @Published var errorMessage: String?
    /// Kind of the item under the selection box, if any.
    @Published var selectedKind: PageItem.Kind?

    weak var controller: NotebookCanvasController?

    private static let key = "toolSettings.v2"

    init() {
        var loaded = ToolSettings()
        if !AppEnv.isUITest,
           let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(ToolSettings.self, from: data) {
            loaded = saved
        }
        settings = loaded
    }

    func persistSettings() {
        guard !AppEnv.isUITest, let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
