import UIKit
import PDFKit
import PencilKit

enum SlateError: LocalizedError {
    case unreadablePDF(String)
    case lockedPDF(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let name): return "\(name) is not a PDF Slate can read."
        case .lockedPDF(let name): return "\(name) is password protected. Unlock it and import again."
        case .writeFailed(let what): return "Could not save \(what)."
        }
    }
}

/// File layout of one notebook folder (`<Title>.slate`).
struct NotebookPaths {
    let root: URL
    var meta: URL { root.appendingPathComponent("notebook.json") }
    var pdf: URL { root.appendingPathComponent("document.pdf") }
    var inkDir: URL { root.appendingPathComponent("ink", isDirectory: true) }
    var thumb: URL { root.appendingPathComponent("thumb.png") }
    var imagesDir: URL { root.appendingPathComponent("images", isDirectory: true) }

    func ink(_ id: UUID) -> URL { inkDir.appendingPathComponent(id.uuidString + ".drawing") }
}

/// An open notebook: its metadata, its PDF (every page, templates included) and per-page ink.
final class NotebookDocument {
    let url: URL
    let paths: NotebookPaths
    var meta: NotebookMeta
    private(set) var pdf: PDFDocument

    init(url: URL) throws {
        self.url = url
        paths = NotebookPaths(root: url)
        var meta = try JSONDecoder.slate.decode(NotebookMeta.self, from: Data(contentsOf: paths.meta))
        guard let pdf = PDFDocument(url: paths.pdf) else { throw SlateError.unreadablePDF(url.lastPathComponent) }
        // The PDF is the source of truth for the page count.
        if meta.pages.count < pdf.pageCount {
            for _ in meta.pages.count..<pdf.pageCount { meta.pages.append(PageMeta(id: UUID(), paper: nil)) }
        } else if meta.pages.count > pdf.pageCount {
            meta.pages.removeLast(meta.pages.count - pdf.pageCount)
        }
        self.meta = meta
        self.pdf = pdf
    }

    var pageCount: Int { meta.pages.count }

    func pageSize(at index: Int) -> CGSize {
        pdf.page(at: index).map(PageGeometry.displaySize) ?? PageSizePreset.a4.size
    }

    var pageSizes: [CGSize] { (0..<pageCount).map(pageSize(at:)) }

    // MARK: Ink

    func inkData(for id: UUID) -> Data? { try? Data(contentsOf: paths.ink(id)) }

    func drawing(for id: UUID) -> PKDrawing {
        inkData(for: id).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
    }

    func writeInk(_ data: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: paths.inkDir, withIntermediateDirectories: true)
        try data.write(to: paths.ink(id), options: .atomic)
    }

    // MARK: Metadata and pages

    func saveMeta() throws {
        meta.modified = Date()
        try JSONEncoder.slate.encode(meta).write(to: paths.meta, options: .atomic)
    }

    // MARK: Pictures

    private var imageCache: [String: UIImage] = [:]

    /// Saves a picture into the notebook (longest side at most 2400 px) and returns its file name.
    func saveImage(_ image: UIImage) throws -> String {
        try FileManager.default.createDirectory(at: paths.imagesDir, withIntermediateDirectories: true)
        let maxSide: CGFloat = 2400
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1, maxSide / max(pixels.width, pixels.height))
        let target = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        let name = UUID().uuidString + ".png"
        guard let data = resized.pngData() else { throw SlateError.writeFailed("the picture") }
        try data.write(to: paths.imagesDir.appendingPathComponent(name), options: .atomic)
        imageCache[name] = resized
        return name
    }

    func image(named name: String) -> UIImage? {
        if let hit = imageCache[name] { return hit }
        let image = UIImage(contentsOfFile: paths.imagesDir.appendingPathComponent(name).path)
        imageCache[name] = image
        return image
    }

    // MARK: Items

    func items(onPage index: Int) -> [PageItem] {
        meta.pages[safe: index]?.items ?? []
    }

    func setItems(_ items: [PageItem], onPage index: Int) {
        guard meta.pages.indices.contains(index) else { return }
        meta.pages[index].items = items
    }

    @discardableResult
    func insertTemplatePage(paper: Paper, size: CGSize, at index: Int) throws -> UUID {
        guard let template = PDFDocument(data: TemplateRenderer.pdfData(paper: paper, size: size)),
              let page = template.page(at: 0) else { throw SlateError.writeFailed("the new page") }
        let at = min(max(index, 0), pdf.pageCount)
        pdf.insert(page, at: at)
        let id = UUID()
        meta.pages.insert(PageMeta(id: id, paper: paper), at: at)
        try withExtendedLifetime(template) { try savePDF() }
        try saveMeta()
        return id
    }

    func deletePage(at index: Int) throws {
        guard meta.pages.indices.contains(index), pageCount > 1 else { return }
        let id = meta.pages[index].id
        pdf.removePage(at: index)
        meta.pages.remove(at: index)
        try savePDF()
        try saveMeta()
        try? FileManager.default.removeItem(at: paths.ink(id))
    }

    func movePage(from: Int, to: Int) throws {
        guard meta.pages.indices.contains(from), meta.pages.indices.contains(to), from != to,
              let page = pdf.page(at: from) else { return }
        pdf.removePage(at: from)
        pdf.insert(page, at: to)
        meta.pages.insert(meta.pages.remove(at: from), at: to)
        try savePDF()
        try saveMeta()
    }

    /// Writes the PDF next to the old one, swaps it in, and reopens it so every page
    /// belongs to the file on disk.
    func savePDF() throws {
        let tmp = paths.root.appendingPathComponent("document.saving.pdf")
        try? FileManager.default.removeItem(at: tmp)
        guard pdf.write(to: tmp) else { throw SlateError.writeFailed("document.pdf") }
        _ = try FileManager.default.replaceItemAt(paths.pdf, withItemAt: tmp)
        if let fresh = PDFDocument(url: paths.pdf) { pdf = fresh }
    }

    /// Covers: notebooks that start with a PDF page show that page; template notebooks
    /// show their coloured cover instead.
    func writeThumbnail(firstPageInk: PKDrawing) {
        guard meta.pages.first?.paper == nil, let first = pdf.page(at: 0) else { return }
        let image = Thumbnailer.image(page: first, pageSize: PageGeometry.displaySize(first),
                                      drawing: firstPageInk, width: 360, items: items(onPage: 0),
                                      imageLoader: { [weak self] in self?.image(named: $0) })
        try? image.pngData()?.write(to: paths.thumb, options: .atomic)
    }
}
