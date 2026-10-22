import CoreGraphics
import XCTest
@testable import OekakiKit

/// Sound effects: heavy white letters with a thick black edge, which may lean.
final class SoundEffectTests: XCTestCase {
    /// The picture on grey, so white letters show, as the grey level of each pixel.
    private func picture(_ document: CanvasDocument) -> (Int, Int) -> UInt8 {
        let context = document.compositeContext(background: RGBA(hex: 0x808080))
        let width = document.width
        // The context is held by the closure, so its pixels stay.
        return { x, y in context.data!.assumingMemoryBound(to: UInt8.self)[(y * width + x) * 4] }
    }

    /// The box round everything that is not the grey under it.
    private func ink(_ document: CanvasDocument) -> CGRect {
        let pixel = picture(document)
        var area = CGRect.null
        for y in 0..<document.height {
            for x in 0..<document.width where abs(Int(pixel(x, y)) - 128) > 20 {
                area = area.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return area
    }

    private func sound(_ document: CanvasDocument, _ id: Int) -> BalloonItem? {
        guard case .balloon(let found)? = document.item(id)?.item else { return nil }
        return found
    }

    func testLettersAreWhiteWithABlackEdge() throws {
        let document = CanvasDocument(width: 300, height: 300)
        let id = try XCTUnwrap(document.addBalloon(BalloonItem(text: "ドン", center: CGPoint(x: 150, y: 150), fontSize: 80, shape: .sound)))
        XCTAssertEqual(document.nextStepNote, "効果音「ドン」を置いた")
        let made = try XCTUnwrap(sound(document, id))
        XCTAssertNil(made.tail)
        let area = BalloonRenderer.bounds(made)
        let pixel = picture(document)
        var white = 0, black = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                if pixel(x, y) > 240 { white += 1 }
                if pixel(x, y) < 15 { black += 1 }
            }
        }
        XCTAssertGreaterThan(white, 800, "the letters are white")
        XCTAssertGreaterThan(black, 800, "with a thick black edge")
        // Every white pixel is edged in black: the grey under it is never near.
        // (A pixel where white and black blend can look grey, but not with its neighbours too.)
        func grey(_ x: Int, _ y: Int) -> Bool {
            [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].allSatisfy { abs(Int(pixel(x + $0.0, y + $0.1)) - 128) <= 3 }
        }
        let near = Int(made.fontSize * 0.28 / 2 * 0.7)
        for y in Int(area.minY) + near..<Int(area.maxY) - near {
            for x in Int(area.minX) + near..<Int(area.maxX) - near where pixel(x, y) > 240 {
                for (dx, dy) in [(near, 0), (-near, 0), (0, near), (0, -near)] {
                    XCTAssertFalse(grey(x + dx, y + dy), "grey beside the white at \(x), \(y)")
                }
            }
        }
        // Nothing is drawn outside its bounds.
        XCTAssertTrue(area.contains(ink(document)), "\(ink(document)) in \(area)")
    }

    func testALongVowelRunsDownWhenWrittenDown() throws {
        let down = CanvasDocument(width: 200, height: 200)
        down.addBalloon(BalloonItem(text: "ー", center: CGPoint(x: 100, y: 100), fontSize: 80, shape: .sound))
        let bar = ink(down)
        XCTAssertGreaterThan(bar.height, bar.width * 1.8, "an upright bar, \(bar)")
        let across = CanvasDocument(width: 200, height: 200)
        across.addBalloon(BalloonItem(text: "ー", center: CGPoint(x: 100, y: 100), fontSize: 80, shape: .sound, vertical: false))
        let line = ink(across)
        XCTAssertGreaterThan(line.width, line.height * 1.8, "a flat bar, \(line)")
    }

    func testSoundEffectsLeanAndTurnWhileBalloonsStayUpright() throws {
        let upright = BalloonItem(text: "ドドドド", center: CGPoint(x: 200, y: 200), fontSize: 40, shape: .sound)
        var leaning = upright
        leaning.angle = .pi / 4
        let straight = BalloonRenderer.bounds(upright), turned = BalloonRenderer.bounds(leaning)
        XCTAssertGreaterThan(turned.width, straight.width * 1.5, "the box round the leaning letters is wider")
        XCTAssertLessThan(turned.height, straight.height)
        // A point in the corner of that box, off the letters, is not on them.
        let corner = CGPoint(x: turned.minX + 4, y: turned.minY + 4)
        XCTAssertFalse(LayerItem.balloon(leaning).paints(corner, canvas: CGRect(x: 0, y: 0, width: 400, height: 400), slack: 2))
        XCTAssertTrue(LayerItem.balloon(leaning).paints(leaning.center, canvas: CGRect(x: 0, y: 0, width: 400, height: 400), slack: 2))

        let document = CanvasDocument(width: 400, height: 400)
        let letters = try XCTUnwrap(document.addBalloon(upright))
        let words = try XCTUnwrap(document.addBalloon(BalloonItem(text: "やあ", center: CGPoint(x: 300, y: 100), fontSize: 20)))
        let turn = CGAffineTransform(translationX: 200, y: 200).rotated(by: .pi / 6).translatedBy(x: -200, y: -200)
        document.transformItems([letters, words], by: turn)
        XCTAssertEqual(try XCTUnwrap(sound(document, letters)).angle, .pi / 6, accuracy: 0.001, "the letters turn with the rest")
        XCTAssertEqual(sound(document, words)?.angle, 0, "the balloon keeps its words upright")
        XCTAssertNotEqual(sound(document, words)?.center, CGPoint(x: 300, y: 100), "but moves round")
        // The turned letters are drawn inside their new bounds, and lean.
        let drawn = ink(document)
        let area = BalloonRenderer.bounds(try XCTUnwrap(sound(document, letters)))
            .union(BalloonRenderer.bounds(try XCTUnwrap(sound(document, words))))
        XCTAssertTrue(area.contains(drawn), "\(drawn) in \(area)")
        XCTAssertGreaterThan(BalloonRenderer.bounds(try XCTUnwrap(sound(document, letters))).width, straight.width * 1.3)
        document.undo()
        XCTAssertEqual(sound(document, letters)?.angle, 0)
    }

    func testSoundEffectsAreSavedOpenedAndReplayed() throws {
        let document = CanvasDocument(width: 300, height: 400)
        document.cutPanel(from: CGPoint(x: 10, y: 200), to: CGPoint(x: 290, y: 200))
        let first = try XCTUnwrap(document.addBalloon(BalloonItem(text: "ゴゴゴ", center: CGPoint(x: 80, y: 200), fontSize: 40, shape: .sound, angle: 0.4)))
        document.addBalloon(BalloonItem(text: "シーン", center: CGPoint(x: 220, y: 300), fontSize: 30, shape: .sound, vertical: false))
        let layer = try XCTUnwrap(document.layers.first { $0.items.contains { $0.id == first } })
        XCTAssertTrue(layer.style.overPanels, "over the frames, as balloons are")

        let data = try DocumentFile.encode(document)
        let reopened = try DocumentFile.decode(data)
        let items = reopened.layers.flatMap(\.items).compactMap { item -> BalloonItem? in
            if case .balloon(let found) = item { return found }
            return nil
        }
        XCTAssertEqual(items.map(\.shape), [.sound, .sound])
        XCTAssertEqual(items.map(\.angle), [0.4, 0])
        XCTAssertEqual(items.map(\.vertical), [true, false])
        let before = picture(document), after = picture(reopened)
        for (x, y) in [(80, 200), (220, 300), (70, 180), (240, 300)] {
            XCTAssertEqual(before(x, y), after(x, y), "at \(x), \(y)")
        }

        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 300, height: 400)
        replay.seek(to: replay.count - 1)
        XCTAssertNotNil(replay.frame(maxSide: 400))
        XCTAssertTrue(replay.titles.contains { $0.contains("効果音「ゴゴゴ」") }, "\(replay.titles)")
    }
}
