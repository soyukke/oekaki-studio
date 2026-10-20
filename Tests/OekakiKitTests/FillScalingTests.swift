import CoreGraphics
import XCTest
@testable import OekakiKit

/// Big fills, with holes and odd sizes, keep their shape when moved and resized.
final class FillScalingTests: XCTestCase {
    func testABigFillMovedAndResizedGrows() {
        let document = CanvasDocument(width: 1600, height: 1200)
        func line(_ points: [(CGFloat, CGFloat)]) -> Int {
            XCTAssertTrue(document.beginStroke(at: StrokePoint(x: points[0].0, y: points[0].1), color: .black, width: 6, isEraser: false))
            for p in points.dropFirst() { document.continueStroke(to: StrokePoint(x: p.0, y: p.1)) }
            document.endStroke()
            return document.activeLayer!.items.last!.id
        }
        let ring = (0...80).map { i -> (CGFloat, CGFloat) in
            let a = CGFloat(i) / 80 * 2 * .pi
            return (800 + 297 * cos(a), 640 + 263 * sin(a))
        }
        let outline = line(ring)
        document.addLayer()
        document.moveLayer(document.activeLayerID, by: -1)
        XCTAssertTrue(document.fill(at: CGPoint(x: 800, y: 640), color: RGBA(r: 1, g: 0, b: 0)))
        let fill = document.layers[0].items[0].id
        func red(_ x: CGFloat, _ y: CGFloat) -> Bool { let c = document.pickColor(at: CGPoint(x: x, y: y))!; return c.r > 0.9 && c.g < 0.2 }
        XCTAssertFalse(red(800, 330), "outside before")
        document.transformItems([outline, fill], by: CGAffineTransform(translationX: 12, y: 0))
        document.scaleItems([outline, fill], by: 1.25)
        XCTAssertTrue(red(800, 330), "inside after")
    }
}
