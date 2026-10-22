import UIKit
import PDFKit
import PencilKit

struct LibraryEntry: Identifiable, Hashable {
    let url: URL
    let isNotebook: Bool
    let name: String
    let modified: Date
    let cover: CoverStyle?
    let itemCount: Int

    var id: URL { url }
}

struct FolderNode: Identifiable, Hashable {
    let url: URL
    let name: String
    var children: [FolderNode]?

    var id: URL { url }
}

/// The library on disk: plain folders, and one `<Title>.slate` folder per notebook.
/// It sits in the app's Documents, so the Files app and a USB copy see the same tree.
final class NotebookStore {
    static let ext = "slate"
    let root: URL
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: Listing

    func entries(in folder: URL) -> [LibraryEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { return nil }
            if url.pathExtension == Self.ext {
                let metaURL = url.appendingPathComponent("notebook.json")
                let meta = (try? Data(contentsOf: metaURL)).flatMap { try? JSONDecoder.slate.decode(NotebookMeta.self, from: $0) }
                return LibraryEntry(url: url, isNotebook: true, name: url.deletingPathExtension().lastPathComponent,
                                    modified: meta?.modified ?? values?.contentModificationDate ?? .distantPast,
                                    cover: meta?.cover, itemCount: meta?.pages.count ?? 0)
            }
            let count = (try? fm.contentsOfDirectory(atPath: url.path))?.filter { !$0.hasPrefix(".") }.count ?? 0
            return LibraryEntry(url: url, isNotebook: false, name: url.lastPathComponent,
                                modified: values?.contentModificationDate ?? .distantPast,
                                cover: nil, itemCount: count)
        }
    }

    func folderTree(at folder: URL? = nil) -> [FolderNode] {
        entries(in: folder ?? root)
            .filter { !$0.isNotebook }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { entry in
                let children = folderTree(at: entry.url)
                return FolderNode(url: entry.url, name: entry.name, children: children.isEmpty ? nil : children)
            }
    }

    func allFolders() -> [URL] {
        func walk(_ nodes: [FolderNode]) -> [URL] {
            nodes.flatMap { [$0.url] + walk($0.children ?? []) }
        }
        return walk(folderTree())
    }

    func displayPath(_ folder: URL) -> String {
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = folder.standardizedFileURL.pathComponents
        return parts.dropFirst(rootParts.count).joined(separator: " › ")
    }

    // MARK: Creating

    @discardableResult
    func createFolder(named name: String, in parent: URL) throws -> URL {
        let url = uniqueURL(named: name, in: parent, ext: nil)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func createNotebook(title: String, paper: Paper, size: CGSize, pages: Int, cover: CoverStyle, in folder: URL) throws -> URL {
        let url = uniqueURL(named: title, in: folder, ext: Self.ext)
        let paths = NotebookPaths(root: url)
        try fm.createDirectory(at: paths.inkDir, withIntermediateDirectories: true)
        let count = max(1, pages)
        try TemplateRenderer.pdfData(paper: paper, size: size, count: count).write(to: paths.pdf, options: .atomic)
        let meta = NotebookMeta(title: url.deletingPathExtension().lastPathComponent, cover: cover,
                                pages: (0..<count).map { _ in PageMeta(id: UUID(), paper: paper) })
        try JSONEncoder.slate.encode(meta).write(to: paths.meta, options: .atomic)
        return url
    }

    @discardableResult
    func importPDF(from source: URL, in folder: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let doc = PDFDocument(url: source), doc.pageCount > 0 else {
            throw SlateError.unreadablePDF(source.lastPathComponent)
        }
        if doc.isLocked { throw SlateError.lockedPDF(source.lastPathComponent) }

        let url = uniqueURL(named: source.deletingPathExtension().lastPathComponent, in: folder, ext: Self.ext)
        let paths = NotebookPaths(root: url)
        try fm.createDirectory(at: paths.inkDir, withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: paths.pdf)
        let meta = NotebookMeta(title: url.deletingPathExtension().lastPathComponent, cover: .slate,
                                pages: (0..<doc.pageCount).map { _ in PageMeta(id: UUID(), paper: nil) },
                                source: source.lastPathComponent)
        try JSONEncoder.slate.encode(meta).write(to: paths.meta, options: .atomic)
        if let first = doc.page(at: 0) {
            let image = Thumbnailer.image(page: first, pageSize: PageGeometry.displaySize(first),
                                          drawing: PKDrawing(), width: 360)
            try? image.pngData()?.write(to: paths.thumb, options: .atomic)
        }
        return url
    }

    /// PDFs put into the library from the Files app or over USB become notebooks in the
    /// folder they were dropped in. A PDF that can't be read yet (still copying) is left
    /// for the next pass.
    @discardableResult
    func adoptLoosePDFs(in folder: URL? = nil) -> Int {
        let dir = folder ?? root
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return 0 }
        var adopted = 0
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if url.pathExtension != Self.ext { adopted += adoptLoosePDFs(in: url) }
            } else if url.pathExtension.lowercased() == "pdf", (try? importPDF(from: url, in: dir)) != nil {
                try? fm.removeItem(at: url)
                adopted += 1
            }
        }
        return adopted
    }

    // MARK: Changing

    @discardableResult
    func rename(_ url: URL, to name: String) throws -> URL {
        let isNotebook = url.pathExtension == Self.ext
        let current = isNotebook ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        guard sanitize(name) != current else { return url }
        let target = uniqueURL(named: name, in: url.deletingLastPathComponent(), ext: isNotebook ? Self.ext : nil)
        try fm.moveItem(at: url, to: target)
        if isNotebook { try retitle(target) }
        return target
    }

    @discardableResult
    func move(_ url: URL, to folder: URL) throws -> URL {
        guard url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL else { return url }
        let isNotebook = url.pathExtension == Self.ext
        let name = isNotebook ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        let target = uniqueURL(named: name, in: folder, ext: isNotebook ? Self.ext : nil)
        try fm.moveItem(at: url, to: target)
        if isNotebook { try retitle(target) }
        return target
    }

    func delete(_ url: URL) throws {
        try fm.removeItem(at: url)
    }

    // MARK: Helpers

    private func retitle(_ notebook: URL) throws {
        let paths = NotebookPaths(root: notebook)
        var meta = try JSONDecoder.slate.decode(NotebookMeta.self, from: Data(contentsOf: paths.meta))
        meta.title = notebook.deletingPathExtension().lastPathComponent
        try JSONEncoder.slate.encode(meta).write(to: paths.meta, options: .atomic)
    }

    func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    func uniqueURL(named name: String, in folder: URL, ext: String?) -> URL {
        let base = sanitize(name)
        func make(_ n: String) -> URL {
            let u = folder.appendingPathComponent(n, isDirectory: true)
            return ext.map { u.appendingPathExtension($0) } ?? u
        }
        var candidate = make(base)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(n)")
            n += 1
        }
        return candidate
    }
}
