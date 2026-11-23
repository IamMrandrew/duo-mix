import XCTest
@testable import DuoMix

final class FaderBankLayoutTests: XCTestCase {
    func testZoomChangesBankCapacityWhileKeepingAReachableTouchTarget() {
        let widths = FaderBankLayout.stripWidths.indices.map {
            FaderBankLayout(width: 390, margin: 8, hinge: nil, zoom: $0, accessible: false).count
        }
        XCTAssertEqual(widths, [7, 6, 5, 4])
        XCTAssertEqual(FaderBankLayout.stripWidths[FaderBankLayout.defaultZoom], 72)
        XCTAssertGreaterThanOrEqual(FaderBankLayout.stripWidths.min()!, 48)
    }

    func testBookSpreadsOneBankAcrossUnequalPanes() {
        let hinge = CGRect(x: 335, y: 0, width: 18, height: 560)
        let layout = FaderBankLayout(width: 780, margin: 12, hinge: hinge, zoom: 1, accessible: false)
        XCTAssertEqual(layout.firstWidth, 321)
        XCTAssertEqual(layout.gap, 22)
        XCTAssertEqual(layout.firstCount, 5)
        XCTAssertEqual(layout.secondCount, 6)
        XCTAssertEqual(layout.count, 11)
    }
}
