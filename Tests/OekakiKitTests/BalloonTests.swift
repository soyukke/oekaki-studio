import CoreGraphics
import XCTest
@testable import OekakiKit

/// Words in a comic: balloons written top to bottom, with a tail.
final class BalloonTests: XCTestCase {
    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    /// How many dark pixels there are in `rect`.
    private func ink(_ document: CanvasDocument, in rect: CGRect) -> Int {
        let picture = document.compositeContext(background: .white)
        guard let data = picture.data?.assumingMemoryBound(to: UInt8.self) else { return 0 }
        let area = rect.integral.intersection(document.bounds)
        var count = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) where data[(y * document.width + x) * 4] < 100 {
                count += 1
            }
        }
        return count
    }

    private func balloon(_ document: CanvasDocument, _ id: Int) -> BalloonItem? {
        guard case .balloon(let found)? = document.item(id)?.item else { return nil }
        return found
    }

    func testWordsAreWrittenDownInColumnsRightToLeft() {
        let one = BalloonItem(text: "こんにちは", center: .zero, fontSize: 20)
        let size = BalloonRenderer.textSize(one)
        XCTAssertGreaterThan(size.height, size.width * 3, "one column, five letters tall")
        var two = one
        two.text = "こんにちは\nまたね"
        XCTAssertGreaterThan(BalloonRenderer.textSize(two).width, size.width * 1.7, "a new line is a new column")
        var across = one
        across.vertical = false
        XCTAssertGreaterThan(BalloonRenderer.textSize(across).width, BalloonRenderer.textSize(across).height * 2)
    }

    func testABalloonIsPlacedWithItsTail() throws {
        let document = CanvasDocument(width: 400, height: 300)
        let id = try XCTUnwrap(document.addBalloon(BalloonItem(text: "やあ", center: CGPoint(x: 150, y: 120), fontSize: 24, tail: CGPoint(x: 330, y: 270))))
        XCTAssertEqual(document.nextStepNote, "吹き出し「やあ」を置いた")
        let made = try XCTUnwrap(balloon(document, id))
        let text = BalloonRenderer.textSize(made)
        // The letters are in the middle, on white.
        XCTAssertGreaterThan(ink(document, in: CGRect(x: 150 - text.width / 2, y: 120 - text.height / 2, width: text.width, height: text.height)), 40)
        let area = BalloonRenderer.bounds(made)
        XCTAssertGreaterThan(area.maxX, 150 + text.width, "the tail reaches out toward the speaker")
        XCTAssertGreaterThan(area.maxY, 120 + text.height)
        // The outline is drawn round the words.
        XCTAssertGreaterThan(ink(document, in: CGRect(x: area.minX, y: 115, width: 30, height: 10)), 0)
        XCTAssertGreaterThan(ink(document, in: CGRect(x: 145, y: area.minY, width: 10, height: 20)), 0)
        // Clicked, it is found.
        XCTAssertEqual(document.trace(CGPoint(x: 150, y: 120))?.path.last, id)
        // Its words can be changed, and the change taken back.
        document.updateItems([id]) { item in
            guard case .balloon(var words) = item else { return }
            words.text = "やあ\nどうも"
            item = .balloon(words)
        }
        XCTAssertEqual(balloon(document, id)?.text, "やあ\nどうも")
        document.undo()
        XCTAssertEqual(balloon(document, id)?.text, "やあ")
    }

    func testMovingAndResizingKeepTheWordsUpright() throws {
        let document = CanvasDocument(width: 400, height: 300)
        let id = try XCTUnwrap(document.addBalloon(BalloonItem(text: "やあ", center: CGPoint(x: 150, y: 120), fontSize: 24, tail: CGPoint(x: 200, y: 200))))
        document.transformItems([id], by: CGAffineTransform(translationX: 30, y: 10))
        XCTAssertEqual(balloon(document, id)?.center, CGPoint(x: 180, y: 130))
        XCTAssertEqual(balloon(document, id)?.tail, CGPoint(x: 230, y: 210), "the tail moves with it")
        document.scaleItems([id], by: 1.5)
        XCTAssertEqual(try XCTUnwrap(balloon(document, id)).fontSize, 36, accuracy: 0.01)
    }

    func testOnAPageOfPanelsBalloonsGoOverTheFrames() throws {
        let document = CanvasDocument(width: 300, height: 400)
        document.cutPanel(from: CGPoint(x: 10, y: 200), to: CGPoint(x: 290, y: 200))
        let first = try XCTUnwrap(document.addBalloon(BalloonItem(text: "あ", center: CGPoint(x: 150, y: 195), fontSize: 30, shape: .shout)))
        let layer = try XCTUnwrap(document.layers.first { $0.items.contains { $0.id == first } })
        XCTAssertEqual(layer.name, "吹き出し")
        XCTAssertTrue(layer.style.overPanels)
        XCTAssertEqual(document.layers.last?.id, layer.id, "on top of the others")
        // Across the gap between panels, it is drawn whole, white over the frames.
        XCTAssertEqual(color(document, document.panels[0].minX + 1, 195).r, 0, accuracy: 0.1, "the frame away from it")
        let made = try XCTUnwrap(balloon(document, first))
        XCTAssertTrue(BalloonRenderer.bounds(made).intersects(document.panels[0]) && BalloonRenderer.bounds(made).intersects(document.panels[1]))
        XCTAssertGreaterThan(color(document, 150 + made.fontSize * 0.9, document.panels[0].maxY - 1).r, 0.9, "the frame is covered")
        // The next one goes on the same layer.
        let second = try XCTUnwrap(document.addBalloon(BalloonItem(text: "い", center: CGPoint(x: 80, y: 300), fontSize: 30)))
        XCTAssertTrue(layer.id == document.layers.first { $0.items.contains { $0.id == second } }?.id)
        XCTAssertEqual(document.layers.filter(\.style.overPanels).count, 1)
    }

    func testBalloonsAreSavedOpenedAndReplayed() throws {
        let document = CanvasDocument(width: 400, height: 300)
        document.addBalloon(BalloonItem(text: "こんにちは", center: CGPoint(x: 120, y: 150), fontSize: 22, tail: CGPoint(x: 60, y: 280)))
        document.addBalloon(BalloonItem(text: "考え中", center: CGPoint(x: 300, y: 100), fontSize: 20, shape: .thought, tail: CGPoint(x: 360, y: 250)))
        document.addBalloon(BalloonItem(text: "Hello", center: CGPoint(x: 300, y: 250), fontSize: 18, shape: .narration, vertical: false))
        let probes: [(CGFloat, CGFloat)] = [(120, 150), (300, 100), (300, 250), (60, 270), (120, 120)]
        let looks = probes.map { color(document, $0.0, $0.1) }
        let data = try DocumentFile.encode(document)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"balloon\""))
        let reopened = try DocumentFile.decode(data)
        XCTAssertEqual(probes.map { color(reopened, $0.0, $0.1) }, looks)
        let items = reopened.layers.flatMap(\.items).compactMap { item -> BalloonItem? in
            if case .balloon(let found) = item { return found }
            return nil
        }
        XCTAssertEqual(items.map(\.shape), [.speech, .thought, .narration])
        XCTAssertEqual(items.map(\.vertical), [true, true, false])
        XCTAssertEqual(items[0].tail, CGPoint(x: 60, y: 280))

        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 400, height: 300)
        replay.seek(to: replay.count - 1)
        XCTAssertNotNil(replay.frame(maxSide: 400))
        XCTAssertTrue(replay.titles.contains { $0.contains("吹き出し「こんにちは」") }, "\(replay.titles)")
    }
}
