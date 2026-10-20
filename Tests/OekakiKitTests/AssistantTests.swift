import CoreGraphics
import XCTest
@testable import OekakiKit

final class AssistantTests: XCTestCase {
    private let red = RGBA(r: 1, g: 0, b: 0)

    private func document(withSquare: Bool = true) -> CanvasDocument {
        let document = CanvasDocument(width: 200, height: 160)
        guard withSquare else { return document }
        let corners = [CGPoint(x: 50, y: 40), CGPoint(x: 150, y: 40), CGPoint(x: 150, y: 120), CGPoint(x: 50, y: 120), CGPoint(x: 50, y: 40)]
        for (start, end) in zip(corners, corners.dropFirst()) {
            document.beginStroke(at: StrokePoint(x: start.x, y: start.y), color: .black, width: 4, isEraser: false)
            for step in 1...20 {
                let t = CGFloat(step) / 20
                document.continueStroke(to: StrokePoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            }
            document.endStroke()
        }
        return document
    }

    private func color(_ document: CanvasDocument, _ x: CGFloat, _ y: CGFloat) -> RGBA {
        document.pickColor(at: CGPoint(x: x, y: y))!
    }

    // MARK: Reading replies

    func testReplyBlocksAreFound() {
        let reply = """
        Here you go.
        <advice>耳をつなげました。
        目をそろえました。</advice>
        <data>{"fills":[{"x":100,"y":80,"color":"#ff0000","label":"顔"},{"x":10,"y":10,"color":"#0f0"}]}</data>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 160"><circle cx="100" cy="80" r="20" fill="#00f"/></svg>
        """
        let response = AIResponse(parsing: reply)
        XCTAssertEqual(response.advice, "耳をつなげました。\n目をそろえました。")
        XCTAssertEqual(response.fills, [
            AIFill(x: 100, y: 80, color: red, label: "顔"),
            AIFill(x: 10, y: 10, color: RGBA(r: 0, g: 1, b: 0), label: ""),
        ])
        XCTAssertNotNil(response.svg)
    }

    func testEmptySVGAndBrokenDataAreIgnored() {
        let response = AIResponse(parsing: "<advice> </advice><data>{not json}</data><svg viewBox=\"0 0 1 1\"></svg>")
        XCTAssertTrue(response.isEmpty)
    }

    func testDataInsideACodeFenceIsRead() {
        let response = AIResponse(parsing: "<data>```json\n{\"fills\":[{\"x\":1,\"y\":2,\"color\":\"#ffffff\",\"label\":\"a\"}]}\n```</data>")
        XCTAssertEqual(response.fills.count, 1)
    }

    func testBadColoursAreSkipped() {
        let response = AIResponse(parsing: "<data>{\"fills\":[{\"x\":1,\"y\":2,\"color\":\"red\"},{\"x\":3,\"y\":4,\"color\":\"#102030\"}]}</data>")
        XCTAssertEqual(response.fills.map(\.x), [3])
    }

    // MARK: Drawing replies

    func testSVGIsDrawnInCanvasCoordinates() throws {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 160\"><rect x=\"20\" y=\"10\" width=\"40\" height=\"20\" fill=\"#ff0000\"/></svg>"
        let image = try XCTUnwrap(SVGRaster.image(from: svg, width: 200, height: 160))
        let document = document(withSquare: false)
        document.insertLayer(named: "svg", items: [.bitmap(image, alpha: 1)], at: document.layers.count)
        XCTAssertEqual(color(document, 40, 20), red, "The shape belongs near the top left")
        XCTAssertEqual(color(document, 40, 140), .white, "It must not be flipped to the bottom")
    }

    func testSVGWithoutAViewBoxStillFillsTheCanvas() {
        let prepared = SVGRaster.prepared("<svg xmlns=\"http://www.w3.org/2000/svg\"><script>x</script><image href=\"http://example.com/a.png\"/><circle r=\"3\"/></svg>", width: 200, height: 160)
        XCTAssertTrue(prepared.contains("viewBox=\"0 0 200 160\""))
        XCTAssertFalse(prepared.contains("script"))
        XCTAssertFalse(prepared.contains("<image"))
    }

    // MARK: Putting results on the canvas

    func testLineArtGoesOnTopAndFadesTheSketch() throws {
        let document = document()
        let sketch = document.activeLayerID
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 160\"><line x1=\"10\" y1=\"150\" x2=\"190\" y2=\"150\" stroke=\"#ff0000\" stroke-width=\"6\"/></svg>"
        let placement = document.applyLineArt(try XCTUnwrap(SVGRaster.image(from: svg, width: 200, height: 160)))

        XCTAssertEqual(document.layers.count, 2)
        XCTAssertEqual(document.layers[1].id, document.activeLayerID, "The new lines are selected, ready to be fixed by hand")
        XCTAssertEqual(document.layers[0].opacity, 0.3)
        XCTAssertEqual(color(document, 100, 150), red)

        document.discard(placement)
        XCTAssertEqual(document.layers.count, 1)
        XCTAssertEqual(document.layers[0].opacity, 1)
        XCTAssertEqual(document.activeLayerID, sketch)
        XCTAssertEqual(color(document, 100, 150), .white)
        XCTAssertEqual(color(document, 100, 40), .black)
    }

    func testOneUndoRemovesAWholeResult() throws {
        let document = document()
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 160\"><circle cx=\"100\" cy=\"80\" r=\"5\" fill=\"#ff0000\"/></svg>"
        _ = document.applyLineArt(try XCTUnwrap(SVGRaster.image(from: svg, width: 200, height: 160)))
        document.undo()
        XCTAssertEqual(document.layers.count, 1)
        XCTAssertEqual(document.layers[0].opacity, 1)
    }

    func testBaseColoursGoUnderTheLines() {
        let document = document()
        let lines = document.activeLayerID
        let fills = [AIFill(x: 100, y: 80, color: red, label: "inside"), AIFill(x: 10, y: 10, color: RGBA(r: 0, g: 0, b: 1), label: "background")]
        let placement = document.applyUnderpaint(fills: fills, details: nil)

        XCTAssertEqual(placement.layerIDs.count, 1)
        XCTAssertEqual(document.layers.count, 2)
        XCTAssertEqual(document.layers[1].id, lines, "The line layer stays on top")
        XCTAssertEqual(document.activeLayerID, lines)
        XCTAssertEqual(color(document, 100, 80), red)
        XCTAssertEqual(color(document, 10, 10), RGBA(r: 0, g: 0, b: 1))
        XCTAssertEqual(color(document, 50, 80), .black)

        document.discard(placement)
        XCTAssertEqual(document.layers.count, 1)
        XCTAssertEqual(color(document, 100, 80), .white)
    }

    func testPointsOffTheCanvasAreIgnored() {
        let document = document()
        let placement = document.applyUnderpaint(fills: [AIFill(x: 900, y: 80, color: red, label: "")], details: nil)
        XCTAssertTrue(placement.isEmpty)
        XCTAssertEqual(document.layers.count, 1)
    }

    // MARK: The picture and the wording

    func testPictureForTheAssistantIsScaledDown() throws {
        let data = try XCTUnwrap(AIPicture.png(of: CanvasDocument(width: 3200, height: 1600)))
        let image = try XCTUnwrap(ImageCoding.image(fromPNG: data))
        XCTAssertEqual(image.width, 1280)
        XCTAssertEqual(image.height, 640)
        XCTAssertEqual(AIPicture.gridStep(for: 1600), 200)
        XCTAssertEqual(AIPicture.gridStep(for: 200), 25)
    }

    func testPromptsCarryTheCanvasSizeAndTheRequest() {
        let prompt = AIPrompts.prompt(for: .underpaint, width: 800, height: 600, request: "  三毛猫  ")
        XCTAssertTrue(prompt.contains("800x600"))
        XCTAssertTrue(prompt.contains("\"三毛猫\""))
        XCTAssertTrue(prompt.contains("viewBox=\"0 0 800 600\""))
        XCTAssertTrue(AIPrompts.prompt(for: .cleanup, width: 800, height: 600, request: "").contains("(nothing)"))
    }

    // MARK: Reading the command's output

    func testCommandOutputIsInterpreted() {
        func interpret(_ json: String, status: Int32 = 0, cancelled: Bool = false) -> Result<ClaudeCLI.Reply, ClaudeCLI.Failure> {
            ClaudeCLI.interpret(output: Data(json.utf8), errors: Data(), status: status, wasCancelled: cancelled, didTimeOut: false, seconds: 1)
        }
        let good = try? interpret("{\"is_error\":false,\"result\":\"hello\",\"session_id\":\"abc\"}").get()
        XCTAssertEqual(good?.text, "hello")
        XCTAssertEqual(good?.sessionID, "abc")

        func failure(_ result: Result<ClaudeCLI.Reply, ClaudeCLI.Failure>) -> ClaudeCLI.Failure? {
            if case .failure(let failure) = result { return failure }
            return nil
        }
        XCTAssertEqual(failure(interpret("{\"is_error\":true,\"result\":\"Usage limit reached\"}", status: 1)), .failed("Usage limit reached"))
        XCTAssertEqual(failure(interpret("{\"is_error\":true,\"result\":\"Please run /login\"}", status: 1)), .notLoggedIn)
        XCTAssertEqual(failure(interpret("{\"result\":\"hello\"}", cancelled: true)), .cancelled)
        XCTAssertEqual(failure(interpret("", status: 2)), .failed("exit 2"))
    }
}
