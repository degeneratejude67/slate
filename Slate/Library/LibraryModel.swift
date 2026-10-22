import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case modified, name

    var id: String { rawValue }
    var label: String { self == .modified ? "Date Modified" : "Name" }
}

struct OpenNotebook: Identifiable {
    let url: URL
    var id: URL { url }
}

@MainActor
final class LibraryModel: ObservableObject {
    let store: NotebookStore

    @Published private(set) var revision = 0
    @Published var openNotebook: OpenNotebook?
    @Published var errorMessage: String?
    @Published var sort: LibrarySort = .modified

    /// Set by the New Notebook sheet; opened once the sheet has gone.
    var pendingOpen: URL?

    init() {
        store = NotebookStore(root: AppEnv.libraryRoot)
        if AppEnv.isUITest && AppEnv.arguments.contains("-uitest-seed-pdf") {
            seedSampleLecture()
        }
    }

    func refresh() { revision += 1 }

    func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func entries(in folder: URL) -> [LibraryEntry] {
        store.entries(in: folder).sorted { a, b in
            if a.isNotebook != b.isNotebook { return !a.isNotebook }   // folders first
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified: return a.modified > b.modified
            }
        }
    }

    func importPDFs(_ urls: [URL], into folder: URL) {
        var last: URL?
        perform {
            for url in urls { last = try store.importPDF(from: url, in: folder) }
        }
        if urls.count == 1, let last { openNotebook = OpenNotebook(url: last) }
    }

    func importExternal(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
        importPDFs([url], into: store.root)
    }

    func openPending() {
        guard let url = pendingOpen else { return }
        pendingOpen = nil
        openNotebook = OpenNotebook(url: url)
    }

    private func seedSampleLecture() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Sample Lecture.pdf")
        do {
            try SamplePDF.make().write(to: file, options: .atomic)
            try store.importPDF(from: file, in: store.root)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
