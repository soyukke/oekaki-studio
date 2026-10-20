import CoreGraphics
import Foundation
import OekakiKit

/// What she holds out to the viewer, nearest of all, in sheet units. Both her
/// elbows rest on the table. Her near forearm rises to the spoon, which she
/// holds out tip first, heaped with ice cream, just under her chin; her other
/// hand waits under it, cupped, and a drop has already fallen into it.
enum Near {
    // MARK: Helpers

    /// A smooth line through `points`, `count` points to each stretch between them.
    static func smooth(_ points: [CGPoint], count: Int = 16) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var line: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            for k in 0..<count {
                let t = CGFloat(k) / CGFloat(count), t2 = t * t, t3 = t2 * t
                func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
                }
                line.append(CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        line.append(points[points.count - 1])
        return line
    }

    /// A finger round a spine through `joints`, `widths` across at each, its tip
    /// rounded off. The outline runs up one side from the root, round the tip
    /// and back down the other; the root is left open, for it goes under a cuff.
    static func finger(_ joints: [CGPoint], _ widths: [CGFloat]) -> [CGPoint] {
        let count = 16
        let spine = joints.count > 2 ? smooth(joints, count: count) : PathData.resampled(joints, spacing: 1)
        var left: [CGPoint] = [], right: [CGPoint] = []
        for k in spine.indices {
            let share = CGFloat(k) / CGFloat(max(spine.count - 1, 1)) * CGFloat(joints.count - 1)
            let segment = min(Int(share), joints.count - 2)
            let width = widths[segment] + (widths[segment + 1] - widths[segment]) * (share - CGFloat(segment))
            let before = spine[max(k - 1, 0)], after = spine[min(k + 1, spine.count - 1)]
            let run = max(hypot(after.x - before.x, after.y - before.y), 0.001)
            let normal = CGPoint(x: -(after.y - before.y) / run, y: (after.x - before.x) / run)
            left.append(CGPoint(x: spine[k].x + normal.x * width / 2, y: spine[k].y + normal.y * width / 2))
            right.append(CGPoint(x: spine[k].x - normal.x * width / 2, y: spine[k].y - normal.y * width / 2))
        }
        let tip = spine[spine.count - 1], before = spine[spine.count - 3]
        let forward = atan2(tip.y - before.y, tip.x - before.x)
        let half = widths[widths.count - 1] / 2
        let cap = (1..<24).map { k -> CGPoint in
            let angle = forward + .pi / 2 - .pi * CGFloat(k) / 24
            return CGPoint(x: tip.x + half * cos(angle), y: tip.y + half * sin(angle))
        }
        return PathData.resampled(left + cap + right.reversed(), spacing: 1)
    }

    /// A strip along a finger, between `from` and `to` across it: -0.5 is
    /// its right edge as it points, 0.5 its left.
    static func fingerStrip(_ joints: [CGPoint], _ widths: [CGFloat], from: CGFloat, to: CGFloat) -> [CGPoint] {
        let count = 16
        let spine = joints.count > 2 ? smooth(joints, count: count) : PathData.resampled(joints, spacing: 1)
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for k in spine.indices {
            let share = CGFloat(k) / CGFloat(max(spine.count - 1, 1)) * CGFloat(joints.count - 1)
            let segment = min(Int(share), joints.count - 2)
            let width = widths[segment] + (widths[segment + 1] - widths[segment]) * (share - CGFloat(segment))
            let before = spine[max(k - 1, 0)], after = spine[min(k + 1, spine.count - 1)]
            let run = max(hypot(after.x - before.x, after.y - before.y), 0.001)
            let normal = CGPoint(x: -(after.y - before.y) / run, y: (after.x - before.x) / run)
            // Rounding off toward the tip, as the finger does.
            let round = min(1, CGFloat(spine.count - 1 - k) / 10)
            outer.append(CGPoint(x: spine[k].x + normal.x * width * from * round, y: spine[k].y + normal.y * width * from * round))
            inner.append(CGPoint(x: spine[k].x + normal.x * width * to * round, y: spine[k].y + normal.y * width * to * round))
        }
        return outer + inner.reversed()
    }

    /// A nail on a finger through `joints`, near its tip, on the side `side` (1
    /// is the finger's left as it points), `width` the finger's width there.
    static func nail(_ joints: [CGPoint], width: CGFloat, side: CGFloat, length: CGFloat) -> [CGPoint] {
        let tip = joints[joints.count - 1], before = joints[joints.count - 2]
        let run = max(hypot(tip.x - before.x, tip.y - before.y), 0.001)
        let along = CGPoint(x: (tip.x - before.x) / run, y: (tip.y - before.y) / run)
        let normal = CGPoint(x: -along.y, y: along.x)
        let center = CGPoint(x: tip.x - along.x * length * 0.25 + normal.x * side * width * 0.2, y: tip.y - along.y * length * 0.25 + normal.y * side * width * 0.2)
        return (0...48).map { k -> CGPoint in
            let angle = 2 * CGFloat.pi * CGFloat(k) / 48
            let a = length / 2 * cos(angle), b = width * 0.17 * sin(angle)
            return CGPoint(x: center.x + along.x * a + normal.x * b, y: center.y + along.y * a + normal.y * b)
        }
    }

    /// The smallest convex outline round all the points.
    static func hull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func turn(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Whether the point is inside the closed outline.
    static func inside(_ p: CGPoint, _ shape: [CGPoint]) -> Bool {
        var result = false
        var j = shape.count - 1
        for i in shape.indices {
            let a = shape[i], b = shape[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { result.toggle() }
            j = i
        }
        return result
    }

    /// The stretches of `line` that none of the shapes in front of it cover,
    /// so a finger's line stops where the finger before it overlaps it.
    static func visible(_ line: [CGPoint], behind front: [[CGPoint]]) -> [[CGPoint]] {
        var runs: [[CGPoint]] = [], run: [CGPoint] = []
        for p in PathData.resampled(line, spacing: 1) {
            if front.contains(where: { inside(p, $0) }) {
                if run.count > 8 { runs.append(run) }
                run = []
            } else {
                run.append(p)
            }
        }
        if run.count > 8 { runs.append(run) }
        return runs
    }

    /// Draws the outlines of shapes stacked back to front, each only where those before it in front leave it showing.
    static func stacked(_ a: Artist, _ outlines: [[CGPoint]], covers: [[CGPoint]] = [], _ pen: Pen) {
        for (k, outline) in outlines.enumerated() {
            for run in visible(outline, behind: Array(outlines[(k + 1)...]) + covers) { a.line(run, pen) }
        }
    }

    /// Lines of knit rib running along a sleeve, between its two edges, both
    /// given from the same end; they stop short of either end.
    static func ribs(_ one: [CGPoint], _ other: [CGPoint], count: Int) -> [[CGPoint]] {
        let n = 60
        func sample(_ line: [CGPoint], _ t: CGFloat) -> CGPoint { line[min(line.count - 1, Int(t * CGFloat(line.count - 1)))] }
        return (1..<count).map { k -> [CGPoint] in
            let share = CGFloat(k) / CGFloat(count)
            return (0...n).compactMap { i -> CGPoint? in
                let t = 0.08 + 0.84 * CGFloat(i) / CGFloat(n)
                let p = sample(one, t), q = sample(other, t)
                return CGPoint(x: p.x + (q.x - p.x) * share, y: p.y + (q.y - p.y) * share)
            }
        }
    }

    // MARK: Nearness

    /// Everything she holds out is nearer the viewer than she is, and the
    /// nearer, the larger: the spoon and her hands are drawn bigger round where
    /// they meet, easing back to life size toward her elbows.
    static var focus: CGPoint { bowl }
    static let enlarge: CGFloat = 1

    static func lens(_ p: CGPoint) -> CGPoint {
        let dx = p.x - focus.x, dy = p.y - focus.y
        let t = min(1, max(0, (hypot(dx, dy) - 120) / 400))
        let m = enlarge + (1 - enlarge) * t * t * (3 - 2 * t)
        return CGPoint(x: focus.x + dx * m, y: focus.y + dy * m)
    }

    // MARK: The spoon, in three dimensions

    /// A direction in the picture: x to the right, y down the sheet, z toward the viewer.
    struct Direction {
        var x: CGFloat, y: CGFloat, z: CGFloat
        var normalized: Direction {
            let length = (x * x + y * y + z * z).squareRoot()
            return Direction(x: x / length, y: y / length, z: z / length)
        }
        func dot(_ other: Direction) -> CGFloat { x * other.x + y * other.y + z * other.z }
        func cross(_ other: Direction) -> Direction {
            Direction(x: y * other.z - z * other.y, y: z * other.x - x * other.z, z: x * other.y - y * other.x)
        }
    }

    /// Along the spoon from its bowl to her hand: up and to the right on the
    /// sheet, but mostly away from the viewer, for she points the tip at them.
    static let along = Direction(x: 0.42, y: -0.32, z: -0.85).normalized
    /// Up out of the bowl, tipped a little toward the viewer, who looks down into it.
    static let up: Direction = {
        let rough = Direction(x: 0.1, y: -0.6, z: 0.8)
        let k = rough.dot(along)
        return Direction(x: rough.x - k * along.x, y: rough.y - k * along.y, z: rough.z - k * along.z).normalized
    }()
    /// Across the bowl; its positive side is the one nearer the viewer.
    static let across = up.cross(along)
    /// The middle of the bowl's rim on the sheet.
    static let bowl = CGPoint(x: 500, y: 1036)
    /// How big the spoon is drawn: she holds it out right in front of the viewer's mouth.
    static let spoonScale: CGFloat = 1.86

    /// A point given in the spoon's own space, on the sheet: `u` along the
    /// spoon toward her hand, `v` across it, `w` up out of the bowl.
    static func place(_ u: CGFloat, _ v: CGFloat, _ w: CGFloat) -> CGPoint {
        let k = spoonScale
        return CGPoint(x: bowl.x + k * (u * along.x + v * across.x + w * up.x), y: bowl.y + k * (u * along.y + v * across.y + w * up.y))
    }

    /// How much nearer the viewer than the bowl's middle such a point is.
    static func nearness(_ u: CGFloat, _ v: CGFloat, _ w: CGFloat) -> CGFloat {
        u * along.z + v * across.z + w * up.z
    }

    static let tipReach: CGFloat = 92, neckReach: CGFloat = 120, halfWidth: CGFloat = 70

    /// A point of the rim in the spoon's own space, `t` 0 at the neck and π at
    /// the tip: an egg, round at the tip and drawn out toward the neck.
    static func rimSpot(_ t: CGFloat, inset: CGFloat = 0) -> (u: CGFloat, v: CGFloat) {
        let c = cos(t)
        return (((c >= 0 ? neckReach : tipReach) - inset) * c, (halfWidth - inset) * sin(t) * (1 - 0.26 * c))
    }

    static func rim(_ t: CGFloat, inset: CGFloat = 0) -> CGPoint {
        let spot = rimSpot(t, inset: inset)
        return place(spot.u, spot.v, 0)
    }

    static let bowlOutline: [CGPoint] = PathData.resampled((0...360).map { rim(2 * .pi * CGFloat($0) / 360) }, spacing: 1.5)

    /// The half of a ring round the bowl nearer the viewer, or the far half,
    /// split where the ring turns as seen along `up`; both run the same way.
    static func half(near: Bool, inset: CGFloat) -> [CGPoint] {
        let count = 720
        let turns = (0..<count).map { 2 * CGFloat.pi * CGFloat($0) / CGFloat(count) }
        let side = CGPoint(x: -up.y, y: up.x)
        let reach = turns.map { t -> CGFloat in
            let p = rim(t, inset: inset)
            return (p.x - bowl.x) * side.x + (p.y - bowl.y) * side.y
        }
        let first = reach.indices.min { reach[$0] < reach[$1] }!, last = reach.indices.max { reach[$0] < reach[$1] }!
        func walk(_ step: Int) -> [Int] {
            var index = first, indices: [Int] = []
            while index != last {
                indices.append(index)
                index = (index + step + count) % count
            }
            return indices + [last]
        }
        func nearness(of indices: [Int]) -> CGFloat {
            let spot = rimSpot(turns[indices[indices.count / 2]], inset: inset)
            return Near.nearness(spot.u, spot.v, 0)
        }
        let forward = walk(1), backward = walk(-1)
        let nearer = nearness(of: forward) > nearness(of: backward) ? forward : backward
        let chosen = near ? nearer : (nearer == forward ? backward : forward)
        return chosen.map { rim(turns[$0], inset: inset) }
    }

    /// The bowl's near lip, which passes in front of the scoop's foot.
    static var lip: [CGPoint] {
        PathData.resampled(half(near: true, inset: -1) + half(near: true, inset: 8).reversed(), spacing: 1.5)
    }

    static let handleStart: CGFloat = 104, handleLength: CGFloat = 380

    /// A point along the handle, `s` 0 where it leaves the bowl and 1 at its
    /// end, `side` -1 to 1 across it. It flares into the bowl, is narrowest
    /// just after, widens toward its end and bends up a little.
    static func handleSpot(_ s: CGFloat, side: CGFloat) -> CGPoint {
        let along = s * handleLength / 220
        let half = 6.5 + 10 * pow(min(along, 1.2), 1.2) + 16 * exp(-along * 22)
        return place(handleStart + s * handleLength, side * half, 26 * min(along, 1))
    }

    static var handle: [CGPoint] {
        let steps = 80
        let near = (0...steps).map { handleSpot(CGFloat($0) / CGFloat(steps), side: 1) }
        let far = (0...steps).map { handleSpot(CGFloat($0) / CGFloat(steps), side: -1) }
        return PathData.resampled(near + far.reversed() + [near[0]], spacing: 1.5)
    }

    // MARK: The ice cream, heaped in the bowl

    static let scoopMiddle = (u: CGFloat(-10), v: CGFloat(2))
    static let scoopReach = (u: CGFloat(72), v: CGFloat(54))
    static let scoopHeight: CGFloat = 82
    static let scoopFoot: CGFloat = -10

    /// A point on the scoop, `r` 0 at its top to 1 at its foot, `angle` round it, in the spoon's space.
    static func scoopSpot(_ r: CGFloat, _ angle: CGFloat) -> (u: CGFloat, v: CGFloat, w: CGFloat) {
        let lump = 1 + 0.05 * sin(3 * angle + 0.6) + 0.03 * sin(7 * angle + 1.9)
        let u = scoopMiddle.u + scoopReach.u * r * cos(angle) * lump
        let v = scoopMiddle.v + scoopReach.v * r * sin(angle) * lump
        let w = scoopFoot + scoopHeight * pow(max(0, 1 - r * r), 0.42) * (1 + 0.05 * sin(2 * angle + 0.5))
        return (u, v, w)
    }

    /// How squarely the scoop's surface there faces the viewer, -1 to 1.
    static func facing(_ r: CGFloat, _ angle: CGFloat) -> CGFloat {
        let rr = min(r, 0.995)
        let nu = rr * cos(angle) / scoopReach.u, nv = rr * sin(angle) / scoopReach.v, nw = (1 - rr * rr).squareRoot() / scoopHeight
        let length = (nu * nu + nv * nv + nw * nw).squareRoot()
        return (nu * along.z + nv * across.z + nw * up.z) / length
    }

    /// The near lip's outer edge as a height for each x across the bowl.
    static let lipEdge: [CGPoint] = half(near: true, inset: -1).sorted { $0.x < $1.x }

    static func lipY(at x: CGFloat) -> CGFloat? {
        guard let first = lipEdge.first, let last = lipEdge.last, x >= first.x, x <= last.x else { return nil }
        let after = lipEdge.firstIndex { $0.x >= x } ?? lipEdge.count - 1
        let b = lipEdge[after], a = lipEdge[max(after - 1, 0)]
        let t = b.x - a.x > 0.001 ? (x - a.x) / (b.x - a.x) : 0
        return a.y + (b.y - a.y) * t
    }

    /// The scoop's outline on the sheet, soft and lumpy as ice cream is, its
    /// foot tucked behind the bowl's near lip.
    static let scoop: [CGPoint] = {
        var points: [CGPoint] = []
        for i in 0...40 {
            for j in 0..<180 {
                let s = scoopSpot(CGFloat(i) / 40, 2 * .pi * CGFloat(j) / 180)
                points.append(place(s.u, s.v, s.w))
            }
        }
        let convex = hull(points)
        let outline = PathData.resampled(convex + [convex[0]], spacing: 1.5)
        let middle = CGPoint(x: outline.map(\.x).reduce(0, +) / CGFloat(outline.count), y: outline.map(\.y).reduce(0, +) / CGFloat(outline.count))
        return outline.map { p in
            let angle = atan2(p.y - middle.y, p.x - middle.x)
            let push = 1 + 0.026 * sin(5 * angle + 0.5) + 0.016 * sin(9 * angle + 2) + 0.012 * sin(17 * angle + 1) + 0.008 * sin(29 * angle + 0.3) + 0.005 * sin(47 * angle)
            var q = CGPoint(x: middle.x + (p.x - middle.x) * push, y: middle.y + (p.y - middle.y) * push)
            if let lip = lipY(at: q.x), q.y > lip - 3 { q.y = lip - 3 }
            return q
        }
    }()

    static var scoopBox: CGRect { scoop.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) } }

    /// Where the scoop turns from the window into its own shade: a wavy line
    /// from high on the left, down across it to low on the right, and all
    /// below it, out past the outline (the layer is clipped to the scoop).
    static var scoopShadow: [CGPoint] {
        let box = scoopBox
        let line = (0...60).map { k -> CGPoint in
            let t = CGFloat(k) / 60
            // From high on the left, down through the middle, to low on the right.
            let x = box.minX + box.width * (0.22 + 0.86 * t)
            let y = box.minY + box.height * (0.08 + 0.78 * pow(t, 1.6)) + 4 * sin(t * 13 + 1)
            return CGPoint(x: x, y: y)
        }
        return line + [CGPoint(x: box.maxX + 40, y: box.maxY + 40), CGPoint(x: box.minX - 40, y: box.maxY + 40), CGPoint(x: box.minX - 40, y: box.minY - 20)]
    }

    /// The top of the scoop, toward the light: everything above a wavy line
    /// across its upper part (the layer is clipped to the scoop).
    static var scoopTopPlane: [CGPoint] {
        let box = scoopBox
        let line = (0...60).map { k -> CGPoint in
            let t = CGFloat(k) / 60
            let x = box.minX + box.width * (0.25 + 0.85 * t)
            let y = box.minY + box.height * (0.04 + 0.4 * t * t) + 3 * sin(t * 9 + 0.6)
            return CGPoint(x: x, y: y)
        }
        return line + [CGPoint(x: box.maxX + 30, y: box.minY - 40), CGPoint(x: box.minX - 30, y: box.minY - 40)]
    }

    /// The scoop's soft, ruffled foot slumping over the lip here and there,
    /// either side of the drip, as scooped ice cream does.
    static var lobes: [[CGPoint]] {
        [(0.24, 8.5), (0.42, 6.5), (0.62, 9.0), (0.78, 6.0)].map { (share: CGFloat, r: CGFloat) -> [CGPoint] in
            let p = lipEdge[Int(CGFloat(lipEdge.count - 1) * share)]
            return PathData.arc(center: CGPoint(x: p.x, y: p.y - 3), rx: r * 1.6, ry: r, from: -12, to: 192, spacing: 1)
        }
    }

    static var scoopTop: CGPoint { scoop.min { $0.y < $1.y } ?? bowl }

    /// Curled ridges the spoon left as it scooped, across the side toward the viewer.
    static let ridges: [[CGPoint]] = {
        [(0.5, 1.0, 2.3), (0.78, 0.75, 2.6)].map { (r: CGFloat, from: CGFloat, to: CGFloat) -> [CGPoint] in
            (0...80).compactMap { k -> CGPoint? in
                let angle = from + (to - from) * CGFloat(k) / 80
                guard facing(r, angle) > 0.25 else { return nil }
                let s = scoopSpot(r, angle)
                return place(s.u, s.v, s.w)
            }
        }
    }()

    /// Little dents and curls in the scoop's surface, short arcs that follow
    /// round it, as a scoop of ice cream has and jelly does not.
    static let pits: [[CGPoint]] = {
        var random = SplitMix(seed: 53)
        var pits: [[CGPoint]] = []
        var tries = 0
        while pits.count < 14, tries < 3000 {
            tries += 1
            let r = 0.2 + random.next() * 0.75, angle = random.next() * 2 * .pi
            guard facing(r, angle) > 0.3 else { continue }
            let span = 0.06 + random.next() * 0.07
            pits.append((0...8).map { k -> CGPoint in
                let a = angle - span / 2 + span * CGFloat(k) / 8
                let s = scoopSpot(r + 0.02 * sin(CGFloat(k) / 8 * .pi), a)
                return place(s.u, s.v, s.w)
            })
        }
        return pits
    }()

    /// Flakes of chocolate: thin broken slivers lying along the scoop's
    /// surface on the side toward the viewer, half sunk into it.
    static let chips: [[CGPoint]] = {
        var random = SplitMix(seed: 41)
        var chips: [[CGPoint]] = []
        var centers: [CGPoint] = []
        var tries = 0
        while chips.count < 11, tries < 3000 {
            tries += 1
            let r = 0.22 + random.next() * 0.66, angle = random.next() * 2 * .pi
            let face = facing(r, angle)
            guard face > 0.35 else { continue }
            let s = scoopSpot(r, angle)
            let center = place(s.u, s.v, s.w)
            guard !centers.contains(where: { hypot($0.x - center.x, $0.y - center.y) < 26 }) else { continue }
            centers.append(center)
            // Along the surface, round the scoop.
            let ahead = scoopSpot(r, angle + 0.06)
            let next = place(ahead.u, ahead.v, ahead.w)
            let run = max(hypot(next.x - center.x, next.y - center.y), 0.001)
            let way = CGPoint(x: (next.x - center.x) / run, y: (next.y - center.y) / run)
            let tilt = (random.next() - 0.5) * 0.9
            let d = CGPoint(x: way.x * cos(tilt) - way.y * sin(tilt), y: way.x * sin(tilt) + way.y * cos(tilt))
            let n = CGPoint(x: -d.y, y: d.x)
            let length = 9 + random.next() * 8, width = 3 + random.next() * 2.4
            let corners: [(CGFloat, CGFloat)] = [(-0.5, -0.3), (-0.1, -0.55), (0.5, -0.2), (0.35, 0.45), (-0.3, 0.5)]
            chips.append(corners.map { (along, across) in
                let jitter = 0.85 + 0.3 * random.next()
                return CGPoint(x: center.x + d.x * along * length * jitter + n.x * across * width, y: center.y + d.y * along * length * jitter + n.y * across * width)
            })
        }
        return chips
    }()

    /// Where the near lip is lowest on the sheet, at the tip: the melt runs over it there.
    static var spill: CGPoint {
        let lip = half(near: true, inset: -1)
        return lip.filter { $0.x < bowl.x - 10 }.max { $0.y < $1.y } ?? bowl
    }

    /// The melt running over the lip at the tip and the drop hanging from it,
    /// from the lip's inner edge, where the scoop's foot is, round and back:
    /// the outline, open along the top.
    static var drip: [CGPoint] {
        let p = spill
        let inner = half(near: true, inset: 8).filter { abs($0.x - p.x) <= 11 }.sorted { $0.x < $1.x }
        guard let left = inner.first, let right = inner.last else { return [] }
        let hang = "M \(right.x) \(right.y) C \(right.x - 3) \(p.y + 4), \(p.x + 4) \(p.y + 8), \(p.x + 3) \(p.y + 18) C \(p.x + 2) \(p.y + 28), \(p.x + 5) \(p.y + 36), \(p.x + 1) \(p.y + 42) C \(p.x - 2) \(p.y + 46), \(p.x - 7) \(p.y + 43), \(p.x - 6) \(p.y + 36) C \(p.x - 5) \(p.y + 28), \(p.x - 3) \(p.y + 20), \(p.x - 4) \(p.y + 12) C \(p.x - 5) \(p.y + 5), \(left.x + 3) \(left.y + 4), \(left.x) \(left.y)"
        return PathData.points(hang, spacing: 1)
    }

    static var dripShape: [CGPoint] {
        let p = spill
        let inner = half(near: true, inset: 8).filter { abs($0.x - p.x) <= 11 }.sorted { $0.x < $1.x }
        return drip + inner
    }

    // MARK: Her near arm: the upper arm hanging from the shoulder, the elbow on the table, the forearm rising to the spoon

    /// Where her fingers hold the handle.
    static let grip = handleSpot(0.39, side: 0)
    /// Her hand is nearer the viewer than her body, and drawn larger.
    static let handScale: CGFloat = 1.6
    /// Along the handle toward the bowl, on the sheet, and square to it, upward.
    static let toBowl: CGPoint = {
        let a = handleSpot(0.36, side: 0), b = handleSpot(0.48, side: 0)
        let run = hypot(a.x - b.x, a.y - b.y)
        return CGPoint(x: (a.x - b.x) / run, y: (a.y - b.y) / run)
    }()
    static let upward = toBowl.x > 0 ? CGPoint(x: toBowl.y, y: -toBowl.x) : CGPoint(x: -toBowl.y, y: toBowl.x)

    /// A point near her hand, `x` along the handle toward the bowl from where
    /// she holds it and `y` square to it, upward.
    static func hand(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: grip.x + handScale * (x * toBowl.x + y * upward.x), y: grip.y + handScale * (x * toBowl.y + y * upward.y))
    }

    static func hand(_ path: String) -> String { PathData.mapped(path) { hand($0.x, $0.y) } }
    static func hand(_ points: [CGPoint]) -> [CGPoint] { points.map { hand($0.x, $0.y) } }

    /// From the sheet back into her hand's own frame.
    static func handLocal(_ p: CGPoint) -> CGPoint {
        let dx = p.x - grip.x, dy = p.y - grip.y
        return CGPoint(x: (dx * toBowl.x + dy * toBowl.y) / handScale, y: (dx * upward.x + dy * upward.y) / handScale)
    }

    // Her elbow rests on the table and her forearm rises toward the viewer to
    // her fist, short with foreshortening. Its loose knit cuff is a band round
    // her wrist, under the fist, seen from a little above.
    static let elbowPoint = CGPoint(x: 936, y: 1186)
    static var wristMiddle: CGPoint { hand(-50, -56) }
    /// Down the forearm toward the elbow, on the sheet.
    static var toElbow: CGPoint {
        let w = wristMiddle
        let run = max(hypot(elbowPoint.x - w.x, elbowPoint.y - w.y), 0.001)
        return CGPoint(x: (elbowPoint.x - w.x) / run, y: (elbowPoint.y - w.y) / run)
    }

    /// A ring round her wrist: `across` wide either side of it, `deep` along the arm.
    static func ring(_ across: CGFloat, _ deep: CGFloat) -> [CGPoint] {
        let w = wristMiddle, d = toElbow, n = CGPoint(x: -toElbow.y, y: toElbow.x)
        return (0...160).map { k -> CGPoint in
            let t = 2 * CGFloat.pi * CGFloat(k) / 160
            return CGPoint(x: w.x + n.x * across * cos(t) + d.x * deep * sin(t), y: w.y + n.y * across * cos(t) + d.y * deep * sin(t))
        }
    }
    static var cuffOuter: [CGPoint] { ring(58, 22) }
    static var cuffInner: [CGPoint] { ring(46, 14) }
    /// The cuff's band, between its rim and the opening.
    static var cuff: [CGPoint] { cuffOuter + cuffInner.reversed() }
    /// Her wrist in the opening, in the sleeve's shadow, so no hole shows.
    static var wrist: [CGPoint] { cuffInner }

    /// The sleeve's two sides, from the cuff down to the elbow, bowing out a little.
    static var sleeveSides: (one: [CGPoint], other: [CGPoint]) {
        let w = wristMiddle, d = toElbow, n = CGPoint(x: -toElbow.y, y: toElbow.x)
        func side(_ k: CGFloat) -> [CGPoint] {
            let a = CGPoint(x: w.x + n.x * 58 * k, y: w.y + n.y * 58 * k)
            let b = CGPoint(x: elbowPoint.x + n.x * 72 * k - d.x * 30, y: elbowPoint.y + n.y * 72 * k - d.y * 30)
            let bow = CGPoint(x: (a.x + b.x) / 2 + n.x * 10 * k, y: (a.y + b.y) / 2 + n.y * 10 * k)
            return smooth([a, bow, b], count: 20)
        }
        return (side(1), side(-1))
    }

    /// The elbow, round where it rests on the table.
    static var elbowRound: [CGPoint] {
        let sides = sleeveSides
        guard let a = sides.one.last, let b = sides.other.last else { return [] }
        let d = toElbow
        let tip = CGPoint(x: elbowPoint.x + d.x * 14, y: elbowPoint.y + d.y * 14)
        return smooth([a, CGPoint(x: (a.x + tip.x) / 2 + d.x * 14, y: (a.y + tip.y) / 2 + d.y * 14), tip, CGPoint(x: (b.x + tip.x) / 2 + d.x * 14, y: (b.y + tip.y) / 2 + d.y * 14), b], count: 12)
    }

    /// The sleeve as one outline round the cuff, down to the elbow.
    static var sleeveOutline: [CGPoint] { hull(cuffOuter + sleeveSides.one + sleeveSides.other + elbowRound) }

    // MARK: Her fingers on the handle

    /// Her fist, seen from in front: the thumb along the top of the handle, the
    /// first finger curled under it, the second under that, the rest in the cuff.
    static let thumbJoints = hand([CGPoint(x: -52, y: 26), CGPoint(x: -18, y: 22), CGPoint(x: 14, y: 13)])
    static let thumbWidths: [CGFloat] = [34, 33, 29].map { $0 * handScale }
    static let indexJoints = hand([CGPoint(x: -62, y: -22), CGPoint(x: -24, y: -30), CGPoint(x: 4, y: -24)])
    static let indexWidths: [CGFloat] = [33, 32, 28].map { $0 * handScale }
    static let middleJoints = hand([CGPoint(x: -60, y: -52), CGPoint(x: -30, y: -60), CGPoint(x: -10, y: -56)])
    static let middleWidths: [CGFloat] = [31, 30, 27].map { $0 * handScale }
    /// The back of her fist, behind the fingers, so the handle goes into it.
    static let fist = hand("M -100 48 C -74 58, -46 50, -32 38 L -32 -74 C -62 -92, -104 -86, -122 -46 C -132 -16, -126 24, -100 48 Z")

    static var thumb: [CGPoint] { finger(thumbJoints, thumbWidths) }
    static var index: [CGPoint] { finger(indexJoints, indexWidths) }
    static var middle: [CGPoint] { finger(middleJoints, middleWidths) }
    static var thumbNail: [CGPoint] { nail(thumbJoints, width: thumbWidths[2], side: 1, length: 17 * handScale) }

    // MARK: Her other arm, the elbow on the table, the hand cupped under the spoon

    /// Her other hand's own frame: the middle of its palm, just under the
    /// spoon, the way its fingers point (right, a little toward the viewer),
    /// and how big it is drawn. `y` is up.
    static let palmMiddle = CGPoint(x: 492, y: 1158)
    static let fingersWay = CGPoint(x: 0.97, y: 0.24)
    static let otherScale: CGFloat = 1.9

    static func other(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: palmMiddle.x + otherScale * (x * fingersWay.x + y * fingersWay.y), y: palmMiddle.y + otherScale * (x * fingersWay.y - y * fingersWay.x))
    }
    static func other(_ path: String) -> String { PathData.mapped(path) { other($0.x, $0.y) } }
    static func other(_ points: [CGPoint]) -> [CGPoint] { points.map { other($0.x, $0.y) } }

    /// Her other hand, palm up under the spoon and cupped: the heel of it in
    /// the cuff, the fingers together and curling up so their pads show, the
    /// thumb coming off the heel of the palm on the near side.
    static let palm = other("M -52 18 C -22 26, 16 24, 36 14 C 46 4, 46 -12, 36 -20 C 10 -30, -26 -30, -52 -22 Z")
    /// Back to front: the little finger, the ring finger, the middle, the first.
    static let otherFingerJoints: [[CGPoint]] = [
        other([CGPoint(x: 26, y: 12), CGPoint(x: 44, y: 18), CGPoint(x: 52, y: 30)]),
        other([CGPoint(x: 32, y: 4), CGPoint(x: 54, y: 9), CGPoint(x: 64, y: 22)]),
        other([CGPoint(x: 35, y: -4), CGPoint(x: 60, y: 0), CGPoint(x: 71, y: 13)]),
        other([CGPoint(x: 33, y: -13), CGPoint(x: 57, y: -10), CGPoint(x: 68, y: 1)]),
    ]
    static let otherFingerWidths: [[CGFloat]] = [[12, 11.5, 11], [13, 12.5, 12], [14, 13.5, 13], [14, 13.5, 13]].map { $0.map { $0 * otherScale } }
    static let otherThumbJoints = other([CGPoint(x: -32, y: -18), CGPoint(x: -12, y: -34), CGPoint(x: 10, y: -36)])
    static let otherThumbWidths: [CGFloat] = [17, 16, 14].map { $0 * otherScale }
    static var otherFingers: [[CGPoint]] { zip(otherFingerJoints, otherFingerWidths).map { finger($0, $1) } }
    static var otherThumb: [CGPoint] { finger(otherThumbJoints, otherThumbWidths) }
    static let palmCrease = other("M -24 2 C -8 8, 10 8, 26 2")
    /// The hollow of the palm, in shade.
    static let hollow = other("M -30 0 C -20 10, 4 10, 20 2 C 24 -6, 10 -14, -6 -14 C -20 -14, -32 -8, -30 0 Z")
    /// The drop that fell, a little pool in the hollow of her palm.
    static let puddle = other("M -14 -3 C -10 2, 2 3, 7 -1 C 10 -5, 5 -9, -2 -9 C -9 -9, -16 -7, -14 -3 Z")

    static let otherCuffRim = other("M -40 30 C -24 20, -22 -16, -38 -34")
    static let otherCuffBand = other("M -52 30 C -36 18, -34 -16, -50 -32")
    /// Her other forearm, from her elbow on the table at the left, short as
    /// it comes toward the viewer.
    static let otherElbow = CGPoint(x: 232, y: 1104)
    static var otherForearmTop: String {
        let a = other(-40, 30)
        return "M \(a.x) \(a.y) C \(a.x - 50) \(a.y - 4), \(otherElbow.x + 90) \(otherElbow.y - 46), \(otherElbow.x + 6) \(otherElbow.y - 40)"
    }
    static var otherForearmBottom: String {
        let a = other(-38, -34)
        return "M \(a.x) \(a.y) C \(a.x - 50) \(a.y + 6), \(otherElbow.x + 110) \(otherElbow.y + 40), \(otherElbow.x + 30) \(otherElbow.y + 34)"
    }
    /// The elbow, round and pressed flat underneath where it rests.
    static var otherElbowRound: String {
        "M \(otherElbow.x + 6) \(otherElbow.y - 40) C \(otherElbow.x - 34) \(otherElbow.y - 36), \(otherElbow.x - 44) \(otherElbow.y + 4), \(otherElbow.x - 30) \(otherElbow.y + 24) C \(otherElbow.x - 16) \(otherElbow.y + 40), \(otherElbow.x + 10) \(otherElbow.y + 40), \(otherElbow.x + 30) \(otherElbow.y + 34)"
    }
    static var otherFolds: [String] {
        let a = other(-46, 0)
        return ["M \(a.x - 40) \(a.y - 12) C \(a.x - 70) \(a.y - 16), \(a.x - 100) \(a.y - 22), \(a.x - 130) \(a.y - 30)",
                "M \(otherElbow.x + 40) \(otherElbow.y - 28) C \(otherElbow.x + 50) \(otherElbow.y - 8), \(otherElbow.x + 50) \(otherElbow.y + 10), \(otherElbow.x + 40) \(otherElbow.y + 28)"]
    }

    static var otherSleeve: [CGPoint] {
        let top = PathData.points(otherForearmTop, spacing: 1.5)
        let bottom = PathData.points(otherForearmBottom, spacing: 1.5)
        let rim = PathData.points(otherCuffRim, spacing: 1.5)
        let round = PathData.points(otherElbowRound, spacing: 1.5)
        return PathData.resampled(rim + bottom + round.reversed() + top.reversed(), spacing: 1.5)
    }

    static var otherCuff: [CGPoint] {
        PathData.resampled(PathData.points(otherCuffRim, spacing: 1.5) + PathData.points(otherCuffBand, spacing: 1.5).reversed(), spacing: 1.5)
    }

    static var roughLines: [[CGPoint]] { [bowlOutline, handle, scoop, sleeveOutline, otherSleeve] }

    // MARK: Drawing

    /// The nearest things get the heaviest lines.
    static func pen(_ color: RGBA) -> Pen {
        Pen(width: 3.6, color: color, start: 0.05, end: 0.05, floor: 0.45)
    }

    static func skinPen(_ c: Bite.Colors) -> Pen {
        Pen(width: 2.8, color: c.skinLine.mixed(with: c.clothLine, 0.35), start: 0.15, end: 0.15, floor: 0.35)
    }

    static func spoonLines(_ a: Artist, _ c: Bite.Colors) {
        a.line(half(near: false, inset: -1), pen(c.metalLine).with(width: 2.6, start: 0.1, end: 0.1))
        a.line(handle, pen(c.metalLine).with(width: 2.6))
    }

    static func spoonFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(handle, c.metal)
        a.shape(bowlOutline, c.metal)
    }

    static func lipLines(_ a: Artist, _ c: Bite.Colors) {
        a.line(half(near: true, inset: -1), pen(c.metalLine).with(width: 3, start: 0.1, end: 0.1))
        a.line(half(near: true, inset: 8), pen(c.metalLine).with(width: 1.4, start: 0.25, end: 0.25, floor: 0.15, opacity: 0.55))
    }

    static func lipFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(lip, c.metal)
    }

    static func scoopLines(_ a: Artist, _ c: Bite.Colors) {
        a.line(scoop, pen(c.creamLine).with(width: 2.6))

        for ridge in ridges where ridge.count > 4 {
            a.line(ridge, Pen(width: 2, color: c.creamLine, start: 0.35, end: 0.5, floor: 0.02, opacity: 0.55))
        }
    }

    static func scoopFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(scoop, c.cream)
        for chip in chips {
            a.shape(chip, c.chip)
            // The broken edge catches a little light.
            a.ribbon([chip[1], chip[2]], c.chipEdge, width: Ribbon.leaf(2.2))
            // Half sunk: the cream laps over its lower side.
            let low = chip.max { $0.y < $1.y } ?? chip[0]
            a.shape(PathData.arc(center: CGPoint(x: low.x, y: low.y + 1.5), rx: 5, ry: 2.4, from: 0, to: 360, spacing: 0.6), c.cream)
        }
    }

    static func dripLines(_ a: Artist, _ c: Bite.Colors) {
        a.line(drip, pen(c.creamLine).with(width: 2.2, start: 0.25, end: 0.25, floor: 0.1))
    }

    static func dripFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(dripShape, c.cream)
    }

    static func armLines(_ a: Artist, _ c: Bite.Colors) {
        let sides = sleeveSides
        a.line(sides.one + elbowRound + sides.other.reversed(), pen(c.clothLine).with(start: 0.05, end: 0.05))
        // Folds where the loose sleeve bunches below the cuff.
        let w = wristMiddle, d = toElbow, n = CGPoint(x: -toElbow.y, y: toElbow.x)
        for (along, offset, length) in [(70.0, -40.0, 60.0), (90.0, 30.0, 70.0), (150.0, -10.0, 60.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let p = CGPoint(x: w.x + d.x * along + n.x * offset, y: w.y + d.y * along + n.y * offset)
            let q = CGPoint(x: p.x + d.x * length + n.x * 8, y: p.y + d.y * length + n.y * 8)
            a.line(smooth([p, CGPoint(x: (p.x + q.x) / 2 + n.x * 6, y: (p.y + q.y) / 2 + n.y * 6), q], count: 10), Pen(width: 2, color: c.clothLine, start: 0.35, end: 0.5, floor: 0.05))
        }
    }

    static func armFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(sleeveOutline, c.knit)
    }

    static func fingerLines(_ a: Artist, _ c: Bite.Colors) {
        let fistLine = PathData.points(fist, spacing: 1)
        stacked(a, [fistLine, middle, index, thumb], skinPen(c))
        a.line(thumbNail + [thumbNail[0]], skinPen(c).with(width: 1.5, start: 0.3, end: 0.3, opacity: 0.7))
    }

    static func fingerFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(wrist, c.skin)
        a.shape(fist, c.skin)
        for finger in [middle, index, thumb] { a.shape(finger, c.skin) }
    }

    static func cuffLines(_ a: Artist, _ c: Bite.Colors) {
        a.line(cuffOuter, pen(c.clothLine))
        a.line(cuffInner, pen(c.clothLine).with(width: 2.2, start: 0.1, end: 0.1, floor: 0.4, opacity: 0.85))
    }

    static func cuffFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(cuff, c.knit)
    }

    static func otherLines(_ a: Artist, _ c: Bite.Colors) {
        let sleeveCover = [otherSleeve, otherCuff]
        stacked(a, [PathData.points(palm, spacing: 1)] + otherFingers + [otherThumb], covers: sleeveCover, skinPen(c).with(width: 2.6))
        a.line(palmCrease, skinPen(c).with(width: 1.6, start: 0.4, end: 0.4, opacity: 0.5))
        a.line(otherForearmTop, pen(c.clothLine))
        a.line(otherForearmBottom, pen(c.clothLine))
        a.line(otherElbowRound, pen(c.clothLine))
        a.line(otherCuffRim, pen(c.clothLine))
        a.line(otherCuffBand, pen(c.clothLine).with(width: 2, start: 0.25, end: 0.25, floor: 0.2, opacity: 0.8))
        for fold in otherFolds { a.line(fold, Pen(width: 1.8, color: c.clothLine, start: 0.35, end: 0.5, floor: 0.05)) }
        a.line(puddle, pen(c.creamLine).with(width: 1.2, start: 0.3, end: 0.3, floor: 0.2, opacity: 0.5))
    }

    static func otherFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(palm, c.skin)
        for finger in otherFingers { a.shape(finger, c.skin) }
        a.shape(otherThumb, c.skin)
        a.shape(otherSleeve, c.knit)
        a.shape(otherCuff, c.knit)
        a.shape(puddle, c.cream)
    }
}
