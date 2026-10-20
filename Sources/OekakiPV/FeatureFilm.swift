import CoreGraphics
import Foundation
import OekakiKit

/// A short film of four features on the evening picture: picking many lines
/// at once, switching colour sets, parts, and the assistant's ideas as versions.
/// Every picture in it is the document itself at that moment.
final class FeatureFilm {
    static let fps = 30

    struct Times {
        static let title = 0.0
        static let multi = 2.5
        static let colors = 9.5
        static let parts = 16.5
        static let versions = 23.5
        static let ending = 31.0
        static let end = 33.5
    }

    // Pictures of the document, taken as each scene is acted out.
    private var waves: [CGImage] = []
    /// The picked lines' boxes, after each press of "stronger".
    private var pickedBoxes: [[CGRect]] = []
    /// The part of the hair shown magnified, before and now, in canvas pixels.
    private var zoomRegion = CGRect.null
    private var pickedCount = 0
    private var evening: CGImage?
    private var night: CGImage?
    private var swatches: [(name: String, evening: RGBA, night: RGBA)] = []
    private var partSteps: [CGImage] = []
    private var partRecolored: CGImage?
    private var partUses = 0
    /// Each idea with the colours it gives, as they would be shown side by side.
    private var ideas: [(name: String, picture: CGImage, note: String, colors: [RGBA])] = []
    private var main: CGImage?
    private var adopted: CGImage?
    let ideaSource: String
    let request: String
    private let wordmark = Logo.dropOnly().flatMap { BrandArt.dropWordmark($0, withTagline: false) }
    private var canvasSize = CGSize(width: 1080, height: 1200)

    init(proposals: [Proposal], source: String, request: String) {
        ideaSource = source
        self.request = request
        act(proposals)
    }

    /// Acts out the four features on the picture, keeping what each looks like.
    private func act(_ proposals: [Proposal]) {
        // Many lines at once: the hair's strands and sheen, wavier step by step.
        let picture = Portrait.draw()
        let document = picture.document
        canvasSize = CGSize(width: document.width, height: document.height)
        let strands = document.layers.filter { ["線画", "光"].contains($0.name) }.flatMap(\.items).compactMap { item -> Int? in
            guard case .stroke(let stroke) = item, !stroke.isEraser else { return nil }
            let area = item.bounds(canvas: document.bounds)
            let isStrand = (stroke.width > 3.1 && stroke.width < 3.6 && max(area.width, area.height) > 140)
            let isSheen = abs(stroke.color.r - Portrait.Paint.shine.r) < 0.01 && abs(stroke.color.g - Portrait.Paint.shine.g) < 0.01
            return isStrand || isSheen ? item.id : nil
        }
        pickedCount = strands.count
        func boxes() -> [CGRect] { strands.compactMap { document.item($0)?.item.bounds(canvas: document.bounds) } }
        pickedBoxes = [boxes()]
        waves = [document.compositeImage()].compactMap { $0 }
        // Where the most strands changed between the first picture and the last, so the change shows most.
        let side: CGFloat = 300
        let first = waves.first
        for _ in 0..<3 {
            document.changeWaviness(strands, by: Self.wave)
            if let image = document.compositeImage() { waves.append(image) }
            pickedBoxes.append(boxes())
        }
        if let first, let last = waves.last {
            zoomRegion = Self.busiest(first, last, side: side)
        }

        // Colour sets: the same picture, evening and night.
        let fresh = Portrait.draw().document
        // The colours scene goes on from the wavier hair of the first.
        for _ in 0..<3 { fresh.changeWaviness(strands, by: Self.wave) }
        let sets = Portrait.nameColors(fresh)
        evening = fresh.compositeImage()
        let eveningColors = fresh.library.swatches
        fresh.applyTheme(sets.night)
        night = fresh.compositeImage()
        swatches = zip(eveningColors, fresh.library.swatches).map { ($0.name, $0.color, $1.color) }
        // The part scene goes on at night, where the last scene left off.

        // Parts: a sparkle made a part, placed again and again, then recoloured.
        let sparkleLayer = fresh.insertLayer(named: "きらめき", items: [], at: fresh.layers.count - 1, style: LayerStyle(glow: 18))
        fresh.activeLayerID = sparkleLayer
        let artist = Artist(document: fresh)
        let gold = RGBA(hex: 0xFFD27A)
        let pen = Pen(width: 9, color: gold, start: 0.45, end: 0.45, floor: 0.05)
        var lines: [Int] = []
        for path in ["M 880 330 Q 880 380, 830 380 Q 880 380, 880 430 Q 880 380, 930 380 Q 880 380, 880 330"] {
            if let id = artist.line(path, pen) { lines.append(id) }
        }
        if let id = artist.line([CGPoint(x: 880, y: 380), CGPoint(x: 880.5, y: 380.5)], .airbrush(40, gold, opacity: 0.8)) { lines.append(id) }
        let sparkleColor = fresh.addSwatch(named: "きらめき", color: gold)
        fresh.bind(lines, to: sparkleColor)
        if fresh.makeComponent(from: lines, named: "きらめき") != nil, let part = fresh.library.components.last?.id {
            if let image = fresh.compositeImage() { partSteps.append(image) }
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(980, 230, 0.6), (790, 620, 0.8), (140, 220, 0.9), (1000, 900, 1.2), (170, 760, 0.7)]
            for (x, y, scale) in spots {
                fresh.placeComponent(part, at: CGPoint(x: x, y: y), scale: scale)
                if let image = fresh.compositeImage() { partSteps.append(image) }
            }
            partUses = fresh.uses(of: part).count
            fresh.setSwatchColor(sparkleColor, RGBA(hex: 0x8FE8FF))
            partRecolored = fresh.compositeImage()
        }

        // Versions: the assistant's ideas, each on a version of its own, tried
        // on the picture as the last scene left it.
        let base = fresh
        main = base.compositeImage()
        for proposal in proposals.prefix(3) {
            let id = base.branch(trying: proposal)
            let colors = base.branches.first { $0.id == id }?.colorChanges.map(\.after) ?? []
            let hidden = proposal.hiddenLayers.isEmpty ? "" : " · 「" + proposal.hiddenLayers.joined(separator: "」「") + "」を隠す"
            if let image = base.picture(ofBranch: id) { ideas.append((proposal.name, image, "\(colors.count) 色" + hidden, colors)) }
        }
        // Take the idea that changes the picture the most, so the change shows.
        func change(_ id: UUID) -> Double {
            base.branches.first { $0.id == id }?.colorChanges.reduce(0) { sum, c in
                sum + abs(c.before.r - c.after.r) + abs(c.before.g - c.after.g) + abs(c.before.b - c.after.b)
            } ?? 0
        }
        let pick = base.branches.dropFirst().max { change($0.id) < change($1.id) }
        if let index = pick.flatMap({ chosen in base.branches.firstIndex { $0.id == chosen.id } }), index > 1 {
            // Shown first, so it is the one compared and taken.
            ideas.swapAt(0, index - 1)
        }
        if let chosen = pick?.id {
            base.adoptBranch(chosen)
            adopted = base.compositeImage()
        }
    }

    /// How much each press of "stronger" adds to the wobble.
    static let wave: CGFloat = 2.2

    var frameCount: Int { Int((Times.end * Double(Self.fps)).rounded()) }

    // MARK: Layout

    private var canvasRect: CGRect {
        let area = Look.canvasArea.insetBy(dx: 24, dy: 24)
        let scale = min(area.width / canvasSize.width, area.height / canvasSize.height)
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func view(_ box: CGRect) -> CGRect {
        let rect = canvasRect
        let scale = rect.width / canvasSize.width
        return CGRect(x: rect.minX + box.minX * scale, y: rect.minY + box.minY * scale, width: box.width * scale, height: box.height * scale)
    }

    // MARK: Drawing

    func draw(at time: Double, in context: CGContext) {
        context.setFillColor(Look.window)
        context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
        if time < Times.multi {
            drawTitle(at: time, in: context)
        } else if time < Times.ending {
            drawChrome(in: context)
            switch time {
            case ..<Times.colors: drawMulti(at: time - Times.multi, in: context)
            case ..<Times.parts: drawColors(at: time - Times.colors, in: context)
            case ..<Times.versions: drawParts(at: time - Times.parts, in: context)
            default: drawVersions(at: time - Times.versions, in: context)
            }
        } else {
            drawEnding(at: time - Times.ending, in: context)
        }
        // Each scene fades in from black.
        let starts = [Times.title, Times.multi, Times.colors, Times.parts, Times.versions, Times.ending]
        if let start = starts.last(where: { $0 <= time }) {
            let dark = 1 - Ease.ramp(time, start, 0.35)
            if dark > 0 {
                context.setFillColor(CGColor(gray: 0, alpha: dark))
                context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
            }
        }
    }

    private func drawChrome(in context: CGContext) {
        context.setFillColor(Look.window)
        context.fill(Look.titleBar)
        for (index, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            context.setFillColor(Look.color(UInt32(hex)))
            context.fillEllipse(in: CGRect(x: 20 + CGFloat(index) * 22, y: 15, width: 14, height: 14))
        }
        Look.draw("picture.\(DocumentFile.fileExtension) — Oekaki Studio", font: Look.uiFont(17), color: Look.dim, centeredAt: CGPoint(x: 960, y: 22), in: context)
        context.setFillColor(Look.editor)
        context.fill(Look.canvasArea)
        context.setFillColor(Look.panelBackground)
        context.fill(Look.panel)
        context.setFillColor(Look.border)
        context.fill(CGRect(x: Look.panel.minX, y: Look.panel.minY, width: 1, height: Look.panel.height))
        context.setFillColor(Look.teal)
        context.fill(Look.statusBar)
    }

    private func drawCanvas(_ image: CGImage?, in context: CGContext) {
        let rect = canvasRect
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 8), blur: 30, color: Look.color(0x000000, alpha: 0.5))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.restoreGState()
        if let image { Look.draw(image, in: rect, context: context) }
    }

    private func blend(_ from: CGImage?, _ to: CGImage?, _ amount: CGFloat, in context: CGContext) {
        drawCanvas(from, in: context)
        guard amount > 0, let to else { return }
        context.saveGState()
        context.setAlpha(amount)
        Look.draw(to, in: canvasRect, context: context)
        context.restoreGState()
    }

    private func caption(_ text: String, at time: Double, length: Double, in context: CGContext) {
        let alpha = min(Ease.ramp(time, 0.3, 0.35), 1 - Ease.ramp(time, length - 0.4, 0.35))
        guard alpha > 0 else { return }
        let font = Look.uiFont(40, bold: true)
        let line = Look.line(text, font: font, color: Look.color(0xFFFFFF))
        let width = Look.width(of: line) + 64
        let center = CGPoint(x: Look.canvasArea.midX, y: Look.canvasArea.maxY - 78)
        let box = CGRect(x: center.x - width / 2, y: center.y - 38, width: width, height: 76)
        context.saveGState()
        context.setAlpha(alpha)
        context.addPath(Look.roundedRect(box, radius: 38))
        context.setFillColor(Look.color(0x101216, alpha: 0.86))
        context.fillPath()
        Look.draw(text, font: font, color: Look.color(0xFFFFFF), centeredAt: center, in: context)
        context.restoreGState()
    }

    /// The panel's heading and a line of code saying what is being done.
    private func panelHeading(_ title: String, code: String, in context: CGContext) -> CGFloat {
        let panel = Look.panel
        Look.draw(Look.line(title, font: Look.uiFont(26, bold: true), color: Look.text), at: CGPoint(x: panel.minX + 32, y: panel.minY + 56), in: context)
        let box = CGRect(x: panel.minX + 24, y: panel.minY + 80, width: panel.width - 48, height: 46)
        context.addPath(Look.roundedRect(box, radius: 8))
        context.setFillColor(Look.color(0x191B21))
        context.fillPath()
        Look.draw(Look.line(code, font: Look.codeFont(17), color: CodeColor.function.cgColor), at: CGPoint(x: box.minX + 16, y: box.midY + 6), in: context)
        return box.maxY + 30
    }

    private func button(_ title: String, in box: CGRect, pressed: Bool, in context: CGContext) {
        context.addPath(Look.roundedRect(box, radius: 10))
        context.setFillColor(pressed ? Look.accent : Look.color(0x31353F))
        context.fillPath()
        Look.draw(title, font: Look.uiFont(20, bold: true), color: pressed ? Look.color(0x0F1A26) : Look.text, centeredAt: CGPoint(x: box.midX, y: box.midY), in: context)
    }

    private func status(_ text: String, in context: CGContext) {
        Look.draw(Look.line(text, font: Look.uiFont(15, bold: true), color: Look.color(0xFFFFFF)), at: CGPoint(x: 20, y: Look.statusBar.minY + 21), in: context)
    }

    // MARK: Scenes

    private func drawTitle(at time: Double, in context: CGContext) {
        context.setFillColor(Look.editor)
        context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
        Look.draw("Oekaki Studio に、IDE らしい道具を 4 つ", font: Look.uiFont(58, bold: true), color: Look.text, centeredAt: CGPoint(x: 960, y: 420), in: context)
        let items = ["まとめて選ぶ", "名前付きの色", "部品", "AI の案"]
        for (index, item) in items.enumerated() {
            let alpha = Ease.out(Ease.ramp(time, 0.5 + Double(index) * 0.25, 0.4))
            context.saveGState()
            context.setAlpha(alpha)
            let box = CGRect(x: 960 - 2 * 250 + CGFloat(index) * 250 + 10, y: 520, width: 230, height: 70)
            context.addPath(Look.roundedRect(box, radius: 14))
            context.setFillColor(Look.color(0x2A2F3A))
            context.fillPath()
            Look.draw(item, font: Look.uiFont(26, bold: true), color: Look.accent, centeredAt: CGPoint(x: box.midX, y: box.midY), in: context)
            context.restoreGState()
        }
    }

    private func drawMulti(at t: Double, in context: CGContext) {
        // Waves get stronger at 2.2s, 3.3s and 4.4s, each blended in over half a second.
        let steps = [2.2, 3.3, 4.4]
        let done = steps.filter { t >= $0 + 0.5 }.count
        let blending = steps.firstIndex { t >= $0 && t < $0 + 0.5 }
        if let blending, blending + 1 < waves.count {
            blend(waves[blending], waves[blending + 1], Ease.inOut(CGFloat((t - steps[blending]) / 0.5)), in: context)
        } else {
            drawCanvas(waves[min(done, waves.count - 1)], in: context)
        }
        // The picked lines light up one after another, like cursors being added.
        let picked = pickedBoxes[min(done, pickedBoxes.count - 1)]
        // The hair is shown as it is for a moment, then picked strand by strand.
        let shown = Int(Double(picked.count) * Double(Ease.ramp(t, 1.2, 0.6)))
        context.saveGState()
        // Lines that run off the canvas are boxed only as far as its edge.
        context.clip(to: canvasRect.insetBy(dx: -6, dy: -6))
        context.setShadow(offset: .zero, blur: 10, color: Look.accent)
        context.setStrokeColor(Look.accent)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [6, 4])
        // Once "stronger" is pressed the boxes fade, so the lines can be seen, but stay faintly to show what is picked.
        context.setAlpha(1 - 0.75 * Ease.ramp(t, steps[0] - 0.2, 0.4))
        for box in picked.prefix(shown) {
            context.stroke(view(box).insetBy(dx: -4, dy: -4).intersection(canvasRect.insetBy(dx: 2, dy: 2)))
        }
        context.restoreGState()
        var y = panelHeading("まとめて選ぶ", code: "select(髪の束 ×\(shown))" + String(repeating: ".wave(×\(Self.wave))", count: done), in: context)
        Look.draw(Look.line("\(shown) 個を選んでいます", font: Look.uiFont(24, bold: true), color: Look.text), at: CGPoint(x: Look.panel.minX + 32, y: y + 10), in: context)
        Look.draw(Look.line("⌘ クリックで足して、ドラッグで囲んで", font: Look.uiFont(18), color: Look.dim), at: CGPoint(x: Look.panel.minX + 32, y: y + 46), in: context)
        y += 90
        Look.draw(Look.line("うねり", font: Look.uiFont(22, bold: true), color: Look.text), at: CGPoint(x: Look.panel.minX + 32, y: y + 34), in: context)
        let pressed = steps.contains { t >= $0 && t < $0 + 0.25 }
        button("おだやかに", in: CGRect(x: Look.panel.minX + 150, y: y, width: 190, height: 50), pressed: false, in: context)
        button("強く", in: CGRect(x: Look.panel.minX + 360, y: y, width: 150, height: 50), pressed: pressed, in: context)
        Look.draw(Look.line("取り消しは 1 回で全部戻る", font: Look.uiFont(18), color: Look.dim), at: CGPoint(x: Look.panel.minX + 32, y: y + 100), in: context)
        drawZoom(t: t, steps: steps, done: done, blending: blending, top: y + 150, in: context)
        status("◆ 選択 \(shown) 個    「強く」を \(done) 回", in: context)
        caption("髪の束をまとめて選んで、うねりを強く。", at: t, length: Times.colors - Times.multi, in: context)
    }

    /// The square of `side` pixels where the two pictures differ most.
    static func busiest(_ a: CGImage, _ b: CGImage, side: CGFloat) -> CGRect {
        let width = a.width, height = a.height
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return data
        }
        let pa = pixels(a), pb = pixels(b)
        // Red, such as the ribbon, is left out of the square: the hair is what changed.
        func isRed(_ i: Int) -> Bool { Int(pa[i]) > 120 && Int(pa[i]) > Int(pa[i + 1]) * 2 && Int(pa[i]) > Int(pa[i + 2]) * 2 }
        // Differences counted on a coarse grid of 20-pixel cells; rows run top down.
        let cell = 10
        let columns = width / cell, rows = height / cell
        var counts = [Int](repeating: 0, count: columns * rows)
        var red = [Int](repeating: 0, count: columns * rows)
        for y in 0..<rows * cell {
            for x in 0..<columns * cell {
                let i = (y * width + x) * 4
                if isRed(i) { red[(y / cell) * columns + x / cell] += 1 }
                if abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2])) > 60 {
                    counts[(y / cell) * columns + x / cell] += 1
                }
            }
        }
        let span = Int(side) / cell
        var best = (score: -1, x: 0, y: 0)
        for row in 0...max(0, rows - span) {
            for column in 0...max(0, columns - span) {
                var score = 0
                var reds = 0
                for r in row..<min(rows, row + span) {
                    for c in column..<min(columns, column + span) {
                        score += counts[r * columns + c]
                        reds += red[r * columns + c]
                    }
                }
                guard reds < 40 else { continue }
                if score > best.score { best = (score, column, row) }
            }
        }
        return CGRect(x: best.x * cell, y: best.y * cell, width: Int(side), height: Int(side))
    }

    /// A part of the hair magnified, as it was and as it is now, so the
    /// stronger wobble can be seen, with that part marked on the canvas.
    private func drawZoom(t: Double, steps: [Double], done: Int, blending: Int?, top: CGFloat, in context: CGContext) {
        guard !zoomRegion.isNull, let first = waves.first, let before = first.cropping(to: zoomRegion) else { return }
        let alpha = Ease.out(Ease.ramp(t, steps[0] - 0.6, 0.4))
        guard alpha > 0 else { return }
        context.saveGState()
        context.setAlpha(alpha)
        // Where on the canvas.
        context.setStrokeColor(Look.color(0xFFFFFF))
        context.setLineWidth(3)
        context.stroke(view(zoomRegion))
        Look.draw(Look.line("同じ所を見比べる", font: Look.uiFont(22, bold: true), color: Look.text), at: CGPoint(x: Look.panel.minX + 32, y: top + 24), in: context)
        let side: CGFloat = 278
        let left = CGRect(x: Look.panel.minX + 32, y: top + 50, width: side, height: side)
        let right = CGRect(x: left.maxX + 20, y: left.minY, width: side, height: side)
        for box in [left, right] {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
        }
        Look.draw(before, in: left, context: context)
        let now = waves[min(done, waves.count - 1)].cropping(to: zoomRegion)
        if let blending, blending + 1 < waves.count, let from = waves[blending].cropping(to: zoomRegion), let to = waves[blending + 1].cropping(to: zoomRegion) {
            Look.draw(from, in: right, context: context)
            context.saveGState()
            context.setAlpha(alpha * Ease.inOut(CGFloat((t - steps[blending]) / 0.5)))
            Look.draw(to, in: right, context: context)
            context.restoreGState()
        } else if let now {
            Look.draw(now, in: right, context: context)
        }
        context.setStrokeColor(Look.color(0xFFFFFF))
        context.setLineWidth(3)
        context.stroke(left)
        context.setStrokeColor(Look.accent)
        context.stroke(right)
        Look.draw(Look.line("前", font: Look.uiFont(20, bold: true), color: Look.dim), at: CGPoint(x: left.minX, y: left.maxY + 30), in: context)
        Look.draw(Look.line(done == 0 ? "いま" : "いま（強く ×\(done)）", font: Look.uiFont(20, bold: true), color: Look.accent), at: CGPoint(x: right.minX, y: right.maxY + 30), in: context)
        context.restoreGState()
    }

    private func drawColors(at t: Double, in context: CGContext) {
        let k = Ease.inOut(Ease.ramp(t, 2.0, 0.8))
        blend(evening, night, k, in: context)
        var y = panelHeading("名前付きの色", code: t >= 2.0 ? "theme = .夜" : "theme = .夕方", in: context)
        for (index, swatch) in swatches.enumerated() {
            let row = y + CGFloat(index) * 52
            let color = RGBA(
                r: swatch.evening.r + (swatch.night.r - swatch.evening.r) * Double(k),
                g: swatch.evening.g + (swatch.night.g - swatch.evening.g) * Double(k),
                b: swatch.evening.b + (swatch.night.b - swatch.evening.b) * Double(k)
            )
            let chip = CGRect(x: Look.panel.minX + 32, y: row, width: 64, height: 38)
            context.addPath(Look.roundedRect(chip, radius: 8))
            context.setFillColor(color.cgColor)
            context.fillPath()
            Look.draw(Look.line(swatch.name, font: Look.uiFont(21, bold: true), color: Look.text), at: CGPoint(x: chip.maxX + 18, y: row + 27), in: context)
            Look.draw(Look.line(CodeLine.hex(color), font: Look.codeFont(17), color: Look.dim), at: CGPoint(x: Look.panel.maxX - 140, y: row + 26), in: context)
        }
        y += CGFloat(swatches.count) * 52 + 20
        Look.draw(Look.line("色の組", font: Look.uiFont(22, bold: true), color: Look.text), at: CGPoint(x: Look.panel.minX + 32, y: y + 10), in: context)
        let atNight = t >= 2.0
        for (index, name) in ["夕方", "夜"].enumerated() {
            let box = CGRect(x: Look.panel.minX + 150 + CGFloat(index) * 170, y: y - 20, width: 150, height: 46)
            button(name, in: box, pressed: (index == 1) == atNight, in: context)
        }
        status(atNight ? "◆ 色の組「夜」    11 色をまとめて変更" : "◆ 色の組「夕方」", in: context)
        caption("色の組を、夕方から夜へ。", at: t, length: Times.parts - Times.colors, in: context)
    }

    private func drawParts(at t: Double, in context: CGContext) {
        // One more use every half second from 0.6s; the part's colour changes at 4.6s.
        let placed = min(partSteps.count - 1, max(0, Int((t - 0.6) / 0.5)))
        let recolor = Ease.inOut(Ease.ramp(t, 4.6, 0.6))
        if recolor > 0 {
            blend(partSteps.last, partRecolored, recolor, in: context)
        } else {
            drawCanvas(partSteps.isEmpty ? evening : partSteps[placed], in: context)
        }
        var y = panelHeading("部品", code: recolor > 0 ? "きらめき.color = ■ 8FE8FF" : "place(きらめき)", in: context)
        let card = CGRect(x: Look.panel.minX + 24, y: y, width: Look.panel.width - 48, height: 110)
        context.addPath(Look.roundedRect(card, radius: 12))
        context.setFillColor(Look.color(0x262A33))
        context.fillPath()
        Look.draw(Look.line("きらめき", font: Look.uiFont(26, bold: true), color: Look.text), at: CGPoint(x: card.minX + 24, y: card.minY + 46), in: context)
        Look.draw(Look.line("\(placed + 1) か所に置いています", font: Look.uiFont(19), color: Look.dim), at: CGPoint(x: card.minX + 24, y: card.minY + 84), in: context)
        let gold = RGBA(hex: 0xFFD27A), cyan = RGBA(hex: 0x8FE8FF)
        let chip = CGRect(x: card.maxX - 90, y: card.minY + 32, width: 60, height: 46)
        context.addPath(Look.roundedRect(chip, radius: 10))
        context.setFillColor(RGBA(
            r: gold.r + (cyan.r - gold.r) * Double(recolor), g: gold.g + (cyan.g - gold.g) * Double(recolor), b: gold.b + (cyan.b - gold.b) * Double(recolor)
        ).cgColor)
        context.fillPath()
        y = card.maxY + 40
        Look.draw(Look.line("元の色や線を直すと、置いた所が全部そろって変わる", font: Look.uiFont(19), color: Look.dim), at: CGPoint(x: Look.panel.minX + 32, y: y), in: context)
        status("◆ 部品「きらめき」    \(placed + 1) / \(partUses) か所", in: context)
        caption("部品を並べて、元の色を変えると全部そろう。", at: t, length: Times.versions - Times.parts, in: context)
    }

    private func drawVersions(at t: Double, in context: CGContext) {
        let length = Times.ending - Times.versions
        // Wipe from the main picture to the first idea, back half way, then take it.
        let take = 5.6
        if t >= take, let adopted {
            drawCanvas(adopted, in: context)
        } else if let first = ideas.first?.picture, t >= 2.2 {
            drawCanvas(main, in: context)
            let wipe = t < 3.6 ? Ease.inOut(Ease.ramp(t, 2.2, 1.4)) : 1 - 0.5 * Ease.inOut(Ease.ramp(t, 3.8, 1.0))
            let rect = canvasRect
            context.saveGState()
            // The main picture on the left, the idea on the right, as in the app.
            context.clip(to: CGRect(x: rect.minX + rect.width * (1 - wipe), y: rect.minY, width: rect.width * wipe, height: rect.height))
            Look.draw(first, in: rect, context: context)
            context.restoreGState()
            context.setFillColor(Look.accent)
            context.fill(CGRect(x: rect.minX + rect.width * (1 - wipe) - 2, y: rect.minY, width: 4, height: rect.height))
            // The comparison: each side named, and the handle that wipes between them.
            let names = [("本番の絵", CGPoint(x: rect.minX + 20, y: rect.minY + 20), false),
                         ("AI の案「\(ideas.first?.name ?? "")」", CGPoint(x: rect.maxX - 20, y: rect.minY + 20), true)]
            for (name, corner, right) in names {
                let line = Look.line(name, font: Look.uiFont(22, bold: true), color: Look.color(0xFFFFFF))
                let width = Look.width(of: line) + 28
                let tag = CGRect(x: right ? corner.x - width : corner.x, y: corner.y, width: width, height: 40)
                context.addPath(Look.roundedRect(tag, radius: 10))
                context.setFillColor(Look.color(0x101216, alpha: 0.8))
                context.fillPath()
                Look.draw(line, at: CGPoint(x: tag.minX + 14, y: tag.minY + 28), in: context)
            }
            let track = CGRect(x: rect.minX + 40, y: rect.maxY - 170, width: rect.width - 80, height: 8)
            context.addPath(Look.roundedRect(track, radius: 4))
            context.setFillColor(Look.color(0x101216, alpha: 0.7))
            context.fillPath()
            let knob = CGPoint(x: track.minX + track.width * (1 - wipe), y: track.midY)
            context.setFillColor(Look.color(0xFFFFFF))
            context.fillEllipse(in: CGRect(x: knob.x - 16, y: knob.y - 16, width: 32, height: 32))
            context.setStrokeColor(Look.accent)
            context.setLineWidth(3)
            context.strokeEllipse(in: CGRect(x: knob.x - 16, y: knob.y - 16, width: 32, height: 32))
        } else {
            drawCanvas(main, in: context)
        }
        var y = panelHeading("案", code: t >= 2.2 && t < take ? "compare(本番の絵, \(ideas.first?.name ?? ""))" : t >= take ? "adopt(\(ideas.first?.name ?? ""))" : "ask(\"\(request)\")  // \(ideaSource)", in: context)
        // The ideas arrive one by one as versions.
        // Once taken, the main picture shows the version taken.
        let rows = [(t >= take ? "本番の絵（「\(ideas.first?.name ?? "")」を採用）" : "本番の絵", t >= take ? adopted ?? main : main)]
            + ideas.map { ($0.name, Optional($0.picture)) }
        for (index, row) in rows.enumerated() {
            let alpha = index == 0 ? 1 : Ease.out(Ease.ramp(t, 0.3 + Double(index) * 0.35, 0.3))
            guard alpha > 0 else { continue }
            context.saveGState()
            context.setAlpha(alpha)
            let box = CGRect(x: Look.panel.minX + 24, y: y, width: Look.panel.width - 48, height: 120)
            let isChosen = index == 0 && t >= take
            context.addPath(Look.roundedRect(box, radius: 12))
            context.setFillColor(isChosen ? Look.color(0x2D4A6E) : Look.color(0x262A33))
            context.fillPath()
            if let picture = row.1 {
                Look.draw(picture, in: CGRect(x: box.minX + 12, y: box.minY + 10, width: 90, height: 100), context: context)
            }
            Look.draw(Look.line(row.0, font: Look.uiFont(24, bold: true), color: Look.text), at: CGPoint(x: box.minX + 124, y: box.minY + 54), in: context)
            // Short enough to stay clear of the button.
            let note = index == 0 ? "いま描いている絵" : "AI の案 · " + ideas[index - 1].note
            let line = Look.line(note, font: Look.uiFont(17), color: Look.dim)
            Look.draw(line, at: CGPoint(x: box.minX + 124, y: box.minY + 88), in: context)
            // The idea's colours, so ideas that change the same names can be told apart.
            if index > 0 {
                // As many as fit; the rest are counted, so the chips match "色 n つ".
                let colors = ideas[index - 1].colors
                let start = box.minX + 124 + Look.width(of: line) + 12
                let room = max(0, Int((box.maxX - 12 - start - 40) / 22))
                let shown = colors.count <= room + 1 ? colors.count : room
                for (n, color) in colors.prefix(shown).enumerated() {
                    let chip = CGRect(x: start + CGFloat(n) * 22, y: box.minY + 74, width: 18, height: 18)
                    context.addPath(Look.roundedRect(chip, radius: 4))
                    context.setFillColor(color.cgColor)
                    context.fillPath()
                }
                if shown < colors.count {
                    Look.draw(Look.line("+\(colors.count - shown)", font: Look.uiFont(16, bold: true), color: Look.dim),
                              at: CGPoint(x: start + CGFloat(shown) * 22 + 2, y: box.minY + 88), in: context)
                }
            }
            if index == 1, t < take + 0.4 {
                // Above the description, so the description is not cut short.
                button("本番にする", in: CGRect(x: box.maxX - 190, y: box.minY + 14, width: 170, height: 44), pressed: t >= take - 0.3 && t < take + 0.4, in: context)
            }
            context.restoreGState()
            y += 136
        }
        if t >= 2.2 && t < take {
            button("見比べる", in: CGRect(x: Look.panel.minX + 24, y: y + 8, width: 200, height: 50), pressed: true, in: context)
        }
        status(t >= take ? "◆ 案「\(ideas.first?.name ?? "")」を本番にした    取り消しで戻せる"
               : t >= 2.2 ? "◆ 見比べ中    つまみを動かして左右を比べる" : "◆ 今の絵は変わらない    案は \(ideas.indices.filter { t >= 0.3 + Double($0 + 1) * 0.35 + 0.15 }.count) つ", in: context)
        caption("AI の案を並べて、見比べて選ぶ。", at: t, length: length, in: context)
    }

    private func drawEnding(at t: Double, in context: CGContext) {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
        let words = Ease.out(Ease.ramp(t, 0.3, 0.6))
        context.saveGState()
        context.setAlpha(words)
        Look.draw(BrandArt.tagline, font: Look.uiFont(60, bold: true), color: Look.color(0x1F2430), centeredAt: CGPoint(x: 960, y: 420), in: context)
        if let wordmark {
            let height: CGFloat = 190
            let width = height * CGFloat(wordmark.width) / CGFloat(wordmark.height)
            Look.draw(wordmark, in: CGRect(x: 960 - width / 2, y: 530, width: width, height: height), context: context)
        }
        context.restoreGState()
    }
}
