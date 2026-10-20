import CoreGraphics
import XCTest
@testable import OekakiKit

/// Blurring a layer, and filling the area an outline goes round.
final class BlurAndShapeTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func square(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> [CGPoint] {
        [CGPoint(x: x, y: y), CGPoint(x: x + side, y: y), CGPoint(x: x + side, y: y + side), CGPoint(x: x, y: y + side)]
    }

    // MARK: The lasso fill

    func testAnOutlineIsFilledWithoutLines() {
        let document = CanvasDocument(width: 200, height: 160)
        XCTAssertTrue(document.fillShape(square(50, 40, 80), color: red))
        XCTAssertEqual(color(document, 90, 80).g, 0, accuracy: 0.01, "inside is red")
        XCTAssertEqual(color(document, 40, 80).g, 1, accuracy: 0.01, "outside stays white")
        guard case .fill(let fill) = document.layers[0].items.last else { return XCTFail("A fill") }
        XCTAssertNil(fill.seed, "nothing was clicked")
        // Nothing to go round, nothing filled.
        XCTAssertFalse(document.fillShape([CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 20)], color: red))
        XCTAssertFalse(document.fillShape(square(300, 300, 20), color: red), "off the canvas")
    }

    func testASlantedEdgeIsSoft() {
        let document = CanvasDocument(width: 200, height: 160)
        document.fillShape([CGPoint(x: 20, y: 20), CGPoint(x: 180, y: 40), CGPoint(x: 100, y: 150)], color: .black)
        // Along the long slanted edge, some pixels are part covered: grey, not black or white.
        let greys = (0..<160).filter { x in
            let y = 20 + CGFloat(x) / 160 * 20
            let value = color(document, 20 + CGFloat(x), y.rounded(.down)).r
            return value > 0.1 && value < 0.9
        }
        XCTAssertGreaterThan(greys.count, 10)
    }

    func testTheLassoFillIsUndoneSavedAndReplayed() throws {
        let document = CanvasDocument(width: 200, height: 160)
        document.fillShape(square(50, 40, 80), color: red)
        document.undo()
        XCTAssertEqual(color(document, 90, 80).g, 1, accuracy: 0.01)
        document.redo()
        XCTAssertEqual(color(document, 90, 80).g, 0, accuracy: 0.01)
        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(color(reopened, 90, 80).g, 0, accuracy: 0.01)
        XCTAssertEqual(color(reopened, 40, 80).g, 1, accuracy: 0.01)
        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        XCTAssertNotNil(replay.frame(maxSide: 200))
        XCTAssertTrue(replay.changes.contains { change in
            change.added.contains { if case .fill = $0.item { return true }; return false }
        })
    }

    // MARK: Blur

    func testABlurredLayerSpreads() {
        let document = CanvasDocument(width: 200, height: 160)
        document.addLayer()
        let id = document.activeLayerID
        document.fillShape(square(80, 60, 40), color: .black)
        let sharpOutside = color(document, 74, 80).r
        let sharpInside = color(document, 100, 80).r
        document.setLayerBlur(id, 16)
        XCTAssertEqual(document.layers[1].style.blur, 16)
        XCTAssertEqual(sharpOutside, 1, accuracy: 0.01)
        XCTAssertLessThan(color(document, 74, 80).r, 0.95, "the dark spreads out past the edge")
        XCTAssertGreaterThan(color(document, 81, 80).r, sharpInside + 0.1, "and the edge goes soft")
        document.undo()
        XCTAssertEqual(color(document, 74, 80).r, 1, accuracy: 0.01, "sharp again")
    }

    func testAClippedLayerBlursInsideItsBase() {
        let document = CanvasDocument(width: 200, height: 160)
        document.addLayer()
        document.fillShape(square(40, 40, 120), color: RGBA(r: 0.5, g: 0.5, b: 0.5))
        document.addLayer()
        let top = document.activeLayerID
        document.setLayerClipped(top, true)
        document.fillShape(square(20, 40, 80), color: red)
        XCTAssertEqual(color(document, 106, 70).g, 0.5, accuracy: 0.02, "grey just past the red")
        document.setLayerBlur(top, 20)
        XCTAssertLessThan(color(document, 106, 70).g, 0.45, "the red spreads past its edge")
        XCTAssertEqual(color(document, 30, 70).g, 1, accuracy: 0.01, "but not outside the base")
    }

    func testBlurIsSavedAndReplayed() throws {
        let document = CanvasDocument(width: 200, height: 160)
        document.addLayer()
        let id = document.activeLayerID
        document.fillShape(square(80, 60, 40), color: .black)
        document.setLayerBlur(id, 12)
        let data = try DocumentFile.encode(document)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"blur\""))
        let reopened = try DocumentFile.decode(data)
        XCTAssertEqual(reopened.layers[1].style, LayerStyle(blur: 12))
        XCTAssertEqual(color(reopened, 74, 80).r, color(document, 74, 80).r, accuracy: 0.02)
        let replay = Replay(steps: reopened.journal, width: 200, height: 160)
        XCTAssertTrue(replay.titles.contains { $0.contains("ぼかした") || $0.contains("Blurred") })
        XCTAssertTrue(replay.changes.contains { $0.restyledLayers.contains { $0.style.blur == 12 } })
    }
}
