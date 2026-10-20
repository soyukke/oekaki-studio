import CoreGraphics
import CoreText
import Foundation

/// A written note on the composition, such as "she holds a microphone here",
/// optionally with an arrow to what it is about. Like the doll, it belongs
/// to the plan of the picture, not to the picture itself.
public struct Note: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var text: String
    /// The top left of the text, in canvas pixels.
    public var x: Double
    public var y: Double
    /// Where the arrow points, if the note has one.
    public var targetX: Double?
    public var targetY: Double?
    public var fontSize: Double

    public init(text: String, at point: CGPoint, pointingAt target: CGPoint? = nil, fontSize: Double) {
        self.text = text
        x = point.x
        y = point.y
        targetX = target.map { Double($0.x) }
        targetY = target.map { Double($0.y) }
        self.fontSize = fontSize
    }

    public var origin: CGPoint {
        get { CGPoint(x: x, y: y) }
        set { x = newValue.x; y = newValue.y }
    }

    public var target: CGPoint? {
        guard let targetX, let targetY else { return nil }
        return CGPoint(x: targetX, y: targetY)
    }

    /// A size that reads well on a canvas of this width.
    public static func fontSize(forCanvasWidth width: Int) -> Double {
        max(18, Double(width) / 50)
    }
}

/// Drawing notes into a context whose y axis points down.
public enum NoteRenderer {
    /// An orange that stands apart from the blue doll and from most drawings.
    public static let ink = CGColor(srgbRed: 0.87, green: 0.36, blue: 0.05, alpha: 1)

    static func font(_ size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private static func lines(of note: Note) -> [CTLine] {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(note.fontSize),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        ]
        let text = note.text.isEmpty ? " " : note.text
        return text.components(separatedBy: "\n").map {
            CTLineCreateWithAttributedString(NSAttributedString(string: $0.isEmpty ? " " : $0, attributes: attributes))
        }
    }

    static func padding(_ note: Note) -> Double { note.fontSize * 0.35 }
    static func lineHeight(_ note: Note) -> Double { note.fontSize * 1.3 }

    /// The box around the text, in canvas pixels.
    public static func box(of note: Note) -> CGRect {
        let widest = lines(of: note).map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        let pad = padding(note)
        let count = Double(max(1, note.text.components(separatedBy: "\n").count))
        return CGRect(x: note.x, y: note.y, width: widest + pad * 2, height: lineHeight(note) * count + pad * 2)
    }

    public static func draw(_ notes: [Note], in context: CGContext, skipping hidden: UUID? = nil) {
        for note in notes where note.id != hidden {
            draw(note, in: context)
        }
    }

    public static func draw(_ note: Note, in context: CGContext) {
        let box = box(of: note)
        context.saveGState()
        context.setStrokeColor(ink)
        context.setFillColor(ink)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let line = max(2, note.fontSize / 10)
        context.setLineWidth(line)
        if let target = note.target {
            let start = edge(of: box, toward: target)
            let angle = atan2(Double(target.y - start.y), Double(target.x - start.x))
            let head = note.fontSize * 0.7
            context.move(to: start)
            context.addLine(to: target)
            context.strokePath()
            context.move(to: target)
            for side in [-1.0, 1.0] {
                let wing = angle + .pi - side * 0.45
                context.addLine(to: CGPoint(x: target.x + head * cos(wing), y: target.y + head * sin(wing)))
            }
            context.closePath()
            context.fillPath()
        }
        let rounded = CGPath(roundedRect: box, cornerWidth: note.fontSize * 0.3, cornerHeight: note.fontSize * 0.3, transform: nil)
        context.setFillColor(CGColor(gray: 1, alpha: 0.92))
        context.addPath(rounded)
        context.fillPath()
        context.addPath(rounded)
        context.strokePath()

        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let pad = padding(note)
        for (index, text) in lines(of: note).enumerated() {
            var ascent: CGFloat = 0
            _ = CTLineGetTypographicBounds(text, &ascent, nil, nil)
            let baseline = note.y + pad + lineHeight(note) * Double(index) + (lineHeight(note) - note.fontSize) / 2 + Double(ascent)
            context.textPosition = CGPoint(x: note.x + pad, y: baseline)
            CTLineDraw(text, context)
        }
        context.restoreGState()
    }

    /// Where a line from the middle of `box` towards `point` leaves it.
    static func edge(of box: CGRect, toward point: CGPoint) -> CGPoint {
        let center = CGPoint(x: box.midX, y: box.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }
        let scale = min(abs(dx) > 0.001 ? box.width / 2 / abs(dx) : .infinity, abs(dy) > 0.001 ? box.height / 2 / abs(dy) : .infinity)
        return CGPoint(x: center.x + dx * min(scale, 1), y: center.y + dy * min(scale, 1))
    }
}
