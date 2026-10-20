import CoreGraphics
import Foundation

/// Moving, resizing, turning and recolouring items after they were drawn.
extension LayerItem {
    /// The item moved by `t`, a combination of moving, scaling, turning and
    /// mirroring. Line widths follow the scale. A picture with no steps behind
    /// it, and fills, are redrawn through the change.
    public func transformed(by t: CGAffineTransform) -> LayerItem {
        if t.isIdentity { return self }
        let scale = sqrt(abs(t.a * t.d - t.b * t.c))
        switch self {
        case .stroke(var stroke):
            stroke.points = stroke.points.map { point in
                let moved = point.point.applying(t)
                return StrokePoint(x: moved.x, y: moved.y, pressure: point.pressure)
            }
            stroke.width *= scale
            return .stroke(stroke)
        case .fill(var fill):
            // A plain move keeps the masks as they are.
            if t.a == 1, t.b == 0, t.c == 0, t.d == 1, t.tx == t.tx.rounded(), t.ty == t.ty.rounded() {
                fill.rect = fill.rect.offsetBy(dx: t.tx, dy: t.ty)
                fill.seed = fill.seed?.applying(t)
                return .fill(fill)
            }
            let area = fill.rect.applying(t).integral
            guard area.width >= 1, area.height >= 1,
                  let full = Self.transformedMask(fill.full, from: fill.rect, to: area, by: t),
                  let interior = Self.transformedMask(fill.interior, from: fill.rect, to: area, by: t)
            else { return self }
            fill.rect = area
            fill.full = full
            fill.interior = interior
            fill.seed = fill.seed?.applying(t)
            return .fill(fill)
        case .gradient(var gradient):
            gradient.start = gradient.start.applying(t)
            gradient.end = gradient.end.applying(t)
            return .gradient(gradient)
        case .group(var group):
            group.items = group.items.map { $0.transformed(by: t) }
            return .group(group)
        case .instance(var instance):
            // A use of a part moves as a whole: its placement changes.
            let center = instance.placement.center.applying(t)
            let turn = atan2(t.b, t.a) * 180 / .pi
            let mirrored = t.a * t.d - t.b * t.c < 0
            instance.placement.center = center
            instance.placement.scale *= scale
            instance.placement.rotation += turn
            if mirrored { instance.placement.flipped.toggle() }
            instance.content = instance.content.map { $0.transformed(by: t) }
            return .instance(instance)
        case .bitmap(let image, let alpha, let id):
            let side = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let context = Raster.makeLayerContext(width: image.width, height: image.height)
            context.concatenate(t)
            Raster.upright(side, in: context) { context.draw(image, in: side) }
            return .bitmap(context.makeImage() ?? image, alpha: alpha, id: id)
        }
    }

    /// A grey mask covering `from`, redrawn through `t` onto `to`.
    private static func transformedMask(_ mask: CGImage, from: CGRect, to: CGRect, by t: CGAffineTransform) -> CGImage? {
        let width = Int(to.width), height = Int(to.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // Canvas coordinates, with y down, shifted to the new area.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -to.minX, y: -to.minY)
        context.concatenate(t)
        Raster.upright(from, in: context) { context.draw(mask, in: from) }
        // Keep the mask hard, as the paint bucket makes it.
        guard let soft = context.makeImage(), let data = soft.dataProvider?.data else { return nil }
        var bytes = [UInt8](data as Data)
        for index in bytes.indices { bytes[index] = bytes[index] >= 128 ? 255 : 0 }
        return Raster.maskImage(bytes: Data(bytes), width: soft.bytesPerRow, height: height)?.cropping(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// A stroke with its bends and wobbles made stronger (`factor` over 1)
    /// or calmer (under 1): each point moves away from, or toward, a smoothed
    /// copy of the line. The ends of an open line stay where they are.
    public func withWaviness(_ factor: CGFloat) -> LayerItem {
        switch self {
        case .stroke(var stroke) where stroke.points.count > 2:
            let points = stroke.points
            // The length of the line, to tell a closed line from an open one.
            let total = max(zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }, 0.001)
            let first = points[0], last = points[points.count - 1]
            // The wobble is measured from a smoothed copy of the line, wrapping
            // round a closed one such as an eye, so the waves grow while the
            // course, such as the sweep of a strand of hair, stays.
            let isClosed = hypot(last.x - first.x, last.y - first.y) < total * 0.1
            let calm = Self.smoothed(points.map(\.point), radius: max(3, points.count / 10), wrapping: isClosed)
            // Stronger also starts a gentle wave on an open line, so a smooth
            // line gains waves instead of staying as it was. Its ends stay.
            // Each point's sideways direction and its share of a wave along the line.
            var along: CGFloat = 0
            let sides = points.indices.map { index -> (normal: CGPoint, wave: CGFloat) in
                if index > 0 { along += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y) }
                let before = calm[max(index - 1, 0)], after = calm[min(index + 1, points.count - 1)]
                let run = max(hypot(after.x - before.x, after.y - before.y), 0.001)
                return (CGPoint(x: -(after.y - before.y) / run, y: (after.x - before.x) / run), sin(3 * .pi * along / total))
            }
            // The new wave goes the way the line already waves, never against it.
            let agrees = points.indices.reduce(CGFloat(0)) { sum, index in
                let away = CGPoint(x: points[index].x - calm[index].x, y: points[index].y - calm[index].y)
                return sum + (away.x * sides[index].normal.x + away.y * sides[index].normal.y) * sides[index].wave
            }
            let swell = (isClosed ? 0 : max(factor - 1, 0) * total * 0.012) * (agrees < 0 ? -1 : 1)
            stroke.points = points.indices.map { index in
                let course = calm[index]
                let point = points[index]
                let push = swell * sides[index].wave
                return StrokePoint(
                    x: course.x + (point.x - course.x) * factor + sides[index].normal.x * push,
                    y: course.y + (point.y - course.y) * factor + sides[index].normal.y * push,
                    pressure: point.pressure
                )
            }
            return .stroke(stroke)
        case .group(var group):
            group.items = group.items.map { $0.withWaviness(factor) }
            return .group(group)
        default:
            return self
        }
    }

    /// The points averaged over their neighbours, wrapping round a closed
    /// line. On an open line the window shrinks toward the ends, which stay put.
    private static func smoothed(_ points: [CGPoint], radius: Int, wrapping: Bool) -> [CGPoint] {
        let count = points.count
        return points.indices.map { index in
            let reach = wrapping ? radius : min(radius, index, count - 1 - index)
            var x: CGFloat = 0, y: CGFloat = 0
            for offset in -reach...reach {
                let point = points[(index + offset + count) % count]
                x += point.x
                y += point.y
            }
            let n = CGFloat(2 * reach + 1)
            return CGPoint(x: x / n, y: y / n)
        }
    }

    /// The colour that a named colour gives, keeping this item's own alpha.
    private static func resolve(_ ref: UUID?, _ current: RGBA, _ colors: [UUID: RGBA]) -> RGBA {
        guard let ref, let named = colors[ref] else { return current }
        return RGBA(r: named.r, g: named.g, b: named.b, a: current.a)
    }

    /// The item with every named colour it uses set to its value in `colors`.
    public func recolored(_ colors: [UUID: RGBA]) -> LayerItem {
        switch self {
        case .stroke(var stroke):
            stroke.color = Self.resolve(stroke.colorRef, stroke.color, colors)
            return .stroke(stroke)
        case .fill(var fill):
            fill.color = Self.resolve(fill.colorRef, fill.color, colors)
            return .fill(fill)
        case .gradient(var gradient):
            gradient.from = Self.resolve(gradient.fromRef, gradient.from, colors)
            gradient.to = Self.resolve(gradient.toRef, gradient.to, colors)
            return .gradient(gradient)
        case .group(var group):
            group.items = group.items.map { $0.recolored(colors) }
            return .group(group)
        case .instance(var instance):
            // This use's own colours win over the shared ones.
            let own = colors.merging(instance.overrides) { _, mine in mine }
            instance.content = instance.content.map { $0.recolored(own) }
            return .instance(instance)
        case .bitmap:
            return self
        }
    }

    /// The named colours the item, and anything inside it, uses.
    public var colorRefs: Set<UUID> {
        switch self {
        case .stroke(let stroke): return stroke.colorRef.map { [$0] } ?? []
        case .fill(let fill): return fill.colorRef.map { [$0] } ?? []
        case .gradient(let gradient): return Set([gradient.fromRef, gradient.toRef].compactMap { $0 })
        case .group(let group): return group.items.reduce(into: Set<UUID>()) { $0.formUnion($1.colorRefs) }
        case .instance(let instance): return instance.content.reduce(into: Set<UUID>()) { $0.formUnion($1.colorRefs) }
        case .bitmap: return []
        }
    }

    /// Which end of a gradient a named colour goes to.
    public enum GradientEnd {
        case start, end, both
    }

    /// The item taking its colour from a named colour. A gradient takes it at
    /// `end`, each end keeping its own transparency.
    public func bound(to swatch: Swatch, gradientEnd: GradientEnd = .both) -> LayerItem {
        switch self {
        case .stroke(var stroke) where !stroke.isEraser:
            stroke.colorRef = swatch.id
            return LayerItem.stroke(stroke).recolored([swatch.id: swatch.color])
        case .fill(var fill):
            fill.colorRef = swatch.id
            return LayerItem.fill(fill).recolored([swatch.id: swatch.color])
        case .gradient(var gradient):
            if gradientEnd != .end { gradient.fromRef = swatch.id }
            if gradientEnd != .start { gradient.toRef = swatch.id }
            return LayerItem.gradient(gradient).recolored([swatch.id: swatch.color])
        case .group(var group):
            group.items = group.items.map { $0.bound(to: swatch, gradientEnd: gradientEnd) }
            return .group(group)
        default:
            return self
        }
    }
}
