import CoreGraphics
import XCTest
@testable import OekakiKit

/// The journal rebuilds the picture as it was after every step.
final class JournalTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)
    private let blue = RGBA(r: 0, g: 0, b: 1)

    private func line(_ document: CanvasDocument, from start: CGPoint, to end: CGPoint, color: RGBA = .black, width: CGFloat = 4) {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: start.x, y: start.y), color: color, width: width, isEraser: false))
        document.continueStroke(to: StrokePoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
        document.continueStroke(to: StrokePoint(x: end.x, y: end.y))
        document.endStroke()
    }

    private func square(_ document: CanvasDocument) {
        line(document, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 150, y: 40))
        line(document, from: CGPoint(x: 150, y: 40), to: CGPoint(x: 150, y: 120))
        line(document, from: CGPoint(x: 150, y: 120), to: CGPoint(x: 50, y: 120))
        line(document, from: CGPoint(x: 50, y: 120), to: CGPoint(x: 50, y: 40))
    }

    /// What can be seen of a picture: each visible layer's items, front-most last.
    private func shape(of document: CanvasDocument) -> [[Int]] {
        document.layers.map { $0.isVisible ? $0.items.flatMap(\.flattened).map(\.id) : [] }
    }

    private func shape(of replay: Replay, at index: Int) -> [[Int]] {
        var state = Replay.State()
        for step in replay.steps.prefix(index + 1) {
            _ = Replay.apply(step, to: &state)
        }
        return state.sheets.map { $0.isVisible ? $0.items.flatMap(\.flattened).map(\.id) : [] }
    }

    /// The colour of the replayed picture at a canvas point.
    private func color(_ replay: Replay, _ x: Int, _ y: Int) -> RGBA {
        guard let image = replay.frame(maxSide: max(replay.width, replay.height)) else { return .white }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -(replay.height - 1 - y), width: replay.width, height: replay.height))
        return RGBA(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
    }

    /// Runs `actions` one by one, and checks that the replay matches the
    /// picture after each of them.
    private func checkReplay(_ document: CanvasDocument, _ actions: [(String, () -> Void)], file: StaticString = #filePath, line: UInt = #line) {
        var expected: [(String, [[Int]])] = []
        for (name, action) in actions {
            action()
            expected.append((name, shape(of: document)))
        }
        document.flushJournal()
        let replay = Replay(steps: document.journal, width: document.width, height: document.height)
        // The first step is the blank paper; after it, one step per action.
        XCTAssertEqual(replay.count, actions.count + 1, file: file, line: line)
        for (index, (name, shape)) in expected.enumerated() where index + 1 < replay.count {
            XCTAssertEqual(self.shape(of: replay, at: index + 1), shape, "after \(name)", file: file, line: line)
        }
    }

    func testEveryKindOfActionReplays() {
        let document = CanvasDocument(width: 200, height: 160)
        var fillID = 0
        checkReplay(document, [
            ("a line", { self.line(document, from: CGPoint(x: 50, y: 40), to: CGPoint(x: 150, y: 40)) }),
            ("the rest of the square", {
                document.transaction {
                    self.line(document, from: CGPoint(x: 150, y: 40), to: CGPoint(x: 150, y: 120))
                    self.line(document, from: CGPoint(x: 150, y: 120), to: CGPoint(x: 50, y: 120))
                    self.line(document, from: CGPoint(x: 50, y: 120), to: CGPoint(x: 50, y: 40))
                }
            }),
            ("a new layer", { document.addLayer() }),
            ("a fill", {
                XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: self.red))
                fillID = document.layers[1].items[0].id
            }),
            ("recolouring", { document.updateItem(fillID) { $0.color = self.blue } }),
            ("undo", { document.undo() }),
            ("redo", { document.redo() }),
            ("hiding", { document.setLayerVisible(document.layers[0].id, false) }),
            ("undo again", { document.undo() }),
            ("merging", { document.mergeLayerDown(document.activeLayerID) }),
            ("deleting", { document.deleteItem(fillID) }),
            ("tidying", { XCTAssertTrue(document.tidyLines()) }),
        ])
    }

    private let probes = [(100, 80), (100, 40), (50, 80), (10, 10)]

    private func looks(_ document: CanvasDocument) -> [RGBA] {
        probes.map { document.pickColor(at: CGPoint(x: $0.0, y: $0.1))! }
    }

    private func looks(_ replay: Replay) -> [RGBA] {
        probes.map { color(replay, $0.0, $0.1) }
    }

    func testTheReplayLooksLikeThePicture() {
        let document = CanvasDocument(width: 200, height: 160)
        var expected: [[RGBA]] = [looks(document)]
        square(document)
        document.addLayer()
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        expected.append(looks(document))
        document.updateItem(document.layers[1].items[0].id) { $0.color = self.blue }
        expected.append(looks(document))
        document.flushJournal()

        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        XCTAssertEqual(looks(replay), expected[2])
        XCTAssertEqual(looks(replay)[0], blue)
        // Back to the blank paper, then forward again.
        replay.seek(to: 0)
        XCTAssertEqual(looks(replay), expected[0])
        replay.seek(to: replay.count - 2)
        XCTAssertEqual(looks(replay), expected[1])
    }

    func testALineCanBeShownHalfDrawn() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 80), to: CGPoint(x: 180, y: 80))
        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        guard let drawn = replay.strokeDrawn(at: 1) else { return XCTFail("Step 1 draws one line") }
        replay.seek(to: 0)
        XCTAssertNotNil(replay.frame(partial: (drawn.layerID, drawn.stroke, 0.5)))
        XCTAssertTrue(replay.titles[1].contains(LayerItem.stroke(drawn.stroke).title))
    }

    func testADragIsOneStep() {
        let document = CanvasDocument(width: 200, height: 160)
        let id = document.activeLayerID
        for opacity in stride(from: 0.9, through: 0.3, by: -0.1) {
            document.setLayerOpacity(id, opacity)
        }
        document.flushJournal()
        XCTAssertEqual(document.journal.map(\.kind), [.start, .edit])
    }

    func testTheJournalIsSavedWithThePicture() throws {
        let document = CanvasDocument(width: 200, height: 160)
        square(document)
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        let whole = looks(document)
        document.deleteItem(document.layers[0].items[0].id)
        let withoutTop = looks(document)
        XCTAssertNotEqual(whole, withoutTop)
        document.undo()

        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(reopened.journal.map(\.kind), document.journal.map(\.kind) + [.opened])
        let replay = Replay(steps: reopened.journal, width: 200, height: 160)
        replay.seek(to: document.journal.count - 2)
        XCTAssertEqual(looks(replay), withoutTop, "The top line was deleted at that point")
        replay.seek(to: document.journal.count - 1)
        XCTAssertEqual(looks(replay), whole, "and brought back by undo")
        replay.seek(to: replay.count - 1)
        XCTAssertEqual(looks(replay), whole)
    }

    func testAnUnchangedLineIsStoredOnce() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let start = StrokePoint(x: 10, y: 10)
        XCTAssertTrue(document.beginStroke(at: start, color: .black, width: 4, isEraser: false))
        for step in 1...2000 {
            document.continueStroke(to: StrokePoint(x: 10 + CGFloat(step % 180), y: 10 + CGFloat(step / 15)))
        }
        document.endStroke()
        let withJournal = try DocumentFile.encode(document).count
        let pointsAlone = 2000 * 3 * 4
        XCTAssertLessThan(withJournal, pointsAlone * 2, "The points should not be written twice")
    }

    func testDescribingSteps() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, from: CGPoint(x: 20, y: 30), to: CGPoint(x: 180, y: 30))
        let id = document.layers[0].items[0].id
        document.updateItem(id) { $0.color = self.red }
        document.undo()
        document.flushJournal()
        let titles = Replay(steps: document.journal, width: 200, height: 160).titles
        XCTAssertEqual(titles.count, 4)
        XCTAssertTrue(titles[1].contains("#\(id)"))
        XCTAssertTrue(titles[2].contains("#\(id)"))
        XCTAssertNotEqual(titles[1], titles[2])
    }

    func testStepsSayWhatTheyChanged() {
        let document = CanvasDocument(width: 200, height: 160)
        document.renameLayer(document.activeLayerID, to: "Lines")
        square(document)
        document.addLayer()
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: red))
        let fillID = document.layers[1].items[0].id
        document.updateItem(fillID) { $0.color = self.blue }
        document.setLayerVisible(document.layers[0].id, false)
        document.flushJournal()
        let changes = Replay(steps: document.journal, width: 200, height: 160).changes
        XCTAssertEqual(changes.map(\.kind), [.start] + Array(repeating: .edit, count: 9))
        XCTAssertEqual(changes[1].renamedLayers.first?.to, "Lines")
        if case .stroke = changes[2].added.first?.item {} else { XCTFail("Step 2 draws a line") }
        XCTAssertEqual(changes[2].added.first?.layer, "Lines")
        XCTAssertEqual(changes[6].addedLayers.count, 1)
        XCTAssertEqual(changes[7].added.first?.item.id, fillID)
        XCTAssertEqual(changes[8].changed.map(\.item.id), [fillID])
        XCTAssertEqual(changes[8].changed.first?.item.color, blue)
        XCTAssertEqual(changes[9].hiddenLayers, ["Lines"])
    }
}
