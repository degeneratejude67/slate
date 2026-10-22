import XCTest

/// Drives the app on an iPad simulator. The app runs with `-uitest`, so a finger draws like
/// the Pencil. Screenshots go to SCREENSHOT_DIR (set by CI) and to the test result.
final class SlateUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    private func canvas(_ app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: "canvas").firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 15), "canvas did not appear")
        return element
    }

    private func strokeCount(_ app: XCUIApplication) -> Int {
        let label = app.staticTexts["stroke-count"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        return Int(label.label) ?? -1
    }

    private func draw(_ canvas: XCUIElement, _ segments: [(CGFloat, CGFloat, CGFloat, CGFloat)]) {
        for (x0, y0, x1, y1) in segments {
            let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: y0))
            let b = canvas.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y1))
            a.press(forDuration: 0.05, thenDragTo: b)
        }
    }

    /// SwiftUI menus fail XCUITest's scroll-to-visible step, so tap their centre directly.
    private func tapCentre(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) missing")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func waitForStrokes(_ app: XCUIApplication, _ expected: Int) {
        let deadline = Date().addingTimeInterval(5)
        while strokeCount(app) != expected && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(strokeCount(app), expected)
    }

    func testNewNotebookInkSurvivesRelaunch() {
        var app = launch(["-uitest-reset"])
        shot("01-library-empty")

        tapCentre(app.buttons["add-menu"])
        tapCentre(app.buttons["New Notebook"])
        XCTAssertTrue(app.buttons["create-notebook"].waitForExistence(timeout: 5))
        shot("02-new-notebook-sheet")
        app.buttons["create-notebook"].tap()

        // An "H" on the first ruled page.
        draw(canvas(app), [(0.30, 0.20, 0.30, 0.32), (0.42, 0.20, 0.42, 0.32), (0.30, 0.26, 0.42, 0.26)])
        waitForStrokes(app, 3)
        shot("03-ink-on-ruled-page")

        app.buttons["undo"].tap()
        waitForStrokes(app, 2)
        app.buttons["redo"].tap()
        waitForStrokes(app, 3)

        app.buttons["tool-highlighter"].tap()
        draw(canvas(app), [(0.25, 0.40, 0.60, 0.40)])
        waitForStrokes(app, 4)
        shot("04-highlighter")

        app.buttons["close-notebook"].tap()
        XCTAssertTrue(app.buttons["notebook-Untitled"].waitForExistence(timeout: 5))
        shot("05-library-with-notebook")

        app.terminate()
        app = launch([])
        XCTAssertTrue(app.buttons["notebook-Untitled"].waitForExistence(timeout: 10))
        app.buttons["notebook-Untitled"].tap()
        _ = canvas(app)
        waitForStrokes(app, 4)
        shot("06-reopened-after-relaunch")
    }

    private func waitForItems(_ app: XCUIApplication, _ expected: Int) {
        let label = app.staticTexts["item-count"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(5)
        while label.label != "\(expected)" && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(label.label, "\(expected)")
    }

    func testMarketplaceTemplateStickerTextAndShape() {
        let app = launch(["-uitest-reset", "-uitest-marketplace"])
        let problem = app.buttons["template-problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        sleep(1)
        shot("20-marketplace")
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        shot("21-marketplace-covers-stickers")
        app.swipeDown()
        app.swipeDown()

        tapCentre(problem)
        XCTAssertTrue(app.buttons["use-template"].waitForExistence(timeout: 5))
        shot("22-template-detail")
        app.buttons["use-template"].tap()

        let surface = canvas(app)
        sleep(1)
        shot("23-problem-sheet")

        tapCentre(app.buttons["insert-menu"])
        tapCentre(app.buttons["Sticker"])
        let sticker = app.buttons["sticker-0-0"]
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        sleep(1)
        shot("24-sticker-picker")
        sticker.tap()
        waitForItems(app, 1)
        sleep(1)
        shot("25-sticker-placed")

        app.buttons["tool-text"].tap()
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.55)).tap()
        let editor = app.textViews["text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Bernoulli: p + rho v^2/2 + rho g z = const")
        shot("26-typing")
        app.buttons["tool-select"].tap()
        waitForItems(app, 2)
        sleep(1)
        shot("27-text-box")

        app.buttons["tool-shape"].tap()
        draw(surface, [(0.20, 0.80, 0.70, 0.81)])
        waitForStrokes(app, 1)
        sleep(1)
        shot("28-shape-line")
    }

    func testSearchTabsSideViewBookmarkLaserExport() {
        let app = launch(["-uitest-reset", "-uitest-seed-pdf", "-uitest-seed-two", "-uitest-search"])
        let hit = app.descendants(matching: .any).matching(identifier: "search-hit").firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 30), "no search result for Pelton")
        sleep(1)
        shot("40-search-results")
        tapCentre(hit)

        let surface = canvas(app)
        sleep(1)
        app.buttons["bookmark-button"].tap()
        sleep(1)
        shot("41-bookmarked")

        app.buttons["tool-laser"].tap()
        draw(surface, [(0.2, 0.3, 0.6, 0.35)])
        shot("42-laser")
        waitForStrokes(app, 0)

        tapCentre(app.buttons["split-button"])
        let reference = app.descendants(matching: .any).matching(identifier: "reference-Past Paper").firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        tapCentre(reference)
        sleep(2)
        shot("43-side-view")
        tapCentre(app.buttons["close-reference"])

        app.buttons["close-notebook"].tap()
        let second = app.descendants(matching: .any).matching(identifier: "search-hit").element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        tapCentre(second)
        _ = canvas(app)
        sleep(1)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tab-Sample Lecture").firstMatch.exists)
        shot("44-two-tabs")

        tapCentre(app.buttons["share-menu"])
        tapCentre(app.buttons["Export as PDF"])
        sleep(3)
        shot("45-share-sheet")
    }

    func testSettingsDarkAndHorizontalBottomToolbar() {
        var app = launch(["-uitest-reset", "-uitest-settings", "-uitest-dark"])
        XCTAssertTrue(app.descendants(matching: .any)["scroll-picker"].waitForExistence(timeout: 10))
        sleep(1)
        shot("30-settings-dark")
        app.terminate()

        app = launch(["-uitest-reset", "-uitest-seed-pdf", "-uitest-horizontal", "-uitest-toolbar-bottom"])
        XCTAssertTrue(app.buttons["notebook-Sample Lecture"].waitForExistence(timeout: 10))
        app.buttons["notebook-Sample Lecture"].tap()
        _ = canvas(app)
        sleep(2)
        shot("31-horizontal-bottom-toolbar")
        let label = app.staticTexts["page-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertTrue(label.label.hasPrefix("1 /"), "page label is \(label.label)")
    }

    func testPDFNotebookPagesZoomAndAddPage() {
        let app = launch(["-uitest-reset", "-uitest-seed-pdf"])
        XCTAssertTrue(app.buttons["notebook-Sample Lecture"].waitForExistence(timeout: 10))
        shot("10-library-pdf-cover")
        app.buttons["notebook-Sample Lecture"].tap()

        let surface = canvas(app)
        sleep(1)
        shot("11-pdf-open")
        draw(surface, [(0.15, 0.12, 0.55, 0.14)])
        waitForStrokes(app, 1)

        surface.pinch(withScale: 2.2, velocity: 1.5)
        sleep(2)
        shot("12-pdf-zoomed")
        surface.pinch(withScale: 0.4, velocity: -1.5)
        sleep(1)

        app.buttons["pages-button"].tap()
        let third = app.descendants(matching: .any).matching(identifier: "page-thumb-2").firstMatch
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        sleep(1)
        shot("13-page-grid")
        third.tap()
        sleep(1)
        shot("14-rotated-page")

        tapCentre(app.buttons["add-page-menu"])
        tapCentre(app.buttons["Ruled"])
        sleep(1)
        let label = app.staticTexts["page-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertTrue(label.label.hasSuffix("/ 4"), "page label is \(label.label)")
        shot("15-added-ruled-page")
    }
}
