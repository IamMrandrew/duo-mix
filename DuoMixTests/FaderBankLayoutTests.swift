import XCTest
@testable import DuoMix

final class FaderBankLayoutTests: XCTestCase {
    func testFitsWholeStripsAtThePresetWidth() {
        // Two 72-point strips, a one-point divider, and two eight-point margins.
        XCTAssertEqual(FaderBankLayout(width: 160, margin: 8, hinge: nil, accessible: false).count, 1)
        XCTAssertEqual(FaderBankLayout(width: 161, margin: 8, hinge: nil, accessible: false).count, 2)
        let standard = FaderBankLayout(width: 390, margin: 8, hinge: nil, accessible: false)
        let accessible = FaderBankLayout(width: 390, margin: 8, hinge: nil, accessible: true)
        XCTAssertEqual(standard.count, 5)
        XCTAssertGreaterThan(accessible.count, 0)
        XCTAssertLessThan(accessible.count, standard.count)
    }

    func testBookSpreadsOneBankAcrossUnequalPanes() {
        let hinge = CGRect(x: 335, y: 0, width: 18, height: 560)
        let layout = FaderBankLayout(width: 780, margin: 12, hinge: hinge, accessible: false)
        XCTAssertEqual(layout.firstWidth, 321)
        XCTAssertEqual(layout.gap, 22)
        XCTAssertEqual(layout.firstCount, 4)
        XCTAssertEqual(layout.secondCount, 5)
        XCTAssertEqual(layout.count, 9)
    }

    func testTabletopToolbarFitsBesideEitherCamera() {
        let right = TabletopToolbarLayout(width: 669, margin: 12, safeTop: 82,
                                          occlusions: [CGRect(x: 525, y: 0, width: 144, height: 82)],
                                          accessible: false)
        XCTAssertEqual(right.leadingInset, 0)
        XCTAssertGreaterThanOrEqual(right.trailingInset, 132)
        XCTAssertLessThan(right.rowTop, 20)
        XCTAssertEqual(right.height, 82)

        let left = TabletopToolbarLayout(width: 669, margin: 12, safeTop: 82,
                                         occlusions: [CGRect(x: 0, y: 0, width: 144, height: 82)],
                                         accessible: false)
        XCTAssertEqual(left.trailingInset, 0)
        XCTAssertGreaterThanOrEqual(left.leadingInset, 132)
        XCTAssertLessThan(left.rowTop, 20)
        XCTAssertEqual(left.height, 82)
    }

    func testTabletopToolbarUsesSafeAreaWhenClearSpanIsUnknownOrTooNarrow() {
        let nearlyFull = CGRect(x: 70, y: 0, width: 599, height: 82)
        for occlusions: [CGRect] in [[], [nearlyFull]] {
            let layout = TabletopToolbarLayout(width: 669, margin: 12, safeTop: 82,
                                               occlusions: occlusions, accessible: false)
            XCTAssertGreaterThanOrEqual(layout.rowTop, 82)
            XCTAssertEqual(layout.leadingInset, 0)
            XCTAssertEqual(layout.trailingInset, 0)
        }
    }
}
