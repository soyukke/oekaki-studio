import CoreGraphics
import Foundation
import OekakiKit

/// How a line is drawn: its width at full pressure, its colour, and how
/// the pressure rises at the start and falls at the end.
struct Pen {
    var width: CGFloat
    var color: RGBA
    /// Share of the length over which the pressure rises from `floor`.
    var start: CGFloat = 0.15
    /// Share of the length over which the pressure falls back to `floor`.
    var end: CGFloat = 0.15
    /// The lightest pressure at either end.
    var floor: CGFloat = 0.15
    /// How much the whole stroke covers.
    var opacity: CGFloat = 1
    /// 0 for a hard edge, 1 for an airbrush.
    var softness: CGFloat = 0

    func with(
        width: CGFloat? = nil, color: RGBA? = nil, start: CGFloat? = nil, end: CGFloat? = nil, floor: CGFloat? = nil,
        opacity: CGFloat? = nil, softness: CGFloat? = nil
    ) -> Pen {
        Pen(
            width: width ?? self.width, color: color ?? self.color, start: start ?? self.start, end: end ?? self.end,
            floor: floor ?? self.floor, opacity: opacity ?? self.opacity, softness: softness ?? self.softness
        )
    }

    /// A soft brush of this diameter.
    static func airbrush(_ width: CGFloat, _ color: RGBA, opacity: CGFloat = 0.5) -> Pen {
        Pen(width: width, color: color, start: 0.2, end: 0.2, floor: 0.4, opacity: opacity, softness: 1)
    }

    func pressure(at share: CGFloat) -> CGFloat {
        func ease(_ x: CGFloat) -> CGFloat {
            let t = min(max(x, 0), 1)
            return t * t * (3 - 2 * t)
        }
        let rise = start > 0 ? ease(share / start) : 1
        let fall = end > 0 ? ease((1 - share) / end) : 1
        return floor + (1 - floor) * min(rise, fall)
    }
}

/// Draws on a document the way a person would: one stroke, one fill, one
/// layer at a time, each an action of its own, so the journal records the
/// picture being made.
final class Artist {
    let document: CanvasDocument
    /// From the coordinates the script is written in to the canvas.
    var transform = CGAffineTransform.identity
    /// Draw the next lines mirrored left to right about x = 0.
    var mirrored = false
    /// A last bend of the coordinates before `transform`, for things nearer
    /// the viewer and so drawn larger, such as what a figure holds out.
    var warp: ((CGPoint) -> CGPoint)?
    /// Canvas pixels per script unit, after `transform`: a picture written at
    /// one size and drawn at a larger one. Widths, sizes and areas grow with it.
    var unit: CGFloat = 1
    private var random = SplitMix(seed: 7)
    /// Fills that went wrong, for the report.
    private(set) var problems: [String] = []
    /// Every fill made, by name, with its id and area.
    private(set) var fills: [(name: String, id: Int, rect: CGRect)] = []

    init(document: CanvasDocument) {
        self.document = document
    }

    func canvas(_ point: CGPoint) -> CGPoint {
        var local = mirrored ? CGPoint(x: -point.x, y: point.y) : point
        if let warp { local = warp(local) }
        let placed = local.applying(transform)
        return CGPoint(x: placed.x * unit, y: placed.y * unit)
    }

    /// Adds a layer on top, makes it the one drawn on and returns its id.
    @discardableResult
    func layer(_ name: String, opacity: Double = 1, style: LayerStyle = LayerStyle(), below other: UUID? = nil) -> UUID {
        let index = other.flatMap { document.index(ofLayer: $0) } ?? document.layers.count
        var style = style
        style.glow *= unit
        style.blur *= unit
        let id = document.insertLayer(named: name, items: [], opacity: opacity, at: index, style: style)
        document.activeLayerID = id
        return id
    }

    func use(_ layer: UUID) {
        document.activeLayerID = layer
    }

    /// Draws one stroke along `data`. `wobble` shakes the hand by up to that
    /// many pixels, for lines that should look rough.
    @discardableResult
    func line(_ data: String, _ pen: Pen, wobble: CGFloat = 0) -> Int? {
        line(PathData.points(data), pen, wobble: wobble)
    }

    /// Returns the stroke's id.
    @discardableResult
    func line(_ local: [CGPoint], _ pen: Pen, wobble: CGFloat = 0) -> Int? {
        guard local.count > 0 else { return nil }
        var points = local.map(canvas)
        let wobble = wobble * unit
        if wobble > 0 {
            // A slow drift plus a little tremor, like a hand.
            let phase = random.next() * 6.28
            let speed = 0.05 + random.next() * 0.04
            points = points.enumerated().map { index, point in
                let drift = sin(CGFloat(index) * speed + phase) * wobble
                let tremor = (random.next() - 0.5) * wobble * 0.5
                return CGPoint(x: point.x + drift + tremor, y: point.y + cos(CGFloat(index) * speed * 1.3 + phase) * wobble * 0.7 + tremor)
            }
        }
        let count = CGFloat(max(points.count - 1, 1))
        let strokePoints = points.enumerated().map { index, point in
            StrokePoint(x: point.x, y: point.y, pressure: pen.pressure(at: CGFloat(index) / count))
        }
        guard document.beginStroke(
            at: strokePoints[0], color: pen.color, width: pen.width * unit, isEraser: false, opacity: pen.opacity, softness: pen.softness
        ) else {
            problems.append("Could not draw on the active layer")
            return nil
        }
        for point in strokePoints.dropFirst() {
            document.continueStroke(to: point)
        }
        document.endStroke()
        return document.activeLayer?.items.last?.id
    }

    /// A gradient over the active layer, its points in script coordinates.
    func gradient(_ shape: GradientItem.Shape, from start: CGPoint, to end: CGPoint, _ first: RGBA, _ last: RGBA) {
        let item = GradientItem(shape: shape, start: canvas(start), end: canvas(end), from: first, to: last)
        if !document.addGradient(item) { problems.append("Could not lay a gradient") }
    }

    /// A round dab, such as a highlight in an eye.
    func dot(_ x: CGFloat, _ y: CGFloat, diameter: CGFloat, color: RGBA) {
        let center = CGPoint(x: x, y: y)
        line([center, CGPoint(x: x + 0.6, y: y + 0.6)], Pen(width: diameter, color: color, start: 0, end: 0, floor: 1))
    }

    /// Fills the area a closed outline goes round, with soft edges and no
    /// lines: the lasso fill, for shapes of shadow and light.
    @discardableResult
    func shape(_ local: [CGPoint], _ color: RGBA) -> Int? {
        let points = local.map(canvas)
        guard document.fillShape(points, color: color) else {
            let xs = points.map(\.x), ys = points.map(\.y)
            problems.append(String(format: "shape of %d points in (%.0f…%.0f, %.0f…%.0f) filled nothing on 「%@」",
                                   points.count, xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0, document.activeLayer?.name ?? "?"))
            return nil
        }
        return document.activeLayer?.items.last?.id
    }

    @discardableResult
    func shape(_ data: String, _ color: RGBA) -> Int? {
        shape(PathData.points(data, spacing: 1.5), color)
    }

    /// A line drawn as a filled shape whose width at each point along it is
    /// `width(t)`, t from 0 at the start to 1 at the end. It can come to a
    /// finer point than a pen, for lashes, the tips of hair and pointed shadows.
    @discardableResult
    func ribbon(_ local: [CGPoint], _ color: RGBA, width: (CGFloat) -> CGFloat) -> Int? {
        shape(Ribbon.outline(PathData.resampled(local, spacing: 1), width: width), color)
    }

    @discardableResult
    func ribbon(_ data: String, _ color: RGBA, width: (CGFloat) -> CGFloat) -> Int? {
        ribbon(PathData.points(data, spacing: 1.5), color, width: width)
    }

    /// Paint-bucket fill at a point. `limit` is the largest area, in canvas
    /// pixels, the region should cover; a bigger one means a leak. The lines
    /// are drawn closed, so only a small gap is closed, and the paint reaches
    /// into sharp corners such as the tips of the hair.
    @discardableResult
    func fill(_ name: String, _ x: CGFloat, _ y: CGFloat, _ color: RGBA, limit: CGFloat = .infinity, gap: Int = 1) -> Int? {
        let point = canvas(CGPoint(x: x, y: y))
        guard document.fill(at: point, color: color, gap: gap),
              let layer = document.activeLayer, let item = layer.items.last
        else {
            problems.append("fill \(name) at \(point) filled nothing")
            return nil
        }
        let rect = item.bounds(canvas: document.bounds)
        fills.append((name, item.id, rect))
        if rect.width * rect.height > limit * unit * unit {
            problems.append("fill \(name) at \(point) leaked: \(rect)")
        }
        return item.id
    }
}

/// Repeatable random numbers, so every run draws the same picture.
struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A number in 0..<1.
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

/// Outlines for lines drawn as shapes, and the widths they swell and taper by.
enum Ribbon {
    /// The outline round `line`, `width(t)` wide at each point.
    static func outline(_ line: [CGPoint], width: (CGFloat) -> CGFloat) -> [CGPoint] {
        guard line.count >= 2 else { return line }
        var lengths: [CGFloat] = [0]
        for (a, b) in zip(line, line.dropFirst()) { lengths.append(lengths.last! + hypot(b.x - a.x, b.y - a.y)) }
        let total = max(lengths.last!, 0.001)
        var left: [CGPoint] = [], right: [CGPoint] = []
        for index in line.indices {
            let before = line[max(index - 1, 0)], after = line[min(index + 1, line.count - 1)]
            let run = max(hypot(after.x - before.x, after.y - before.y), 0.001)
            let normal = CGPoint(x: -(after.y - before.y) / run, y: (after.x - before.x) / run)
            let half = max(width(lengths[index] / total), 0) / 2
            left.append(CGPoint(x: line[index].x + normal.x * half, y: line[index].y + normal.y * half))
            right.append(CGPoint(x: line[index].x - normal.x * half, y: line[index].y - normal.y * half))
        }
        return left + right.reversed()
    }

    /// Swells to `widest` in the middle and comes to a point at both ends, like a leaf.
    static func leaf(_ widest: CGFloat, at middle: CGFloat = 0.5) -> (CGFloat) -> CGFloat {
        { t in
            let s = t < middle ? t / middle : (1 - t) / (1 - middle)
            return widest * sqrt(max(0, sin(min(s, 1) * .pi / 2)))
        }
    }

    /// Full at the start, coming to a point at the end.
    static func taper(_ widest: CGFloat, holding: CGFloat = 0.2) -> (CGFloat) -> CGFloat {
        { t in t < holding ? widest : widest * max(0, (1 - t) / (1 - holding)) }
    }

    /// From `start` to `end` wide, smoothly.
    static func between(_ start: CGFloat, _ end: CGFloat) -> (CGFloat) -> CGFloat {
        { t in start + (end - start) * t * t * (3 - 2 * t) }
    }
}
