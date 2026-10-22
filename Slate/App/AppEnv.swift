import Foundation

/// Launch-time switches. The UI tests start the app with `-uitest` so it uses a throwaway
/// library and lets a finger draw (the simulator has no Apple Pencil).
enum AppEnv {
    static let arguments = ProcessInfo.processInfo.arguments
    static let isUITest = arguments.contains("-uitest")

    static let libraryRoot: URL = {
        let fm = FileManager.default
        if isUITest {
            let root = fm.temporaryDirectory.appendingPathComponent("SlateUITest/Library", isDirectory: true)
            if arguments.contains("-uitest-reset") { try? fm.removeItem(at: root) }
            return root
        }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Library", isDirectory: true)
    }()
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
