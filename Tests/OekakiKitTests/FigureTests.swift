import CoreGraphics
import XCTest
@testable import OekakiKit

final class FigureTests: XCTestCase {
    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }

    func testAStandingFigureFitsTheCanvasAtItsHeight() {
        let figure = Figure.standing(in: CGSize(width: 1600, height: 1200))
        let joints = figure.joints
        XCTAssertEqual(Double(joints.head.y) - joints.headRadius, 120, accuracy: 0.01, "the head starts near the top")
        let lowest = joints.ankle.map { Double($0.y) }.max() ?? 0
        XCTAssertEqual(lowest - (Double(joints.head.y) - joints.headRadius), 960, accuracy: 15, "head to ankles is the height")
        XCTAssertEqual(Double(joints.pelvis.x), 800, accuracy: 0.01)
    }

    func testHeadsTallSetsTheSizeOfTheHead() {
        var figure = Figure(x: 500, y: 500, height: 800)
        for heads in [2.0, 4, 6, 8] {
            figure.heads = heads
            let joints = figure.joints
            let headLength = joints.headRadius * (1 + figure.face.chin)
            XCTAssertEqual(headLength, 800 / heads, accuracy: 0.01)
        }
    }

    func testChangingTheBuildKeepsThePoseAndThePlace() {
        var figure = Figure(x: 500, y: 600, height: 800)
        figure.apply(.waving)
        let before = figure.pose
        figure.heads = 3
        figure.shoulders = 1.3
        figure.legs = 1.1
        XCTAssertEqual(figure.pose, before)
        XCTAssertEqual(figure.joints.pelvis, CGPoint(x: 500, y: 600))
    }

    func testDraggingAHandMovesTheWholeArmAndKeepsItsLength() {
        var figure = Figure(x: 500, y: 600, height: 800)
        let joints = figure.joints
        let shoulder = joints.shoulder[1]
        let upper = distance(shoulder, joints.elbow[1])
        let fore = distance(joints.elbow[1], joints.wrist[1])
        let target = CGPoint(x: shoulder.x + 120, y: shoulder.y - 160)
        figure.move(.wrist(1), to: target)
        let moved = figure.joints
        XCTAssertEqual(distance(moved.wrist[1], target), 0, accuracy: 0.5, "the hand goes where it was dragged")
        XCTAssertEqual(distance(moved.shoulder[1], moved.elbow[1]), upper, accuracy: 0.01)
        XCTAssertEqual(distance(moved.elbow[1], moved.wrist[1]), fore, accuracy: 0.01)
        XCTAssertEqual(moved.wrist[0], joints.wrist[0], "the other hand stays")
    }

    func testAHandDraggedTooFarPointsTheArmStraightAtIt() {
        var figure = Figure(x: 500, y: 600, height: 800)
        let shoulder = figure.joints.shoulder[0]
        let target = CGPoint(x: shoulder.x - 2000, y: shoulder.y)
        figure.move(.wrist(0), to: target)
        let joints = figure.joints
        XCTAssertEqual(Double(joints.elbow[0].y), Double(shoulder.y), accuracy: 0.5)
        XCTAssertEqual(Double(joints.wrist[0].y), Double(shoulder.y), accuracy: 0.5)
        XCTAssertLessThan(joints.wrist[0].x, joints.elbow[0].x)
    }

    func testTheElbowKeepsBendingTheSameWay() {
        var figure = Figure(x: 500, y: 600, height: 800)
        figure.apply(.handsOnHips)
        let elbow = figure.joints.elbow[0]
        let wrist = figure.joints.wrist[0]
        figure.move(.wrist(0), to: CGPoint(x: wrist.x + 5, y: wrist.y + 5))
        XCTAssertLessThan(distance(figure.joints.elbow[0], elbow), 20, "the elbow does not flip to the other side")
    }

    func testHoldingTheHipsMovesEverything() {
        var figure = Figure(x: 500, y: 600, height: 800)
        let head = figure.joints.head
        figure.move(.pelvis, to: CGPoint(x: 610, y: 650), grab: CGVector(dx: 10, dy: 0))
        XCTAssertEqual(figure.joints.head, CGPoint(x: head.x + 100, y: head.y + 50))
    }

    func testLeaningTheBodyCarriesTheArmsAndHeadButNotTheLegs() {
        var figure = Figure(x: 500, y: 600, height: 800)
        let before = figure.joints
        let chest = before.chest
        figure.move(.chest, to: CGPoint(x: chest.x + 150, y: chest.y))
        let after = figure.joints
        XCTAssertGreaterThan(figure.pose.torso, 10)
        XCTAssertGreaterThan(after.head.x, before.head.x + 100)
        XCTAssertGreaterThan(after.shoulder[1].x, before.shoulder[1].x)
        // The hips tilt a little with the body; the feet stay about where they were.
        XCTAssertEqual(after.ankle[0].x, before.ankle[0].x, accuracy: 5)
    }

    func testTheHandleUnderThePointerIsFound() {
        let figure = Figure(x: 500, y: 600, height: 800)
        let elbow = figure.joints.elbow[1]
        XCTAssertEqual(figure.part(at: CGPoint(x: elbow.x + 3, y: elbow.y), reach: 10), .elbow(1))
        XCTAssertNil(figure.part(at: CGPoint(x: 5, y: 5), reach: 10))
    }

    // MARK: In a document

    func testTheDollIsNotPartOfThePicture() {
        let document = CanvasDocument(width: 200, height: 160)
        document.setFigure(Figure.standing(in: document.size))
        XCTAssertNotNil(document.figure)
        XCTAssertTrue(document.isBlank)
        XCTAssertEqual(document.pickColor(at: CGPoint(x: 100, y: 80)), .white, "the export and the tools do not see it")
    }

    func testOneDragIsOneUndoStep() {
        let document = CanvasDocument(width: 400, height: 400)
        document.setFigure(Figure.standing(in: document.size))
        let placed = document.figure
        for step in 1...10 {
            var figure = document.figure!
            figure.move(.wrist(1), to: CGPoint(x: 300 + step, y: 100))
            document.setFigure(figure, coalescing: "drag-1")
        }
        XCTAssertNotEqual(document.figure, placed)
        document.undo()
        XCTAssertEqual(document.figure, placed)
        document.undo()
        XCTAssertNil(document.figure)
        document.redo()
        XCTAssertEqual(document.figure, placed)
    }

    func testTheDollIsSavedWithThePicture() throws {
        let document = CanvasDocument(width: 400, height: 300)
        var figure = Figure.standing(in: document.size)
        figure.heads = 3
        figure.face = .pointed
        figure.yaw = 30
        figure.apply(.peace)
        document.setFigure(figure)
        let reopened = try DocumentFile.decode(DocumentFile.encode(document))
        XCTAssertEqual(reopened.figure, figure)
    }

    func testAPictureWithoutADollStillOpens() throws {
        let document = CanvasDocument(width: 100, height: 100)
        XCTAssertNil(try DocumentFile.decode(DocumentFile.encode(document)).figure)
    }
}
