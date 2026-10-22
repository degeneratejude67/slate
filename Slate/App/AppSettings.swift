import SwiftUI

enum ThemeChoice: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ToolbarPlacement: String, Codable, CaseIterable, Identifiable {
    case top, bottom

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ScrollAxis: String, Codable, CaseIterable, Identifiable {
    case vertical, horizontal

    var id: String { rawValue }
    var label: String { self == .vertical ? "Vertical" : "Horizontal" }
}

enum DeskColor: String, Codable, CaseIterable, Identifiable {
    case grey, white, warm, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var uiColor: UIColor {
        switch self {
        case .grey: return Theme.desk
        case .white: return UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.16, alpha: 1) : UIColor(white: 0.975, alpha: 1) }
        case .warm: return UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.16, green: 0.14, blue: 0.12, alpha: 1) : UIColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1) }
        case .dark: return UIColor(white: 0.12, alpha: 1)
        }
    }
}

enum GridDensity: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var tileWidth: CGFloat {
        switch self {
        case .small: return 120
        case .medium: return 150
        case .large: return 200
        }
    }

    var coverHeight: CGFloat { tileWidth * 1.4 }
}

/// App-wide preferences, edited on the Settings screen.
struct Prefs: Codable, Equatable {
    var theme: ThemeChoice = .system
    var toolbar: ToolbarPlacement = .top
    var scroll: ScrollAxis = .vertical
    var desk: DeskColor = .grey
    var defaultPaper = Paper(kind: .ruled, tone: .white)
    var defaultSize: PageSizePreset = .a4
    var defaultCover: CoverStyle = .slate
    var autoAddPage = true
    var fingerDraws = false
    var twoFingerUndo = true
    var showPageNumber = true
    var gridDensity: GridDensity = .medium
    var stickerPacks: [String] = StickerCatalog.defaultPacks

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = Prefs()
        theme = value(.theme, d.theme)
        toolbar = value(.toolbar, d.toolbar)
        scroll = value(.scroll, d.scroll)
        desk = value(.desk, d.desk)
        defaultPaper = value(.defaultPaper, d.defaultPaper)
        defaultSize = value(.defaultSize, d.defaultSize)
        defaultCover = value(.defaultCover, d.defaultCover)
        autoAddPage = value(.autoAddPage, d.autoAddPage)
        fingerDraws = value(.fingerDraws, d.fingerDraws)
        twoFingerUndo = value(.twoFingerUndo, d.twoFingerUndo)
        showPageNumber = value(.showPageNumber, d.showPageNumber)
        gridDensity = value(.gridDensity, d.gridDensity)
        stickerPacks = value(.stickerPacks, d.stickerPacks)
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private static let key = "prefs.v1"

    @Published var prefs: Prefs {
        didSet { save() }
    }

    private init() {
        var loaded = Prefs()
        if !AppEnv.isUITest,
           let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Prefs.self, from: data) {
            loaded = saved
        }
        if AppEnv.arguments.contains("-uitest-horizontal") { loaded.scroll = .horizontal }
        if AppEnv.arguments.contains("-uitest-toolbar-bottom") { loaded.toolbar = .bottom }
        if AppEnv.arguments.contains("-uitest-dark") { loaded.theme = .dark }
        prefs = loaded
    }

    private func save() {
        guard !AppEnv.isUITest, let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

/// Reads the signing expiry from the provisioning profile embedded by the signer, so the
/// app can warn before a free Apple ID signature runs out. Nil on unsigned builds.
enum Provisioning {
    static let expiry: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }()

    static var daysLeft: Int? {
        guard let expiry else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }
}
