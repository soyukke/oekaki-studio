import CoreGraphics
import Foundation

/// Turns roughly painted colour into clean flat areas, without an assistant.
///
/// The person paints loosely on one layer. Lines on the other layers split the
/// canvas into areas. In each area the colour that slopped over from next door
/// is taken out, an area that is mostly painted is filled to its edges, and the
/// borders between colours that no line separates are smoothed.
enum PaintTidy {
    struct Report: Equatable {
        /// Pixels of colour taken away, such as paint that crossed a line.
        var removed = 0
        /// Pixels of colour added, such as gaps left next to a line.
        var added = 0
        /// False when no lines were found to tidy against.
        var foundLines = false
    }

    /// Openings in an outline up to about twice this many pixels are closed.
    static let gap = BucketFill.defaultGap
    /// An area at least this much painted is filled all the way to its lines.
    static let fillOutCoverage = 0.5
    /// Paint that crossed a line is taken out when it is this small next to
    /// the rest of its patch and covers less than `keepCoverage` of where it landed.
    static let strayShare = 0.35
    static let keepCoverage = 0.5
    /// How strongly colour borders are smoothed, in pixels.
    static let smoothing = 3.5
    /// A patch of colour that smoothing would shrink below this share of
    /// itself is left as painted instead.
    static let smallPatchKept = 0.7
    static let maximumColors = 24

    /// Marks the pixels of `picture` that are lines: solid and dark. Returns how many.
    static func markLines(in picture: CGContext, into wall: inout [UInt8]) -> Int {
        guard let data = picture.data else { return 0 }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var count = 0
        for index in 0..<picture.width * picture.height {
            let alpha = Int(pixels[index * 4 + 3])
            guard alpha >= 128 else { continue }
            // Channels are premultiplied, so compare against alpha rather than 255.
            let luma = 2126 * Int(pixels[index * 4]) + 7152 * Int(pixels[index * 4 + 1]) + 722 * Int(pixels[index * 4 + 2])
            if luma < 5500 * alpha {
                wall[index] = 255
                count += 1
            }
        }
        return count
    }

    /// Tidies `paint`, a tightly packed premultiplied RGBA bitmap, against the
    /// lines in `wall`. `tuck` is how far colour may reach under a line.
    /// Returns nil when there is no colour to tidy.
    static func run(
        paint: CGContext, wall: [UInt8], tuck: Int, smoothing: Double = PaintTidy.smoothing
    ) -> (image: CGImage, report: Report)? {
        let width = paint.width
        let height = paint.height
        let count = width * height
        precondition(paint.bytesPerRow == width * 4 && wall.count == count)
        guard let data = paint.data else { return nil }
        let source = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count * 4)

        guard let palette = Palette(source: source, count: count) else { return nil }
        var label = palette.labels(source: source, count: count)
        let before = label
        let region = Regions(wall: wall, width: width, height: height)

        removeStrays(label: &label, region: region, width: width, height: height)
        fillOut(label: &label, region: region, width: width, height: height)
        smooth(label: &label, region: region, width: width, height: height, colors: palette.colors.count, by: smoothing)
        for index in 0..<count where wall[index] != 0 {
            label[index] = 0
        }
        tuckUnder(label: &label, wall: wall, width: width, height: height, steps: tuck)

        var report = Report(foundLines: wall.contains { $0 != 0 })
        for index in 0..<count where wall[index] == 0 {
            if before[index] != 0, label[index] == 0 { report.removed += 1 }
            if before[index] == 0, label[index] != 0 { report.added += 1 }
        }
        guard let image = render(label: label, colors: palette.colors, width: width, height: height) else { return nil }
        return (image, report)
    }

    /// How much two drawings sit on top of each other: the share of `a`'s
    /// solid pixels within `reach` of `b`'s, and the other way round.
    static func overlap(of a: CGContext, with b: CGContext, reach: Int) -> (followed: Double, kept: Double)? {
        func solid(_ context: CGContext) -> [UInt8]? {
            guard let data = context.data else { return nil }
            let pixels = data.assumingMemoryBound(to: UInt8.self)
            return (0..<context.width * context.height).map { pixels[$0 * 4 + 3] >= 128 ? 255 : 0 }
        }
        guard a.width == b.width, a.height == b.height, let first = solid(a), let second = solid(b) else { return nil }
        func share(of mask: [UInt8], near other: [UInt8]) -> Double {
            let grown = dilate(other, width: a.width, height: a.height, radius: reach)
            var total = 0
            var inside = 0
            for index in mask.indices where mask[index] != 0 {
                total += 1
                if grown[index] != 0 { inside += 1 }
            }
            return total == 0 ? 0 : Double(inside) / Double(total)
        }
        return (share(of: first, near: second), share(of: second, near: first))
    }

    // MARK: Colours

    /// The handful of flat colours the person painted with.
    private struct Palette {
        /// Index 0 is "no colour".
        var colors: [(r: UInt8, g: UInt8, b: UInt8)] = [(0, 0, 0)]

        init?(source: UnsafeBufferPointer<UInt8>, count: Int) {
            // A coarse histogram finds the flat colours; soft brush edges
            // land in bins too small to count.
            var bins = [Int](repeating: 0, count: 4096)
            var sums = [(r: Int, g: Int, b: Int)](repeating: (0, 0, 0), count: 4096)
            var painted = 0
            for index in 0..<count where source[index * 4 + 3] == 255 {
                let r = Int(source[index * 4]), g = Int(source[index * 4 + 1]), b = Int(source[index * 4 + 2])
                let bin = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
                bins[bin] += 1
                sums[bin].r += r
                sums[bin].g += g
                sums[bin].b += b
                painted += 1
            }
            let least = max(30, painted / 2000)
            let kept = bins.indices.filter { bins[$0] >= least }.sorted { bins[$0] > bins[$1] }
            for bin in kept {
                let n = bins[bin]
                let color = (r: UInt8(sums[bin].r / n), g: UInt8(sums[bin].g / n), b: UInt8(sums[bin].b / n))
                // One colour can straddle two bins; keep the bigger one only.
                if Self.nearest(to: color, in: colors).distance <= 24 { continue }
                colors.append(color)
                if colors.count > PaintTidy.maximumColors { break }
            }
            if colors.count == 1 { return nil }
        }

        private static func nearest(
            to color: (r: UInt8, g: UInt8, b: UInt8), in colors: [(r: UInt8, g: UInt8, b: UInt8)]
        ) -> (index: Int, distance: Int) {
            var best = (index: 0, distance: Int.max)
            for index in colors.indices.dropFirst() {
                let other = colors[index]
                let distance = max(abs(Int(color.r) - Int(other.r)), abs(Int(color.g) - Int(other.g)), abs(Int(color.b) - Int(other.b)))
                if distance < best.distance { best = (index, distance) }
            }
            return best
        }

        /// Which colour each pixel is, 0 where it is less than half covered.
        func labels(source: UnsafeBufferPointer<UInt8>, count: Int) -> [UInt8] {
            var label = [UInt8](repeating: 0, count: count)
            var lastKey = -1
            var lastLabel: UInt8 = 0
            for index in 0..<count {
                let alpha = Int(source[index * 4 + 3])
                guard alpha >= 128 else { continue }
                let r = Int(source[index * 4]) * 255 / alpha
                let g = Int(source[index * 4 + 1]) * 255 / alpha
                let b = Int(source[index * 4 + 2]) * 255 / alpha
                let key = r << 16 | g << 8 | b
                if key != lastKey {
                    lastKey = key
                    let color = (r: UInt8(min(r, 255)), g: UInt8(min(g, 255)), b: UInt8(min(b, 255)))
                    lastLabel = UInt8(Self.nearest(to: color, in: colors).index)
                }
                label[index] = lastLabel
            }
            return label
        }
    }

    // MARK: Areas

    /// The areas the lines split the canvas into. Area 0 is the lines themselves.
    private struct Regions {
        var id: [Int32]
        var area: [Int]

        init(wall: [UInt8], width: Int, height: Int) {
            let count = width * height
            id = [Int32](repeating: 0, count: count)
            area = [0]
            // Fattened lines close small openings, as the paint bucket does.
            let thick = PaintTidy.dilate(wall, width: width, height: height, radius: PaintTidy.gap)
            var stack: [Int32] = []
            var edge: [Int32] = []
            for start in 0..<count where thick[start] == 0 && id[start] == 0 {
                let name = Int32(area.count)
                area.append(0)
                id[start] = name
                stack.append(Int32(start))
                while let top = stack.popLast() {
                    let index = Int(top)
                    area[Int(name)] += 1
                    edge.append(top)
                    PaintTidy.eachNeighbor(of: index, width: width, height: height) { next in
                        if thick[next] == 0, id[next] == 0 {
                            id[next] = name
                            stack.append(Int32(next))
                        }
                    }
                }
            }
            // Give the band beside each line back to the area it borders.
            var head = 0
            while head < edge.count {
                let index = Int(edge[head])
                head += 1
                let name = id[index]
                PaintTidy.eachNeighbor(of: index, width: width, height: height) { next in
                    if wall[next] == 0, id[next] == 0 {
                        id[next] = name
                        area[Int(name)] += 1
                        edge.append(Int32(next))
                    }
                }
            }
            // Slivers too thin to survive the fattening become areas of their own.
            for start in 0..<count where wall[start] == 0 && id[start] == 0 {
                let name = Int32(area.count)
                area.append(0)
                id[start] = name
                stack.append(Int32(start))
                while let top = stack.popLast() {
                    area[Int(name)] += 1
                    PaintTidy.eachNeighbor(of: Int(top), width: width, height: height) { next in
                        if wall[next] == 0, id[next] == 0 {
                            id[next] = name
                            stack.append(Int32(next))
                        }
                    }
                }
            }
        }
    }

    @inline(__always)
    private static func eachNeighbor(of index: Int, width: Int, height: Int, _ body: (Int) -> Void) {
        let x = index % width
        if x > 0 { body(index - 1) }
        if x < width - 1 { body(index + 1) }
        if index >= width { body(index - width) }
        if index < width * (height - 1) { body(index + width) }
    }

    /// Grows the marked pixels by `radius` in every direction (a square brush).
    static func dilate(_ mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0 else { return mask }
        let far = width + height + radius + 1
        var rows = [UInt8](repeating: 0, count: mask.count)
        for y in 0..<height {
            let row = y * width
            var last = -far
            for x in 0..<width {
                if mask[row + x] != 0 { last = x }
                if x - last <= radius { rows[row + x] = 255 }
            }
            var next = far * 2
            for x in stride(from: width - 1, through: 0, by: -1) {
                if mask[row + x] != 0 { next = x }
                if next - x <= radius { rows[row + x] = 255 }
            }
        }
        var out = [UInt8](repeating: 0, count: mask.count)
        for x in 0..<width {
            var last = -far
            for y in 0..<height {
                if rows[y * width + x] != 0 { last = y }
                if y - last <= radius { out[y * width + x] = 255 }
            }
            var next = far * 2
            for y in stride(from: height - 1, through: 0, by: -1) {
                if rows[y * width + x] != 0 { next = y }
                if next - y <= radius { out[y * width + x] = 255 }
            }
        }
        return out
    }

    // MARK: Steps

    /// Takes out paint that slopped over a line into the next area.
    ///
    /// A patch is one connected blob of a colour, lines ignored. The part of
    /// a patch in an area is a spill when it is small next to the patch's
    /// main part and does not cover much of the area it landed in.
    private static func removeStrays(label: inout [UInt8], region: Regions, width: Int, height: Int) {
        let count = width * height
        var patch = [Int32](repeating: 0, count: count)
        var patches: Int32 = 0
        var stack: [Int32] = []
        for start in 0..<count where label[start] != 0 && patch[start] == 0 {
            patches += 1
            let color = label[start]
            patch[start] = patches
            stack.append(Int32(start))
            while let top = stack.popLast() {
                eachNeighbor(of: Int(top), width: width, height: height) { next in
                    if label[next] == color, patch[next] == 0 {
                        patch[next] = patches
                        stack.append(Int32(next))
                    }
                }
            }
        }
        func key(_ index: Int) -> UInt64 { UInt64(UInt32(patch[index])) << 32 | UInt64(UInt32(region.id[index])) }
        var shares: [UInt64: Int] = [:]
        var index = 0
        while index < count {
            guard label[index] != 0, region.id[index] != 0 else {
                index += 1
                continue
            }
            // Count a run of equal keys at once; rows are mostly long runs.
            let current = key(index)
            var end = index + 1
            while end < count, label[end] != 0, region.id[end] != 0, key(end) == current { end += 1 }
            shares[current, default: 0] += end - index
            index = end
        }
        var largest = [Int](repeating: 0, count: Int(patches) + 1)
        for (key, share) in shares {
            let name = Int(key >> 32)
            largest[name] = max(largest[name], share)
        }
        var strays = Set<UInt64>()
        for (key, share) in shares {
            let area = region.area[Int(key & 0xFFFF_FFFF)]
            if Double(share) < strayShare * Double(largest[Int(key >> 32)]), Double(share) < keepCoverage * Double(area) {
                strays.insert(key)
            }
        }
        guard !strays.isEmpty else { return }
        for index in 0..<count where label[index] != 0 && region.id[index] != 0 && strays.contains(key(index)) {
            label[index] = 0
        }
    }

    /// Spreads colour to the edges of every area that is mostly painted.
    private static func fillOut(label: inout [UInt8], region: Regions, width: Int, height: Int) {
        let count = width * height
        var painted = [Int](repeating: 0, count: region.area.count)
        for index in 0..<count where label[index] != 0 {
            painted[Int(region.id[index])] += 1
        }
        var full = [Bool](repeating: false, count: region.area.count)
        for name in 1..<region.area.count {
            full[name] = Double(painted[name]) >= fillOutCoverage * Double(region.area[name])
        }
        var queue: [Int32] = []
        for index in 0..<count where label[index] != 0 && full[Int(region.id[index])] {
            queue.append(Int32(index))
        }
        var head = 0
        while head < queue.count {
            let index = Int(queue[head])
            head += 1
            let name = region.id[index]
            let color = label[index]
            eachNeighbor(of: index, width: width, height: height) { next in
                if label[next] == 0, region.id[next] == name {
                    label[next] = color
                    queue.append(Int32(next))
                }
            }
        }
    }

    /// Smooths borders between colours inside an area. Each pixel near a
    /// border takes the colour that outweighs the others around it, counting
    /// only pixels of its own area so colour never crosses a line.
    private static func smooth(
        label: inout [UInt8], region: Regions, width: Int, height: Int, colors: Int, by smoothing: Double
    ) {
        guard smoothing > 0 else { return }
        let count = width * height
        let radius = Int((smoothing * 2).rounded(.up))
        var near = [UInt8](repeating: 0, count: count)
        var any = false
        for index in 0..<count where region.id[index] != 0 {
            let name = region.id[index]
            let color = label[index]
            eachNeighbor(of: index, width: width, height: height) { next in
                if region.id[next] == name, label[next] != color {
                    near[index] = 255
                    any = true
                }
            }
        }
        guard any else { return }
        near = dilate(near, width: width, height: height, radius: radius)
        var weights = [Float](repeating: 0, count: (2 * radius + 1) * (2 * radius + 1))
        for dy in -radius...radius {
            for dx in -radius...radius {
                let d2 = Double(dx * dx + dy * dy)
                weights[(dy + radius) * (2 * radius + 1) + dx + radius] = Float(exp(-d2 / (2 * smoothing * smoothing)))
            }
        }
        let old = label
        var votes = [Float](repeating: 0, count: colors)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard near[index] != 0, region.id[index] != 0 else { continue }
                let name = region.id[index]
                for color in 0..<colors { votes[color] = 0 }
                for dy in max(-radius, -y)...min(radius, height - 1 - y) {
                    let row = (y + dy) * width
                    let weightRow = (dy + radius) * (2 * radius + 1) + radius
                    for dx in max(-radius, -x)...min(radius, width - 1 - x) where region.id[row + x + dx] == name {
                        votes[Int(old[row + x + dx])] += weights[weightRow + dx]
                    }
                }
                var best = Int(old[index])
                for color in 0..<colors where votes[color] > votes[best] {
                    best = color
                }
                label[index] = UInt8(best)
            }
        }
        // Smoothing wears small dabs and thin strokes away. Any patch that
        // lost much of itself is put back as the person painted it, unless
        // it is only a hair of stray colour left where two brush edges met.
        var patch = [Int32](repeating: 0, count: count)
        var before = [0]
        var kept = [0]
        var isSolid = [false]
        var stack: [Int32] = []
        /// True when every pixel within two of this one is the same colour.
        func hasBody(at index: Int, color: UInt8) -> Bool {
            let x = index % width
            let y = index / width
            guard x >= 2, y >= 2, x < width - 2, y < height - 2 else { return false }
            for dy in -2...2 {
                for dx in -2...2 where old[index + dy * width + dx] != color {
                    return false
                }
            }
            return true
        }
        for start in 0..<count where old[start] != 0 && patch[start] == 0 {
            let name = Int32(before.count)
            let color = old[start]
            before.append(0)
            kept.append(0)
            isSolid.append(false)
            patch[start] = name
            stack.append(Int32(start))
            while let top = stack.popLast() {
                before[Int(name)] += 1
                if label[Int(top)] == color { kept[Int(name)] += 1 }
                if !isSolid[Int(name)], hasBody(at: Int(top), color: color) { isSolid[Int(name)] = true }
                eachNeighbor(of: Int(top), width: width, height: height) { next in
                    if old[next] == color, patch[next] == 0 {
                        patch[next] = name
                        stack.append(Int32(next))
                    }
                }
            }
        }
        for index in 0..<count where patch[index] != 0 {
            let name = Int(patch[index])
            if isSolid[name], Double(kept[name]) < smallPatchKept * Double(before[name]) {
                label[index] = old[index]
            }
        }
    }

    /// Lets colour reach a little way under the lines, so no paper shows
    /// between a colour and the soft edge of the line above it.
    private static func tuckUnder(label: inout [UInt8], wall: [UInt8], width: Int, height: Int, steps: Int) {
        guard steps > 0 else { return }
        var front: [Int32] = []
        for index in 0..<width * height where label[index] != 0 {
            front.append(Int32(index))
        }
        for _ in 0..<steps {
            var next: [Int32] = []
            for from in front {
                let color = label[Int(from)]
                eachNeighbor(of: Int(from), width: width, height: height) { index in
                    if wall[index] != 0, label[index] == 0 {
                        label[index] = color
                        next.append(Int32(index))
                    }
                }
            }
            front = next
        }
    }

    /// Paints the colours, softening each border by one pixel.
    private static func render(
        label: [UInt8], colors: [(r: UInt8, g: UInt8, b: UInt8)], width: Int, height: Int
    ) -> CGImage? {
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    let own = label[index]
                    var mixed = false
                    if x > 0, x < width - 1, y > 0, y < height - 1 {
                        mixed = label[index - 1] != own || label[index + 1] != own
                            || label[index - width] != own || label[index + width] != own
                    }
                    if !mixed {
                        guard own != 0 else { continue }
                        let color = colors[Int(own)]
                        out[index * 4] = color.r
                        out[index * 4 + 1] = color.g
                        out[index * 4 + 2] = color.b
                        out[index * 4 + 3] = 255
                        continue
                    }
                    // A 3x3 tent over premultiplied colour; "no colour" is transparent.
                    var r = 0, g = 0, b = 0, a = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let other = label[index + dy * width + dx]
                            guard other != 0 else { continue }
                            let weight = (2 - abs(dx)) * (2 - abs(dy))
                            let color = colors[Int(other)]
                            r += Int(color.r) * weight
                            g += Int(color.g) * weight
                            b += Int(color.b) * weight
                            a += 255 * weight
                        }
                    }
                    out[index * 4] = UInt8(r / 16)
                    out[index * 4 + 1] = UInt8(g / 16)
                    out[index * 4 + 2] = UInt8(b / 16)
                    out[index * 4 + 3] = UInt8(a / 16)
                }
            }
        }
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: Raster.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
