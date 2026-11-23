import XCTest

final class MixerSurfaceTests: XCTestCase {
    func testPracticeMixSelectionMuteFinePadAndBanking() {
        let app = XCUIApplication()
        app.launch()
        continueAfterFailure = false
        let snare = app.buttons["channel-2"]
        XCTAssertTrue(snare.waitForExistence(timeout: 8))
        let connection = app.buttons["connections"]
        XCTAssertEqual(connection.label, "Mixer connection, Demo")
        XCTAssertFalse(app.staticTexts["demo-desk-title"].exists)
        snare.tap()
        XCTAssertTrue(snare.isSelected)
        app.buttons["channel-1"].tap()
        let range = app.staticTexts["visible-inputs"]
        let originalRange = range.label
        let strips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "channel-"))
        let originalCount = strips.count
        let zoomOut = app.buttons["zoom-out"]
        let zoomIn = app.buttons["zoom-in"]
        let showMore = zoomOut.isEnabled
        let first = showMore ? zoomOut : zoomIn
        let restore = showMore ? zoomIn : zoomOut
        for control in [connection, zoomOut, zoomIn, app.buttons["previous-bank"], app.buttons["next-bank"]] {
            assertTouchSize(control)
        }
        // Tap inside the padded target, beyond the smaller painted icon.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.12)).tap()
        XCTAssertNotEqual(range.label, originalRange)
        if showMore { XCTAssertGreaterThan(strips.count, originalCount) }
        else { XCTAssertLessThan(strips.count, originalCount) }
        let mute = app.buttons["mute-2"]
        let fader = app.descendants(matching: .any).matching(identifier: "fader-2").firstMatch
        for control in [snare, fader, mute] { assertTouchSize(control) }
        restore.tap()
        XCTAssertEqual(range.label, originalRange)
        XCTAssertEqual(strips.count, originalCount)

        XCTAssertEqual(fader.label, "Snare fader position")
        XCTAssertEqual(fader.value as? String, "63%")
        let meter = app.descendants(matching: .any).matching(identifier: "meter-2").firstMatch
        XCTAssertEqual(meter.label, "Snare input meter")
        XCTAssertTrue((meter.value as? String)?.contains("decibels") == true)
        let nearBottom = fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.87))
        nearBottom.tap()
        XCTAssertTrue(snare.isSelected)
        XCTAssertEqual(fader.value as? String, "63%", "Tapping the lane selects the channel at its current level")

        let pad = app.descendants(matching: .any).matching(identifier: "fine-pad").firstMatch
        if pad.exists {
            XCTAssertEqual(pad.label, "Fine fader position for Snare")
            for control in [pad, app.buttons["fine-up"], app.buttons["fine-down"]] { assertTouchSize(control) }
            XCTAssertEqual(pad.value as? String, "63%")
            app.buttons["fine-up"].tap()
            XCTAssertEqual(pad.value as? String, "64%")
            let start = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.1, thenDragTo: end)
            let fine = (pad.value as? String).flatMap { Int($0.dropLast()) } ?? 0
            XCTAssertGreaterThan(fine, 64)
            XCTAssertLessThan(fine, 80)
        } else {
            let percentages = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", #"^\d+\s*%$"#))
            XCTAssertEqual(percentages.count, 0)
        }
        let value = (fader.value as? String).flatMap { Int($0.dropLast()) } ?? 0
        let lower = fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let upper = fader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        upper.press(forDuration: 0.1, thenDragTo: lower)
        let afterDrag = (fader.value as? String).flatMap { Int($0.dropLast()) } ?? 100
        XCTAssertLessThan(afterDrag, value)

        mute.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.12)).tap()
        XCTAssertEqual(mute.value as? String, "On")
        app.buttons["next-bank"].tap()
        XCTAssertFalse(snare.exists)
        app.buttons["previous-bank"].tap()
        XCTAssertEqual(mute.value as? String, "On")
        app.buttons["connections"].tap()
        XCTAssertTrue(app.textFields["mixer-host"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connect-mixer"].exists)
        app.buttons["use-demo"].tap()
        XCTAssertTrue(connection.waitForExistence(timeout: 5))
        XCTAssertEqual(connection.label, "Mixer connection, Demo")
        XCTAssertEqual(mute.value as? String, "On")
    }

    private func assertTouchSize(_ control: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let frame = control.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(control.identifier) width", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 44, "\(control.identifier) height", file: file, line: line)
    }
}
