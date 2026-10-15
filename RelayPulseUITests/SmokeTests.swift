import XCTest

/// Opens the app on the demo fleet (no server is contacted), walks the screens
/// changed in 1.0.14 and saves a screenshot of each step. Runs on a cloud Mac
/// in the iOS Simulator (.github/workflows/build.yml); the pictures are the
/// "does it look right" check before anything goes to TestFlight.
final class SmokeTests: XCTestCase {
    private let shots = (ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()) + "/rp-shots"

    override func setUp() {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        let image = XCUIScreen.main.screenshot()
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        try? image.pngRepresentation.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
        let a = XCTAttachment(screenshot: image)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // No "-appearance" argument: it would outrank the Settings picker the test taps.
        app.launchArguments += ["-demoMode", "YES"]
        app.launch()
        let demo = app.buttons["Try Demo Fleet"]
        if demo.waitForExistence(timeout: 4) { demo.tap() }
        return app
    }

    private func open(_ app: XCUIApplication, _ title: String) {
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(title) row in the menu")
        row.tap()
    }

    private func back(_ app: XCUIApplication) {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
    }

    func testScreens() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Servers"].waitForExistence(timeout: 15), "main menu shows")
        shot("01-menu")

        open(app, "Servers")
        XCTAssertTrue(app.staticTexts["web-01"].waitForExistence(timeout: 10), "demo relays listed")
        shot("02-servers")

        // Range search: demo names end in 01 / 02; "2-2" keeps the 02 ones only.
        app.swipeDown()
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("2-2")
            XCTAssertTrue(app.staticTexts["web-02"].waitForExistence(timeout: 5), "web-02 matches 2-2")
            XCTAssertFalse(app.staticTexts["web-01"].exists, "web-01 is filtered out by 2-2")
            shot("03-range-search")
            if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        } else {
            XCTFail("search field not found")
        }
        back(app)

        open(app, "Fleet Health")
        shot("04-fleet-health")
        back(app)

        open(app, "Settings")
        let dark = app.buttons["Dark"].firstMatch
        if !dark.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(dark.waitForExistence(timeout: 5), "Appearance picker in Settings")
        if dark.exists { dark.tap() }
        shot("05-settings-dark")
        back(app)

        open(app, "Servers")
        _ = app.staticTexts["web-01"].waitForExistence(timeout: 10)
        shot("06-servers-dark")
    }
}
