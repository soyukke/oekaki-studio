import CoreGraphics
import Foundation

/// Steadies the person's own lines, without an assistant.
///
/// Nothing is redrawn: each stroke keeps its place, its corners and its ends.
/// Only the shake of the hand is smoothed away, a stroke that nearly returns
/// to its start is closed, and an end that stops just short of another line
/// is carried on to meet it.
enum LineTidy {
    /// Distance between the points a stroke is measured at, in pixels.
    static let spacing: CGFloat = 2
    /// A bend sharper than this, in degrees, is a corner the person meant.
    static let cornerAngle: CGFloat = 70
    /// An end this close to another line is joined to it.
    static let joinReach: CGFloat = 16

    static func tidied(_ strokes: [Stroke], smoothing: CGFloat) -> [Stroke] {
        var lines = strokes.map { stroke -> Stroke in
            guard !stroke.isEraser, stroke.points.count > 2 else { return stroke }
            var smooth = stroke
            smooth.points = smoothed(stroke.points, by: smoothing)
            return smooth
        }
        join(&lines)
        return lines
    }

    // MARK: Smoothing

    static func smoothed(_ original: [StrokePoint], by smoothing: CGFloat) -> [StrokePoint] {
        var points = resampled(original)
        guard points.count > 4, smoothing > 0 else { return original }
        let length = CGFloat(points.count - 1) * spacing
        let first = points[0]
        let last = points[points.count - 1]
        let isLoop = length > 60 && hypot(first.x - last.x, first.y - last.y) < max(12, length * 0.04)
        if isLoop {
            points.removeLast()
        }
        // Each run between two corners is smoothed on its own, so corners stay sharp.
        var cuts = corners(in: points, isLoop: isLoop, window: max(8, Int((smoothing * 2 / spacing).rounded())))
        var result: [StrokePoint] = []
        if isLoop {
            if cuts.isEmpty {
                result = blurred(points, sigma: min(smoothing, length / 10) / spacing, wraps: true)
                restoreSize(of: &result, to: points)
                result.append(result[0])
                return thinned(result)
            }
            // Start the loop at a corner so every run is an open one.
            let turn = cuts[0]
            points = Array(points[turn...] + points[..<turn])
            cuts = cuts.map { $0 - turn }
            points.append(points[0])
        }
        let stops = [0] + cuts.filter { $0 > 0 && $0 < points.count - 1 } + [points.count - 1]
        for (from, to) in zip(stops, stops.dropFirst()) {
            let run = Array(points[from...to])
            // A short run cannot take the full strength without losing its shape.
            let sigma = min(smoothing, CGFloat(run.count) * spacing / 6) / spacing
            let smooth = blurred(run, sigma: sigma, wraps: false)
            result.append(contentsOf: result.isEmpty ? smooth : Array(smooth.dropFirst()))
        }
        return thinned(result)
    }

    /// The stroke measured again at even steps along its length.
    static func resampled(_ points: [StrokePoint]) -> [StrokePoint] {
        guard var previous = points.first else { return [] }
        var result = [previous]
        var owed = spacing
        for point in points.dropFirst() {
            var gap = hypot(point.x - previous.x, point.y - previous.y)
            while gap >= owed {
                let t = owed / gap
                previous = StrokePoint(
                    x: previous.x + (point.x - previous.x) * t, y: previous.y + (point.y - previous.y) * t,
                    pressure: previous.pressure + (point.pressure - previous.pressure) * t
                )
                result.append(previous)
                gap -= owed
                owed = spacing
            }
            owed -= gap
            previous = point
        }
        if let last = points.last, let kept = result.last, hypot(last.x - kept.x, last.y - kept.y) > 0.01 {
            result.append(last)
        }
        return result
    }

    /// Where the stroke turns sharply, judged over `window` points each way
    /// so that shake is not mistaken for a corner.
    private static func corners(in points: [StrokePoint], isLoop: Bool, window: Int) -> [Int] {
        let count = points.count
        guard count > window * 2 + 1 else { return [] }
        func at(_ index: Int) -> StrokePoint? {
            if isLoop { return points[((index % count) + count) % count] }
            return index >= 0 && index < count ? points[index] : nil
        }
        var turn = [CGFloat](repeating: 0, count: count)
        for index in 0..<count {
            guard let before = at(index - window), let after = at(index + window) else { continue }
            let here = points[index]
            let a = CGVector(dx: here.x - before.x, dy: here.y - before.y)
            let b = CGVector(dx: after.x - here.x, dy: after.y - here.y)
            let lengths = hypot(a.dx, a.dy) * hypot(b.dx, b.dy)
            guard lengths > 0.001 else { continue }
            turn[index] = acos(max(-1, min(1, (a.dx * b.dx + a.dy * b.dy) / lengths))) * 180 / .pi
        }
        var found: [Int] = []
        for index in 0..<count where turn[index] >= cornerAngle {
            // Keep only the sharpest point of each bend.
            var isPeak = true
            for offset in -window...window where offset != 0 {
                let other = isLoop ? ((index + offset) % count + count) % count : index + offset
                guard other >= 0, other < count else { continue }
                if turn[other] > turn[index] || (turn[other] == turn[index] && other < index) {
                    isPeak = false
                    break
                }
            }
            if isPeak { found.append(index) }
        }
        return found
    }

    /// A Gaussian average along the stroke. An open run keeps both ends
    /// exactly where they were.
    private static func blurred(_ points: [StrokePoint], sigma: CGFloat, wraps: Bool) -> [StrokePoint] {
        let count = points.count
        guard sigma > 0.2, count > 2 else { return points }
        let reach = max(1, Int((sigma * 3).rounded(.up)))
        let weights = (-reach...reach).map { exp(-CGFloat($0 * $0) / (2 * sigma * sigma)) }
        let total = weights.reduce(0, +)
        func sample(_ index: Int) -> StrokePoint {
            if wraps { return points[((index % count) + count) % count] }
            if index < 0 {
                // Mirrored through the end point, which holds that end still.
                let mirror = points[min(-index, count - 1)]
                return StrokePoint(x: 2 * points[0].x - mirror.x, y: 2 * points[0].y - mirror.y, pressure: mirror.pressure)
            }
            if index >= count {
                let mirror = points[max(2 * (count - 1) - index, 0)]
                let end = points[count - 1]
                return StrokePoint(x: 2 * end.x - mirror.x, y: 2 * end.y - mirror.y, pressure: mirror.pressure)
            }
            return points[index]
        }
        return (0..<count).map { index in
            var x: CGFloat = 0, y: CGFloat = 0, pressure: CGFloat = 0
            for offset in -reach...reach {
                let point = sample(index + offset)
                let weight = weights[offset + reach]
                x += point.x * weight
                y += point.y * weight
                pressure += point.pressure * weight
            }
            return StrokePoint(x: x / total, y: y / total, pressure: pressure / total)
        }
    }

    /// Averaging pulls a loop inward a little. This grows it back about its
    /// centre to the size the person drew.
    private static func restoreSize(of loop: inout [StrokePoint], to original: [StrokePoint]) {
        func measure(_ points: [StrokePoint]) -> (center: CGPoint, radius: CGFloat) {
            let count = CGFloat(points.count)
            let center = CGPoint(x: points.reduce(0) { $0 + $1.x } / count, y: points.reduce(0) { $0 + $1.y } / count)
            return (center, points.reduce(0) { $0 + hypot($1.x - center.x, $1.y - center.y) } / count)
        }
        let before = measure(original)
        let after = measure(loop)
        guard after.radius > 0.001 else { return }
        let scale = before.radius / after.radius
        for index in loop.indices {
            loop[index].x = before.center.x + (loop[index].x - after.center.x) * scale
            loop[index].y = before.center.y + (loop[index].y - after.center.y) * scale
        }
    }

    /// Drops points that add nothing to the shape, to keep the stroke light:
    /// those within a fraction of a pixel of the line through their neighbours.
    private static func thinned(_ points: [StrokePoint], tolerance: CGFloat = 0.35) -> [StrokePoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(0, points.count - 1)]
        while let (first, last) = spans.popLast() {
            guard last > first + 1 else { continue }
            let a = points[first]
            let b = points[last]
            let length = hypot(b.x - a.x, b.y - a.y)
            var farthest = first
            var distance: CGFloat = -1
            for index in first + 1..<last {
                let p = points[index]
                let d = length < 0.001
                    ? hypot(p.x - a.x, p.y - a.y)
                    : abs((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)) / length
                if d > distance {
                    distance = d
                    farthest = index
                }
            }
            if distance > tolerance {
                keep[farthest] = true
                spans.append((first, farthest))
                spans.append((farthest, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    // MARK: Joining

    /// Carries each loose end on to the nearest other line within reach.
    private static func join(_ strokes: inout [Stroke]) {
        let lines = strokes.indices.filter { !strokes[$0].isEraser && strokes[$0].points.count > 1 }
        for index in lines {
            for atStart in [true, false] {
                let points = strokes[index].points
                let end = atStart ? points[0] : points[points.count - 1]
                var along: [CGFloat] = [0]
                for (a, b) in zip(points, points.dropFirst()) {
                    along.append(along[along.count - 1] + hypot(b.x - a.x, b.y - a.y))
                }
                var best: (point: CGPoint, distance: CGFloat)?
                for other in lines {
                    let candidates = strokes[other].points
                    for position in 0..<candidates.count - 1 {
                        let a = candidates[position].point
                        let b = candidates[position + 1].point
                        let span = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)
                        let t = span < 0.0001 ? 0 : max(0, min(1, ((end.x - a.x) * (b.x - a.x) + (end.y - a.y) * (b.y - a.y)) / span))
                        // On its own stroke, an end may only join a part that is well away along the line.
                        if other == index {
                            let here = along[position] + (along[position + 1] - along[position]) * t
                            let away = atStart ? here : along[along.count - 1] - here
                            if away < joinReach * 3 { continue }
                        }
                        let nearest = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                        let distance = hypot(nearest.x - end.x, nearest.y - end.y)
                        if distance <= joinReach, distance < (best?.distance ?? .infinity) {
                            best = (nearest, distance)
                        }
                    }
                }
                guard let best, best.distance > 0.5 else { continue }
                let target = StrokePoint(x: best.point.x, y: best.point.y, pressure: end.pressure)
                if atStart {
                    strokes[index].points.insert(target, at: 0)
                } else {
                    strokes[index].points.append(target)
                }
            }
        }
    }
}
