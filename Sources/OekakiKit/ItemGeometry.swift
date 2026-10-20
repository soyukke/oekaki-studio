import CoreGraphics
import Foundation

/// Where items lie on the canvas, so a spot on the picture can be traced
/// back to the item that put it there.
extension LayerItem {
    /// The area the item can touch, in canvas pixels.
    public func bounds(canvas: CGRect) -> CGRect {
        switch self {
        case .stroke(let stroke):
            guard let first = stroke.points.first else { return .null }
            var rect = CGRect(origin: first.point, size: .zero)
            for point in stroke.points.dropFirst() {
                rect = rect.union(CGRect(origin: point.point, size: .zero))
            }
            return rect.insetBy(dx: -stroke.width / 2, dy: -stroke.width / 2)
        case .fill(let fill):
            return fill.rect
        case .bitmap, .gradient:
            return canvas
        case .group(let group):
            return group.items.reduce(CGRect.null) { $0.union($1.bounds(canvas: canvas)) }
        case .instance(let instance):
            return instance.content.reduce(CGRect.null) { $0.union($1.bounds(canvas: canvas)) }
        }
    }

    /// Whether the item paints the pixel at `point`. Erasers never count:
    /// they take paint away rather than put it there.
    func paints(_ point: CGPoint, canvas: CGRect, slack: CGFloat) -> Bool {
        switch self {
        case .stroke(let stroke):
            guard !stroke.isEraser else { return false }
            let reach = stroke.width / 2 + slack
            let points = stroke.points.map(\.point)
            guard let first = points.first else { return false }
            if points.count == 1 { return hypot(first.x - point.x, first.y - point.y) <= reach }
            for index in 1..<points.count where Self.distance(from: point, to: points[index - 1], points[index]) <= reach {
                return true
            }
            return false
        case .fill(let fill):
            guard fill.rect.contains(point) else { return false }
            return Raster.sample(fill.full, covering: fill.rect, at: point) > 0
        case .bitmap(let image, let alpha, _):
            return alpha > 0 && Raster.sample(image, covering: canvas, at: point) > 0
        case .group(let group):
            return group.alpha > 0 && group.items.contains { $0.paints(point, canvas: canvas, slack: slack) }
        case .gradient(let gradient):
            return canvas.contains(point) && gradient.alpha(at: point) > 0.02
        case .instance(let instance):
            return instance.content.contains { $0.paints(point, canvas: canvas, slack: slack) }
        }
    }

    /// The front-most item at `point`, looking inside groups: the path from
    /// the outermost item to the innermost one. Empty when none paints there.
    static func path(to point: CGPoint, in items: [LayerItem], canvas: CGRect, slack: CGFloat) -> [Int] {
        for item in items.reversed() where item.paints(point, canvas: canvas, slack: slack) {
            return [item.id] + path(to: point, in: item.children, canvas: canvas, slack: slack)
        }
        return []
    }

    static func distance(from point: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = dx * dx + dy * dy
        guard length > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / length, 0), 1)
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

extension GradientItem {
    /// How far along from `start` to `end` a point is, 0...1.
    func share(at point: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        switch shape {
        case .linear:
            let length = dx * dx + dy * dy
            guard length > 0 else { return 0 }
            return min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / length, 0), 1)
        case .radial:
            let radius = max(hypot(dx, dy), 1)
            return min(hypot(point.x - start.x, point.y - start.y) / radius, 1)
        }
    }

    func alpha(at point: CGPoint) -> CGFloat {
        let t = share(at: point)
        return from.a + (to.a - from.a) * t
    }
}
