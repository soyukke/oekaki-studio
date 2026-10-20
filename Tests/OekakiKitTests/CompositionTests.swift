import CoreGraphics
import XCTest
@testable import OekakiKit

final class CompositionTests: XCTestCase {
    private func line(_ document: CanvasDocument, from start: CGPoint, to end: CGPoint, on layer: UUID? = nil) {
        XCTAssertTrue(document.beginStroke(at: StrokePoint(x: start.x, y: start.y), color: .black, width: 6, isEraser: false, on: layer))
        for step in 1...20 {
            let t = CGFloat(step) / 20
            document.continueStroke(to: StrokePoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        document.endStroke()
    }

    private func color(of image: CGImage, at point: CGPoint) -> RGBA {
        let context = Raster.makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixel = context.data!.assumingMemoryBound(to: UInt8.self) + (Int(point.y) * image.width + Int(point.x)) * 4
        return RGBA(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
    }

    func testTheCompositionSheetIsMadeOnceAtTheBackWithoutTakingOver() {
        let document = CanvasDocument(width: 200, height: 160)
        let drawing = document.activeLayerID
        let sheet = document.makeCompositionLayer()
        XCTAssertEqual(document.layers.first?.id, sheet)
        XCTAssertEqual(document.layers.first?.isComposition, true)
        XCTAssertEqual(document.activeLayerID, drawing, "the layer in use stays")
        XCTAssertEqual(document.makeCompositionLayer(), sheet)
        XCTAssertEqual(document.layers.count, 2)
    }

    func testCompositionLinesStayOutOfThePictureAndTheBucket() {
        let document = CanvasDocument(width: 200, height: 160)
        let sheet = document.makeCompositionLayer()
        // A box on the composition sheet only.
        let corners = [CGPoint(x: 40, y: 40), CGPoint(x: 160, y: 40), CGPoint(x: 160, y: 120), CGPoint(x: 40, y: 120), CGPoint(x: 40, y: 40)]
        for (a, b) in zip(corners, corners.dropFirst()) { line(document, from: a, to: b, on: sheet) }
        XCTAssertEqual(document.pickColor(at: CGPoint(x: 100, y: 40)), .white, "the finished picture leaves it out")
        XCTAssertTrue(document.fill(at: CGPoint(x: 100, y: 80), color: RGBA(r: 1, g: 0, b: 0)))
        XCTAssertEqual(document.pickColor(at: CGPoint(x: 20, y: 20)), RGBA(r: 1, g: 0, b: 0), "the bucket is not stopped by it")

        let brief = document.compositeImage(includingComposition: true)!
        XCTAssertEqual(color(of: brief, at: CGPoint(x: 100, y: 40)), .black, "the brief shows it")
    }

    func testTheBriefShowsTheDollAndNotesButThePictureDoesNot() {
        let document = CanvasDocument(width: 400, height: 300)
        document.setFigure(Figure.standing(in: document.size))
        document.setNotes([Note(text: "マイク", at: CGPoint(x: 20, y: 20), pointingAt: CGPoint(x: 300, y: 200), fontSize: 24)])
        let picture = document.compositeImage()!
        let brief = document.compositeImage(includingComposition: true)!
        func inked(_ image: CGImage) -> Int {
            var count = 0
            for y in stride(from: 0, to: 300, by: 3) {
                for x in stride(from: 0, to: 400, by: 3) where color(of: image, at: CGPoint(x: x, y: y)) != .white { count += 1 }
            }
            return count
        }
        XCTAssertEqual(inked(picture), 0)
        XCTAssertGreaterThan(inked(brief), 100)
    }

    func testNotesAreUndoneAndSaved() throws {
        let document = CanvasDocument(width: 300, height: 200)
        let note = Note(text: "ここは青", at: CGPoint(x: 10, y: 10), pointingAt: CGPoint(x: 150, y: 100), fontSize: 20)
        document.setNotes([note])
        var moved = note
        for step in 1...5 {
            moved.origin = CGPoint(x: 10 + step * 4, y: 10)
            document.setNotes([moved], coalescing: "drag")
        }
        document.undo()
        XCTAssertEqual(document.notes, [note], "one drag is one step")
        document.undo()
        XCTAssertTrue(document.notes.isEmpty)
        document.redo()

        document.makeCompositionLayer()
        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(reopened.notes, [note])
        XCTAssertEqual(reopened.layers.map(\.isComposition), document.layers.map(\.isComposition))
    }

    func testAnArrowLeavesTheEdgeOfItsNote() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 40)
        let start = NoteRenderer.edge(of: box, toward: CGPoint(x: 300, y: 20))
        XCTAssertEqual(start, CGPoint(x: 100, y: 20))
        XCTAssertGreaterThan(NoteRenderer.box(of: Note(text: "長いメモの文", at: .zero, fontSize: 20)).width, 60)
    }

    func testPropsFromTheAssistantGoOnTheirOwnCompositionLayer() {
        let document = CanvasDocument(width: 200, height: 160)
        let drawing = document.activeLayerID
        let sheet = document.makeCompositionLayer()
        let image = Raster.makeContext(width: 200, height: 160).makeImage()!
        let placement = document.applyGuide(image)
        let added = document.layers.first { $0.id == placement.layerIDs.first }
        XCTAssertEqual(added?.isComposition, true)
        XCTAssertEqual(document.index(ofLayer: added!.id), (document.index(ofLayer: sheet) ?? 0) + 1)
        XCTAssertEqual(document.activeLayerID, drawing)
    }
}
