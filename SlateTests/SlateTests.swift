import XCTest
import PDFKit
import PencilKit
@testable import Slate

final class SlateTests: XCTestCase {
    private var tmp: URL!
    private let a4 = PageSizePreset.a4.size
    private let slide = PageSizePreset.slide.size

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func stroke(at p: CGPoint) -> PKStroke {
        let points = (0..<5).map { i in
            PKStrokePoint(location: CGPoint(x: p.x + CGFloat(i) * 4, y: p.y), timeOffset: TimeInterval(i) * 0.01,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path, transform: .identity, mask: nil)
    }

    func testMetaRoundTrip() throws {
        var meta = NotebookMeta(title: "ME 445", cover: .navy,
                                pages: [PageMeta(id: UUID(), paper: .ruled), PageMeta(id: UUID(), paper: nil)])
        meta.bookmarks = [meta.pages[1].id]
        meta.lastPage = 1
        let back = try JSONDecoder.slate.decode(NotebookMeta.self, from: JSONEncoder.slate.encode(meta))
        XCTAssertEqual(back.title, "ME 445")
        XCTAssertEqual(back.cover, .navy)
        XCTAssertEqual(back.pages, meta.pages)
        XCTAssertEqual(back.bookmarks, meta.bookmarks)
        XCTAssertEqual(back.lastPage, 1)
    }

    func testMetaToleratesMissingKeys() throws {
        let json = #"{"title":"Old","pages":[]}"#.data(using: .utf8)!
        let meta = try JSONDecoder.slate.decode(NotebookMeta.self, from: json)
        XCTAssertEqual(meta.title, "Old")
        XCTAssertEqual(meta.lastPage, 0)
        XCTAssertEqual(meta.cover, .slate)
    }

    func testTemplatePagesHaveRequestedSize() throws {
        for kind in PaperKind.allCases {
            for tone in PaperTone.allCases {
                let doc = try XCTUnwrap(PDFDocument(data: TemplateRenderer.pdfData(paper: Paper(kind: kind, tone: tone),
                                                                                  size: a4, count: 2)))
                XCTAssertEqual(doc.pageCount, 2)
                let size = PageGeometry.displaySize(try XCTUnwrap(doc.page(at: 1)))
                XCTAssertEqual(size.width, a4.width, accuracy: 0.5)
                XCTAssertEqual(size.height, a4.height, accuracy: 0.5)
            }
        }
    }

    func testRotatedPageSizeIsSwapped() throws {
        let doc = try XCTUnwrap(PDFDocument(data: SamplePDF.make()))
        XCTAssertEqual(doc.pageCount, 3)
        let rotated = PageGeometry.displaySize(try XCTUnwrap(doc.page(at: 2)))
        XCTAssertEqual(rotated.width, a4.height, accuracy: 0.5)
        XCTAssertEqual(rotated.height, a4.width, accuracy: 0.5)
    }

    func testLayoutStacksAndFindsPages() {
        let layout = PageLayout(sizes: [a4, slide, a4])
        XCTAssertEqual(layout.frames.count, 3)
        XCTAssertEqual(layout.contentSize.width, slide.width + 2 * PageLayout.margin, accuracy: 0.01)
        XCTAssertEqual(layout.frames[0].midX, layout.frames[1].midX, accuracy: 0.01)
        XCTAssertEqual(layout.index(atY: layout.frames[1].midY), 1)
        XCTAssertEqual(layout.index(atY: layout.frames[2].maxY + 500), 2)
        XCTAssertEqual(layout.index(atY: -10), 0)
    }

    func testSplitMergeKeepsStrokesOnTheirPages() {
        let layout = PageLayout(sizes: [a4, slide, a4])
        let local: [[PKStroke]] = [[stroke(at: CGPoint(x: 50, y: 50))],
                                   [stroke(at: CGPoint(x: 100, y: 100)), stroke(at: CGPoint(x: 300, y: 400))],
                                   []]
        let drawings = local.map { PKDrawing(strokes: $0) }
        let merged = InkLayout.merge(drawings, origins: layout.frames.map(\.origin))
        XCTAssertEqual(merged.strokes.count, 3)
        XCTAssertEqual(merged.strokes[1].renderBounds.minY, drawings[1].strokes[0].renderBounds.minY + layout.frames[1].minY,
                       accuracy: 0.5)

        let split = InkLayout.split(merged, layout: layout)
        XCTAssertEqual(split.map { $0.strokes.count }, [1, 2, 0])
        XCTAssertEqual(split[1].bounds.minX, drawings[1].bounds.minX, accuracy: 0.5)
        XCTAssertEqual(split[1].bounds.minY, drawings[1].bounds.minY, accuracy: 0.5)
    }

    func testStoreCreateEditImportRenameMoveDelete() throws {
        let store = NotebookStore(root: tmp)
        let notebook = try store.createNotebook(title: "Vibration", paper: .ruled, size: a4, pages: 3,
                                                cover: .navy, in: tmp)
        XCTAssertEqual(notebook.lastPathComponent, "Vibration.slate")

        let doc = try NotebookDocument(url: notebook)
        XCTAssertEqual(doc.pageCount, 3)
        let inked = doc.meta.pages[1].id
        try doc.writeInk(PKDrawing(strokes: [stroke(at: CGPoint(x: 20, y: 20))]).dataRepresentation(), for: inked)

        try doc.insertTemplatePage(paper: Paper(kind: .grid, tone: .cream), size: a4, at: 1)
        XCTAssertEqual(doc.pageCount, 4)
        let reopened = try NotebookDocument(url: notebook)
        XCTAssertEqual(reopened.pageCount, 4)
        XCTAssertEqual(reopened.meta.pages[2].id, inked)
        XCTAssertEqual(reopened.drawing(for: inked).strokes.count, 1)

        try reopened.movePage(from: 2, to: 0)
        XCTAssertEqual(try NotebookDocument(url: notebook).meta.pages[0].id, inked)
        try reopened.deletePage(at: 0)
        XCTAssertEqual(try NotebookDocument(url: notebook).pageCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.paths.ink(inked).path))

        let pdfURL = tmp.appendingPathComponent("Lecture 1.pdf")
        try SamplePDF.make().write(to: pdfURL)
        let imported = try store.importPDF(from: pdfURL, in: tmp)
        XCTAssertEqual(try NotebookDocument(url: imported).pageCount, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: NotebookPaths(root: imported).thumb.path))

        let renamed = try store.rename(notebook, to: "Noise")
        XCTAssertEqual(renamed.lastPathComponent, "Noise.slate")
        XCTAssertEqual(try NotebookDocument(url: renamed).meta.title, "Noise")

        let folder = try store.createFolder(named: "ME 445", in: tmp)
        let moved = try store.move(renamed, to: folder)
        XCTAssertEqual(store.entries(in: folder).map(\.name), ["Noise"])
        XCTAssertEqual(store.folderTree().map(\.name), ["ME 445"])
        XCTAssertEqual(try NotebookDocument(url: moved).pageCount, 3)

        let duplicate = try store.createNotebook(title: "Lecture 1", paper: .ruled, size: a4, pages: 1, cover: .slate, in: tmp)
        XCTAssertEqual(duplicate.lastPathComponent, "Lecture 1 2.slate")

        try store.delete(folder)
        XCTAssertTrue(store.folderTree().isEmpty)
    }

    func testLoosePDFsBecomeNotebooks() throws {
        let store = NotebookStore(root: tmp)
        let course = try store.createFolder(named: "ME 421", in: tmp)
        try SamplePDF.make().write(to: course.appendingPathComponent("Pelton.pdf"))
        try Data("not a pdf".utf8).write(to: course.appendingPathComponent("Broken.pdf"))
        XCTAssertEqual(store.adoptLoosePDFs(), 1)
        XCTAssertEqual(store.entries(in: course).map(\.name), ["Pelton"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: course.appendingPathComponent("Pelton.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.appendingPathComponent("Broken.pdf").path))
    }

    func testThumbnailHasPageAspect() throws {
        let doc = try XCTUnwrap(PDFDocument(data: SamplePDF.make()))
        let image = Thumbnailer.image(page: doc.page(at: 0), pageSize: slide,
                                      drawing: PKDrawing(strokes: [stroke(at: CGPoint(x: 10, y: 10))]), width: 300)
        XCTAssertEqual(image.size.width, 300, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 300 * slide.height / slide.width, accuracy: 1)
    }
}
