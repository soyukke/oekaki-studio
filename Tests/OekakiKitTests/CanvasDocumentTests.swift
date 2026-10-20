import CoreGraphics
import XCTest
@testable import OekakiKit

final class CanvasDocumentTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)
    private let blue = RGBA(r: 0, g: 0, b: 1)

    private func makeDocument() -> CanvasDocument {
        CanvasDocument(width: 200, height: 160)
    }

    private func line(_ document: CanvasDocument, from start: CGPoint, to end: CGPoint, color: RGBA = .black, width: CGFloat = 4, eraser: Bool = false) {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: start.x, y: start.y), color: color, width: width, isEraser: eraser))
        let steps = 20
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            document.continueStroke(to: StrokePoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        document.endStroke()
    }

    /// A square outline from (50, 40) to (150, 120). `gap` leaves an opening in the top edge.
    private func square(_ document: CanvasDocument, gap: CGFloat = 0) {
        if gap > 0 {
            line(document, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 100 - gap / 2 - 2, y: 40))
            line(document, from: CGPoint(x: 100 + gap / 2 + 2, y: 40), to: CGPoint(x: 150, y: 40))
        } else {
            line(document, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 150, y: 40))
        }
        line(document, from: CGPoint(x: 150, y: 40), to: CGPoint(x: 150, y: 120))
        line(document, from: CGPoint(x: 150, y: 120), to: CGPoint(x: 50, y: 120))
        line(document, from: CGPoint(x: 50, y: 120), to: CGPoint(x: 50, y: 40))
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    func testStrokeLandsWhereItWasDrawn() {
        let document = makeDocument()
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        XCTAssertEqual(color(document, 100, 30), .black)
        XCTAssertEqual(color(document, 100, 130), .white, "The mirrored row must stay empty")
    }

    func testUndoAndRedoRestoreThePicture() {
        let document = makeDocument()
        XCTAssertFalse(document.canUndo)
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        line(document, from: CGPoint(x: 20, y: 90), to: CGPoint(x: 180, y: 90))
        document.undo()
        XCTAssertEqual(color(document, 100, 30), .black)
        XCTAssertEqual(color(document, 100, 90), .white)
        document.undo()
        XCTAssertEqual(color(document, 100, 30), .white)
        XCTAssertFalse(document.canUndo)
        document.redo()
        document.redo()
        XCTAssertEqual(color(document, 100, 90), .black)
        XCTAssertFalse(document.canRedo)
    }

    func testEraserRemovesInkAndIsUndone() {
        let document = makeDocument()
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        line(document, from: CGPoint(x: 100, y: 10), to: CGPoint(x: 100, y: 50), width: 20, eraser: true)
        XCTAssertEqual(color(document, 100, 30), .white)
        XCTAssertEqual(color(document, 40, 30), .black)
        document.undo()
        XCTAssertEqual(color(document, 100, 30), .black)
    }

    func testFillStaysInsideAClosedOutline() {
        let document = makeDocument()
        square(document)
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        XCTAssertEqual(color(document, 100, 80), red)
        XCTAssertEqual(color(document, 60, 50), red, "The fill should reach the corners")
        XCTAssertEqual(color(document, 20, 20), .white, "The fill must not leak outside")
        XCTAssertEqual(color(document, 50, 80), .black, "The outline keeps its colour")
    }

    func testFillClosesASmallOpening() {
        let document = makeDocument()
        square(document, gap: 4)
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        XCTAssertEqual(color(document, 100, 80), red)
        XCTAssertEqual(color(document, 20, 20), .white, "A 4 pixel opening should not leak")
        XCTAssertEqual(color(document, 100, 10), .white)
    }

    func testFillLeaksThroughAWideOpening() {
        let document = makeDocument()
        square(document, gap: 30)
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        XCTAssertEqual(color(document, 20, 20), red, "A 30 pixel opening is not an accident; the fill goes through")
    }

    func testFillOutsideTheCanvasDoesNothing() {
        let document = makeDocument()
        XCTAssertFalse(document.fill(at: CGPoint(x: -5, y: 10), color: red))
        XCTAssertFalse(document.canUndo)
    }

    func testRefillingReplacesTheColour() {
        let document = makeDocument()
        square(document)
        document.fill(at: CGPoint(x: 100, y: 80), color: red)
        document.fill(at: CGPoint(x: 100, y: 80), color: blue)
        XCTAssertEqual(color(document, 100, 80), blue)
        XCTAssertEqual(color(document, 60, 50), blue)
        document.undo()
        XCTAssertEqual(color(document, 100, 80), red)
    }

    func testFillOnALayerBelowSeesTheOutlineAbove() {
        let document = makeDocument()
        let lineLayer = document.activeLayerID
        square(document)
        document.addLayer()
        document.moveLayer(document.activeLayerID, by: -1)
        XCTAssertNotEqual(document.activeLayerID, lineLayer)
        XCTAssertEqual(document.layers.first?.id, document.activeLayerID)
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        XCTAssertEqual(color(document, 100, 80), red)
        XCTAssertEqual(color(document, 20, 20), .white)
        document.setLayerVisible(lineLayer, false)
        XCTAssertEqual(color(document, 100, 80), red, "The colour lives on the lower layer")
    }

    func testHiddenLayerRefusesStrokes() {
        let document = makeDocument()
        document.setLayerVisible(document.activeLayerID, false)
        XCTAssertFalse(document.beginStroke(at: StrokePoint(x: 10, y: 10), color: .black, width: 4, isEraser: false))
        XCTAssertFalse(document.fill(at: CGPoint(x: 10, y: 10), color: red))
    }

    func testLayerOpacityAndVisibility() {
        let document = makeDocument()
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30), width: 10)
        let id = document.activeLayerID
        document.setLayerOpacity(id, 0.5)
        document.setLayerOpacity(id, 0.4)
        XCTAssertEqual(color(document, 100, 30).r, 0.6, accuracy: 0.02)
        document.undo()
        XCTAssertEqual(color(document, 100, 30), .black, "A slider drag is one undo step")
        document.setLayerVisible(id, false)
        XCTAssertEqual(color(document, 100, 30), .white)
    }

    func testMergeDownKeepsThePicture() {
        let document = makeDocument()
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        document.addLayer()
        line(document, from: CGPoint(x: 20, y: 90), to: CGPoint(x: 180, y: 90), color: red)
        XCTAssertEqual(document.layers.count, 2)
        document.mergeLayerDown(document.activeLayerID)
        XCTAssertEqual(document.layers.count, 1)
        XCTAssertEqual(color(document, 100, 30), .black)
        XCTAssertEqual(color(document, 100, 90), red)
        document.undo()
        XCTAssertEqual(document.layers.count, 2)
        XCTAssertEqual(color(document, 100, 90), red)
    }

    func testDeletingTheLastLayerEmptiesIt() {
        let document = makeDocument()
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        document.deleteLayer(document.activeLayerID)
        XCTAssertEqual(document.layers.count, 1)
        XCTAssertTrue(document.isBlank)
        XCTAssertEqual(color(document, 100, 30), .white)
    }

    func testSaveAndReopenGivesTheSamePicture() throws {
        let document = makeDocument()
        square(document)
        document.fill(at: CGPoint(x: 100, y: 80), color: red)
        document.addLayer()
        line(document, from: CGPoint(x: 20, y: 140), to: CGPoint(x: 180, y: 140), color: blue, width: 8)
        document.setLayerOpacity(document.activeLayerID, 0.5)
        document.addLayer()
        line(document, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 10))
        document.mergeLayerDown(document.activeLayerID)

        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(reopened.layers.map(\.name), document.layers.map(\.name))
        XCTAssertEqual(reopened.layers.map(\.opacity), document.layers.map(\.opacity))
        XCTAssertEqual(reopened.pngData(), document.pngData())
        XCTAssertFalse(reopened.hasUnsavedChanges)
    }

    func testOpeningSomethingElseExplainsWhy() {
        XCTAssertThrowsError(try DocumentFile.decode(Data("{\"hello\": 1}".utf8))) { error in
            guard case DocumentFile.Failure.notADocument = error else { return XCTFail("Got \(error)") }
        }
        let future = Data("{\"format\": \"oekaki-studio\", \"version\": 99}".utf8)
        XCTAssertThrowsError(try DocumentFile.decode(future)) { error in
            guard case DocumentFile.Failure.newerVersion(99) = error else { return XCTFail("Got \(error)") }
        }
    }

    /// The name inside the file and its extension are what the Finder and
    /// the app go by, so they must not change by accident.
    func testFilesCarryTheAppName() throws {
        let saved = try DocumentFile.encode(CanvasDocument())
        let header = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(header["format"] as? String, "oekaki-studio")
        XCTAssertEqual(DocumentFile.fileExtension, "oekakistudio")
    }

    /// A small gap lets paint reach into a sharp corner that the usual gap
    /// closing cuts off.
    func testASmallGapFillsSharpCorners() {
        func coverage(gap: Int) -> Int {
            let document = CanvasDocument(width: 200, height: 160)
            // A thin wedge: two lines meeting at a sharp tip on the right.
            for (start, end) in [((20.0, 40.0), (180.0, 78.0)), ((20.0, 120.0), (180.0, 82.0)), ((20.0, 40.0), (20.0, 120.0))] {
                XCTAssertTrue(document.beginStroke(at: StrokePoint(x: start.0, y: start.1), color: .black, width: 3, isEraser: false))
                document.continueStroke(to: StrokePoint(x: end.0, y: end.1))
                document.endStroke()
            }
            document.addLayer()
            XCTAssertTrue(document.fill(at: CGPoint(x: 60, y: 80), color: RGBA(r: 1, g: 0, b: 0), gap: gap))
            guard case .fill(let fill) = document.layers[1].items[0] else { return 0 }
            // Painted pixels in the narrow end of the wedge.
            var count = 0
            for x in 140..<180 {
                for y in 60..<100 where Raster.sample(fill.interior, covering: fill.rect, at: CGPoint(x: x, y: y)) > 0 {
                    count += 1
                }
            }
            return count
        }
        let small = coverage(gap: 1), usual = coverage(gap: BucketFill.defaultGap)
        XCTAssertGreaterThan(small, usual, "small gap \(small) px, usual gap \(usual) px")
    }
}
