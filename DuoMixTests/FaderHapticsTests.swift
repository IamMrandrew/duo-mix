import XCTest
@testable import DuoMix

final class FaderHapticsTests: XCTestCase {
    func testDragHasPickupSpacedTicksAndASingleStop() {
        let time = Date()
        var haptics = FaderHaptics(divisions: 10)
        haptics.begin(at: 0.5, time: time)
        XCTAssertEqual(haptics.pulse.kind, .pickup)
        haptics.move(to: 0.55, time: time.addingTimeInterval(0.1))
        XCTAssertEqual(haptics.pulse.sequence, 1)
        haptics.move(to: 0.65, time: time.addingTimeInterval(0.12))
        XCTAssertEqual(haptics.pulse.kind, .tick)
        haptics.move(to: 0.75, time: time.addingTimeInterval(0.13))
        XCTAssertEqual(haptics.pulse.sequence, 2)
        haptics.move(to: 1, time: time.addingTimeInterval(0.16))
        haptics.move(to: 1, time: time.addingTimeInterval(0.28))
        XCTAssertEqual(haptics.pulse.sequence, 3)
        XCTAssertEqual(haptics.pulse.kind, .endStop)
    }

    func testPrecisionPadTicksAtOnePercentAndNudgesAtLimits() {
        let time = Date()
        var haptics = FaderHaptics(divisions: 100)
        haptics.begin(at: 0.4, time: time)
        haptics.move(to: 0.414, time: time.addingTimeInterval(0.2))
        XCTAssertEqual(haptics.pulse.kind, .tick)
        haptics.nudge(to: 0)
        XCTAssertEqual(haptics.pulse.kind, .endStop)
    }
}
