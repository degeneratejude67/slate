import UIKit
import PencilKit
import Vision

/// Searchable text of one page: the PDF's own text, handwriting read by Vision, and text boxes.
struct PageText: Codable, Equatable {
    var id: UUID
    var pdf: String
    var ink: String
    var items: String
}

/// Contents of `search.json` inside a notebook folder.
struct NotebookIndex: Codable {
    var version = 1
    var pages: [PageText]
}

struct SearchHit: Identifiable {
    enum Source: String { case title = "Title", handwriting = "Handwriting", text = "Text box", pdf = "Page text" }

    let id = UUID()
    let notebook: URL
    let title: String
    let page: Int?
    let source: Source
    let snippet: String
}

/// What the indexer needs to know about one page, captured on the main thread.
struct PageSnapshot {
    let id: UUID
    let size: CGSize
    /// nil keeps the text already indexed.
    let pdfText: String?
    /// nil keeps the handwriting already indexed.
    let ink: PKDrawing?
    let itemsText: String
}

enum SearchIndex {
    static func url(for notebook: URL) -> URL { notebook.appendingPathComponent("search.json") }

    static func load(_ notebook: URL) -> NotebookIndex? {
        guard let data = try? Data(contentsOf: url(for: notebook)) else { return nil }
        return try? JSONDecoder().decode(NotebookIndex.self, from: data)
    }

    static func save(_ index: NotebookIndex, notebook: URL) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: url(for: notebook), options: .atomic)
    }

    static func itemsText(_ items: [PageItem]) -> String {
        items.compactMap { $0.kind == .text ? $0.text : nil }.joined(separator: "\n")
    }

    /// Reads handwriting with Vision's on-device text recognizer.
    static func recognize(_ drawing: PKDrawing, pageSize: CGSize) -> String {
        guard !drawing.strokes.isEmpty else { return "" }
        let bounds = drawing.bounds.intersection(CGRect(origin: .zero, size: pageSize)).insetBy(dx: -8, dy: -8)
        guard !bounds.isNull, bounds.width > 4, bounds.height > 4 else { return "" }
        let scale = min(3, 2400 / max(bounds.width, bounds.height))
        var inkImage: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            inkImage = drawing.image(from: bounds, scale: scale)
        }
        guard let ink = inkImage else { return "" }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let flat = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = flat.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    static func search(_ text: String, in store: NotebookStore) -> [SearchHit] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var hits: [SearchHit] = []
        for entry in store.allNotebooks() {
            if entry.name.range(of: query, options: options) != nil {
                hits.append(SearchHit(notebook: entry.url, title: entry.name, page: nil, source: .title, snippet: entry.name))
            }
            guard let index = load(entry.url) else { continue }
            for (i, page) in index.pages.enumerated() {
                let sources: [(SearchHit.Source, String)] = [(.text, page.items), (.handwriting, page.ink), (.pdf, page.pdf)]
                for (source, body) in sources {
                    if let range = body.range(of: query, options: options) {
                        hits.append(SearchHit(notebook: entry.url, title: entry.name, page: i, source: source,
                                              snippet: snippet(body, around: range)))
                        break
                    }
                }
            }
        }
        return hits
    }

    private static func snippet(_ body: String, around range: Range<String.Index>) -> String {
        let start = body.index(range.lowerBound, offsetBy: -40, limitedBy: body.startIndex) ?? body.startIndex
        let end = body.index(range.upperBound, offsetBy: 60, limitedBy: body.endIndex) ?? body.endIndex
        let piece = body[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > body.startIndex ? "…" : "") + piece + (end < body.endIndex ? "…" : "")
    }
}

/// Updates search.json files one at a time, off the main thread.
actor SearchIndexer {
    static let shared = SearchIndexer()

    /// Indexes notebooks that have never been indexed (imported PDFs, notebooks copied in).
    func indexMissing(_ notebooks: [URL]) {
        for url in notebooks where SearchIndex.load(url) == nil {
            guard let document = try? NotebookDocument(url: url) else { continue }
            var pages: [PageSnapshot] = []
            for (i, page) in document.meta.pages.enumerated() {
                let ink = document.drawing(for: page.id)
                pages.append(PageSnapshot(id: page.id, size: document.pageSize(at: i),
                                          pdfText: document.pdf.page(at: i)?.string ?? "",
                                          ink: ink.strokes.isEmpty ? nil : ink,
                                          itemsText: SearchIndex.itemsText(page.items)))
            }
            update(notebook: url, pageOrder: document.meta.pages.map(\.id), pages: pages)
        }
    }

    func update(notebook: URL, pageOrder: [UUID], pages: [PageSnapshot]) {
        var index = SearchIndex.load(notebook) ?? NotebookIndex(pages: [])
        var byID = Dictionary(index.pages.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for page in pages {
            var entry = byID[page.id] ?? PageText(id: page.id, pdf: "", ink: "", items: "")
            if let pdf = page.pdfText { entry.pdf = pdf }
            if let ink = page.ink { entry.ink = SearchIndex.recognize(ink, pageSize: page.size) }
            entry.items = page.itemsText
            byID[page.id] = entry
        }
        index.pages = pageOrder.map { byID[$0] ?? PageText(id: $0, pdf: "", ink: "", items: "") }
        SearchIndex.save(index, notebook: notebook)
    }
}
