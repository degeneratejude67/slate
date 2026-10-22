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

    func testHorizontalLayoutPlacesPagesSideBySide() {
        let layout = PageLayout(sizes: [a4, slide, a4], axis: .horizontal)
        XCTAssertEqual(layout.frames[0].midY, layout.frames[2].midY, accuracy: 0.01)
        XCTAssertEqual(layout.frames[1].minX, layout.frames[0].maxX + PageLayout.gap, accuracy: 0.01)
        XCTAssertEqual(layout.contentSize.height, a4.height + 2 * PageLayout.margin, accuracy: 0.01)
        XCTAssertEqual(layout.index(at: CGPoint(x: layout.frames[2].midX, y: 10)), 2)
        let stroke = InkLayout.translated(stroke(at: CGPoint(x: 30, y: 30)), by: layout.frames[1].origin)
        XCTAssertEqual(InkLayout.split(PKDrawing(strokes: [stroke]), layout: layout).map { $0.strokes.count }, [0, 1, 0])
    }

    func testItemsRoundTripAndOldPagesDecode() throws {
        let text = PageItem(kind: .text, frame: CGRect(x: 10, y: 20, width: 200, height: 40), text: "Bernoulli",
                            style: TextStyle(font: .serif, size: 22, bold: true, fill: .yellow), color: RGBA(0.1, 0.2, 0.3))
        let sticker = PageItem(kind: .sticker, frame: CGRect(x: 50, y: 60, width: 64, height: 64), sticker: "sym:star.fill")
        let page = PageMeta(id: UUID(), paper: Paper(kind: .problem, tone: .cream), items: [text, sticker])
        let back = try JSONDecoder.slate.decode(PageMeta.self, from: JSONEncoder.slate.encode(page))
        XCTAssertEqual(back, page)

        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","paper":{"kind":"someFutureKind","tone":"white"}}"#
        let decoded = try JSONDecoder.slate.decode(PageMeta.self, from: Data(old.utf8))
        XCTAssertNil(decoded.paper)
        XCTAssertTrue(decoded.items.isEmpty)
    }

    func testTextBoxGrowsWithText() {
        var item = PageItem(kind: .text, frame: CGRect(x: 0, y: 0, width: 160, height: 30), text: "short")
        let one = item.fittedTextHeight()
        item.text = String(repeating: "longer words wrap onto more lines ", count: 6)
        XCTAssertGreaterThan(item.fittedTextHeight(), one * 2)
    }

    func testPrefsSurviveMissingAndUnknownKeys() throws {
        let json = #"{"theme":"dark","scroll":"horizontal","defaultCover":"notACover"}"#
        let prefs = try JSONDecoder().decode(Prefs.self, from: Data(json.utf8))
        XCTAssertEqual(prefs.theme, .dark)
        XCTAssertEqual(prefs.scroll, .horizontal)
        XCTAssertEqual(prefs.defaultCover, .slate)
        XCTAssertTrue(prefs.autoAddPage)
    }

    private func ring(_ f: (CGFloat) -> CGPoint, count: Int = 80) -> [CGPoint] {
        (0..<count).map { f(CGFloat($0) / CGFloat(count)) }
    }

    func testShapeRecognizer() {
        // Rough circle with wobble, starting at the right.
        let circle = ring { t in
            let a = t * 2 * .pi, r = 100 + 4 * sin(a * 7)
            return CGPoint(x: 300 + r * cos(a), y: 300 + r * sin(a))
        }
        guard case .ellipse(let rect)? = ShapeRecognizer.recognize(circle) else { return XCTFail("circle not found") }
        XCTAssertEqual(rect.width, rect.height, accuracy: 0.5)
        XCTAssertEqual(rect.midX, 300, accuracy: 6)

        // Rectangle drawn from the middle of its top edge, with a little shake.
        var rect4: [CGPoint] = []
        let corners = [CGPoint(x: 200, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 220),
                       CGPoint(x: 100, y: 220), CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)]
        for i in 0..<(corners.count - 1) {
            for k in 0..<20 {
                let t = CGFloat(k) / 20
                rect4.append(CGPoint(x: corners[i].x + (corners[i + 1].x - corners[i].x) * t + CGFloat(k % 3) - 1,
                                     y: corners[i].y + (corners[i + 1].y - corners[i].y) * t + CGFloat(k % 2)))
            }
        }
        guard case .polygon(let quad)? = ShapeRecognizer.recognize(rect4) else { return XCTFail("rectangle not found") }
        XCTAssertEqual(quad.count, 4)

        let triangle = [CGPoint(x: 0, y: 200), CGPoint(x: 100, y: 20), CGPoint(x: 200, y: 200), CGPoint(x: 0, y: 200)]
        var tri: [CGPoint] = []
        for i in 0..<3 {
            for k in 0..<25 {
                let t = CGFloat(k) / 25
                tri.append(CGPoint(x: triangle[i].x + (triangle[i + 1].x - triangle[i].x) * t,
                                   y: triangle[i].y + (triangle[i + 1].y - triangle[i].y) * t))
            }
        }
        guard case .polygon(let three)? = ShapeRecognizer.recognize(tri) else { return XCTFail("triangle not found") }
        XCTAssertEqual(three.count, 3)

        let line = (0..<40).map { CGPoint(x: CGFloat($0) * 5, y: 50 + CGFloat($0 % 2)) }
        guard case .line? = ShapeRecognizer.recognize(line) else { return XCTFail("line not found") }

        let scribble = (0..<60).map { i in CGPoint(x: CGFloat(i) * 4, y: 100 + 40 * sin(CGFloat(i) * 0.5)) }
        XCTAssertNil(ShapeRecognizer.recognize(scribble))

        let strokes = ShapeRecognizer.strokes(for: .polygon(quad), like: stroke(at: .zero))
        XCTAssertEqual(strokes.count, 1)
        XCTAssertGreaterThan(strokes[0].path.count, 8)
    }

    func testEveryTemplateAndStickerRenders() throws {
        for kind in PaperKind.allCases {
            let image = TemplateRenderer.previewImage(Paper(kind: kind, tone: .dark), size: a4, width: 120)
            XCTAssertEqual(image.size.width, 120, accuracy: 0.5, kind.rawValue)
        }
        for pack in StickerCatalog.packs {
            for sticker in pack.stickers {
                XCTAssertEqual(StickerCatalog.sticker(sticker.id), sticker)
                XCTAssertGreaterThan(StickerCatalog.image(for: sticker, width: 80).size.width, 0, sticker.id)
            }
        }
        XCTAssertEqual(Set(StickerCatalog.packs.flatMap { $0.stickers.map(\.id) }).count,
                       StickerCatalog.packs.reduce(0) { $0 + $1.stickers.count }, "sticker ids must be unique")
    }

    func testImagesSaveIntoNotebook() throws {
        let store = NotebookStore(root: tmp)
        let doc = try NotebookDocument(url: try store.createNotebook(title: "Pics", paper: .ruled, size: a4, pages: 1,
                                                                     cover: .teal, in: tmp))
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let name = try doc.saveImage(big)
        let reopened = try NotebookDocument(url: doc.url)
        let loaded = try XCTUnwrap(reopened.image(named: name))
        XCTAssertLessThanOrEqual(max(loaded.size.width * loaded.scale, loaded.size.height * loaded.scale), 2400.5)
    }

    /// Ink strokes that trace the outlines of letters, so Vision has "handwriting" to read.
    private func strokes(spelling text: String, size: CGFloat, at origin: CGPoint) -> [PKStroke] {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        var strokes: [PKStroke] = []
        var x = origin.x
        for scalar in text.utf16 {
            var char = scalar
            var glyph: CGGlyph = 0
            CTFontGetGlyphsForCharacters(font, &char, &glyph, 1)
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
                var subpaths: [[CGPoint]] = []
                var current: [CGPoint] = []
                let place = { (p: CGPoint) in CGPoint(x: x + p.x, y: origin.y - p.y) }
                path.applyWithBlock { element in
                    let e = element.pointee
                    switch e.type {
                    case .moveToPoint:
                        if current.count > 1 { subpaths.append(current) }
                        current = [place(e.points[0])]
                    case .addLineToPoint:
                        current.append(place(e.points[0]))
                    case .addQuadCurveToPoint:
                        current.append(place(e.points[1]))
                    case .addCurveToPoint:
                        current.append(place(e.points[2]))
                    case .closeSubpath:
                        if let first = current.first { current.append(first) }
                    @unknown default:
                        break
                    }
                }
                if current.count > 1 { subpaths.append(current) }
                for sub in subpaths {
                    let points = sub.enumerated().map { i, p in
                        PKStrokePoint(location: p, timeOffset: Double(i) * 0.01, size: CGSize(width: 3, height: 3),
                                      opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                    }
                    strokes.append(PKStroke(ink: PKInk(.pen, color: .black),
                                            path: PKStrokePath(controlPoints: points, creationDate: Date()),
                                            transform: .identity, mask: nil))
                }
            }
            x += advance.width
        }
        return strokes
    }

    func testHandwritingIsRecognised() {
        let drawing = PKDrawing(strokes: strokes(spelling: "PELTON", size: 90, at: CGPoint(x: 40, y: 200)))
        let text = SearchIndex.recognize(drawing, pageSize: a4)
        XCTAssertTrue(text.uppercased().contains("PELTON"), "Vision read: \(text)")
    }

    func testSearchFindsTextBoxesPDFTextAndTitles() async throws {
        let store = NotebookStore(root: tmp)
        let pdfURL = tmp.appendingPathComponent("Fluid Machines.pdf")
        try SamplePDF.make().write(to: pdfURL)
        let imported = try store.importPDF(from: pdfURL, in: tmp)
        let doc = try NotebookDocument(url: imported)
        doc.setItems([PageItem(kind: .text, frame: CGRect(x: 10, y: 10, width: 200, height: 30), text: "Euler turbine equation")],
                     onPage: 1)
        try doc.saveMeta()
        await SearchIndexer.shared.indexMissing([imported])

        let pdfHits = SearchIndex.search("pelton", in: store)
        XCTAssertTrue(pdfHits.contains { $0.page == 0 && $0.source == .pdf }, "\(pdfHits.map(\.snippet))")
        let boxHits = SearchIndex.search("EULER", in: store)
        XCTAssertTrue(boxHits.contains { $0.page == 1 && $0.source == .text })
        XCTAssertTrue(SearchIndex.search("fluid", in: store).contains { $0.source == .title })
        XCTAssertTrue(SearchIndex.search("zz", in: store).isEmpty)
    }

    func testExportedPDFKeepsPagesAndDrawsInk() throws {
        let store = NotebookStore(root: tmp)
        let doc = try NotebookDocument(url: try store.createNotebook(title: "Export", paper: .ruled, size: a4, pages: 2,
                                                                     cover: .slate, in: tmp))
        doc.setItems([PageItem(kind: .text, frame: CGRect(x: 40, y: 40, width: 200, height: 30), text: "Hello")], onPage: 0)
        let ink = PKDrawing(strokes: [stroke(at: CGPoint(x: 100, y: 300))])
        let data = ExportRenderer.pdf(of: doc, drawings: [ink, PKDrawing()])
        let exported = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(exported.pageCount, 2)
        XCTAssertEqual(PageGeometry.displaySize(try XCTUnwrap(exported.page(at: 0))).width, a4.width, accuracy: 0.5)
        XCTAssertTrue(exported.page(at: 0)?.string?.contains("Hello") ?? false)

        let zip = tmp.appendingPathComponent("backup.zip")
        try ExportRenderer.zip(folder: doc.url, to: zip)
        let size = try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000)
    }

    func testRecordingMatchFindsTheMoment() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let a = Recording(id: UUID(), file: "a.m4a", started: start, duration: 600)
        let b = Recording(id: UUID(), file: "b.m4a", started: start.addingTimeInterval(3600), duration: 300)
        let hit = Recording.match(start.addingTimeInterval(3700), in: [a, b])
        XCTAssertEqual(hit?.0.id, b.id)
        XCTAssertEqual(hit?.1 ?? -1, 100, accuracy: 0.001)
        XCTAssertNil(Recording.match(start.addingTimeInterval(1000), in: [a, b]))
        XCTAssertEqual(Recording.clock(3725), "1:02:05")
        XCTAssertEqual(Recording.clock(65), "1:05")
    }

    func testThumbnailHasPageAspect() throws {
        let doc = try XCTUnwrap(PDFDocument(data: SamplePDF.make()))
        let image = Thumbnailer.image(page: doc.page(at: 0), pageSize: slide,
                                      drawing: PKDrawing(strokes: [stroke(at: CGPoint(x: 10, y: 10))]), width: 300)
        XCTAssertEqual(image.size.width, 300, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 300 * slide.height / slide.width, accuracy: 1)
    }
}
