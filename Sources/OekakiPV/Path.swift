import CoreGraphics
import Foundation

/// A pen path written like SVG path data: `M x y`, `L x y`, `Q cx cy x y`,
/// `C c1x c1y c2x c2y x y` and `Z`, absolute coordinates only.
enum PathData {
    /// The path as points about `spacing` apart along its length.
    static func points(_ data: String, spacing: CGFloat = 2.5) -> [CGPoint] {
        let tokens = tokenize(data)
        var dense: [CGPoint] = []
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var subpath = CGPoint.zero
        func number() -> CGFloat {
            defer { index += 1 }
            guard index < tokens.count, let value = Double(tokens[index]) else {
                fatalError("Bad number in path: \(data)")
            }
            return CGFloat(value)
        }
        func point() -> CGPoint { CGPoint(x: number(), y: number()) }
        func curve(_ count: Int, _ at: (CGFloat) -> CGPoint) {
            for step in 1...count { dense.append(at(CGFloat(step) / CGFloat(count))) }
        }
        while index < tokens.count {
            if let letter = tokens[index].first, letter.isLetter {
                command = letter
                index += 1
            }
            switch command {
            case "M":
                current = point()
                subpath = current
                dense.append(current)
                command = "L"
            case "Z":
                // Back to where the shape started.
                let start = current, end = subpath
                curve(40) { t in CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t) }
                current = end
            case "L":
                let end = point()
                let start = current
                curve(40) { t in
                    let x: CGFloat = start.x + (end.x - start.x) * t
                    let y: CGFloat = start.y + (end.y - start.y) * t
                    return CGPoint(x: x, y: y)
                }
                current = end
            case "Q":
                let control = point(), end = point(), start = current
                curve(60) { t in
                    let u = 1 - t
                    let a = u * u, b = 2 * u * t, c = t * t
                    let x: CGFloat = a * start.x + b * control.x + c * end.x
                    let y: CGFloat = a * start.y + b * control.y + c * end.y
                    return CGPoint(x: x, y: y)
                }
                current = end
            case "C":
                let first = point(), second = point(), end = point(), start = current
                curve(80) { t in
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    let x: CGFloat = a * start.x + b * first.x + c * second.x + d * end.x
                    let y: CGFloat = a * start.y + b * first.y + c * second.y + d * end.y
                    return CGPoint(x: x, y: y)
                }
                current = end
            default:
                fatalError("Unknown path command \(command) in \(data)")
            }
        }
        return resampled(dense, spacing: spacing)
    }

    /// Paths that each start where the one before ended, as one path: the
    /// starting "M x y" of all but the first is dropped.
    static func join(_ paths: [String]) -> String {
        paths.enumerated().map { index, path in
            guard index > 0 else { return path }
            let tokens = tokenize(path)
            precondition(tokens.first == "M", "A path to join must start with M: \(path)")
            return tokens.dropFirst(3).joined(separator: " ")
        }.joined(separator: " ")
    }

    /// The path with every point moved by `move`, commands kept.
    static func mapped(_ data: String, _ move: (CGPoint) -> CGPoint) -> String {
        var out: [String] = []
        var pending: CGFloat?
        for token in tokenize(data) {
            if let value = Double(token) {
                if let x = pending {
                    let point = move(CGPoint(x: x, y: CGFloat(value)))
                    out.append(String(format: "%.2f %.2f", point.x, point.y))
                    pending = nil
                } else {
                    pending = CGFloat(value)
                }
            } else {
                out.append(token)
            }
        }
        return out.joined(separator: " ")
    }

    /// The part of `shape` inside `convex`, a shape that bulges outward all round
    /// (Sutherland and Hodgman's way: cut by each of its edges in turn).
    static func clipped(_ shape: [CGPoint], to convex: [CGPoint]) -> [CGPoint] {
        guard convex.count >= 3 else { return shape }
        // Which side is inside depends on which way the convex shape winds.
        var area: CGFloat = 0
        for (p, q) in zip(convex, convex.dropFirst() + [convex[0]]) { area += p.x * q.y - q.x * p.y }
        let sign: CGFloat = area > 0 ? 1 : -1
        var output = shape
        for (p, q) in zip(convex, convex.dropFirst() + [convex[0]]) where hypot(q.x - p.x, q.y - p.y) > 0.01 {
            let input = output
            output = []
            guard let last = input.last else { break }
            func inside(_ r: CGPoint) -> Bool { sign * ((q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)) >= 0 }
            func crossing(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                let d1 = (q.x - p.x) * (a.y - p.y) - (q.y - p.y) * (a.x - p.x)
                let d2 = (q.x - p.x) * (b.y - p.y) - (q.y - p.y) * (b.x - p.x)
                let t = d1 / (d1 - d2)
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            var previous = last
            for current in input {
                if inside(current) {
                    if !inside(previous) { output.append(crossing(previous, current)) }
                    output.append(current)
                } else if inside(previous) {
                    output.append(crossing(previous, current))
                }
                previous = current
            }
        }
        return output
    }

    /// Points `spacing` apart along the polyline, keeping both ends.
    static func resampled(_ line: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard var previous = line.first else { return [] }
        var result = [previous]
        var carried: CGFloat = 0
        for next in line.dropFirst() {
            var segment = hypot(next.x - previous.x, next.y - previous.y)
            var from = previous
            while carried + segment >= spacing {
                let t = (spacing - carried) / segment
                from = CGPoint(x: from.x + (next.x - from.x) * t, y: from.y + (next.y - from.y) * t)
                result.append(from)
                segment = hypot(next.x - from.x, next.y - from.y)
                carried = 0
            }
            carried += segment
            previous = next
        }
        if let last = line.last, let end = result.last, hypot(last.x - end.x, last.y - end.y) > spacing * 0.3 {
            result.append(last)
        }
        return result
    }

    /// Points on an ellipse, from angle `from` to `to` in degrees (0 is to
    /// the right, 90 is down).
    static func arc(center: CGPoint, rx: CGFloat, ry: CGFloat, from: CGFloat, to: CGFloat, spacing: CGFloat = 2.5) -> [CGPoint] {
        let count = 200
        let line = (0...count).map { step -> CGPoint in
            let angle = (from + (to - from) * CGFloat(step) / CGFloat(count)) * .pi / 180
            return CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle))
        }
        return resampled(line, spacing: spacing)
    }

    private static func tokenize(_ data: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in data {
            if character.isLetter {
                if !current.isEmpty { tokens.append(current) }
                tokens.append(String(character))
                current = ""
            } else if character == " " || character == "," || character == "\n" {
                if !current.isEmpty { tokens.append(current) }
                current = ""
            } else if character == "-", !current.isEmpty {
                tokens.append(current)
                current = "-"
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
