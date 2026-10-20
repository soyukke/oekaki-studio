import CoreGraphics
import XCTest
@testable import OekakiKit

/// Every item stays something that can be found, read and changed, the way
/// the lines of a program can.
final class ItemTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)
    private let blue = RGBA(r: 0, g: 0, b: 1)

    private func line(_ document: CanvasDocument, from start: CGPoint, to end: CGPoint, color: RGBA = .black, width: CGFloat = 4) {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: start.x, y: start.y), color: color, width: width, isEraser: false))
        document.continueStroke(to: StrokePoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
        document.continueStroke(to: StrokePoint(x: end.x, y: end.y))
        document.endStroke()
    }

    /// A square outline from (50, 40) to (150, 120).
    private func square(_ document: CanvasDocument) {
        line(document, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 150, y: 40))
        line(document, from: CGPoint(x: 150, y: 40), to: CGPoint(x: 150, y: 120))
        line(document, from: CGPoint(x: 150, y: 120), to: CGPoint(x: 50, y: 120))
        line(document, from: CGPoint(x: 50, y: 120), to: CGPoint(x: 50, y: 40))
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func allIDs(_ document: CanvasDocument) -> [Int] {
        document.layers.flatMap { $0.items.flatMap(\.flattened) }.map(\.id)
    }

    func testEveryItemGetsItsOwnNumber() {
        let document = CanvasDocument(width: 200, height: 160)
        square(document)
        document.addLayer()
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        document.addLayer()
        line(document, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 10))
        document.mergeLayerDown(document.activeLayerID)
        let ids = allIDs(document)
        XCTAssertEqual(ids.count, 7, "Four lines, a fill, a group and the line inside it")
        XCTAssertFalse(ids.contains(0))
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTracingFindsTheLineThatDrewTheSpot() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        line(document, from: CGPoint(x: 20, y: 90), to: CGPoint(x: 180, y: 90))
        let second = document.layers[0].items[1].id
        XCTAssertEqual(document.trace(CGPoint(x: 100, y: 90))?.path, [second])
        XCTAssertNil(document.trace(CGPoint(x: 100, y: 60)), "Blank paper was drawn by nothing")
    }

    func testTracingSeesOnlyWhatIsStillVisible() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: 100, y: 10), color: .black, width: 30, isEraser: true))
        document.continueStroke(to: StrokePoint(x: 100, y: 50))
        document.endStroke()
        XCTAssertNil(document.trace(CGPoint(x: 100, y: 30)), "The line was erased there")
        XCTAssertNotNil(document.trace(CGPoint(x: 40, y: 30)))
    }

    func testAFillCanBeRecoloredAfterwards() {
        let document = CanvasDocument(width: 200, height: 160)
        square(document)
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        guard let path = document.trace(CGPoint(x: 100, y: 80))?.path, let id = path.last,
              case .fill(let fill) = document.item(id)?.item
        else { return XCTFail("The fill should be found") }
        XCTAssertEqual(fill.seed, CGPoint(x: 100, y: 80))

        document.updateItem(id) { $0.color = self.blue }
        XCTAssertEqual(color(document, 100, 80), blue)
        XCTAssertEqual(color(document, 100, 40), .black, "The outline stays as it was")
        document.undo()
        XCTAssertEqual(color(document, 100, 80), red)
    }

    func testALineCanBeMadeThickerAfterwards() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 80), to: CGPoint(x: 180, y: 80), width: 4)
        XCTAssertEqual(color(document, 100, 90), .white)
        let id = document.layers[0].items[0].id
        document.updateItem(id) { item in
            if case .stroke(var stroke) = item {
                stroke.width = 30
                item = .stroke(stroke)
            }
        }
        XCTAssertEqual(color(document, 100, 90), .black)
    }

    func testDeletingAnItemTakesItOutOfThePicture() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        line(document, from: CGPoint(x: 20, y: 90), to: CGPoint(x: 180, y: 90))
        document.deleteItem(document.layers[0].items[0].id)
        XCTAssertEqual(color(document, 100, 30), .white)
        XCTAssertEqual(color(document, 100, 90), .black)
        document.undo()
        XCTAssertEqual(color(document, 100, 30), .black)
    }

    func testMergedLayersStayEditable() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        document.addLayer()
        line(document, from: CGPoint(x: 20, y: 90), to: CGPoint(x: 180, y: 90), color: red)
        let upper = document.activeLayerID
        document.mergeLayerDown(upper)
        XCTAssertEqual(document.layers.count, 1)
        guard let path = document.trace(CGPoint(x: 100, y: 90))?.path, path.count == 2 else {
            return XCTFail("The line should be found inside the merged group")
        }
        document.updateItem(path[1]) { $0.color = self.blue }
        XCTAssertEqual(color(document, 100, 90), blue)
        XCTAssertEqual(color(document, 100, 30), .black)
    }

    func testAnEraserInAMergedLayerOnlyErasesThatLayer() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 80), to: CGPoint(x: 180, y: 80), width: 10)
        document.addLayer()
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: 100, y: 60), color: .black, width: 30, isEraser: true))
        document.continueStroke(to: StrokePoint(x: 100, y: 100))
        document.endStroke()
        document.mergeLayerDown(document.activeLayerID)
        XCTAssertEqual(color(document, 100, 80), .black)
    }

    func testTheFileKeepsNumbersSeedsAndGroups() throws {
        let document = CanvasDocument(width: 200, height: 160)
        square(document)
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        document.addLayer()
        line(document, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 10))
        document.mergeLayerDown(document.activeLayerID)

        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(allIDs(reopened), allIDs(document))
        XCTAssertEqual(reopened.itemCounter, document.itemCounter)
        guard case .fill(let fill) = reopened.layers[0].items[4], case .group(let group) = reopened.layers[0].items[5] else {
            return XCTFail("The fill and the group should come back")
        }
        XCTAssertEqual(fill.seed, CGPoint(x: 100, y: 80))
        XCTAssertEqual(group.items.count, 1)
        XCTAssertEqual(color(reopened, 25, 10), .black)
    }

    func testItemsFromOlderFilesAreNumbered() {
        let source = CanvasDocument(width: 200, height: 160)
        square(source)
        XCTAssertTrue(source.fill(at: CGPoint(x: 100, y: 80), color: red))
        var layer = source.layers[0]
        // Older files kept numbers for strokes only.
        layer.items = layer.items.map { item in
            guard case .fill(var fill) = item else { return item }
            fill.id = 0
            return .fill(fill)
        }
        let document = CanvasDocument(width: 200, height: 160, layers: [layer], activeIndex: 0, itemCounter: 4)
        let ids = allIDs(document)
        XCTAssertEqual(ids, [1, 2, 3, 4, 5])
        XCTAssertEqual(document.itemCounter, 5)
    }

    func testTidiedCopiesGetNumbersOfTheirOwn() {
        let document = CanvasDocument(width: 200, height: 160)
        square(document)
        XCTAssertTrue(document.tidyLines())
        let ids = allIDs(document)
        XCTAssertEqual(ids.count, 8)
        XCTAssertEqual(Set(ids).count, 8)
    }
}
