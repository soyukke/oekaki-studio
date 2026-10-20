import AppKit
import CoreGraphics
import CoreText
import Foundation

/// The steps the assistant can take over.
public enum AITask: String, CaseIterable, Identifiable {
    /// Redraw the rough sketch as clean line art.
    case cleanup
    /// Put base colours under the line art.
    case underpaint
    /// Suggest where things should go, as guide lines.
    case guide
    /// Give advice in words only.
    case consult

    public var id: String { rawValue }
}

/// One area to flood with colour, chosen by the assistant.
public struct AIFill: Equatable {
    public var x: Double
    public var y: Double
    public var color: RGBA
    public var label: String
}

/// What the assistant sent back, picked out of its reply text.
public struct AIResponse {
    public var advice: String?
    public var svg: String?
    public var fills: [AIFill] = []

    public init(parsing text: String) {
        advice = Self.firstMatch(of: "<advice>(.*?)</advice>", in: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if advice?.isEmpty == true { advice = nil }
        if let found = Self.firstMatch(of: "(<svg\\b.*?</svg>)", in: text), Self.hasShapes(found) {
            svg = found
        }
        if let json = Self.firstMatch(of: "<data>(.*?)</data>", in: text) {
            fills = Self.fills(fromJSON: json)
        }
    }

    public var isEmpty: Bool { advice == nil && svg == nil && fills.isEmpty }

    private static func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func hasShapes(_ svg: String) -> Bool {
        svg.range(of: "<(path|ellipse|circle|line|polyline|polygon|rect)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func fills(fromJSON json: String) -> [AIFill] {
        struct Payload: Decodable {
            struct Entry: Decodable {
                var x: Double
                var y: Double
                var color: String
                var label: String?
            }
            var fills: [Entry]
        }
        // The reply sometimes wraps the JSON in a code fence.
        let cleaned = json.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(cleaned.utf8)) else { return [] }
        return payload.fills.compactMap { entry in
            guard let color = RGBA(hexString: entry.color) else { return nil }
            return AIFill(x: entry.x, y: entry.y, color: color, label: entry.label ?? "")
        }
    }
}

extension RGBA {
    /// Reads "#rrggbb" or "#rgb".
    public init?(hexString: String) {
        var digits = hexString.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

/// The picture of the canvas that is sent to the assistant.
public enum AIPicture {
    static let longestSide = 1280

    /// A grid spacing that gives roughly eight lines across the longer side.
    static func gridStep(for longest: Int) -> Int {
        let wanted = Double(longest) / 9
        return [25, 50, 100, 200, 250, 500, 1000, 2000].first { Double($0) >= wanted } ?? 2000
    }

    /// The canvas over white paper, scaled down, with a labelled coordinate
    /// grid so positions can be read off in canvas pixels.
    public static func png(of document: CanvasDocument, includingComposition: Bool = false) -> Data? {
        guard let image = document.compositeImage(background: .white, includingComposition: includingComposition) else { return nil }
        let scale = min(1, CGFloat(longestSide) / CGFloat(max(document.width, document.height)))
        let width = Int((CGFloat(document.width) * scale).rounded())
        let height = Int((CGFloat(document.height) * scale).rounded())
        let context = Raster.makeContext(width: width, height: height)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let magenta = CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let step = gridStep(for: max(document.width, document.height))
        context.setStrokeColor(magenta.copy(alpha: 0.35) ?? magenta)
        context.setLineWidth(1)
        for x in stride(from: 0, through: document.width, by: step) {
            context.move(to: CGPoint(x: CGFloat(x) * scale, y: 0))
            context.addLine(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(height)))
        }
        for y in stride(from: 0, through: document.height, by: step) {
            context.move(to: CGPoint(x: 0, y: CGFloat(height) - CGFloat(y) * scale))
            context.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(height) - CGFloat(y) * scale))
        }
        context.strokePath()

        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        func label(_ text: String, at point: CGPoint) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): magenta,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = point
            CTLineDraw(line, context)
        }
        for x in stride(from: 0, through: document.width, by: step) {
            label("\(x)", at: CGPoint(x: CGFloat(x) * scale + 3, y: CGFloat(height) - 14))
        }
        for y in stride(from: step, through: document.height, by: step) {
            label("\(y)", at: CGPoint(x: 3, y: CGFloat(height) - CGFloat(y) * scale + 3))
        }
        return context.makeImage().flatMap(ImageCoding.png)
    }
}

/// Turning the assistant's SVG into pixels.
public enum SVGRaster {
    /// Removes the parts of an SVG that could load or run something, and
    /// makes sure it is laid out on the canvas's coordinates.
    static func prepared(_ svg: String, width: Int, height: Int) -> String {
        var cleaned = svg
        for pattern in ["<script\\b.*?</script>", "<foreignObject\\b.*?</foreignObject>", "<image\\b[^>]*>", "</image>"] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        guard let tagEnd = cleaned.firstIndex(of: ">") else { return cleaned }
        let openingTag = cleaned[..<tagEnd]
        if openingTag.range(of: "viewBox", options: .caseInsensitive) == nil {
            cleaned.insert(contentsOf: " viewBox=\"0 0 \(width) \(height)\"", at: tagEnd)
        }
        return cleaned
    }

    /// Draws an SVG over the whole canvas. Returns nil when it cannot be read.
    public static func image(from svg: String, width: Int, height: Int) -> CGImage? {
        guard let source = NSImage(data: Data(prepared(svg, width: width, height: height).utf8)) else { return nil }
        let context = Raster.makeContext(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        source.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

/// The wording of each request.
public enum AIPrompts {
    static func lineWidth(for width: Int) -> Int {
        max(3, width / 320)
    }

    private static func opening(width: Int, height: Int, request: String) -> String {
        let wish = request.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        You are an assistant inside a drawing app. A person leads the drawing and hands you one step at a time.
        Read the image ./canvas.png with the Read tool. It shows the current canvas (\(width)x\(height) pixels, white paper).
        The thin magenta grid lines and numbers are a coordinate guide, not part of the drawing.
        Coordinates: origin at the top left, x to the right from 0 to \(width), y downward from 0 to \(height).

        What the person wrote about this picture: \(wish.isEmpty ? "(nothing)" : "\"\(wish)\"")
        """
    }

    private static var adviceLanguage: String {
        Localization.isJapanese ? "Japanese" : "English"
    }

    private static func svgOpening(width: Int, height: Int) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(width) \(height)\">...</svg>"
    }

    public static func prompt(for task: AITask, width: Int, height: Int, request: String) -> String {
        let intro = opening(width: width, height: height, request: request)
        let stroke = lineWidth(for: width)
        switch task {
        case .cleanup:
            return """
            \(intro)

            Your step: clean line art. Redraw the person's rough sketch as tidy lines, in the same place and at the same size, so your lines sit on top of theirs. Keep what they drew and how they drew it; smooth shaky lines, join lines that should meet, and close outlines that should be closed so the areas can be filled with colour later. If the canvas is blank, draw what they wrote instead.

            Reply with exactly these two blocks and nothing else:
            <advice>Up to 3 short lines for the person, in \(adviceLanguage): what you tidied, and one thing they may want to fix by hand.</advice>
            \(svgOpening(width: width, height: height))

            SVG rules: only path, ellipse, circle, line, polyline and polygon elements, each with stroke="#111111" fill="none" stroke-width="\(stroke)" stroke-linecap="round" stroke-linejoin="round". No text and no images.
            """
        case .underpaint:
            return """
            \(intro)

            Your step: base colours. Choose flat colours for this line art, following what the person wrote about colours and mood.

            Reply with exactly these three blocks and nothing else:
            <advice>Up to 2 short lines for the person, in \(adviceLanguage): anything you could not do, or a gap in the lines that will let colour leak.</advice>
            <data>{"fills":[{"x":0,"y":0,"color":"#rrggbb","label":"part name"}]}</data>
            \(svgOpening(width: width, height: height))

            fills: for each area enclosed by lines, give one point well inside it, away from the lines. The app floods colour from that point out to the lines. Include one point for the background.
            svg: extra colour that no line encloses, such as fur patterns, one step of shadow or blush. It is drawn above the base colours and below the lines. Use fill only, no stroke, stay inside the outlines, and do not draw the lines themselves. Use only path, ellipse, circle and polygon elements. Leave the svg empty if nothing is needed.
            """
        case .guide:
            return """
            \(intro)

            Your step: props and background for the composition. The person plans the picture before drawing it themselves or handing it to an illustrator. The light blue jointed doll, if there is one, is the pose they chose for the character; grey lines are their own composition sketch; orange boxes are their written notes, and an arrow from a note points at what it is about. Keep all of that as it is, and do not draw the character.
            Add the props and background they asked for, as very simple outlines that only show what each thing is, where it is and how big: a few lines per object, no shading, no texture, no detail. Put held things in the doll's hands and the ground under its feet. For a room or a street, a horizon and a few lines of depth are enough.

            Reply with exactly these two blocks and nothing else:
            <advice>Up to 3 short lines for the person, in \(adviceLanguage): what you placed and where.</advice>
            \(svgOpening(width: width, height: height))

            SVG rules: only path, ellipse, circle, line, polyline and polygon elements, each with stroke="#8B5CF6" fill="none" stroke-width="\(stroke)" stroke-linecap="round" stroke-linejoin="round". No text and no images.
            """
        case .consult:
            return """
            \(intro)

            Your step: advice. Look at the picture as it is and tell the person, kindly and concretely, what is working and the next one or two things to do. They may be new to drawing, so avoid jargon and point at places in the picture ("the left ear", "the top edge").

            Reply with exactly this block and nothing else:
            <advice>Up to 6 short lines, in \(adviceLanguage).</advice>
            """
        }
    }

    /// Asks for a change to the previous reply in the same conversation.
    public static func followUp(for task: AITask, change: String) -> String {
        let blocks: String
        switch task {
        case .cleanup, .guide: blocks = "<advice> and <svg>"
        case .underpaint: blocks = "<advice>, <data> and <svg>"
        case .consult: blocks = "<advice>"
        }
        return """
        The person looked at your result and asked for a change: "\(change.trimmingCharacters(in: .whitespacesAndNewlines))"
        You do not need to read the image again. Change only what they asked for and keep everything else as it was.
        Reply in the same format as before: the complete \(blocks) blocks and nothing else. Write the advice in \(adviceLanguage).
        """
    }
}

/// Where an assistant's result was put, so it can be taken out again.
public struct AIPlacement {
    public var layerIDs: [UUID] = []
    var dimmed: (id: UUID, opacity: Double)?
    var previousActive: UUID?

    public init() {}

    public var isEmpty: Bool { layerIDs.isEmpty }
}

extension CanvasDocument {
    /// How much of a rough sketch stays visible under clean lines.
    static let roughOpacity = 0.3

    /// Adds clean lines above the active layer and fades that layer, so the
    /// new lines read clearly over the sketch they came from.
    public func applyLineArt(_ image: CGImage) -> AIPlacement {
        var placement = AIPlacement()
        transaction {
            let activeIndex = index(ofLayer: activeLayerID) ?? layers.count - 1
            let rough = layers[activeIndex]
            placement.previousActive = rough.id
            if !rough.items.isEmpty, rough.opacity > Self.roughOpacity {
                placement.dimmed = (rough.id, rough.opacity)
                setLayerOpacity(rough.id, Self.roughOpacity)
            }
            let id = insertLayer(named: L("AI 清書", "AI Line Art"), items: [.bitmap(image, alpha: 1)], at: activeIndex + 1)
            activeLayerID = id
            placement.layerIDs = [id]
        }
        return placement
    }

    /// Adds props and background as a composition layer of its own, just
    /// above the person's composition sheet, so it stays out of the finished
    /// picture and can be told apart from their own lines.
    public func applyGuide(_ image: CGImage) -> AIPlacement {
        var placement = AIPlacement()
        transaction {
            let below = compositionLayerID.flatMap { index(ofLayer: $0) } ?? -1
            let active = activeLayerID
            let id = insertLayer(
                named: L("AI 小物と背景", "AI Props and Background"), items: [.bitmap(image, alpha: 1)], at: below + 1, isComposition: true
            )
            activeLayerID = active
            placement.layerIDs = [id]
        }
        return placement
    }

    /// Adds base colours, and any extra colour detail above them, under the active layer.
    public func applyUnderpaint(fills: [AIFill], details: CGImage?) -> AIPlacement {
        let items = makeFills(fills.map { (point: CGPoint(x: $0.x, y: $0.y), color: $0.color) })
        var placement = AIPlacement()
        guard !items.isEmpty || details != nil else { return placement }
        transaction {
            var index = index(ofLayer: activeLayerID) ?? 0
            if !items.isEmpty {
                placement.layerIDs.append(insertLayer(named: L("AI 下塗り", "AI Base Colors"), items: items, at: index))
                index += 1
            }
            if let details {
                placement.layerIDs.append(insertLayer(named: L("AI 模様と影", "AI Details"), items: [.bitmap(details, alpha: 1)], at: index))
            }
        }
        return placement
    }

    /// Takes an assistant's result back out and puts the layers as they were.
    public func discard(_ placement: AIPlacement) {
        transaction {
            removeLayers(Set(placement.layerIDs))
            if let dimmed = placement.dimmed, index(ofLayer: dimmed.id) != nil {
                setLayerOpacity(dimmed.id, dimmed.opacity)
            }
            if let previous = placement.previousActive, index(ofLayer: previous) != nil {
                activeLayerID = previous
            }
        }
    }
}
