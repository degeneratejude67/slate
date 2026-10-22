import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case modified, name

    var id: String { rawValue }
    var label: String { self == .modified ? "Date Modified" : "Name" }
}

@MainActor
final class LibraryModel: ObservableObject {
    let store: NotebookStore

    @Published private(set) var revision = 0
    @Published var errorMessage: String?
    @Published var sort: LibrarySort = .modified

    /// Open notebooks, shown as tabs in the editor (GoodNotes style).
    @Published var tabs: [URL] = []
    @Published var activeTab: URL?
    @Published var editorShown = false
    /// Page to open a notebook at (from search results).
    var pendingPage: [URL: Int] = [:]

    /// Set by sheets that create a notebook; opened once the sheet has gone.
    var pendingOpen: URL?

    init() {
        store = NotebookStore(root: AppEnv.libraryRoot)
        if AppEnv.isUITest && AppEnv.arguments.contains("-uitest-seed-pdf") {
            seedSampleLecture()
        }
        store.adoptLoosePDFs()
    }

    func refresh() {
        tabs.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        if let active = activeTab, !tabs.contains(active) { activeTab = tabs.first }
        revision += 1
    }

    /// Called when the app comes to the front: picks up PDFs added from Files or the PC.
    func rescan() {
        store.adoptLoosePDFs()
        refresh()
    }

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

    // MARK: Opening and tabs

    func open(_ url: URL, page: Int? = nil) {
        if !tabs.contains(url) { tabs.append(url) }
        if let page { pendingPage[url] = page }
        activeTab = url
        editorShown = true
    }

    func closeTab(_ url: URL) {
        guard let i = tabs.firstIndex(of: url) else { return }
        tabs.remove(at: i)
        if activeTab == url {
            if tabs.isEmpty {
                activeTab = nil
                editorShown = false
            } else {
                activeTab = tabs[min(i, tabs.count - 1)]
            }
        }
    }

    func importPDFs(_ urls: [URL], into folder: URL) {
        var last: URL?
        perform {
            for url in urls { last = try store.importPDF(from: url, in: folder) }
        }
        if urls.count == 1, let last { open(last) }
    }

    func importExternal(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { return }
        importPDFs([url], into: store.root)
    }

    func openPending() {
        guard let url = pendingOpen else { return }
        pendingOpen = nil
        open(url)
    }

    private func seedSampleLecture() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Sample Lecture.pdf")
        do {
            try SamplePDF.make().write(to: file, options: .atomic)
            try store.importPDF(from: file, in: store.root)
            if AppEnv.arguments.contains("-uitest-seed-two") {
                let second = FileManager.default.temporaryDirectory.appendingPathComponent("Past Paper.pdf")
                try SamplePDF.make().write(to: second, options: .atomic)
                try store.importPDF(from: second, in: store.root)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
