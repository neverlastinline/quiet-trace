import XCTest

/// End-to-end checks in a simulator: choose a colour, trace a square with real touches,
/// see the next drawing arrive, and use the hidden grown-up exit.
final class QuietTraceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The first drawing is always the square, so the test knows where to trace.
        app.launchArguments = ["-QuietTraceFirst", "shapes/square"]
        app.launch()
    }

    private var stage: XCUIElement { app.otherElements["stage"] }

    /// Keeps a screenshot with the test results, and also writes it to $QT_SHOTS when set
    /// (CI sets TEST_RUNNER_QT_SHOTS) so the pictures can be looked at without Xcode.
    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["QT_SHOTS"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    /// Saves what's on screen, as the accessibility hierarchy, for working out why a test failed.
    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["QT_SHOTS"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? text.write(toFile: dir + "/" + name + ".txt", atomically: true, encoding: .utf8)
        }
    }

    private func wait(for element: XCUIElement, _ format: String, timeout: TimeInterval) {
        let found = expectation(for: NSPredicate(format: format), evaluatedWith: element)
        wait(for: [found], timeout: timeout)
    }

    private func chooseAColour() {
        let rose = app.buttons["rose"]
        XCTAssertTrue(rose.waitForExistence(timeout: 10))
        snap("1-colours")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier IN %@",
            ["rose", "peach", "sunflower", "mint", "sky", "ocean", "lavender", "berry"])).count, 8)
        rose.tap()
        // Generous: the first launch on a freshly booted simulator can be slow.
        if !stage.waitForExistence(timeout: 15) {
            snap("choose-failed")
            note("choose-failed-app", app.debugDescription)
            note("choose-failed-springboard", XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
            XCTFail("Choosing a colour didn't open the tracing screen")
        }
        wait(for: stage, "value == 'square'", timeout: 5)
        // Let the drawing fade in.
        Thread.sleep(forTimeInterval: 1)
    }

    /// A point in the 100 × 100 drawing box, on screen (the box fills 74% of the shorter side).
    private func boxPoint(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        let frame = app.windows.firstMatch.frame
        let size = min(frame.width, frame.height) * 0.74
        let left = (frame.width - size) / 2, top = (frame.height - size) / 2
        return app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: left + x * size / 100, dy: top + y * size / 100))
    }

    func testTracingTheSquareBringsTheNextDrawing() {
        chooseAColour()
        snap("2-square")
        let corners: [(CGFloat, CGFloat)] = [(15, 15), (85, 15), (85, 85), (15, 85), (15, 15)]
        for i in 0..<4 {
            boxPoint(corners[i].0, corners[i].1)
                .press(forDuration: 0.05, thenDragTo: boxPoint(corners[i + 1].0, corners[i + 1].1))
            if i == 1 { snap("3-half-traced") }
        }
        snap("4-celebrating")
        // Celebration, then a fade, then something new.
        wait(for: stage, "value != 'square' AND value != nil", timeout: 15)
        Thread.sleep(forTimeInterval: 1)
        snap("5-next")
    }

    func testAScribbleIsNotEnough() {
        chooseAColour()
        boxPoint(40, 40).press(forDuration: 0.05, thenDragTo: boxPoint(60, 60))
        Thread.sleep(forTimeInterval: 5)
        XCTAssertEqual(stage.value as? String, "square")
    }

    func testHoldingTheTopLeftCornerGoesBackToTheColours() {
        chooseAColour()
        let corner = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 30, dy: 30))
        // A short press does nothing...
        corner.press(forDuration: 1)
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertFalse(app.buttons["rose"].exists)
        XCTAssertEqual(stage.value as? String, "square")
        // ...a three-second hold goes back.
        corner.press(forDuration: 3.5)
        XCTAssertTrue(app.buttons["rose"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["rose"].isHittable)
        XCTAssertFalse(stage.exists)
    }
}
