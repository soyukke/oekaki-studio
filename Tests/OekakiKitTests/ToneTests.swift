import CoreGraphics
import XCTest
@testable import OekakiKit

/// Turning a layer's paint into dots, like the screen tone of comics.
final class ToneTests: XCTestCase {
    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func square(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat) -> [CGPoint] {
        [CGPoint(x: x, y: y), CGPoint(x: x + side, y: y), CGPoint(x: x + side, y: y + side), CGPoint(x: x, y: y + side)]
    }

    /// The red of every pixel in a square, x and y from `x` up to `x + side`.
    private func reds(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat, _ side: Int) -> [Double] {
        (0..<side).flatMap { dy in (0..<side).map { dx in color(document, x + CGFloat(dx), y + CGFloat(dy)).r } }
    }

    private func grey(_ value: Double) -> RGBA { RGBA(r: value, g: value, b: value) }

    func testGreyPaintTurnsIntoBlackDots() {
        let document = CanvasDocument(width: 200, height: 160)
        document.addLayer()
        let id = document.activeLayerID
        document.fillShape(square(40, 40, 100), color: grey(0.5))
        XCTAssertEqual(color(document, 90, 90).r, 0.5, accuracy: 0.02)
        document.setLayerTone(id, 8)
        XCTAssertEqual(document.layers[1].style.tone, 8)
        let inside = reds(document, 60, 60, 40)
        XCTAssertGreaterThan(inside.filter { $0 < 0.15 }.count, 200, "black dots")
        XCTAssertGreaterThan(inside.filter { $0 > 0.85 }.count, 200, "and white paper between them")
        XCTAssertEqual(inside.reduce(0, +) / Double(inside.count), 0.5, accuracy: 0.15, "about as dark as the grey was")
        XCTAssertEqual(color(document, 20, 20).r, 1, accuracy: 0.01, "no dots where there is no paint")
        document.undo()
        XCTAssertEqual(color(document, 90, 90).r, 0.5, accuracy: 0.02, "grey again")
    }

    func testDarkerPaintHasBiggerDots() {
        let document = CanvasDocument(width: 240, height: 120)
        document.addLayer()
        let id = document.activeLayerID
        document.fillShape(square(10, 10, 100), color: grey(0.8))
        document.fillShape(square(130, 10, 100), color: grey(0.3))
        document.setLayerTone(id, 8)
        let light = reds(document, 30, 30, 40).filter { $0 < 0.5 }.count
        let dark = reds(document, 150, 30, 40).filter { $0 < 0.5 }.count
        XCTAssertGreaterThan(dark, light * 2)
    }

    func testAClippedLayerTurnsIntoDotsInsideItsBase() {
        let document = CanvasDocument(width: 200, height: 160)
        document.addLayer()
        document.fillShape(square(40, 40, 100), color: .white)
        document.addLayer()
        let top = document.activeLayerID
        document.setLayerClipped(top, true)
        document.fillShape(square(20, 20, 160), color: grey(0.5))
        document.setLayerTone(top, 8)
        let inside = reds(document, 60, 60, 40)
        XCTAssertGreaterThan(inside.filter { $0 < 0.15 }.count, 200, "dots inside the base")
        XCTAssertEqual(color(document, 30, 30).r, 1, accuracy: 0.01, "nothing outside it")
    }

    func testDotsAreSavedAndReplayed() throws {
        let document = CanvasDocument(width: 200, height: 160)
        document.addLayer()
        let id = document.activeLayerID
        document.fillShape(square(40, 40, 100), color: grey(0.5))
        document.setLayerTone(id, 6)
        let data = try DocumentFile.encode(document)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"tone\""))
        let reopened = try DocumentFile.decode(data)
        XCTAssertEqual(reopened.layers[1].style, LayerStyle(tone: 6))
        XCTAssertEqual(reds(reopened, 60, 60, 20), reds(document, 60, 60, 20))
        let replay = Replay(steps: reopened.journal, width: 200, height: 160)
        XCTAssertTrue(replay.titles.contains { $0.contains("点で塗った") || $0.contains("into dots") })
        XCTAssertTrue(replay.changes.contains { $0.restyledLayers.contains { $0.style.tone == 6 } })
    }
}
