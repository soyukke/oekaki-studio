import CoreGraphics
import XCTest
@testable import OekakiKit

/// Two- and three-finger taps, told from scrolling, pinching and pressing.
final class FingerTapsTests: XCTestCase {
    private func fingers(_ places: [(Int, CGFloat, CGFloat)]) -> [(id: AnyHashable, position: CGPoint)] {
        places.map { (AnyHashable($0.0), CGPoint(x: $0.1, y: $0.2)) }
    }

    func testTwoFingersTapped() {
        var taps = FingerTaps()
        XCTAssertNil(taps.update(touching: fingers([(1, 0.4, 0.5)]), at: 0))
        XCTAssertNil(taps.update(touching: fingers([(1, 0.4, 0.5), (2, 0.5, 0.5)]), at: 0.02))
        XCTAssertNil(taps.update(touching: fingers([(2, 0.5, 0.5)]), at: 0.12))
        XCTAssertEqual(taps.update(touching: [], at: 0.14), .two)
    }

    func testThreeFingersTapped() {
        var taps = FingerTaps()
        _ = taps.update(touching: fingers([(1, 0.3, 0.5), (2, 0.4, 0.5), (3, 0.5, 0.5)]), at: 1)
        XCTAssertEqual(taps.update(touching: [], at: 1.1), .three)
    }

    func testScrollingIsNotATap() {
        var taps = FingerTaps()
        _ = taps.update(touching: fingers([(1, 0.4, 0.5), (2, 0.5, 0.5)]), at: 0)
        _ = taps.update(touching: fingers([(1, 0.4, 0.4), (2, 0.5, 0.4)]), at: 0.1)
        XCTAssertNil(taps.update(touching: [], at: 0.2), "the fingers moved")
    }

    func testPressingIsNotATap() {
        var taps = FingerTaps()
        _ = taps.update(touching: fingers([(1, 0.4, 0.5), (2, 0.5, 0.5)]), at: 0)
        XCTAssertNil(taps.update(touching: [], at: 0.8), "held too long")
    }

    func testOneOrFourFingersAreNotTaps() {
        var taps = FingerTaps()
        _ = taps.update(touching: fingers([(1, 0.4, 0.5)]), at: 0)
        XCTAssertNil(taps.update(touching: [], at: 0.1))
        _ = taps.update(touching: fingers([(1, 0.2, 0.5), (2, 0.3, 0.5), (3, 0.4, 0.5), (4, 0.5, 0.5)]), at: 1)
        XCTAssertNil(taps.update(touching: [], at: 1.1))
    }

    func testEachTapStartsAfresh() {
        var taps = FingerTaps()
        _ = taps.update(touching: fingers([(1, 0.4, 0.5), (2, 0.5, 0.5)]), at: 0)
        XCTAssertEqual(taps.update(touching: [], at: 0.1), .two)
        _ = taps.update(touching: fingers([(3, 0.4, 0.5), (4, 0.5, 0.5)]), at: 0.5)
        XCTAssertEqual(taps.update(touching: [], at: 0.6), .two)
        // Cancelled by the system part way, nothing comes of it.
        _ = taps.update(touching: fingers([(5, 0.4, 0.5), (6, 0.5, 0.5)]), at: 1)
        taps.cancel()
        XCTAssertNil(taps.update(touching: [], at: 1.1))
    }
}
