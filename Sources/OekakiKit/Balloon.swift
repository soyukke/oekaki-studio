import CoreGraphics
import CoreText
import Foundation

/// Words in a comic: a speech balloon, a shout, a thought, the narrator's
/// box, words alone, or a sound effect lettered big into the picture.
/// Written top to bottom in columns read right to left, as Japanese comics
/// are, or across.
public struct BalloonItem {
    public enum Shape: String, CaseIterable, Identifiable {
        /// Spoken: an oval.
        case speech
        /// Shouted: a spiky burst.
        case shout
        /// Thought: a soft, scalloped outline, with bubbles for a tail.
        case thought
        /// The narrator: a box.
        case narration
        /// Words with no balloon, edged in white so they read over a picture.
        case none
        /// A sound effect: heavy white letters with a thick black edge, set
        /// tight, which may lean any way.
        case sound

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .speech: return L("ふつう", "Speech")
            case .shout: return L("叫び", "Shout")
            case .thought: return L("考え", "Thought")
            case .narration: return L("ナレーション", "Narration")
            case .none: return L("枠なし", "No Balloon")
            case .sound: return L("効果音", "Sound Effect")
            }
        }
    }

    public var id = 0
    /// A new line starts a new column, or a new line when written across.
    public var text: String
    /// The middle of the words, in canvas pixels.
    public var center: CGPoint
    /// The size of the letters.
    public var fontSize: CGFloat
    public var shape: Shape
    /// Where the tail points, such as the mouth of whoever speaks; nil for none.
    public var tail: CGPoint?
    /// Top to bottom, the columns right to left; false for across.
    public var vertical = true
    /// How far the letters lean, in radians, clockwise on the canvas. Only
    /// sound effects lean; balloons stay upright.
    public var angle: CGFloat = 0

    public init(id: Int = 0, text: String, center: CGPoint, fontSize: CGFloat, shape: Shape = .speech, tail: CGPoint? = nil, vertical: Bool = true, angle: CGFloat = 0) {
        self.id = id
        self.text = text
        self.center = center
        self.fontSize = fontSize
        self.shape = shape
        self.tail = tail
        self.vertical = vertical
        self.angle = angle
    }

    /// A size that reads well on a canvas this wide.
    public static func fontSize(forCanvasWidth width: Int) -> CGFloat {
        max(14, (CGFloat(width) / 36).rounded())
    }
}

/// Setting the words and drawing the balloon round them.
enum BalloonRenderer {
    private static func font(_ balloon: BalloonItem) -> CTFont {
        // A bold Mincho for spoken words and a light one for the narrator, as
        // comics use; the heaviest gothic for sound effects.
        let name: String
        switch balloon.shape {
        case .narration: name = "HiraMinProN-W3"
        case .sound: name = "HiraginoSans-W9"
        case .speech, .shout, .thought, .none: name = "HiraMinProN-W6"
        }
        return CTFontCreateWithName(name as CFString, balloon.fontSize, nil)
    }

    /// The width of the black edge round a sound effect's letters, half of it outside them.
    private static func edge(_ balloon: BalloonItem) -> CGFloat { balloon.fontSize * 0.28 }

    private static func words(_ balloon: BalloonItem, color: CGColor = CGColor(gray: 0, alpha: 1)) -> NSAttributedString {
        var spacing = balloon.fontSize * 0.2
        var alignment: CTTextAlignment = balloon.vertical ? .left : .center
        let style = withUnsafeBytes(of: &spacing) { spacingBytes in
            withUnsafeBytes(of: &alignment) { alignmentBytes in
                let settings = [
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: spacingBytes.baseAddress!),
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentBytes.baseAddress!),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(balloon),
            NSAttributedString.Key(kCTVerticalFormsAttributeName as String): balloon.vertical,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ]
        if balloon.shape == .sound {
            // Sound effects are set tight, the letters almost touching.
            attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = -balloon.fontSize * 0.05
        }
        return NSAttributedString(string: balloon.text.isEmpty ? " " : balloon.text, attributes: attributes)
    }

    private static func frameAttributes(_ balloon: BalloonItem) -> CFDictionary {
        let progression: CTFrameProgression = balloon.vertical ? .rightToLeft : .topToBottom
        return [kCTFrameProgressionAttributeName: progression.rawValue] as CFDictionary
    }

    /// The size the words take up.
    static func textSize(_ balloon: BalloonItem) -> CGSize {
        let setter = CTFramesetterCreateWithAttributedString(words(balloon))
        let lines = (balloon.text.isEmpty ? " " : balloon.text).split(separator: "\n", omittingEmptySubsequences: false)
        let longest = CGFloat(lines.map(\.count).max() ?? 1)
        // Down, each column is as tall as the longest, with room to spare in
        // a balloon, and just as tall for a sound effect, so it sits in the
        // middle; across, each line is as long as it needs.
        let constraint = balloon.vertical && balloon.shape != .sound
            ? CGSize(width: CGFloat.greatestFiniteMagnitude, height: longest * balloon.fontSize * 1.04 + balloon.fontSize * 0.4)
            : CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), frameAttributes(balloon), constraint, nil)
        return balloon.vertical && balloon.shape != .sound
            ? CGSize(width: ceil(fit.width) + 2, height: constraint.height)
            : CGSize(width: ceil(fit.width) + 2, height: ceil(fit.height) + 2)
    }

    /// The half widths of the balloon round the words, in canvas pixels.
    private static func radii(_ balloon: BalloonItem, text: CGSize) -> CGSize {
        let pad = balloon.fontSize * 0.7
        switch balloon.shape {
        case .narration: return CGSize(width: text.width / 2 + pad * 0.6, height: text.height / 2 + pad * 0.6)
        case .none, .sound: return CGSize(width: text.width / 2, height: text.height / 2)
        case .speech, .shout, .thought: return CGSize(width: text.width / 2 * 1.22 + pad, height: text.height / 2 * 1.12 + pad * 0.8)
        }
    }

    /// The area the balloon covers, tail and all.
    static func bounds(_ balloon: BalloonItem) -> CGRect {
        let r = radii(balloon, text: textSize(balloon))
        if balloon.shape == .sound {
            // The box round the leaning letters, and their edge.
            let c = abs(cos(balloon.angle)), s = abs(sin(balloon.angle))
            let half = CGSize(width: r.width * c + r.height * s, height: r.width * s + r.height * c)
            let reach = edge(balloon) / 2 + 1
            return CGRect(x: balloon.center.x - half.width, y: balloon.center.y - half.height, width: 2 * half.width, height: 2 * half.height)
                .insetBy(dx: -reach, dy: -reach)
        }
        let spikes: CGFloat = balloon.shape == .shout ? 1.3 : 1.05
        var area = CGRect(x: balloon.center.x - r.width * spikes, y: balloon.center.y - r.height * spikes, width: 2 * r.width * spikes, height: 2 * r.height * spikes)
        if let tip = tailTip(balloon, radii: r) {
            area = area.union(CGRect(origin: CGPoint(x: balloon.center.x + tip.x, y: balloon.center.y - tip.y), size: .zero))
        }
        return area.insetBy(dx: -line(balloon), dy: -line(balloon))
    }

    private static func line(_ balloon: BalloonItem) -> CGFloat { max(1.5, balloon.fontSize * 0.1) }

    /// The end of the tail from the middle, y up, kept to a modest length.
    private static func tailTip(_ balloon: BalloonItem, radii r: CGSize) -> CGPoint? {
        guard let tail = balloon.tail, ![.none, .narration, .sound].contains(balloon.shape) else { return nil }
        let d = CGPoint(x: tail.x - balloon.center.x, y: -(tail.y - balloon.center.y))
        let length = hypot(d.x, d.y)
        guard length > 1 else { return nil }
        let u = CGPoint(x: d.x / length, y: d.y / length)
        let edge = 1 / sqrt(pow(u.x / r.width, 2) + pow(u.y / r.height, 2))
        let reach = min(length, edge + min(r.width, r.height) * 0.9 + balloon.fontSize)
        return CGPoint(x: u.x * reach, y: u.y * reach)
    }

    /// Whether `point` is on the balloon, or on the leaning box of a sound effect.
    static func covers(_ balloon: BalloonItem, _ point: CGPoint, slack: CGFloat) -> Bool {
        guard balloon.shape == .sound else { return bounds(balloon).insetBy(dx: -slack, dy: -slack).contains(point) }
        // Turned back upright about the middle, the point must fall in the letters' box.
        let d = CGPoint(x: point.x - balloon.center.x, y: point.y - balloon.center.y)
        let c = cos(-balloon.angle), s = sin(-balloon.angle)
        let upright = CGPoint(x: d.x * c - d.y * s, y: d.x * s + d.y * c)
        let r = radii(balloon, text: textSize(balloon))
        let reach = edge(balloon) / 2 + slack
        return abs(upright.x) <= r.width + reach && abs(upright.y) <= r.height + reach
    }

    /// Draws the balloon into a canvas-coordinate context.
    static func draw(_ balloon: BalloonItem, in context: CGContext) {
        let text = textSize(balloon)
        let r = radii(balloon, text: text)
        context.saveGState()
        // Upright about the middle, so the words are set the right way up,
        // then leaning as far as a sound effect leans.
        context.translateBy(x: balloon.center.x, y: balloon.center.y)
        if balloon.shape == .sound { context.rotate(by: balloon.angle) }
        context.scaleBy(x: 1, y: -1)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        let parts = outline(balloon, radii: r)
        if !parts.isEmpty {
            // Outline under, white over, so the tail joins the body without a seam.
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(line(balloon) * 2)
            parts.forEach { context.addPath($0); context.strokePath() }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            parts.forEach { context.addPath($0); context.fillPath() }
        }
        let box = CGRect(x: -text.width / 2, y: -text.height / 2, width: text.width, height: text.height)
        func set(in color: CGColor) -> CTFrame {
            let setter = CTFramesetterCreateWithAttributedString(words(balloon, color: color))
            return CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), frameAttributes(balloon))
        }
        if balloon.shape == .sound {
            // A thick black edge under, the letters white over it.
            context.setTextDrawingMode(.stroke)
            context.setLineWidth(edge(balloon))
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            CTFrameDraw(set(in: CGColor(gray: 0, alpha: 1)), context)
            context.setTextDrawingMode(.fill)
            CTFrameDraw(set(in: CGColor(gray: 1, alpha: 1)), context)
            context.restoreGState()
            return
        }
        let frame = set(in: CGColor(gray: 0, alpha: 1))
        if balloon.shape == .none {
            context.setTextDrawingMode(.stroke)
            context.setLineWidth(balloon.fontSize * 0.25)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            CTFrameDraw(frame, context)
            context.setTextDrawingMode(.fill)
        }
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    /// The body and its tail, each a path of its own, about the middle with y up.
    private static func outline(_ balloon: BalloonItem, radii r: CGSize) -> [CGPath] {
        let body = CGMutablePath()
        switch balloon.shape {
        case .none, .sound:
            return []
        case .narration:
            body.addRect(CGRect(x: -r.width, y: -r.height, width: 2 * r.width, height: 2 * r.height))
        case .speech:
            body.addEllipse(in: CGRect(x: -r.width, y: -r.height, width: 2 * r.width, height: 2 * r.height))
        case .shout:
            let count = 22
            let points = (0..<(count * 2)).map { index -> CGPoint in
                let angle = CGFloat(index) / CGFloat(count * 2) * 2 * .pi
                let k: CGFloat = index % 2 == 0 ? 1.28 : 0.98
                return CGPoint(x: cos(angle) * r.width * k, y: sin(angle) * r.height * k)
            }
            body.addLines(between: points)
            body.closeSubpath()
        case .thought:
            let count = 16
            let bump = min(r.width, r.height) * 0.3
            for index in 0..<count {
                let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
                let p = CGPoint(x: cos(angle) * r.width * 0.92, y: sin(angle) * r.height * 0.92)
                body.addEllipse(in: CGRect(x: p.x - bump, y: p.y - bump, width: 2 * bump, height: 2 * bump))
            }
            body.addEllipse(in: CGRect(x: -r.width * 0.95, y: -r.height * 0.95, width: r.width * 1.9, height: r.height * 1.9))
        }
        guard let tip = tailTip(balloon, radii: r) else { return [body] }
        let length = hypot(tip.x, tip.y)
        let u = CGPoint(x: tip.x / length, y: tip.y / length)
        let n = CGPoint(x: -u.y, y: u.x)
        let edge = 1 / sqrt(pow(u.x / r.width, 2) + pow(u.y / r.height, 2))
        let tail = CGMutablePath()
        if balloon.shape == .thought {
            // Bubbles getting smaller toward the one who thinks.
            for (index, size) in [0.22, 0.14, 0.08].enumerated() {
                let along = edge + (length - edge) * CGFloat(index + 1) / 3.2
                let radius = min(r.width, r.height) * CGFloat(size)
                tail.addEllipse(in: CGRect(x: u.x * along - radius, y: u.y * along - radius, width: 2 * radius, height: 2 * radius))
            }
            return [body, tail]
        }
        let base = min(r.width, r.height) * 0.3
        let start = CGPoint(x: u.x * edge * 0.75, y: u.y * edge * 0.75)
        let bend = CGPoint(x: (start.x + tip.x) / 2 + n.x * base * 0.8, y: (start.y + tip.y) / 2 + n.y * base * 0.8)
        tail.move(to: CGPoint(x: start.x + n.x * base, y: start.y + n.y * base))
        tail.addQuadCurve(to: tip, control: bend)
        tail.addQuadCurve(to: CGPoint(x: start.x - n.x * base, y: start.y - n.y * base),
                          control: CGPoint(x: bend.x - n.x * base * 0.6, y: bend.y - n.y * base * 0.6))
        tail.closeSubpath()
        return [body, tail]
    }
}

extension CanvasDocument {
    /// Puts words in a balloon, or a sound effect, on the active layer. On a
    /// page divided into panels they go on a layer laid over the frames
    /// instead, made if there is none, so they can run across the panels.
    /// Returns the balloon.
    @discardableResult
    public func addBalloon(_ balloon: BalloonItem) -> Int? {
        guard liveStroke == nil, var index = layers.firstIndex(where: { $0.id == activeLayerID }) else { return nil }
        transaction {
            if library.page != nil, !layers[index].style.overPanels {
                if let over = layers.lastIndex(where: { $0.style.overPanels && $0.isVisible && !$0.isComposition }) {
                    index = over
                } else {
                    let made = insertLayer(named: L("吹き出し", "Balloons"), items: [], at: layers.count, style: LayerStyle(overPanels: true))
                    index = layers.firstIndex { $0.id == made } ?? index
                }
            }
            guard layers[index].isVisible else { return }
            appendItem(.balloon(balloon), toLayerAt: index, alreadyDrawn: false)
        }
        guard case .balloon(let made)? = layers[index].items.last else { return nil }
        activeLayerID = layers[index].id
        nextStepNote = L("\(LayerItem.balloon(made).title)を置いた", "Placed \(LayerItem.balloon(made).title)")
        invalidate(nil)
        return made.id
    }
}
