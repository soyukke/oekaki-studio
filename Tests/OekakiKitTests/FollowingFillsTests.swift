import CoreGraphics
import XCTest
@testable import OekakiKit

/// Fills follow the lines around them when only the lines change shape.
final class FollowingFillsTests: XCTestCase {
    private let green = RGBA(r: 0, g: 0.6, b: 0)

    private func outline(_ document: CanvasDocument, _ points: [(CGFloat, CGFloat)]) -> Int {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: points[0].0, y: points[0].1), color: .black, width: 4, isEraser: false))
        for point in points.dropFirst() { document.continueStroke(to: StrokePoint(x: point.0, y: point.1)) }
        document.endStroke()
        return document.activeLayer!.items.last!.id
    }

    private func isGreen(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> Bool {
        let c = document.pickColor(at: CGPoint(x: x, y: y))!
        return abs(c.r - green.r) < 0.03 && abs(c.g - green.g) < 0.03 && abs(c.b - green.b) < 0.03
    }

    func testAFillGrowsWithItsOutline() {
        let document = CanvasDocument(width: 200, height: 160)
        let square = outline(document, [(70, 50), (110, 50), (110, 90), (70, 90), (70, 50)])
        XCTAssertTrue(document.fill(at: CGPoint(x: 90, y: 70), color: green))
        XCTAssertFalse(isGreen(document, 60, 70), "outside the square before")
        // Only the line is made bigger; the fill inside follows it.
        document.scaleItems([square], by: 1.8)
        XCTAssertTrue(isGreen(document, 60, 70), "the fill reaches the bigger outline")
        XCTAssertTrue(isGreen(document, 90, 70))
        let note = document.nextStepNote ?? ""
        XCTAssertTrue(note.contains("塗り 1 つも線に合わせた") || note.contains("refilled 1 fills"), note)
        // One step: taking it back brings back both.
        document.undo()
        XCTAssertFalse(isGreen(document, 60, 70))
        XCTAssertTrue(isGreen(document, 90, 70))
        document.redo()
        XCTAssertTrue(isGreen(document, 60, 70))
        // The replay shows the fill grown too.
        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        let frame = try! XCTUnwrap(replay.frame(maxSide: 200))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(frame, in: CGRect(x: -60, y: -(160 - 1 - 70), width: 200, height: 160))
        XCTAssertEqual(Int(pixel[1]), Int((0.6 * 255).rounded()), accuracy: 6, "the replay shows the grown fill: \(pixel)")
    }

    func testAFillFollowsAWobblierOutline() {
        let document = CanvasDocument(width: 240, height: 240)
        let ring = (0...60).map { i -> (CGFloat, CGFloat) in
            let a = CGFloat(i) / 60 * 2 * .pi
            let r: CGFloat = 70 + 8 * sin(a * 6)
            return (120 + r * cos(a), 120 + r * sin(a))
        }
        let line = outline(document, ring)
        XCTAssertTrue(document.fill(at: CGPoint(x: 120, y: 120), color: green))
        guard case .fill(let before) = document.activeLayer!.items.last! else { return XCTFail("no fill") }
        document.changeWaviness([line], by: 3)
        guard case .fill(let after) = document.activeLayer!.items.last! else { return XCTFail("no fill") }
        XCTAssertNotEqual(before.rect, after.rect, "the fill was painted again to the new outline")
        // Where the wobble now reaches past the old outline, it is filled.
        guard case .stroke(let stroke) = document.item(line)!.item else { return XCTFail() }
        let far = stroke.points.max { hypot($0.x - 120, $0.y - 120) < hypot($1.x - 120, $1.y - 120) }!
        let inside = CGPoint(x: 120 + (far.x - 120) * 0.93, y: 120 + (far.y - 120) * 0.93)
        XCTAssertGreaterThan(hypot(inside.x - 120, inside.y - 120), 80, "past the old outline")
        XCTAssertTrue(isGreen(document, inside.x, inside.y), "filled out to the wobble at \(inside)")
    }

    func testAFillStaysWhenItsOutlineOpens() {
        let document = CanvasDocument(width: 200, height: 160)
        let top = outline(document, [(70, 50), (110, 50)])
        _ = outline(document, [(110, 50), (110, 90), (70, 90), (70, 50)])
        XCTAssertTrue(document.fill(at: CGPoint(x: 90, y: 70), color: green))
        // Lifting the top line away opens the outline; the paint does not run out.
        document.transformItems([top], by: CGAffineTransform(translationX: 0, y: -30))
        XCTAssertTrue(isGreen(document, 90, 70))
        XCTAssertFalse(isGreen(document, 20, 20), "the paint did not run over the canvas")
    }

    func testAFillDoesNotSpillIntoTheNextRegion() {
        let document = CanvasDocument(width: 200, height: 160)
        _ = outline(document, (0...80).map { i -> (CGFloat, CGFloat) in
            let a = CGFloat(i) / 80 * 2 * .pi
            return (100 + 85 * cos(a), 80 + 60 * sin(a))
        })
        let divider = outline(document, (0...20).map { (100, 10 + CGFloat($0) * 7) })
        XCTAssertTrue(document.fill(at: CGPoint(x: 60, y: 80), color: green))
        XCTAssertFalse(isGreen(document, 140, 80))
        // Lifting the divider opens a way into the right half; the fill stays on its side.
        document.transformItems([divider], by: CGAffineTransform(translationX: 0, y: -60))
        XCTAssertTrue(isGreen(document, 60, 80))
        XCTAssertFalse(isGreen(document, 140, 80), "the paint did not run into the right half")
    }

    func testAnOlderFillIsLeftAlone() {
        let document = CanvasDocument(width: 200, height: 160)
        _ = outline(document, [(70, 50), (110, 50), (110, 90), (70, 90), (70, 50)])
        XCTAssertTrue(document.fill(at: CGPoint(x: 90, y: 70), color: green))
        guard case .fill(let before) = document.activeLayer!.items.last! else { return XCTFail() }
        // A line drawn across the fill later did not bound it, so moving it changes nothing.
        let across = outline(document, [(60, 70), (120, 70)])
        document.transformItems([across], by: CGAffineTransform(translationX: 0, y: 6))
        guard case .fill(let after) = document.activeLayer!.items.dropLast().last! else { return XCTFail() }
        XCTAssertEqual(before.rect, after.rect)
    }
}
