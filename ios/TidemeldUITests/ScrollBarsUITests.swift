import XCTest

/// Scrolls a long page up and down and saves a screenshot after each step to
/// the directory in `TIDEMELD_SHOTS`, to see how the bars follow the scroll. Runs
/// on a simulator with no real login only.
final class ScrollBarsUITests: XCTestCase {
    @MainActor
    func testBarsFollowTheScroll() throws {
        let shots = ProcessInfo.processInfo.environment["TIDEMELD_SHOTS"] ?? NSTemporaryDirectory()
        let app = XCUIApplication()
        app.launchArguments = ["-tidemeld-open", ProcessInfo.processInfo.environment["TIDEMELD_PAGE"] ?? "licenses"]
        app.launch()
        sleep(2)
        func shot(_ name: String) {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try? data.write(to: URL(fileURLWithPath: shots).appendingPathComponent("\(name).png"))
        }
        shot("0-start")
        let window = app.windows.firstMatch
        func drag(_ from: CGFloat, _ to: CGFloat) {
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            sleep(1)
        }
        // Well down the page, then a little way back, short of the top.
        drag(0.8, 0.2)
        drag(0.8, 0.2)
        shot("1-down")
        drag(0.4, 0.6)
        shot("2-back")
        // On again, then a flick back, as people scroll.
        drag(0.8, 0.2)
        shot("3-on-again")
        window.swipeDown(velocity: .fast)
        sleep(1)
        shot("4-flick")
    }

    /// The tab bar hidden on 关于, then 开源许可 opened over it and closed
    /// again: it should show on both.
    @MainActor
    func testBarsOverAPageOpened() throws {
        let shots = ProcessInfo.processInfo.environment["TIDEMELD_SHOTS"] ?? NSTemporaryDirectory()
        let app = XCUIApplication()
        app.launchArguments = ["-tidemeld-open", "about"]
        app.launch()
        sleep(2)
        func shot(_ name: String) {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try? data.write(to: URL(fileURLWithPath: shots).appendingPathComponent("\(name).png"))
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        shot("open-1-hidden")
        app.staticTexts["开源许可"].firstMatch.tap()
        sleep(2)
        shot("open-2-opened")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(2)
        shot("open-3-back")
    }
}
