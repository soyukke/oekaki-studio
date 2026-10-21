import CoreGraphics
import XCTest
@testable import OekakiKit

/// Many items at once, named colours, parts, and versions.
final class WorkshopTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)
    private let blue = RGBA(r: 0, g: 0, b: 1)
    private let green = RGBA(r: 0, g: 0.6, b: 0)

    @discardableResult
    private func line(_ document: CanvasDocument, _ points: [(CGFloat, CGFloat)], color: RGBA = .black, width: CGFloat = 6) -> Int {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: points[0].0, y: points[0].1), color: color, width: width, isEraser: false))
        for point in points.dropFirst() { document.continueStroke(to: StrokePoint(x: point.0, y: point.1)) }
        document.endStroke()
        return document.activeLayer!.items.last!.id
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    private func close(_ a: RGBA, _ b: RGBA, _ limit: Double = 0.03) -> Bool {
        abs(a.r - b.r) < limit && abs(a.g - b.g) < limit && abs(a.b - b.b) < limit
    }

    private func strokeColor(_ document: CanvasDocument, _ id: Int) -> RGBA? {
        document.item(id)?.item.color
    }

    /// A small closed square with a fill inside, for parts and colours.
    private func square(_ document: CanvasDocument, at x: CGFloat, _ y: CGFloat, size: CGFloat = 40) -> [Int] {
        let a = line(document, [(x, y), (x + size, y), (x + size, y + size), (x, y + size), (x, y)], width: 4)
        XCTAssertTrue(document.fill(at: CGPoint(x: x + size / 2, y: y + size / 2), color: green, gap: 1))
        return [a, document.activeLayer!.items.last!.id]
    }

    // MARK: Many at once

    func testManyItemsChangeInOneStep() {
        let document = CanvasDocument(width: 200, height: 160)
        let ids = [line(document, [(20, 20), (180, 20)]), line(document, [(20, 60), (180, 60)]), line(document, [(20, 100), (180, 100)])]
        document.updateItems(ids) { $0.color = self.red }
        XCTAssertTrue(ids.allSatisfy { strokeColor(document, $0) == red })
        XCTAssertTrue(close(color(document, 100, 60), red))
        document.undo()
        XCTAssertTrue(ids.allSatisfy { strokeColor(document, $0) == .black }, "one undo takes all three back")
        document.redo()
        document.flushJournal()
        let titles = Replay(steps: document.journal, width: 200, height: 160).titles
        XCTAssertTrue(titles.contains("3 個をまとめて直した"), "the replay says all three changed together: \(titles)")
        document.changeWaviness(ids, by: 1.5)
        document.transformItems(ids, by: CGAffineTransform(translationX: 5, y: 0))
        document.scaleItems(ids, by: 1.2)
        document.flushJournal()
        let more = Replay(steps: document.journal, width: 200, height: 160).titles.suffix(3)
        XCTAssertEqual(Array(more), ["線 3 本のうねりを変えた", "線 3 本を動かした", "線 3 本の大きさを変えた"])
    }

    func testMovingAndScalingItems() {
        let document = CanvasDocument(width: 200, height: 160)
        let ids = square(document, at: 20, 20)
        XCTAssertTrue(close(color(document, 40, 40), green))
        document.transformItems(ids, by: CGAffineTransform(translationX: 100, y: 60))
        XCTAssertTrue(close(color(document, 140, 100), green), "the fill moved with its outline")
        XCTAssertTrue(close(color(document, 40, 40), .white))
        let before = document.selectionBounds(ids)!
        document.scaleItems(ids, by: 1.5)
        let after = document.selectionBounds(ids)!
        XCTAssertEqual(after.width, before.width * 1.5, accuracy: 3)
        XCTAssertEqual(after.midX, before.midX, accuracy: 2, "scaled about the middle")
        XCTAssertTrue(close(color(document, after.midX, after.midY), green), "a scaled fill is redrawn")
        document.undo()
        XCTAssertEqual(document.selectionBounds(ids)!.width, before.width, accuracy: 0.5)
    }

    /// A fill made bigger covers the bigger area, not just its old one.
    func testScalingAFillGrowsIt() {
        let document = CanvasDocument(width: 200, height: 160)
        let ids = square(document, at: 70, 50, size: 40)
        XCTAssertTrue(close(color(document, 90, 70), green))
        XCTAssertTrue(close(color(document, 60, 70), .white), "outside the square before")
        document.scaleItems(ids, by: 1.8)
        XCTAssertTrue(close(color(document, 60, 70), green), "inside the bigger square after: \(color(document, 60, 70))")
        XCTAssertTrue(close(color(document, 90, 70), green))
        // And so does the replay.
        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        let frame = try! XCTUnwrap(replay.frame(maxSide: 200))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(frame, in: CGRect(x: -60, y: -(160 - 1 - 70), width: 200, height: 160))
        XCTAssertEqual(Int(pixel[1]), Int((0.6 * 255).rounded()), accuracy: 6, "the replay shows the bigger fill: \(pixel)")
    }

    func testWaviness() {
        let document = CanvasDocument(width: 200, height: 160)
        let points: [(CGFloat, CGFloat)] = (0...40).map { index -> (CGFloat, CGFloat) in
            let x = CGFloat(10 + index * 4)
            let y: CGFloat = index % 2 == 0 ? 86 : 74
            return (x, y)
        }
        let id = line(document, points)
        func wobble() -> CGFloat {
            guard case .stroke(let stroke) = document.item(id)!.item else { return 0 }
            // How far each point strays from the middle of its neighbours: the small waves.
            let y = stroke.points.map(\.y)
            var sum: CGFloat = 0
            for index in 6..<(y.count - 6) {
                let middle: CGFloat = (y[index - 1] + y[index + 1]) / 2
                sum += abs(y[index] - middle)
            }
            return sum
        }
        let start = wobble()
        document.changeWaviness([id], by: 2)
        XCTAssertGreaterThan(wobble(), start * 1.5)
        // The waves grow, but the line keeps its course and its ends.
        guard case .stroke(let wavier) = document.item(id)!.item else { return XCTFail() }
        let middle = wavier.points.dropFirst(5).dropLast(5)
        XCTAssertEqual(middle.map(\.y).reduce(0, +) / CGFloat(middle.count), 80, accuracy: 3)
        document.changeWaviness([id], by: 0.1)
        XCTAssertLessThan(wobble(), start * 0.5)
    }

    /// A closed line, such as an eye, keeps its place and size when made wavier.
    /// A smooth line gains a gentle wave when made stronger; its ends stay.
    func testASmoothLineGainsAWave() {
        let document = CanvasDocument(width: 400, height: 160)
        let id = line(document, (0...60).map { (CGFloat(20 + $0 * 6), 80) })
        document.changeWaviness([id], by: 2)
        guard case .stroke(let stroke) = document.item(id)!.item else { return XCTFail() }
        XCTAssertGreaterThan(stroke.points.map { abs($0.y - 80) }.max() ?? 0, 2, "it waves now")
        XCTAssertEqual(stroke.points.first!.y, 80, accuracy: 0.5)
        XCTAssertEqual(stroke.points.last!.y, 80, accuracy: 0.5)
    }

    func testWavinessKeepsAClosedLineInPlace() {
        let document = CanvasDocument(width: 200, height: 160)
        let ring: [(CGFloat, CGFloat)] = (0...60).map { index -> (CGFloat, CGFloat) in
            let angle = CGFloat(index) / 60 * 2 * .pi
            let wobble: CGFloat = index % 2 == 0 ? 3 : -3
            return (100 + (30 + wobble) * cos(angle), 80 + (30 + wobble) * sin(angle))
        }
        let id = line(document, ring, width: 3)
        let before = document.selectionBounds([id])!
        document.changeWaviness([id], by: 1.8)
        let after = document.selectionBounds([id])!
        XCTAssertEqual(after.midX, before.midX, accuracy: 2)
        XCTAssertEqual(after.midY, before.midY, accuracy: 2)
        XCTAssertEqual(after.width, before.width, accuracy: 8, "about the same size, only wavier")
    }

    func testSelectingByAreaAndByColour() {
        let document = CanvasDocument(width: 200, height: 160)
        let a = line(document, [(20, 20), (60, 20)], color: red)
        let b = line(document, [(120, 20), (160, 20)])
        let c = line(document, [(20, 120), (60, 120)], color: red)
        XCTAssertEqual(document.items(in: CGRect(x: 0, y: 0, width: 100, height: 50)), [a])
        XCTAssertEqual(Set(document.items(coloured: red)), [a, c])
        XCTAssertFalse(document.items(coloured: red).contains(b))
    }

    // MARK: Named colours

    func testANamedColourChangesEverythingThatUsesIt() {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        let other = line(document, [(120, 140), (180, 140)])
        let skin = document.addSwatch(named: "肌", color: green)
        document.bind(parts, to: skin)
        document.setSwatchColor(skin, blue)
        XCTAssertTrue(close(color(document, 40, 40), blue), "the fill follows the name")
        XCTAssertEqual(strokeColor(document, parts[0]), blue)
        XCTAssertEqual(strokeColor(document, other), .black, "items without the name keep their colour")
        document.undo()
        XCTAssertTrue(close(color(document, 40, 40), green), "one undo")
        // A colour given directly cuts the link.
        document.updateItem(parts[0]) { $0.color = self.red }
        document.setSwatchColor(skin, blue)
        XCTAssertEqual(strokeColor(document, parts[0]), red)
    }

    func testColourSets() {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        let sky = document.addSwatch(named: "空", color: green)
        document.bind(parts, to: sky)
        let evening = document.saveTheme(named: "夕方")
        document.setSwatchColor(sky, blue)
        let night = document.saveTheme(named: "夜")
        document.applyTheme(evening)
        XCTAssertTrue(close(color(document, 40, 40), green))
        XCTAssertEqual(document.library.currentTheme, evening)
        document.applyTheme(night)
        XCTAssertTrue(close(color(document, 40, 40), blue))
        document.flushJournal()
        let titles = Replay(steps: document.journal, width: 200, height: 160).titles
        XCTAssertTrue(titles.contains { $0.contains("夜") })
    }

    func testStyleFileKeepsTheRest() {
        var library = Library()
        library.swatches = [Swatch(name: "肌", color: RGBA(hex: 0xFFE4D6))]
        let existing = "# STYLE\n\n線は細め。\n"
        let first = StyleColors.merged(library, into: existing)
        XCTAssertTrue(first.contains("線は細め。"))
        XCTAssertTrue(first.contains("| 肌 | `#FFE4D6` |"))
        library.swatches[0].color = RGBA(hex: 0x112233)
        let second = StyleColors.merged(library, into: first + "\n終わりのメモ\n")
        XCTAssertTrue(second.contains("`#112233`"))
        XCTAssertFalse(second.contains("`#FFE4D6`"), "the section is replaced, not added again")
        XCTAssertTrue(second.contains("終わりのメモ"))
    }

    // MARK: Parts

    private func sparkle(_ document: CanvasDocument) -> [Int] {
        [line(document, [(40, 20), (40, 60)]), line(document, [(20, 40), (60, 40)])]
    }

    func testAPartChangesEveryUse() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let use = try XCTUnwrap(document.makeComponent(from: sparkle(document), named: "きらめき"))
        let part = try XCTUnwrap(document.library.components.first).id
        let second = try XCTUnwrap(document.placeComponent(part, at: CGPoint(x: 140, y: 100)))
        XCTAssertEqual(document.uses(of: part).count, 2)
        XCTAssertTrue(close(color(document, 40, 40), .black))
        XCTAssertTrue(close(color(document, 140, 100), .black))
        // Change one line inside the second use: the part changes, so both do.
        guard case .instance(let placed) = document.item(second)!.item else { return XCTFail("a use") }
        document.updateItem(placed.content[0].id) { $0.color = self.red }
        XCTAssertTrue(close(color(document, 140, 90), red))
        XCTAssertTrue(close(color(document, 40, 30), red), "the first use follows the part")
        document.undo()
        XCTAssertTrue(close(color(document, 40, 30), .black))
        XCTAssertNotEqual(use, second)
        // Every item number is still unique.
        let numbers = document.layers.flatMap { $0.items.flatMap(\.flattened) }.map(\.id)
        XCTAssertEqual(numbers.count, Set(numbers).count)
    }

    /// A part can gain lines after it was made, and lose them, and every use follows.
    func testAPartGainsAndLosesLines() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let first = try XCTUnwrap(document.makeComponent(from: sparkle(document), named: "きらめき"))
        let part = try XCTUnwrap(document.library.components.first).id
        let second = try XCTUnwrap(document.placeComponent(part, at: CGPoint(x: 140, y: 100), scale: 2))
        // A new line by the first use, put into the part.
        let extra = line(document, [(50, 50), (58, 58)], color: red)
        XCTAssertTrue(close(color(document, 168, 128), .white), "not in the bigger use yet")
        let found = try XCTUnwrap(document.partAndOthers([first, extra]))
        XCTAssertEqual(found.use, first)
        XCTAssertEqual(found.others, [extra])
        document.addToComponent(found.others, joining: found.use)
        XCTAssertNil(document.item(extra), "the line left its layer")
        XCTAssertEqual(document.library.component(part)?.items(for: nil).count, 3)
        XCTAssertTrue(close(color(document, 54, 54), red), "the first use has it where it was drawn")
        XCTAssertTrue(close(color(document, 168, 128), red), "the bigger use has it too, twice as big")
        XCTAssertEqual(document.nextStepNote, "部品「きらめき」に線 1 本を足した")
        document.undo()
        XCTAssertNotNil(document.item(extra))
        XCTAssertEqual(document.library.component(part)?.items(for: nil).count, 2)
        XCTAssertTrue(close(color(document, 168, 128), .white))
        document.redo()
        XCTAssertTrue(close(color(document, 168, 128), red))

        // Taking a line out of one use takes it out of the part, so out of every use.
        guard case .instance(let big) = document.item(second)!.item else { return XCTFail("a use") }
        let across = big.content[1].id
        XCTAssertTrue(close(color(document, 120, 100), .black))
        document.removeFromComponent([across])
        XCTAssertEqual(document.library.component(part)?.items(for: nil).count, 2)
        XCTAssertTrue(close(color(document, 120, 100), .white), "gone from the bigger use")
        XCTAssertTrue(close(color(document, 25, 40), .white), "and from the first")
        XCTAssertTrue(close(color(document, 40, 25), .black), "the other line stays")
        XCTAssertEqual(document.nextStepNote, "部品「きらめき」から線 1 本を消した")
        // The last item of a part is kept.
        guard case .instance(let fewer) = document.item(second)!.item else { return XCTFail("a use") }
        document.removeFromComponent(fewer.content.map(\.id))
        XCTAssertEqual(document.library.component(part)?.items(for: nil).count, 2)
        // Saved and opened again, and replayed, it looks the same.
        let probes: [(CGFloat, CGFloat)] = [(54, 54), (168, 128), (120, 100), (40, 25)]
        let looks = probes.map { color(document, $0.0, $0.1) }
        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(probes.map { color(reopened, $0.0, $0.1) }, looks)
        let numbers = document.layers.flatMap { $0.items.flatMap(\.flattened) }.map(\.id)
        XCTAssertEqual(numbers.count, Set(numbers).count)
        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        XCTAssertNotNil(replay.frame(maxSide: 200))
        XCTAssertTrue(replay.titles.contains { $0.contains("部品「きらめき」に線 1 本を足した") }, "\(replay.titles)")
        XCTAssertTrue(replay.titles.contains { $0.contains("部品「きらめき」から線 1 本を消した") })
    }

    func testPlacingAndCuttingLoose() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let use = try XCTUnwrap(document.makeComponent(from: sparkle(document), named: "きらめき"))
        let before = document.selectionBounds([use])!
        document.setPlacement(use, Placement(center: CGPoint(x: 100, y: 80), scale: 2))
        let after = document.selectionBounds([use])!
        XCTAssertGreaterThan(after.width, before.width * 1.8)
        XCTAssertEqual(after.midX, 100, accuracy: 3)
        // Turned a quarter, the plus becomes an X, narrower than twice the plus.
        document.setPlacement(use, Placement(center: CGPoint(x: 100, y: 80), scale: 2, rotation: 45, flipped: true))
        let turned = document.selectionBounds([use])!
        XCTAssertLessThan(turned.width, after.width)
        XCTAssertEqual(turned.midX, 100, accuracy: 3)
        document.detach(use)
        guard case .group = document.item(use)!.item else { return XCTFail("a group now") }
        let part = document.library.components[0].id
        let other = try XCTUnwrap(document.placeComponent(part, at: CGPoint(x: 160, y: 130), scale: 0.5))
        guard case .instance(let placed) = document.item(other)!.item else { return XCTFail("a use") }
        document.updateItem(placed.content[0].id) { $0.color = self.blue }
        XCTAssertEqual(document.item(use)!.item.children.first?.color, .black, "a loose copy no longer follows")
    }

    func testOneUseCanHaveItsOwnColours() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let lines = sparkle(document)
        let gold = document.addSwatch(named: "金", color: red)
        document.bind(lines, to: gold)
        let first = try XCTUnwrap(document.makeComponent(from: lines, named: "きらめき"))
        let part = document.library.components[0].id
        let second = try XCTUnwrap(document.placeComponent(part, at: CGPoint(x: 140, y: 100)))
        document.setOverride(second, swatch: gold, blue)
        XCTAssertTrue(close(color(document, 140, 90), blue))
        XCTAssertTrue(close(color(document, 40, 30), red))
        document.setSwatchColor(gold, green)
        XCTAssertTrue(close(color(document, 40, 30), green), "the shared colour changed")
        XCTAssertTrue(close(color(document, 140, 90), blue), "the use's own colour stays")
        XCTAssertNotEqual(first, second)
    }

    // MARK: Keeping it all

    func testEverythingNewIsSavedOpenedAndReplayed() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        let skin = document.addSwatch(named: "肌", color: green)
        document.bind(parts, to: skin)
        document.saveTheme(named: "夕方")
        let use = try XCTUnwrap(document.makeComponent(from: sparkle(document), named: "きらめき"))
        document.setPlacement(use, Placement(center: CGPoint(x: 140, y: 100), scale: 1.5, rotation: 30))
        document.setSwatchColor(skin, blue)
        let probes: [(CGFloat, CGFloat)] = [(40, 40), (140, 100), (140, 80), (10, 10)]
        let looks = probes.map { color(document, $0.0, $0.1) }

        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(probes.map { color(reopened, $0.0, $0.1) }, looks)
        XCTAssertEqual(reopened.library.swatches.map(\.name), ["肌"])
        XCTAssertEqual(reopened.library.themes.map(\.name), ["夕方"])
        XCTAssertEqual(reopened.library.components.map(\.name), ["きらめき"])
        // The link to the name survives: changing it still recolours.
        reopened.setSwatchColor(reopened.library.swatches[0].id, red)
        XCTAssertTrue(close(color(reopened, 40, 40), red))

        // The replay rebuilds the same picture.
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        let frame = try XCTUnwrap(replay.frame(maxSide: 200))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(frame, in: CGRect(x: -40, y: -(160 - 1 - 40), width: 200, height: 160))
        XCTAssertTrue(close(RGBA(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255), blue))
        XCTAssertTrue(replay.titles.contains { $0.contains("きらめき") })
    }

    func testAFileFromVersionFourOpens() throws {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [(20, 20), (180, 20)])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentFile.encode(document)) as? [String: Any])
        json["version"] = 4
        let opened = try DocumentFile.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(opened.library.isEmpty)
        XCTAssertEqual(opened.branches.count, 1)
    }

    // MARK: Versions

    func testVersionsKeepTheirOwnHistory() {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [(20, 20), (180, 20)])
        let main = document.currentBranch
        let other = document.makeBranch(named: "笑顔")
        XCTAssertEqual(document.currentBranch, other)
        line(document, [(20, 120), (180, 120)])
        XCTAssertTrue(close(color(document, 100, 120), .black))
        document.switchBranch(main)
        XCTAssertTrue(close(color(document, 100, 120), .white), "the main picture does not have the new line")
        XCTAssertTrue(close(color(document, 100, 20), .black))
        let mainSteps = document.journal.count
        document.switchBranch(other)
        XCTAssertGreaterThan(document.journal.count, mainSteps, "each version keeps its own steps")
        document.undo()
        XCTAssertTrue(close(color(document, 100, 120), .white), "and its own undo")
    }

    func testTakingAVersion() throws {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [(20, 20), (180, 20)])
        let other = document.makeBranch(named: "線を足す")
        line(document, [(20, 120), (180, 120)], color: red)
        document.switchBranch(document.mainBranch)
        let theirs = try XCTUnwrap(document.picture(ofBranch: other))
        XCTAssertEqual(theirs.width, 200)
        document.adoptBranch(other)
        XCTAssertEqual(document.currentBranch, document.mainBranch)
        document.flushJournal()
        XCTAssertEqual(Replay(steps: document.journal, width: 200, height: 160).titles.last, "案「線を足す」を本番にした")
        // The replay shows the version taken, too.
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        let frame = try XCTUnwrap(replay.frame(maxSide: 200))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(frame, in: CGRect(x: -100, y: -(160 - 1 - 120), width: 200, height: 160))
        XCTAssertGreaterThan(Int(pixel[0]), 200, "red line in the replay")
        XCTAssertLessThan(Int(pixel[1]), 60)
        XCTAssertTrue(close(color(document, 100, 120), red))
        document.undo()
        XCTAssertTrue(close(color(document, 100, 120), .white), "taking a version can be taken back")
    }

    func testAProposalIsTriedOnAVersionOfItsOwn() {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        let sky = document.addSwatch(named: "空", color: green)
        document.bind(parts, to: sky)
        let home = document.currentBranch
        let version = document.branch(trying: Proposal(name: "夜", colors: ["空": blue]))
        XCTAssertEqual(document.currentBranch, home, "stays on the picture in hand")
        XCTAssertTrue(close(color(document, 40, 40), green), "which is not changed")
        XCTAssertEqual(document.branches.last?.name, "夜")
        document.switchBranch(version)
        XCTAssertTrue(close(color(document, 40, 40), blue))
    }

    /// Stands in for the assistant: answers as it would, at once.
    private struct FakeAssistant: ProposalSource {
        let reply: String
        func propose(_ request: String, for document: CanvasDocument, completion: @escaping (Result<[Proposal], Error>) -> Void) {
            completion(.success(ProposalPrompt.parse(reply)))
        }
    }

    func testTheAssistantsIdeasBecomeVersions() {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        let sky = document.addSwatch(named: "空", color: green)
        document.bind(parts, to: sky)
        let prompt = ProposalPrompt.prompt(for: "夜の配色", library: document.library, layers: document.layers.map(\.name))
        XCTAssertTrue(prompt.contains("空: #009900"))
        let reply = """
        Here you are:
        {"proposals": [{"name": "月夜", "colors": {"空": "#0000FF", "無い色": "#FF0000"}, "hide": [], "show": []},
                       {"name": "星空", "colors": {"空": "#000033"}}]}
        """
        var made: [UUID] = []
        FakeAssistant(reply: reply).propose("夜の配色", for: document) { result in
            for idea in (try? result.get()) ?? [] { made.append(document.branch(trying: idea)) }
        }
        XCTAssertEqual(made.count, 2)
        XCTAssertEqual(document.branches.map(\.name).suffix(2), ["月夜", "星空"])
        XCTAssertEqual(document.branches.last?.note, "色: 空", "the version says what it changed")
        XCTAssertEqual(document.branches.last?.colorChanges, [ColorChange(name: "空", before: green, after: RGBA(hex: 0x000033))], "and each colour before and after")
        XCTAssertTrue(close(color(document, 40, 40), green))
        XCTAssertEqual(ProposalPrompt.parse("no json here"), [])
    }

    /// Without the assistant, the colour sets give the ideas.
    func testColourSetsBecomeVersionsWithoutTheAssistant() {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        let sky = document.addSwatch(named: "空", color: green)
        document.bind(parts, to: sky)
        document.saveTheme(named: "夕方")
        document.setSwatchColor(sky, blue)
        document.saveTheme(named: "夜")
        document.applyTheme(document.library.themes[0].id)
        var ideas: [Proposal] = []
        ThemeProposalSource().propose("夜", for: document) { ideas = (try? $0.get()) ?? [] }
        XCTAssertEqual(ideas.map(\.name), ["夜の色"], "the request picks the set by name")
        ThemeProposalSource().propose("", for: document) { ideas = (try? $0.get()) ?? [] }
        XCTAssertEqual(ideas.map(\.name), ["夜の色"], "no request gives every set that differs from the picture")
        let home = document.currentBranch
        let night = document.branch(trying: ideas[0])
        XCTAssertEqual(document.currentBranch, home)
        XCTAssertTrue(close(color(document, 40, 40), green), "the picture in hand is not changed")
        document.switchBranch(night)
        XCTAssertTrue(close(color(document, 40, 40), blue))
    }

    /// The whole way through the assistant, with a stand-in for the Claude
    /// command line: what it is asked, what it answers, and the versions made.
    func testTheAssistantPathEndToEnd() {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        let sky = document.addSwatch(named: "空", color: green)
        document.bind(parts, to: sky)
        var asked = ""
        let assistant = AssistantProposalSource { prompt, _, completion in
            asked = prompt
            completion(.success(##"{"proposals": [{"name": "月夜", "colors": {"空": "#0000FF"}}, {"name": "夜明け", "colors": {"空": "#FF0000"}}]}"##))
        }
        var made: [UUID] = []
        assistant.propose("夜の配色", for: document) { result in
            for idea in (try? result.get()) ?? [] { made.append(document.branch(trying: idea)) }
        }
        XCTAssertTrue(asked.contains("夜の配色"), "the request is passed on")
        XCTAssertTrue(asked.contains("空: #009900"), "with the named colours")
        XCTAssertTrue(asked.contains("レイヤー 1"), "and the layers")
        XCTAssertEqual(made.count, 2)
        XCTAssertTrue(close(color(document, 40, 40), green), "the picture in hand is not changed")
        document.adoptBranch(made[0])
        document.flushJournal()
        XCTAssertEqual(Replay(steps: document.journal, width: 200, height: 160).titles.last, "AI の案「月夜」を本番にした")
        document.undo()
        document.switchBranch(made[0])
        XCTAssertTrue(close(color(document, 40, 40), blue))
        document.switchBranch(made[1])
        XCTAssertTrue(close(color(document, 40, 40), red))

        // An answer with no ideas, or a failure, makes no versions.
        var failed = false
        AssistantProposalSource { _, _, completion in completion(.success("sorry")) }.propose("x", for: document) { result in
            if case .failure = result { failed = true }
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(document.branches.count, 3)
    }

    /// The assistant can propose drawing, such as another mouth, on a layer
    /// of its own in the new version, as ordinary lines.
    func testTheAssistantCanProposeLines() throws {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [(20, 20), (180, 20)])
        var folder: URL?
        let assistant = AssistantProposalSource { prompt, given, completion in
            folder = given
            XCTAssertTrue(prompt.contains("picture.png"))
            completion(.success(##"{"proposals": [{"name": "笑顔", "lines": [{"points": [[60, 100], [100, 120], [140, 100]], "width": 8, "color": "#FF0000"}]}]}"##))
        }
        var made: [UUID] = []
        assistant.propose("別の表情", for: document) { result in
            for idea in (try? result.get()) ?? [] { made.append(document.branch(trying: idea)) }
        }
        let shown = try XCTUnwrap(folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shown.appendingPathComponent("picture.png").path), "the picture is there to read")
        XCTAssertEqual(made.count, 1)
        XCTAssertEqual(document.branches.last?.note, "AI の案 · 上に線を 1 本描き足す")
        XCTAssertTrue(close(color(document, 100, 115), .white), "the picture in hand is not changed")
        document.switchBranch(made[0])
        XCTAssertTrue(close(color(document, 100, 115), red), "the version has the new line")
        guard case .stroke = document.layers.last?.items.first else { return XCTFail("an ordinary line, which can be changed") }
        XCTAssertEqual(document.layers.last?.name, "AI の線")
    }

    /// The assistant can take the old mouth out before drawing a new one,
    /// instead of painting over it. Only in the new version.
    func testTheAssistantCanEraseTheOldLines() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let face = line(document, [(20, 20), (180, 20)])
        // A face outline, a mouth inside it, and the face filled around the mouth.
        line(document, (0...80).map { i -> (CGFloat, CGFloat) in
            let a = CGFloat(i) / 80 * 2 * .pi
            return (100 + 80 * cos(a), 115 + 40 * sin(a))
        })
        let mouth = line(document, [(70, 110), (85, 116), (100, 120), (115, 116), (130, 110)], color: RGBA(r: 0, g: 0, b: 1))
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 140), color: green))
        XCTAssertTrue(close(color(document, 100, 104), green), "the face is filled above the mouth too")
        let assistant = AssistantProposalSource { prompt, _, completion in
            XCTAssertTrue(prompt.contains("\"erase\""))
            completion(.success(##"{"proposals": [{"name": "笑顔", "erase": [[60, 100, 140, 130]], "lines": [{"points": [[70, 100], [100, 90], [130, 100]], "width": 6, "color": "#FF0000"}]}]}"##))
        }
        var made: [UUID] = []
        assistant.propose("別の表情", for: document) { result in
            for idea in (try? result.get()) ?? [] { made.append(document.branch(trying: idea)) }
        }
        XCTAssertEqual(made.count, 1)
        XCTAssertEqual(document.branches.last?.note, "AI の案 · 元の線を消して、線を 1 本描き直す")
        XCTAssertNotNil(document.item(mouth), "the picture in hand keeps its mouth")
        document.switchBranch(made[0])
        XCTAssertNil(document.item(mouth), "the old mouth is gone in the version")
        XCTAssertNotNil(document.item(face), "what was outside the box stays")
        XCTAssertNotNil(document.layers.first?.items.first { if case .stroke(let s) = $0, s.points.count > 40 { return true } else { return false } }, "the face outline stays")
        XCTAssertTrue(close(color(document, 100, 118), green), "the face fill spreads over where the old mouth was")
        XCTAssertTrue(close(color(document, 100, 91), red), "the new mouth is drawn")
        // Taking it makes the main picture lose the old mouth, as one step to take back.
        document.adoptBranch(made[0])
        XCTAssertNil(document.item(mouth))
        document.undo()
        XCTAssertNotNil(document.item(mouth))
    }

    /// Taking a version that only changed colours keeps every line in the replay.
    func testTakingARecolouredVersionReplaysWithItsLines() throws {
        let document = CanvasDocument(width: 200, height: 160)
        let parts = square(document, at: 20, 20)
        document.addLayer()
        document.moveLayer(document.activeLayerID, by: -1)
        let sky = document.addSwatch(named: "空", color: green)
        document.bind([parts[1]], to: sky)
        let version = document.branch(trying: Proposal(name: "夜", colors: ["空": blue]))
        document.adoptBranch(version)
        let looks = [(20, 40), (40, 40), (100, 100)].map { color(document, CGFloat($0.0), CGFloat($0.1)) }
        XCTAssertTrue(close(looks[0], .black), "the line is in the picture")
        document.flushJournal()
        let replay = Replay(steps: document.journal, width: 200, height: 160)
        replay.seek(to: replay.count - 1)
        let frame = try XCTUnwrap(replay.frame(maxSide: 200))
        for ((x, y), expected) in zip([(20, 40), (40, 40), (100, 100)], looks) {
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(frame, in: CGRect(x: -x, y: -(160 - 1 - y), width: 200, height: 160))
            let seen = RGBA(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
            XCTAssertTrue(close(seen, expected, 0.05), "replay at \(x),\(y): \(seen) vs \(expected)")
        }
    }

    func testVersionsAreSavedAndOpened() throws {
        let document = CanvasDocument(width: 200, height: 160)
        line(document, [(20, 20), (180, 20)])
        let other = document.makeBranch(named: "赤い線")
        line(document, [(20, 120), (180, 120)], color: red)
        document.switchBranch(document.mainBranch)
        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(reopened.branches.map(\.name), document.branches.map(\.name))
        XCTAssertEqual(reopened.branches.map(\.note), document.branches.map(\.note))
        XCTAssertEqual(reopened.branches.map(\.colorChanges), document.branches.map(\.colorChanges))
        XCTAssertTrue(close(color(reopened, 100, 120), .white))
        reopened.switchBranch(other)
        XCTAssertTrue(close(color(reopened, 100, 120), red))
        reopened.undo()
        XCTAssertTrue(close(color(reopened, 100, 120), red), "history before saving is not kept as undo")
        XCTAssertGreaterThan(reopened.journal.count, 2, "but the version's journal is")
    }
}
