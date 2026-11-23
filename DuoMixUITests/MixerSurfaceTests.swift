import XCTest

final class MixerSurfaceTests: XCTestCase {
    func testPracticeMixSelectionMuteFinePadAndBanking() {
        let app = XCUIApplication()
        app.launch()
        let snare = app.buttons["channel-2"]
        XCTAssertTrue(snare.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["demo-desk-title"].exists)
        snare.tap()

        let pad = app.descendants(matching: .any).matching(identifier: "fine-pad").firstMatch
        XCTAssertEqual(pad.value as? String, "63%")
        app.buttons["fine-up"].tap()
        XCTAssertEqual(pad.value as? String, "64%")
        let start = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end)
        let value = (pad.value as? String).flatMap { Int($0.dropLast()) } ?? 0
        XCTAssertGreaterThan(value, 64)
        XCTAssertLessThan(value, 80)

        let fader = app.descendants(matching: .any).matching(identifier: "fader-2").firstMatch
        let lower = fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let upper = fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        upper.press(forDuration: 0.1, thenDragTo: lower)
        let afterDrag = (fader.value as? String).flatMap { Int($0.dropLast()) } ?? 100
        XCTAssertLessThan(afterDrag, value)

        let mute = app.buttons["mute-2"]
        mute.tap()
        XCTAssertEqual(mute.value as? String, "On")
        app.buttons["next-bank"].tap()
        XCTAssertFalse(snare.exists)
        app.buttons["previous-bank"].tap()
        XCTAssertEqual(mute.value as? String, "On")
        app.buttons["connections"].tap()
        XCTAssertTrue(app.textFields["mixer-host"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connect-mixer"].exists)
        app.buttons["use-demo"].tap()
        XCTAssertTrue(app.staticTexts["demo-desk-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(mute.value as? String, "On")
    }
}
