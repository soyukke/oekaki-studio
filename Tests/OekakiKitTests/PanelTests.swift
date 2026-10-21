import CoreGraphics
import XCTest
@testable import OekakiKit

/// Comic pages: cutting the page into panels, and keeping what is drawn
/// inside the panel it was begun in.
final class PanelTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)

    @discardableResult
    private func line(_ document: CanvasDocument, _ points: [(CGFloat, CGFloat)], width: CGFloat = 6) -> Int {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: points[0].0, y: points[0].1), color: .black, width: width, isEraser: false))
        for point in points.dropFirst() { document.continueStroke(to: StrokePoint(x: point.0, y: point.1)) }
        document.endStroke()
        return document.activeLayer!.items.last!.id
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func isBlack(_ c: RGBA) -> Bool { c.r < 0.1 && c.g < 0.1 && c.b < 0.1 }
    private func isWhite(_ c: RGBA) -> Bool { c.r > 0.9 && c.g > 0.9 && c.b > 0.9 }

    /// A 300 × 400 page cut once across the middle.
    private func page() -> CanvasDocument {
        let document = CanvasDocument(width: 300, height: 400)
        XCTAssertTrue(document.cutPanel(from: CGPoint(x: 10, y: 200), to: CGPoint(x: 290, y: 205)))
        return document
    }

    func testCuttingThePageMakesPanelsInReadingOrder() throws {
        let document = page()
        let layout = try XCTUnwrap(document.library.page)
        XCTAssertEqual(document.panels.count, 2)
        XCTAssertEqual(document.nextStepNote, "コマを切った（2 コマ）")
        let top = document.panels[0], bottom = document.panels[1]
        XCTAssertEqual(top.minX, CGFloat(layout.margin))
        XCTAssertLessThan(top.maxY, bottom.minY, "a gap between them")
        XCTAssertEqual(bottom.minY - top.maxY, CGFloat(layout.gapAcross), accuracy: 0.5)
        // The frames are drawn, and the gap is paper.
        XCTAssertTrue(isBlack(color(document, top.minX + 1, 100)))
        XCTAssertTrue(isWhite(color(document, 150, 100)))
        XCTAssertTrue(isWhite(color(document, 150, (top.maxY + bottom.minY) / 2)))
        // Cut down through the bottom panel: the right half is read first.
        XCTAssertTrue(document.cutPanel(from: CGPoint(x: 150, y: 220), to: CGPoint(x: 152, y: 390)))
        XCTAssertEqual(document.panels.count, 3)
        XCTAssertGreaterThan(document.panels[1].minX, document.panels[2].maxX)
        XCTAssertEqual(document.panels[1].minY, bottom.minY)
        // A short line, or one leaving a sliver, cuts nothing.
        XCTAssertFalse(document.cutPanel(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 130, y: 102)))
        XCTAssertFalse(document.cutPanel(from: CGPoint(x: 20, y: 25), to: CGPoint(x: 280, y: 25)))
        XCTAssertEqual(document.panels.count, 3)
        document.undo()
        XCTAssertEqual(document.panels.count, 2)
        document.setPage(nil)
        XCTAssertTrue(document.panels.isEmpty)
        XCTAssertEqual(document.nextStepNote, "コマ割りをやめた")
        XCTAssertTrue(isWhite(color(document, top.minX + 1, 100)), "no frames")
    }

    func testALineStaysInsideThePanelItWasBegunIn() throws {
        let document = page()
        document.addLayer()
        let top = document.panels[0], bottom = document.panels[1]
        // Begun in the top panel and dragged down into the bottom one.
        line(document, [(150, 150), (150, 350)])
        XCTAssertTrue(isBlack(color(document, 150, 150)))
        XCTAssertTrue(isWhite(color(document, 150, 300)), "cut off at the panel")
        XCTAssertTrue(isWhite(color(document, 150, (top.maxY + bottom.minY) / 2)), "not in the gap either")
        // Drawn again from the items, it is the same.
        document.undo()
        document.redo()
        XCTAssertTrue(isWhite(color(document, 150, 300)))
        // Begun in the gap, a line runs across the panels.
        line(document, [(100, (top.maxY + bottom.minY) / 2), (100, 350)])
        XCTAssertTrue(isBlack(color(document, 100, 300)))
        // A fill keeps to the panel too: the frame bounds it.
        XCTAssertTrue(document.fill(at: CGPoint(x: 60, y: 100), color: red))
        XCTAssertEqual(color(document, 60, 100), red)
        XCTAssertTrue(isWhite(color(document, 60, 300)))
        // A different cut and the line keeps to its new panel, the whole page high.
        document.setPage(nil)
        XCTAssertTrue(isBlack(color(document, 150, 300)), "a plain picture again")
    }

    func testALayerOverThePanelsRunsAcrossThem() throws {
        let document = page()
        document.addLayer()
        let balloons = document.activeLayerID
        document.setLayerOverPanels(balloons, true)
        line(document, [(150, 150), (150, 350)])
        XCTAssertTrue(isBlack(color(document, 150, 300)), "not kept inside the panel")
        // A thick white line on it covers the frame: it lies over the frames.
        let frameX = document.panels[0].minX + 1
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: frameX, y: 60), color: .white, width: 12, isEraser: false))
        document.continueStroke(to: StrokePoint(x: frameX, y: 140))
        document.endStroke()
        XCTAssertTrue(isWhite(color(document, frameX, 100)))
        // Put back under the frames, its items keep to their panels again.
        document.setLayerOverPanels(balloons, false)
        XCTAssertTrue(isWhite(color(document, 150, 300)))
        XCTAssertTrue(isBlack(color(document, frameX, 100)), "the frame shows over it")
        document.undo()
        XCTAssertTrue(isBlack(color(document, 150, 300)))
    }

    func testPanelsAreSavedOpenedAndReplayed() throws {
        let document = page()
        document.addLayer()
        line(document, [(150, 150), (150, 350)])
        document.addLayer()
        document.setLayerOverPanels(document.activeLayerID, true)
        line(document, [(60, 150), (60, 350)])
        let probes: [(CGFloat, CGFloat)] = [(150, 150), (150, 300), (60, 300), (document.panels[0].minX + 1, 100)]
        let looks = probes.map { color(document, $0.0, $0.1) }

        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(reopened.library.page, document.library.page)
        XCTAssertTrue(reopened.layers[2].style.overPanels)
        XCTAssertEqual(probes.map { color(reopened, $0.0, $0.1) }, looks)

        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 300, height: 400)
        replay.seek(to: replay.count - 1)
        let frame = try XCTUnwrap(replay.frame(maxSide: 400))
        func replayed(_ x: Int, _ y: Int) -> UInt8 {
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(frame, in: CGRect(x: -x, y: -(400 - 1 - y), width: 300, height: 400))
            return pixel[0]
        }
        XCTAssertLessThan(replayed(Int(document.panels[0].minX) + 1, 100), 30, "the frames are replayed")
        XCTAssertGreaterThan(replayed(150, 300), 225, "and the line kept to its panel")
        XCTAssertLessThan(replayed(60, 300), 30)
        XCTAssertTrue(replay.titles.contains { $0.contains("コマを切った") }, "\(replay.titles)")
        XCTAssertTrue(replay.titles.contains { $0.contains("コマの上に重ねた") })
    }
}
