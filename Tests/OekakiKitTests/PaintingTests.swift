import CoreGraphics
import XCTest
@testable import OekakiKit

/// Soft and see-through strokes, blend modes, clipping, gradients and glow.
final class PaintingTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)
    private let blue = RGBA(r: 0, g: 0, b: 1)

    private func stroke(
        _ document: CanvasDocument, _ points: [(CGFloat, CGFloat)], color: RGBA, width: CGFloat,
        opacity: CGFloat = 1, softness: CGFloat = 0
    ) {
        XCTAssertTrue(document.beginStroke(
            at: StrokePoint(x: points[0].0, y: points[0].1), color: color, width: width, isEraser: false,
            opacity: opacity, softness: softness
        ))
        for point in points.dropFirst() {
            document.continueStroke(to: StrokePoint(x: point.0, y: point.1))
        }
        document.endStroke()
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func assertClose(_ a: RGBA, _ b: RGBA, within limit: Double = 0.03, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.r, b.r, accuracy: limit, "red", file: file, line: line)
        XCTAssertEqual(a.g, b.g, accuracy: limit, "green", file: file, line: line)
        XCTAssertEqual(a.b, b.b, accuracy: limit, "blue", file: file, line: line)
    }

    // MARK: Strokes

    func testAnAirbrushFadesOutAtItsEdge() {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(40, 80), (100, 80), (160, 80)], color: .black, width: 60, softness: 1)
        let middle = color(document, 100, 80).r
        let halfway = color(document, 100, 95).r
        let edge = color(document, 100, 108).r
        XCTAssertLessThan(middle, 0.1, "dark along the middle")
        XCTAssertGreaterThan(halfway, middle + 0.1, "lighter toward the edge")
        XCTAssertGreaterThan(edge, halfway, "lighter still at the edge")
        XCTAssertEqual(color(document, 100, 120).r, 1, accuracy: 0.01, "nothing past the edge")
    }

    func testASeeThroughStrokeDoesNotDarkenWhereItCrossesItself() {
        let document = CanvasDocument(width: 200, height: 160)
        // A loop that crosses itself at (100, 80).
        stroke(document, [(40, 40), (100, 80), (160, 120), (160, 40), (100, 80), (40, 120)], color: .black, width: 12, opacity: 0.5)
        let crossing = color(document, 100, 80).r
        let single = color(document, 160, 80).r
        XCTAssertEqual(single, 0.5, accuracy: 0.05)
        XCTAssertEqual(crossing, single, accuracy: 0.03)
    }

    func testAStrokeDrawnLiveMatchesTheSameStrokeDrawnAgain() throws {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(30, 30), (90, 60), (150, 50), (170, 130)], color: red, width: 50, opacity: 0.7, softness: 0.8)
        stroke(document, [(20, 140), (180, 20)], color: blue, width: 10, opacity: 0.4)
        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        for (x, y) in [(90, 60), (110, 70), (60, 45), (100, 80), (170, 128), (40, 120)] {
            assertClose(color(reopened, CGFloat(x), CGFloat(y)), color(document, CGFloat(x), CGFloat(y)), within: 0.02)
        }
    }

    // MARK: Layers

    private func twoLayers(top: RGBA, blend: BlendMode) -> CanvasDocument {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(20, 80), (180, 80)], color: RGBA(r: 0.5, g: 0.5, b: 0.5), width: 60)
        document.addLayer()
        stroke(document, [(100, 20), (100, 140)], color: top, width: 40)
        document.setLayerBlend(document.activeLayerID, blend)
        return document
    }

    func testBlendModes() {
        let grey = 0.5
        // Multiply: red over grey keeps the red channel at grey, the rest go black.
        let multiplied = color(twoLayers(top: red, blend: .multiply), 100, 80)
        assertClose(multiplied, RGBA(r: grey, g: 0, b: 0), within: 0.05)
        // Over white paper, multiply changes nothing where white.
        assertClose(color(twoLayers(top: red, blend: .multiply), 100, 140), red, within: 0.02)
        // Screen lightens: grey under red.
        let screened = color(twoLayers(top: red, blend: .screen), 100, 80)
        assertClose(screened, RGBA(r: 1, g: grey, b: grey), within: 0.05)
        // Add: grey plus grey is white.
        let added = color(twoLayers(top: RGBA(r: 0.5, g: 0.5, b: 0.5), blend: .add), 100, 80)
        assertClose(added, .white, within: 0.03)
        // Overlay keeps a mid grey base close to the top colour's direction.
        let overlaid = color(twoLayers(top: red, blend: .overlay), 100, 80)
        XCTAssertGreaterThan(overlaid.r, overlaid.g + 0.3)
    }

    func testAClippedLayerStaysInsideThePaintBelow() {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(20, 80), (180, 80)], color: .black, width: 40)
        document.addLayer()
        stroke(document, [(100, 10), (100, 150)], color: red, width: 30)
        assertClose(color(document, 100, 20), red, within: 0.02)
        document.setLayerClipped(document.activeLayerID, true)
        assertClose(color(document, 100, 20), .white, within: 0.02)
        assertClose(color(document, 100, 80), red, within: 0.02)
        assertClose(color(document, 30, 80), .black, within: 0.02)
        // Hiding the base hides what is clipped to it.
        document.setLayerVisible(document.layers[0].id, false)
        assertClose(color(document, 100, 80), .white, within: 0.02)
    }

    func testAGradientFadesFromItsColourToClear() {
        let document = CanvasDocument(width: 200, height: 160)
        var clear = blue
        clear.a = 0
        XCTAssertTrue(document.addGradient(GradientItem(shape: .linear, start: CGPoint(x: 0, y: 80), end: CGPoint(x: 200, y: 80), from: blue, to: clear)))
        assertClose(color(document, 1, 80), blue, within: 0.03)
        XCTAssertEqual(color(document, 100, 80).r, 0.5, accuracy: 0.06)
        assertClose(color(document, 199, 80), .white, within: 0.03)
        // A round one spreads out from its start.
        let round = CanvasDocument(width: 200, height: 160)
        round.addGradient(GradientItem(shape: .radial, start: CGPoint(x: 100, y: 80), end: CGPoint(x: 160, y: 80), from: red, to: RGBA(r: 1, g: 0, b: 0, a: 0)))
        assertClose(color(round, 100, 80), red, within: 0.03)
        XCTAssertEqual(color(round, 100, 110).g, color(round, 130, 80).g, accuracy: 0.03, "the same at the same distance")
        assertClose(color(round, 10, 10), .white, within: 0.02)
    }

    func testAGlowSpreadsLightAroundALayer() {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(0, 80), (200, 80)], color: RGBA(r: 0.1, g: 0.1, b: 0.3), width: 160)
        document.addLayer()
        stroke(document, [(90, 80), (110, 80)], color: RGBA(r: 1, g: 0.8, b: 0.4), width: 10)
        let before = color(document, 100, 100).r
        document.setLayerGlow(document.activeLayerID, 40)
        let after = color(document, 100, 100).r
        XCTAssertGreaterThan(after, before + 0.05, "light around the stroke")
        document.undo()
        XCTAssertEqual(color(document, 100, 100).r, before, accuracy: 0.01)
    }

    // MARK: Keeping it

    func testStylesUndoRedoAndReplay() {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(20, 80), (180, 80)], color: RGBA(r: 0.5, g: 0.5, b: 0.5), width: 60)
        document.addLayer()
        stroke(document, [(100, 10), (100, 150)], color: red, width: 30, opacity: 0.8, softness: 0.5)
        let id = document.activeLayerID
        let looks: () -> [RGBA] = { [(100, 80), (100, 20), (60, 80)].map { self.color(document, CGFloat($0.0), CGFloat($0.1)) } }
        var expected = [looks()]
        document.setLayerBlend(id, .multiply)
        expected.append(looks())
        document.setLayerClipped(id, true)
        expected.append(looks())
        document.undo()
        XCTAssertEqual(looks(), expected[1])
        document.redo()
        XCTAssertEqual(looks(), expected[2])
        XCTAssertNotEqual(expected[0], expected[1])
        XCTAssertNotEqual(expected[1], expected[2])

        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        XCTAssertTrue(replay.titles.contains { $0.contains(BlendMode.multiply.title) })
        XCTAssertEqual(replay.changes.compactMap { $0.restyledLayers.first?.style.blend }.first, .multiply)
        replay.seek(to: replay.count - 1)
        guard let frame = replay.frame(maxSide: 200) else { return XCTFail("No frame") }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(frame, in: CGRect(x: -100, y: -(160 - 1 - 20), width: 200, height: 160))
        XCTAssertEqual(Double(pixel[0]) / 255, expected[2][1].r, accuracy: 0.02, "the clipped stroke is gone above the base in the replay too")
    }

    func testEverythingNewIsSavedAndOpened() throws {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(20, 80), (180, 80)], color: .black, width: 40, opacity: 0.6, softness: 0.7)
        document.addLayer()
        document.addGradient(GradientItem(shape: .radial, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 90, y: 50), from: red, to: blue))
        let id = document.activeLayerID
        document.setLayerBlend(id, .screen)
        document.setLayerClipped(id, true)
        document.setLayerGlow(id, 24)

        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(reopened.layers[1].style, LayerStyle(blend: .screen, isClipped: true, glow: 24))
        guard case .stroke(let saved) = reopened.layers[0].items[0] else { return XCTFail("A stroke") }
        XCTAssertEqual(saved.opacity, 0.6, accuracy: 0.001)
        XCTAssertEqual(saved.softness, 0.7, accuracy: 0.001)
        guard case .gradient(let gradient) = reopened.layers[1].items[0] else { return XCTFail("A gradient") }
        XCTAssertEqual(gradient.shape, .radial)
        XCTAssertEqual(gradient.end, CGPoint(x: 90, y: 50))
        XCTAssertEqual(gradient.to, blue)
        for (x, y) in [(50, 50), (60, 80), (150, 80)] {
            assertClose(color(reopened, CGFloat(x), CGFloat(y)), color(document, CGFloat(x), CGFloat(y)), within: 0.02)
        }
        // The journal keeps the styles too.
        let replay = Replay(steps: reopened.journal, width: 200, height: 160)
        XCTAssertTrue(replay.changes.contains { $0.restyledLayers.contains { $0.style.glow == 24 } })
    }

    func testAFileFromBeforeTheseFeaturesStillOpens() throws {
        let document = CanvasDocument(width: 200, height: 160)
        stroke(document, [(20, 80), (180, 80)], color: .black, width: 8)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentFile.encode(document)) as? [String: Any])
        json["version"] = 3
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("\"blend\""))
        let opened = try DocumentFile.decode(old)
        XCTAssertEqual(opened.layers[0].style, LayerStyle())
        guard case .stroke(let saved) = opened.layers[0].items[0] else { return XCTFail("A stroke") }
        XCTAssertTrue(saved.isPlain)
    }
}
