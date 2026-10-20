import CoreGraphics
import XCTest
@testable import OekakiKit

final class TidyTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)
    private let blue = RGBA(r: 0, g: 0, b: 1)

    private func line(
        _ document: CanvasDocument, _ points: [CGPoint], color: RGBA = .black, width: CGFloat = 4
    ) {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: points[0].x, y: points[0].y), color: color, width: width, isEraser: false))
        for (start, end) in zip(points, points.dropFirst()) {
            for step in 1...20 {
                let t = CGFloat(step) / 20
                document.continueStroke(to: StrokePoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            }
        }
        document.endStroke()
    }

    /// A square outline from (50, 40) to (150, 120) with a paint layer under it, in use.
    private func outlinedSquare() -> CanvasDocument {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [CGPoint(x: 50, y: 40), CGPoint(x: 150, y: 40), CGPoint(x: 150, y: 120), CGPoint(x: 50, y: 120), CGPoint(x: 50, y: 40)])
        document.addLayer()
        document.moveLayer(document.activeLayerID, by: -1)
        return document
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func stroke(_ points: [(CGFloat, CGFloat)]) -> Stroke {
        Stroke(id: 1, points: points.map { StrokePoint(x: $0.0, y: $0.1) }, color: .black, width: 4, isEraser: false)
    }

    // MARK: Paint

    func testPaintThatCrossedALineIsTakenOutAndGapsAreFilled() {
        let document = outlinedSquare()
        // Covers most of the square, misses its left side and runs out past its right side.
        for y in stride(from: CGFloat(50), through: 110, by: 10) {
            line(document, [CGPoint(x: 75, y: y), CGPoint(x: 160, y: y)], color: red, width: 14)
        }
        XCTAssertEqual(color(document, 160, 80), red)
        XCTAssertEqual(color(document, 58, 80), .white)

        let result = document.tidyPaint()
        XCTAssertEqual(result?.foundLines, true)
        XCTAssertGreaterThan(result?.removed ?? 0, 0)
        XCTAssertGreaterThan(result?.added ?? 0, 0)
        XCTAssertEqual(color(document, 160, 80), .white, "the spill is gone")
        XCTAssertEqual(color(document, 58, 80), red, "the gap is filled")
        XCTAssertEqual(color(document, 100, 80), red)
        XCTAssertEqual(color(document, 150, 80), .black, "the outline is untouched")
    }

    func testTheRoughPaintIsKeptHiddenAndUndoBringsItBack() {
        let document = outlinedSquare()
        let rough = document.activeLayerID
        line(document, [CGPoint(x: 70, y: 80), CGPoint(x: 165, y: 80)], color: red, width: 60)
        document.tidyPaint()
        XCTAssertEqual(document.layers.count, 3)
        XCTAssertEqual(document.layers.first { $0.id == rough }?.isVisible, false)
        XCTAssertNotEqual(document.activeLayerID, rough)

        document.undo()
        XCTAssertEqual(document.layers.count, 2)
        XCTAssertEqual(document.layers.first { $0.id == rough }?.isVisible, true)
        XCTAssertEqual(color(document, 162, 80), red)
    }

    func testAnAreaThatIsBarelyPaintedIsNotFilled() {
        let document = outlinedSquare()
        line(document, [CGPoint(x: 70, y: 60), CGPoint(x: 90, y: 60)], color: red, width: 10)
        document.tidyPaint()
        XCTAssertEqual(color(document, 80, 60), red)
        XCTAssertEqual(color(document, 130, 100), .white)
    }

    func testTwoColorsInOneAreaBothStay() {
        let document = outlinedSquare()
        line(document, [CGPoint(x: 60, y: 60), CGPoint(x: 140, y: 60)], color: red, width: 36)
        line(document, [CGPoint(x: 60, y: 100), CGPoint(x: 140, y: 100)], color: blue, width: 36)
        document.tidyPaint()
        XCTAssertEqual(color(document, 100, 55), red)
        XCTAssertEqual(color(document, 100, 105), blue)
        XCTAssertEqual(color(document, 56, 55), red, "each colour reaches the outline")
        XCTAssertEqual(color(document, 56, 105), blue)
    }

    func testPaintWithoutAnyLinesIsOnlySmoothed() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [CGPoint(x: 60, y: 80), CGPoint(x: 140, y: 80)], color: red, width: 30)
        let result = document.tidyPaint()
        XCTAssertEqual(result?.foundLines, false)
        XCTAssertEqual(color(document, 100, 80), red)
        XCTAssertEqual(color(document, 100, 20), .white)
    }

    func testALayerWithoutColorIsLeftAlone() {
        let document = outlinedSquare()
        XCTAssertNil(document.tidyPaint())
        XCTAssertEqual(document.layers.count, 2)
    }

    // MARK: Lines

    func testAShakyLineIsSteadiedAndKeepsItsEnds() {
        let shaky = (0...100).map { step -> (CGFloat, CGFloat) in
            (20 + CGFloat(step) * 3, 80 + (step % 2 == 0 ? 3 : -3))
        }
        let tidy = LineTidy.tidied([stroke(shaky)], smoothing: 10)[0]
        XCTAssertEqual(tidy.points.first?.x ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(tidy.points.last?.x ?? 0, 320, accuracy: 0.01)
        // Away from the two fixed ends, the wobble of 3 px either way is nearly gone.
        let middle = tidy.points.filter { $0.x > 60 && $0.x < 280 }
        XCTAssertFalse(middle.isEmpty)
        XCTAssertLessThan(middle.map { abs($0.y - 80) }.max() ?? 99, 0.6)
    }

    func testCornersStaySharp() {
        let corner = LineTidy.tidied([stroke([(20, 20), (120, 20), (120, 120)])], smoothing: 10)[0]
        let nearest = corner.points.map { hypot($0.x - 120, $0.y - 20) }.min() ?? 99
        XCTAssertLessThan(nearest, 0.5)
    }

    func testAnOutlineThatNearlyClosesIsClosed() {
        let ring = (0...58).map { step -> (CGFloat, CGFloat) in
            let angle = CGFloat(step) / 60 * 2 * .pi
            return (100 + 60 * cos(angle), 100 + 60 * sin(angle))
        }
        let tidy = LineTidy.tidied([stroke(ring)], smoothing: 10)[0]
        XCTAssertEqual(tidy.points.first, tidy.points.last)
        // Still a circle of about the same size.
        for point in tidy.points {
            XCTAssertEqual(hypot(point.x - 100, point.y - 100), 60, accuracy: 2.5)
        }
    }

    func testALooseEndIsJoinedToTheLineItNearlyTouches() {
        let wall = stroke([(100, 20), (100, 180)])
        let reaching = stroke([(20, 100), (90, 100)])
        let tidy = LineTidy.tidied([wall, reaching], smoothing: 10)
        XCTAssertEqual(tidy[1].points.last?.x ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(tidy[1].points.last?.y ?? 0, 100, accuracy: 2)
        XCTAssertEqual(tidy[1].points.first?.x ?? 0, 20, accuracy: 0.01, "an end with nothing near it stays put")
    }

    func testTidyingLinesKeepsTheOriginalHidden() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [CGPoint(x: 20, y: 80), CGPoint(x: 180, y: 80)])
        let rough = document.activeLayerID
        XCTAssertTrue(document.tidyLines())
        XCTAssertEqual(document.layers.count, 2)
        XCTAssertEqual(document.layers.first { $0.id == rough }?.isVisible, false)
        XCTAssertEqual(color(document, 100, 80), .black)

        document.undo()
        XCTAssertEqual(document.layers.count, 1)
        XCTAssertEqual(document.layers[0].isVisible, true)
    }

    func testALayerWithoutLinesIsLeftAlone() {
        let document = CanvasDocument(width: 200, height: 160)
        XCTAssertFalse(document.tidyLines())
        XCTAssertEqual(document.layers.count, 1)
    }
}
