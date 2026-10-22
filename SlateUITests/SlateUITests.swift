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

    private func waitForStrokes(_ app: XCUIApplication, _ expected: Int) {
        let deadline = Date().addingTimeInterval(5)
        while strokeCount(app) != expected && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(strokeCount(app), expected)
    }

    func testNewNotebookInkSurvivesRelaunch() {
        var app = launch(["-uitest-reset"])
        shot("01-library-empty")

        app.buttons["add-menu"].tap()
        app.buttons["New Notebook"].tap()
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

        app.buttons["add-page-menu"].tap()
        app.buttons["Ruled"].tap()
        sleep(1)
        let label = app.staticTexts["page-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(label.label, "4 / 4")
        shot("15-added-ruled-page")
    }
}
