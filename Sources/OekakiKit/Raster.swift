import CoreGraphics
import CoreImage
import Foundation

/// Bitmap drawing shared by the canvas, export and the paint bucket.
///
/// Layer bitmaps use canvas coordinates: the origin is the top left and y
/// grows downward, so a canvas point (x, y) is the pixel at row y, column x.
enum Raster {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An RGBA bitmap with y growing upward, as CoreGraphics has it by default.
    static func makeContext(width: Int, height: Int) -> CGContext {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Could not create a \(width)x\(height) bitmap")
        }
        return context
    }

    /// A transparent bitmap set up for canvas coordinates.
    static func makeLayerContext(width: Int, height: Int) -> CGContext {
        let context = makeContext(width: width, height: height)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        return context
    }

    /// An image that reads the context's pixels directly instead of copying
    /// them. Only valid while the context is alive and not being drawn into.
    static func liveImage(of context: CGContext) -> CGImage? {
        guard let data = context.data else { return nil }
        let size = context.bytesPerRow * context.height
        guard let provider = CGDataProvider(dataInfo: nil, data: data, size: size, releaseData: { _, _, _ in }) else {
            return nil
        }
        return CGImage(
            width: context.width, height: context.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: context.bytesPerRow, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Runs `body` with y growing upward inside `rect`, so images and masks
    /// drawn into `rect` come out the right way up in a canvas-coordinate context.
    static func upright(_ rect: CGRect, in context: CGContext, _ body: () -> Void) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.minY + rect.maxY)
        context.scaleBy(x: 1, y: -1)
        body()
        context.restoreGState()
    }

    static func clear(_ context: CGContext) {
        context.clear(CGRect(x: 0, y: 0, width: context.width, height: context.height))
    }

    /// Draws one layer item into a canvas-coordinate context.
    static func draw(_ item: LayerItem, in context: CGContext) {
        switch item {
        case .stroke(let stroke):
            StrokeRenderer.draw(stroke, in: context)
        case .bitmap(let image, let alpha, _):
            let rect = CGRect(x: 0, y: 0, width: context.width, height: context.height)
            upright(rect, in: context) {
                context.setAlpha(alpha)
                context.draw(image, in: rect)
            }
        case .group(let group):
            // A sheet of its own, so an eraser inside the group only erases the group.
            let sheet = makeLayerContext(width: context.width, height: context.height)
            group.items.forEach { draw($0, in: sheet) }
            guard let image = sheet.makeImage() else { return }
            draw(.bitmap(image, alpha: group.alpha), in: context)
        case .gradient(let gradient):
            drawGradient(gradient, in: context)
        case .instance(let instance):
            // Like a group: a sheet of its own, so its erasers stay inside it.
            let sheet = makeLayerContext(width: context.width, height: context.height)
            instance.content.forEach { draw($0, in: sheet) }
            guard let image = sheet.makeImage() else { return }
            draw(.bitmap(image, alpha: 1), in: context)
        case .fill(let fill):
            upright(fill.rect, in: context) {
                context.setFillColor(fill.color.cgColor)
                // The ring goes behind whatever is already on the layer, so an
                // outline drawn on the same layer keeps its edge.
                context.saveGState()
                context.clip(to: fill.rect, mask: fill.full)
                context.setBlendMode(.destinationOver)
                context.fill(fill.rect)
                context.restoreGState()
                // The region itself is repainted.
                context.saveGState()
                context.clip(to: fill.rect, mask: fill.interior)
                context.setBlendMode(.normal)
                context.fill(fill.rect)
                context.restoreGState()
            }
        }
    }

    static func drawGradient(_ item: GradientItem, in context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: colorSpace, colors: [item.from.cgColor, item.to.cgColor] as CFArray, locations: [0, 1]
        ) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(.normal)
        switch item.shape {
        case .linear:
            context.drawLinearGradient(gradient, start: item.start, end: item.end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radial:
            let radius = max(hypot(item.end.x - item.start.x, item.end.y - item.start.y), 1)
            context.drawRadialGradient(
                gradient, startCenter: item.start, startRadius: 0, endCenter: item.start, endRadius: radius, options: [.drawsAfterEndLocation]
            )
        }
    }

    /// The alpha (0...255) of the pixel at canvas point (x, y) of a picture
    /// that covers `rect`, or 0 outside it. For a grey mask it is the grey.
    static func sample(_ image: CGImage, covering rect: CGRect, at point: CGPoint) -> UInt8 {
        let column = Int((point.x - rect.minX).rounded(.down))
        let row = Int((point.y - rect.minY).rounded(.down))
        guard column >= 0, row >= 0, column < Int(rect.width), row < Int(rect.height) else { return 0 }
        let isMask = image.colorSpace?.model == .monochrome && image.alphaInfo == .none
        var pixel = [UInt8](repeating: 0, count: isMask ? 1 : 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: isMask ? 1 : 4,
                space: isMask ? CGColorSpaceCreateDeviceGray() : colorSpace,
                bitmapInfo: isMask ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Shift the picture so the wanted pixel lands on the one pixel of the context.
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: -column, y: -(Int(rect.height) - 1 - row), width: Int(rect.width), height: Int(rect.height)))
            return true
        }
        guard drawn else { return 0 }
        return isMask ? pixel[0] : pixel[3]
    }

    /// An 8-bit grey image over `bytes`, used as a clipping mask (255 = paint).
    static func maskImage(bytes: Data, width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

/// Draws strokes as a chain of short curves whose width follows the pressure.
///
/// A stroke is drawn piece by piece as points arrive, and replayed the same
/// way later, so the picture on screen and the picture after undo match.
enum StrokeRenderer {
    /// The thinnest a pressure-sensitive stroke gets, as a share of its width.
    static let minimumPressureScale: CGFloat = 0.25

    static func width(of stroke: Stroke, pressure: CGFloat) -> CGFloat {
        let clamped = min(max(pressure, 0), 1)
        return stroke.width * (minimumPressureScale + (1 - minimumPressureScale) * clamped)
    }

    private static func prepare(_ context: CGContext, for stroke: Stroke, marking: Bool = false) {
        // A see-through or soft stroke is marked at full strength on a sheet
        // of its own, which is then laid on the layer; see `draw`.
        context.setBlendMode(stroke.isEraser && !marking ? .clear : .normal)
        context.setStrokeColor(stroke.color.cgColor)
        context.setFillColor(stroke.color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    private static func middle(_ a: StrokePoint, _ b: StrokePoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func bounds(of points: [CGPoint], padding: CGFloat) -> CGRect {
        var rect = CGRect(origin: points[0], size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    /// Draws the piece that the point at `index` adds. Returns the area touched.
    /// For a stroke that is not plain this is its mark, at full strength;
    /// see `draw` for how the marks are laid on the layer.
    @discardableResult
    static func drawPiece(of stroke: Stroke, endingAt index: Int, in context: CGContext) -> CGRect {
        let points = stroke.points
        guard index >= 0, index < points.count else { return .null }
        if stroke.softness > 0 {
            return dab(stroke, endingAt: index, in: context)
        }
        context.saveGState()
        defer { context.restoreGState() }
        prepare(context, for: stroke, marking: !stroke.isPlain)

        if index == 0 {
            let diameter = width(of: stroke, pressure: points[0].pressure)
            let dot = CGRect(x: points[0].x - diameter / 2, y: points[0].y - diameter / 2, width: diameter, height: diameter)
            context.fillEllipse(in: dot)
            return dot.insetBy(dx: -2, dy: -2)
        }

        let lineWidth = width(of: stroke, pressure: (points[index - 1].pressure + points[index].pressure) / 2)
        context.setLineWidth(lineWidth)
        let end = middle(points[index - 1], points[index])
        context.beginPath()
        if index == 1 {
            context.move(to: points[0].point)
            context.addLine(to: end)
            context.strokePath()
            return bounds(of: [points[0].point, end], padding: lineWidth / 2 + 2)
        }
        let start = middle(points[index - 2], points[index - 1])
        context.move(to: start)
        context.addQuadCurve(to: end, control: points[index - 1].point)
        context.strokePath()
        return bounds(of: [start, points[index - 1].point, end], padding: lineWidth / 2 + 2)
    }

    /// Draws the last bit, from the final midpoint to the final point.
    @discardableResult
    static func drawTail(of stroke: Stroke, in context: CGContext) -> CGRect {
        let points = stroke.points
        guard points.count >= 2, stroke.softness <= 0 else { return .null }
        context.saveGState()
        defer { context.restoreGState() }
        prepare(context, for: stroke, marking: !stroke.isPlain)
        let last = points[points.count - 1]
        let lineWidth = width(of: stroke, pressure: last.pressure)
        let start = middle(points[points.count - 2], last)
        context.setLineWidth(lineWidth)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: last.point)
        context.strokePath()
        return bounds(of: [start, last.point], padding: lineWidth / 2 + 2)
    }

    static func draw(_ stroke: Stroke, in context: CGContext) {
        guard !stroke.isPlain else {
            for index in stroke.points.indices {
                drawPiece(of: stroke, endingAt: index, in: context)
            }
            drawTail(of: stroke, in: context)
            return
        }
        // Mark the stroke on a sheet of its own, then lay the sheet on the
        // layer at the stroke's opacity, so overlaps do not build up.
        let area = extent(of: stroke).intersection(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard !area.isEmpty else { return }
        let sheet = Raster.makeLayerContext(width: Int(area.width), height: Int(area.height))
        sheet.translateBy(x: -area.minX, y: -area.minY)
        for index in stroke.points.indices {
            drawPiece(of: stroke, endingAt: index, in: sheet)
        }
        drawTail(of: stroke, in: sheet)
        guard let marks = sheet.makeImage() else { return }
        lay(marks, of: stroke, in: area, on: context)
    }

    /// Puts a stroke's marks, drawn on a sheet covering `area`, on a layer.
    static func lay(_ marks: CGImage, of stroke: Stroke, in area: CGRect, on context: CGContext) {
        Raster.upright(area, in: context) {
            context.setAlpha(min(max(stroke.opacity, 0), 1))
            context.setBlendMode(stroke.isEraser ? .destinationOut : .normal)
            context.draw(marks, in: area)
        }
    }

    /// The whole area a stroke can touch, in whole pixels.
    static func extent(of stroke: Stroke) -> CGRect {
        guard !stroke.points.isEmpty else { return .null }
        return bounds(of: stroke.points.map(\.point), padding: stroke.width / 2 + 3).integral
    }

    // MARK: Airbrush

    /// Distance between the dabs of a soft stroke.
    static func dabSpacing(_ stroke: Stroke) -> CGFloat {
        max(0.75, stroke.width * 0.06)
    }

    /// Draws the soft dabs that fall on the segment ending at point `index`.
    /// Dabs sit at fixed distances along the stroke, so drawing the stroke
    /// piece by piece or all at once puts them in the same places.
    private static func dab(_ stroke: Stroke, endingAt index: Int, in context: CGContext) -> CGRect {
        let points = stroke.points
        let spacing = dabSpacing(stroke)
        var before: CGFloat = 0
        for step in stride(from: 1, to: index, by: 1) {
            before += hypot(points[step].x - points[step - 1].x, points[step].y - points[step - 1].y)
        }
        var dabs: [(CGPoint, CGFloat)] = []
        if index == 0 {
            dabs.append((points[0].point, points[0].pressure))
        } else {
            let a = points[index - 1], b = points[index]
            let length = hypot(b.x - a.x, b.y - a.y)
            var next = (before / spacing).rounded(.down) * spacing + spacing
            while next <= before + length, length > 0 {
                let t = (next - before) / length
                dabs.append((CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), a.pressure + (b.pressure - a.pressure) * t))
                next += spacing
            }
        }
        guard !dabs.isEmpty else { return .null }
        let core = min(max(1 - stroke.softness, 0), 0.95)
        let solid = RGBA(r: stroke.color.r, g: stroke.color.g, b: stroke.color.b)
        let clear = RGBA(r: stroke.color.r, g: stroke.color.g, b: stroke.color.b, a: 0)
        guard let gradient = CGGradient(
            colorsSpace: Raster.colorSpace, colors: [solid.cgColor, solid.cgColor, clear.cgColor] as CFArray, locations: [0, core, 1]
        ) else { return .null }
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(.normal)
        var touched = CGRect.null
        for (center, pressure) in dabs {
            let radius = max(width(of: stroke, pressure: pressure) / 2, 0.5)
            // Enough dabs overlap across one width to build up to nearly full.
            context.setAlpha(1 - pow(0.0015, spacing / (2 * radius)))
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            touched = touched.union(CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        return touched.insetBy(dx: -2, dy: -2)
    }
}

// MARK: Putting layers together

/// A layer ready to be put together with the others.
struct SheetPicture {
    var id: UUID
    var image: CGImage?
    var isVisible: Bool
    var opacity: Double
    var style: LayerStyle
    /// Changes whenever the pixels change, so the glow is made again.
    var revision: Int
}

/// Puts layers together with their blend modes, clipping, glow, blur and dots.
final class Compositor {
    let width: Int
    let height: Int
    private lazy var group = Raster.makeContext(width: width, height: height)
    private lazy var masked = Raster.makeContext(width: width, height: height)
    /// Each glowing layer's blurred picture, with the revision and radius it was made for.
    private var glows: [UUID: (revision: Int, radius: CGFloat, image: CGImage)] = [:]
    /// Each blurred layer's picture, kept the same way.
    private var blurs: [UUID: (revision: Int, radius: CGFloat, image: CGImage)] = [:]
    /// Each layer turned into dots, kept the same way.
    private var tones: [UUID: (revision: Int, spacing: CGFloat, image: CGImage)] = [:]
    private static let blur = CIContext(options: [.workingColorSpace: Raster.colorSpace, .outputColorSpace: Raster.colorSpace])

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    private var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    /// Draws the layers, back to front, onto `picture`: a plain context the
    /// size of the canvas. With `region` (canvas coordinates) only that part.
    func flatten(_ sheets: [SheetPicture], onto picture: CGContext, region: CGRect? = nil) {
        let clip = region.map { CGRect(x: $0.minX, y: CGFloat(height) - $0.maxY, width: $0.width, height: $0.height).integral } ?? bounds
        var index = 0
        var used: Set<UUID> = []
        while index < sheets.count {
            let base = sheets[index]
            index += 1
            var clipped: [SheetPicture] = []
            while index < sheets.count, sheets[index].style.isClipped {
                clipped.append(sheets[index])
                index += 1
            }
            guard base.isVisible, var image = base.image else { continue }
            let shown = clipped.filter { $0.isVisible && $0.image != nil }
            // A blurred layer keeps the sharp edge of the base for what is clipped to it.
            let edge = image
            if !shown.isEmpty {
                // The clipped layers go onto a copy of the base, kept inside its paint.
                group.saveGState()
                group.clip(to: clip)
                group.clear(bounds)
                group.draw(image, in: bounds)
                for layer in shown {
                    guard var top = layer.image else { continue }
                    if layer.style.blur > 0, let soft = blurred(layer.id, revision: layer.revision, radius: layer.style.blur, image: top) {
                        top = soft
                        used.insert(layer.id)
                    }
                    if layer.style.tone > 0, let dots = toned(layer.id, revision: Self.revision(layer.revision, blur: layer.style.blur), spacing: layer.style.tone, image: top) {
                        top = dots
                        used.insert(layer.id)
                    }
                    masked.saveGState()
                    masked.clip(to: clip)
                    masked.clear(bounds)
                    masked.draw(top, in: bounds)
                    masked.setBlendMode(.destinationIn)
                    masked.draw(edge, in: bounds)
                    masked.restoreGState()
                    guard let inside = Raster.liveImage(of: masked) else { continue }
                    if layer.style.glow > 0, let glow = glow(of: layer, image: top) {
                        group.setAlpha(layer.opacity)
                        group.setBlendMode(layer.style.blend == .add ? .plusLighter : .screen)
                        group.draw(glow, in: bounds)
                    }
                    group.setAlpha(layer.opacity)
                    group.setBlendMode(layer.style.blend.cgBlendMode)
                    group.draw(inside, in: bounds)
                    used.insert(layer.id)
                }
                group.restoreGState()
                guard let together = group.makeImage() else { continue }
                image = together
            }
            var lit = base
            if !shown.isEmpty {
                // The glow follows the clipped layers too.
                var hasher = Hasher()
                hasher.combine(base.revision)
                shown.forEach {
                    hasher.combine($0.revision); hasher.combine($0.opacity); hasher.combine($0.style.blend)
                    hasher.combine($0.style.glow); hasher.combine($0.style.blur); hasher.combine($0.style.tone)
                }
                lit.revision = hasher.finalize()
            }
            // The base blurs with everything clipped to it, as one.
            if base.style.blur > 0, let soft = blurred(base.id, revision: lit.revision, radius: base.style.blur, image: image) {
                image = soft
                used.insert(base.id)
            }
            // And turns into dots with them, after any blur, so a soft edge gives smaller dots.
            if base.style.tone > 0, let dots = toned(base.id, revision: Self.revision(lit.revision, blur: base.style.blur), spacing: base.style.tone, image: image) {
                image = dots
                used.insert(base.id)
            }
            picture.saveGState()
            picture.clip(to: clip)
            if base.style.glow > 0, let glow = glow(of: lit, image: image) {
                picture.setAlpha(base.opacity)
                picture.setBlendMode(base.style.blend == .add ? .plusLighter : .screen)
                picture.draw(glow, in: bounds)
                used.insert(base.id)
            }
            picture.setAlpha(base.opacity)
            picture.setBlendMode(base.style.blend.cgBlendMode)
            picture.draw(image, in: bounds)
            picture.restoreGState()
        }
        glows = glows.filter { used.contains($0.key) }
        blurs = blurs.filter { used.contains($0.key) }
        tones = tones.filter { used.contains($0.key) }
    }

    /// What the dots are made from: the pixels, and how far they were blurred first.
    private static func revision(_ revision: Int, blur: CGFloat) -> Int {
        var hasher = Hasher()
        hasher.combine(revision)
        hasher.combine(blur)
        return hasher.finalize()
    }

    /// The picture as black dots on a 45° screen, `spacing` pixels apart: the
    /// darker the paint, the bigger the dots, and none where there is no paint.
    private func toned(_ id: UUID, revision: Int, spacing: CGFloat, image: CGImage) -> CGImage? {
        if let kept = tones[id], kept.revision == revision, kept.spacing == spacing {
            return kept.image
        }
        let input = CIImage(cgImage: image)
        let paper = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: input.extent)
        let screened = input.composited(over: paper).applyingFilter("CIDotScreen", parameters: [
            kCIInputCenterKey: CIVector(x: 0, y: 0),
            kCIInputAngleKey: Double.pi / 4,
            kCIInputWidthKey: Double(spacing),
            kCIInputSharpnessKey: 0.9,
        ])
        // Dark dots become black ink; the paper between them becomes clear.
        let ink = screened.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha").applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
        let kept = ink.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: input]).cropped(to: input.extent)
        guard let output = Self.blur.createCGImage(kept, from: input.extent) else { return nil }
        tones[id] = (revision, spacing, output)
        return output
    }

    private func blurred(_ id: UUID, revision: Int, radius: CGFloat, image: CGImage) -> CGImage? {
        if let kept = blurs[id], kept.revision == revision, kept.radius == radius {
            return kept.image
        }
        let input = CIImage(cgImage: image)
        let soft = input.clampedToExtent().applyingGaussianBlur(sigma: Double(radius) / 2).cropped(to: input.extent)
        guard let output = Self.blur.createCGImage(soft, from: input.extent) else { return nil }
        blurs[id] = (revision, radius, output)
        return output
    }

    private func glow(of sheet: SheetPicture, image: CGImage) -> CGImage? {
        if let kept = glows[sheet.id], kept.revision == sheet.revision, kept.radius == sheet.style.glow {
            return kept.image
        }
        let input = CIImage(cgImage: image)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: Double(sheet.style.glow) / 2).cropped(to: input.extent)
        guard let output = Self.blur.createCGImage(blurred, from: input.extent) else { return nil }
        glows[sheet.id] = (sheet.revision, sheet.style.glow, output)
        return output
    }
}
