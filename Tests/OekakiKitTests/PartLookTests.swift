import CoreGraphics
import XCTest
@testable import OekakiKit

/// A part holding several drawings of the same thing, like a character
/// sheet: each use shows one of them.
final class PartLookTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)

    @discardableResult
    private func line(_ document: CanvasDocument, _ points: [(CGFloat, CGFloat)], color: RGBA = .black) -> Int {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: points[0].0, y: points[0].1), color: color, width: 6, isEraser: false))
        for point in points.dropFirst() { document.continueStroke(to: StrokePoint(x: point.0, y: point.1)) }
        document.endStroke()
        return document.activeLayer!.items.last!.id
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func close(_ a: RGBA, _ b: RGBA) -> Bool {
        abs(a.r - b.r) < 0.03 && abs(a.g - b.g) < 0.03 && abs(a.b - b.b) < 0.03
    }

    private func content(_ document: CanvasDocument, _ use: Int) -> [LayerItem] {
        guard case .instance(let found)? = document.item(use)?.item else { return [] }
        return found.content
    }

    private func numbersAreUnique(_ document: CanvasDocument, file: StaticString = #filePath, line: UInt = #line) {
        let numbers = document.layers.flatMap { $0.items.flatMap(\.flattened) }.map(\.id)
        XCTAssertEqual(numbers.count, Set(numbers).count, file: file, line: line)
        XCTAssertFalse(numbers.contains(0), file: file, line: line)
    }

    /// A plus made a part, used at (40, 40) and at (140, 100).
    private func sparkle(_ document: CanvasDocument) throws -> (part: UUID, first: Int, second: Int) {
        let lines = [line(document, [(40, 20), (40, 60)]), line(document, [(20, 40), (60, 40)])]
        let first = try XCTUnwrap(document.makeComponent(from: lines, named: "きらめき"))
        let part = try XCTUnwrap(document.library.components.first).id
        let second = try XCTUnwrap(document.placeComponent(part, at: CGPoint(x: 140, y: 100)))
        return (part, first, second)
    }

    func testAnotherDrawingStartsAsACopyAndChangesAlone() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let (part, first, second) = try sparkle(document)
        let look = try XCTUnwrap(document.addLook(copying: second, named: "赤"))
        XCTAssertEqual(document.library.component(part)?.looks.map(\.title), ["もと", "赤"])
        XCTAssertEqual(document.nextStepNote, "部品「きらめき」に描き分け「赤」を足した")
        XCTAssertTrue(close(color(document, 140, 90), .black), "a copy looks the same")
        XCTAssertEqual(document.uses(of: part, showing: look), [second])
        // Changing a line of the copy changes only the uses showing it.
        document.updateItem(content(document, second)[0].id) { $0.color = self.red }
        XCTAssertTrue(close(color(document, 140, 90), red))
        XCTAssertTrue(close(color(document, 40, 30), .black), "the first drawing stays")
        // And changing the first drawing leaves the copy alone.
        document.updateItem(content(document, first)[1].id) { $0.color = RGBA(r: 0, g: 0, b: 1) }
        XCTAssertTrue(close(color(document, 130, 100), .black))
        // Another use can show the copy.
        document.setLook(first, look)
        XCTAssertTrue(close(color(document, 40, 30), red))
        XCTAssertEqual(document.nextStepNote, "ここに置いた「きらめき」を「赤」にした")
        XCTAssertEqual(document.uses(of: part, showing: look).count, 2)
        document.undo()
        XCTAssertTrue(close(color(document, 40, 30), .black))
        numbersAreUnique(document)
    }

    func testLinesAddedOrTakenGoOnlyToTheDrawingShown() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let (part, first, second) = try sparkle(document)
        let look = try XCTUnwrap(document.addLook(copying: second, named: "ななめ"))
        let extra = line(document, [(150, 110), (158, 118)], color: red)
        document.addToComponent([extra], joining: second)
        XCTAssertEqual(document.library.component(part)?.looks.map(\.items.count), [2, 3])
        XCTAssertTrue(close(color(document, 154, 114), red))
        XCTAssertTrue(close(color(document, 54, 54), .white), "not in the first drawing")
        // Showing the drawing with more lines gives the new one a number.
        document.setLook(first, look)
        XCTAssertTrue(close(color(document, 54, 54), red))
        XCTAssertEqual(content(document, first).count, 3)
        numbersAreUnique(document)
        document.setLook(first, document.library.component(part)!.looks[0].id)
        // A line taken out goes from that drawing only.
        document.removeFromComponent([content(document, second)[0].id])
        XCTAssertEqual(document.library.component(part)?.looks.map(\.items.count), [2, 2])
        XCTAssertTrue(close(color(document, 140, 90), .white))
        XCTAssertTrue(close(color(document, 40, 30), .black), "the first drawing keeps it")
        numbersAreUnique(document)
    }

    func testADrawingCanBeRenamedAndDeleted() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let (part, _, second) = try sparkle(document)
        let first = try XCTUnwrap(document.library.component(part)?.looks[0].id)
        document.renameLook(part, first, to: " 正面 ")
        XCTAssertEqual(document.library.component(part)?.looks[0].title, "正面")
        document.removeLook(part, first)
        XCTAssertEqual(document.library.component(part)?.looks.count, 1, "a part keeps one drawing")
        let look = try XCTUnwrap(document.addLook(copying: second, named: "赤"))
        document.updateItem(content(document, second)[0].id) { $0.color = self.red }
        XCTAssertTrue(close(color(document, 140, 90), red))
        document.removeLook(part, look)
        XCTAssertEqual(document.nextStepNote, "描き分け「赤」を消した")
        XCTAssertEqual(document.library.component(part)?.looks.map(\.title), ["正面"])
        XCTAssertTrue(close(color(document, 140, 90), .black), "the use shows the first drawing again")
        document.undo()
        XCTAssertTrue(close(color(document, 140, 90), red))
        numbersAreUnique(document)
    }

    func testDrawingsAreSavedOpenedAndReplayed() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let (part, _, second) = try sparkle(document)
        let plain = try DocumentFile.encode(document)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("\"looks\""), "a part with one drawing is saved as before")
        let look = try XCTUnwrap(document.addLook(copying: second, named: "赤"))
        document.updateItem(content(document, second)[0].id) { $0.color = self.red }
        let probes: [(CGFloat, CGFloat)] = [(40, 30), (140, 90), (130, 100)]
        let looks = probes.map { color(document, $0.0, $0.1) }

        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(probes.map { color(reopened, $0.0, $0.1) }, looks)
        XCTAssertEqual(reopened.library.component(part)?.looks.map(\.title), ["もと", "赤"])
        XCTAssertEqual(reopened.uses(of: part, showing: look), [second])
        // Still a copy of its own after opening.
        reopened.updateItem(content(reopened, second)[1].id) { $0.color = self.red }
        XCTAssertTrue(close(color(reopened, 40, 30), .black))

        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        XCTAssertNotNil(replay.frame(maxSide: 200))
        XCTAssertTrue(replay.titles.contains { $0.contains("描き分け「赤」を足した") }, "\(replay.titles)")
    }
}
