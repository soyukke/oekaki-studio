import CoreGraphics
import CoreText
import Foundation
import OekakiKit

/// The promotional film: the picture being made, played back from its
/// journal, beside the journal written out as source code.
final class Film {
    static let fps = 30

    let picture: Picture
    let replay: Replay
    let code: [CodeLine]
    /// The logo, shown at the end.
    private let wordmark = Logo.dropOnly().flatMap { BrandArt.dropWordmark($0, withTagline: false) }

    // MARK: Timeline, in seconds

    struct Times {
        var drawStart = 3.5
        var drawEnd = 0.0
        var openStart = 0.0
        var recolorStart = 0.0
        var tidyStart = 0.0
        var replayStart = 0.0
        var replayEnd = 0.0
        var whiteStart = 0.0
        var end = 0.0
    }

    private(set) var times = Times()
    /// Slots for the steps drawn in the second scene, the doodles, and the
    /// whole replay at 16x.
    private let drawing: Slots
    private var doodling: Slots
    private var rerun: Slots
    /// How long the whole picture takes to play at 1x, as the replay player plays it.
    let naturalLength: Double

    init(picture: Picture) {
        self.picture = picture
        let document = picture.document
        document.flushJournal()
        replay = Replay(steps: document.journal, width: document.width, height: document.height)
        code = Code.lines(for: replay, width: document.width, height: document.height)

        let replay = self.replay
        func natural(_ index: Int) -> Double {
            if let drawn = replay.strokeDrawn(at: index) {
                return min(max(Double(drawn.stroke.points.count) / 120, 0.2), 1.2)
            }
            return 0.3
        }
        naturalLength = (1..<replay.count).map(natural).reduce(0, +)

        var t = Times()
        let rerunLength = naturalLength / 16
        // Fit the film into 49.5 seconds: the drawing scene takes what is left.
        let fixed = 3.5 + 6.0 + 6.5 + 6.5 + rerunLength + 3.9
        let drawLength = max(12, 49.5 - fixed)
        t.drawEnd = t.drawStart + drawLength
        t.openStart = t.drawEnd
        t.recolorStart = t.openStart + 6.0
        t.tidyStart = t.recolorStart + 6.5
        t.replayStart = t.tidyStart + 6.5
        t.replayEnd = t.replayStart + rerunLength
        t.whiteStart = t.replayEnd + 0.5
        t.end = t.whiteStart + 3.4
        times = t

        drawing = Slots(steps: Array(1..<picture.drawnUpTo), start: t.drawStart + 0.2, length: drawLength - 0.7, weight: natural)
        doodling = Slots(steps: Array(picture.recoloredUpTo..<(picture.tidiedUpTo - 1)), start: t.tidyStart + 0.8, length: 2.6, weight: natural)
        rerun = Slots(steps: Array(1..<replay.count), start: t.replayStart, length: rerunLength, weight: natural)
    }

    var frameCount: Int { Int((times.end * Double(Self.fps)).rounded()) }

    // MARK: What the canvas shows

    enum Shot: Equatable {
        /// The picture after a step.
        case step(Int)
        /// A step's line drawn part way.
        case partial(Int, Double)
        /// Fading from the picture after one step to the picture after another.
        case blend(Int, Int, CGFloat)
    }

    func shot(at time: Double) -> Shot {
        let t = times
        let tidy = picture.tidiedUpTo - 1
        switch time {
        case ..<t.drawStart:
            return .step(0)
        case ..<t.openStart:
            return drawing.shot(at: time, before: 0, replay: replay)
        case ..<(t.recolorStart + 1.05):
            return .step(picture.drawnUpTo - 1)
        case ..<(t.recolorStart + 2.6):
            return .step(picture.drawnUpTo)
        case ..<(t.recolorStart + 4.3):
            return .step(picture.drawnUpTo + 1)
        case ..<(t.tidyStart + 0.8):
            return .step(picture.drawnUpTo + 2)
        case ..<(t.tidyStart + 3.4):
            return doodling.shot(at: time, before: picture.recoloredUpTo - 1, replay: replay)
        case ..<(t.tidyStart + 4.15):
            return .step(tidy - 1)
        case ..<(t.tidyStart + 4.65):
            return .blend(tidy - 1, tidy, Ease.inOut(Ease.ramp(time, t.tidyStart + 4.15, 0.5)))
        case ..<t.replayStart:
            return .step(tidy)
        case ..<t.replayEnd:
            return rerun.shot(at: time, before: 0, replay: replay)
        default:
            return .step(replay.count - 1)
        }
    }

    private var cached: (Shot, CGImage)?
    private var blendFrom: (Int, CGImage)?

    func image(for shot: Shot) -> CGImage? {
        if let cached, cached.0 == shot { return cached.1 }
        var image: CGImage?
        switch shot {
        case .step(let index):
            replay.seek(to: index)
            image = replay.frame(maxSide: 1200)
        case .partial(let index, let share):
            guard let drawn = replay.strokeDrawn(at: index) else { return nil }
            replay.seek(to: index - 1)
            image = replay.frame(maxSide: 1200, partial: (drawn.layerID, drawn.stroke, share))
        case .blend(let from, let to, let amount):
            if blendFrom?.0 != from {
                replay.seek(to: from)
                blendFrom = replay.frame(maxSide: 1200).map { (from, $0) }
            }
            replay.seek(to: to)
            guard let start = blendFrom?.1, let end = replay.frame(maxSide: 1200) else { return nil }
            let context = CGContext(
                data: nil, width: end.width, height: end.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: Look.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let rect = CGRect(x: 0, y: 0, width: end.width, height: end.height)
            context.draw(start, in: rect)
            context.setAlpha(amount)
            context.draw(end, in: rect)
            image = context.makeImage()
        }
        if let image { cached = (shot, image) }
        return image
    }

    // MARK: Where things are

    var canvasSize: CGSize { CGSize(width: picture.document.width, height: picture.document.height) }

    /// Where the whole canvas sits in the frame when not zoomed.
    var restingCanvasRect: CGRect {
        let area = Look.canvasArea.insetBy(dx: 24, dy: 24)
        let scale = min(area.width / canvasSize.width, area.height / canvasSize.height)
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// The canvas, zoomed in on the doodles.
    var zoomedCanvasRect: CGRect {
        let area = Look.canvasArea
        let focus = picture.doodleArea
        let scale = min(area.width * 0.62 / focus.width, area.height * 0.62 / focus.height)
        return CGRect(
            x: area.midX - focus.midX * scale, y: area.midY - focus.midY * scale,
            width: canvasSize.width * scale, height: canvasSize.height * scale
        )
    }

    func canvasRect(at time: Double) -> CGRect {
        let t = times
        let zoomIn = Ease.inOut(Ease.ramp(time, t.tidyStart, 0.8))
        let zoomOut = Ease.inOut(Ease.ramp(time, t.tidyStart + 5.6, 0.8))
        return Ease.mix(restingCanvasRect, zoomedCanvasRect, zoomIn * (1 - zoomOut))
    }

    func view(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x / canvasSize.width * rect.width, y: rect.minY + point.y / canvasSize.height * rect.height)
    }

    func view(_ box: CGRect, in rect: CGRect) -> CGRect {
        let origin = view(box.origin, in: rect)
        let end = view(CGPoint(x: box.maxX, y: box.maxY), in: rect)
        return CGRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
    }

    var ribbonBox: CGRect {
        picture.document.item(picture.ribbon)?.item.bounds(canvas: picture.document.bounds) ?? .zero
    }

    /// Where the ribbon is clicked, on the canvas.
    var ribbonPoint: CGPoint { CGPoint(x: ribbonBox.minX + ribbonBox.width * 0.22, y: ribbonBox.minY + ribbonBox.height * 0.28) }

    var inspectorRect: CGRect {
        let box = view(ribbonBox, in: restingCanvasRect)
        return CGRect(x: box.maxX + 36, y: box.minY - 70, width: 320, height: 190)
    }

    /// The card for the shadow layer, whose blend mode is changed.
    static let layerCard = CGRect(x: 40, y: 150, width: 470, height: 196)
    static var blendBox: CGRect { CGRect(x: layerCard.minX + 110, y: layerCard.minY + 112, width: 340, height: 44) }

    static func blendItem(_ index: Int) -> CGRect {
        CGRect(x: blendBox.minX, y: blendBox.maxY + 6 + CGFloat(index) * 40, width: blendBox.width, height: 40)
    }

    static let tidyButton = CGRect(x: 32, y: 72, width: 168, height: 48)

    // MARK: Drawing a frame

    func draw(at time: Double, in context: CGContext) {
        let t = times
        context.setFillColor(Look.window)
        context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
        drawChrome(at: time, in: context)
        drawCanvas(at: time, in: context)
        drawPanel(at: time, in: context)
        drawStatus(at: time, in: context)
        drawOverlays(at: time, in: context)
        drawCaption(at: time, in: context)

        // The ending: white, then the line it all comes to.
        let white = Ease.inOut(Ease.ramp(time, t.whiteStart, 0.6))
        if white > 0 {
            context.setFillColor(CGColor(gray: 1, alpha: white))
            context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
            let words = Ease.out(Ease.ramp(time, t.whiteStart + 0.7, 0.7))
            if words > 0 {
                context.saveGState()
                context.setAlpha(words)
                let rise = (1 - words) * 18
                Look.draw(
                    BrandArt.tagline, font: Look.uiFont(64, bold: true), color: Look.color(0x1F2430),
                    centeredAt: CGPoint(x: 960, y: 420 + rise), in: context
                )
                context.restoreGState()
            }
            // Then the name, as the logo.
            let name = Ease.out(Ease.ramp(time, t.whiteStart + 1.4, 0.6))
            if name > 0, let wordmark {
                context.saveGState()
                context.setAlpha(name)
                let height: CGFloat = 200
                let width = height * CGFloat(wordmark.width) / CGFloat(wordmark.height)
                Look.draw(wordmark, in: CGRect(x: 960 - width / 2, y: 540 + (1 - name) * 12, width: width, height: height), context: context)
                context.restoreGState()
            }
        }

        // Fade in from black at the very start.
        let dark = 1 - Ease.ramp(time, 0, 0.5)
        if dark > 0 {
            context.setFillColor(CGColor(gray: 0, alpha: dark))
            context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
        }
    }

    private func drawChrome(at time: Double, in context: CGContext) {
        FilmKit.chrome(title: "picture.\(DocumentFile.fileExtension) — Oekaki Studio", in: context)
    }

    private func drawCanvas(at time: Double, in context: CGContext) {
        let rect = canvasRect(at: time)
        context.saveGState()
        context.clip(to: Look.canvasArea)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 8), blur: 30, color: Look.color(0x000000, alpha: 0.5))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.restoreGState()
        if let image = image(for: shot(at: time)) {
            Look.draw(image, in: rect, context: context)
        }
        context.restoreGState()
    }

    // MARK: The source panel

    static let lineHeight: CGFloat = 29
    static let panelHeader: CGFloat = 46

    /// The last line written, and how much of it has been typed.
    func writing(at time: Double) -> (line: Int, typed: CGFloat) {
        let t = times
        switch time {
        case ..<t.drawStart:
            return (0, Ease.ramp(time, 1.0, 0.8))
        case ..<t.openStart:
            if case .partial(let index, let share) = drawing.shot(at: time, before: 0, replay: replay) {
                return (index, CGFloat(min(1, share * 1.6)))
            }
            return (drawing.lastStep(at: time) ?? 0, 1)
        case ..<(t.recolorStart + 1.05):
            return (picture.drawnUpTo - 1, 1)
        case ..<(t.recolorStart + 2.6):
            return (picture.drawnUpTo, Ease.ramp(time, t.recolorStart + 1.05, 0.4))
        case ..<(t.recolorStart + 4.3):
            return (picture.drawnUpTo + 1, Ease.ramp(time, t.recolorStart + 2.6, 0.25))
        case ..<(t.tidyStart + 0.8):
            return (picture.drawnUpTo + 2, Ease.ramp(time, t.recolorStart + 4.3, 0.25))
        case ..<(t.tidyStart + 3.4):
            if case .partial(let index, let share) = doodling.shot(at: time, before: picture.recoloredUpTo - 1, replay: replay) {
                return (index, CGFloat(min(1, share * 1.6)))
            }
            return (doodling.lastStep(at: time) ?? picture.recoloredUpTo - 1, 1)
        case ..<(t.tidyStart + 4.15):
            return (picture.tidiedUpTo - 2, 1)
        default:
            return (picture.tidiedUpTo - 1, Ease.ramp(time, t.tidyStart + 4.15, 0.4))
        }
    }

    /// The line the replay is running, during the replay.
    func running(at time: Double) -> Int? {
        let t = times
        guard time >= t.replayStart else { return nil }
        guard time < t.replayEnd else { return replay.count - 1 }
        switch rerun.shot(at: time, before: 0, replay: replay) {
        case .partial(let index, _): return index
        case .step(let index): return index
        case .blend(_, let index, _): return index
        }
    }

    private var ribbonLine: Int {
        code.firstIndex { $0.itemID == picture.ribbon } ?? 0
    }

    private func drawPanel(at time: Double, in context: CGContext) {
        let t = times
        let panel = Look.panel
        context.setFillColor(Look.panelBackground)
        context.fill(panel)
        context.setFillColor(Look.border)
        context.fill(CGRect(x: panel.minX, y: panel.minY, width: 1, height: panel.height))
        // Header.
        context.setFillColor(Look.color(0x191B21))
        context.fill(CGRect(x: panel.minX + 1, y: panel.minY, width: panel.width, height: Self.panelHeader))
        Look.draw(Look.line("ソース", font: Look.uiFont(18, bold: true), color: Look.text), at: CGPoint(x: panel.minX + 24, y: panel.minY + 30), in: context)
        Look.draw(
            Look.line("1 手 = 1 行", font: Look.uiFont(15), color: Look.dim), at: CGPoint(x: panel.minX + 100, y: panel.minY + 30), in: context
        )

        let body = CGRect(x: panel.minX, y: panel.minY + Self.panelHeader, width: panel.width, height: panel.height - Self.panelHeader)
        let visible = Int(body.height / Self.lineHeight)
        let writing = self.writing(at: time)
        let runningLine = running(at: time)
        let lastShown = runningLine == nil ? writing.line : code.count - 1

        // Scroll: keep the line being written, or run, near the bottom;
        // during the jump to the ribbon's line, centre that line.
        let focus = CGFloat(runningLine ?? writing.line) + (runningLine == nil ? writing.typed : 0)
        let follow = max(0, focus - CGFloat(visible - 5))
        let jumpTarget = max(0, CGFloat(ribbonLine) - CGFloat(visible) / 2)
        let jumpIn = Ease.inOut(Ease.ramp(time, t.openStart + 1.5, 0.6))
        let jumpOut = Ease.inOut(Ease.ramp(time, t.recolorStart + 0.1, 0.6))
        let jump = jumpIn * (1 - jumpOut)
        let top = Ease.mix(follow, jumpTarget, jump)

        context.saveGState()
        context.clip(to: body)
        let first = max(0, Int(top.rounded(.down)))
        let font = Look.codeFont(16.5)
        for index in first..<min(lastShown + 1, first + visible + 2) {
            let y = body.minY + 8 + (CGFloat(index) - top) * Self.lineHeight
            let isCurrent = index == (runningLine ?? writing.line)
            if index == ribbonLine, jump > 0 {
                context.setFillColor(Look.color(0x2D4A6E, alpha: jump))
                context.fill(CGRect(x: body.minX + 1, y: y, width: body.width, height: Self.lineHeight))
                context.setFillColor(Look.accent.copy(alpha: jump)!)
                context.fill(CGRect(x: body.minX + 1, y: y, width: 4, height: Self.lineHeight))
            } else if isCurrent {
                context.setFillColor(Look.color(runningLine == nil ? 0x2A2F3A : 0x2B4440))
                context.fill(CGRect(x: body.minX + 1, y: y, width: body.width, height: Self.lineHeight))
            }
            let number = Look.line("\(index + 1)", font: Look.codeFont(14), color: isCurrent ? Look.text : Look.color(0x4B5263))
            Look.draw(number, at: CGPoint(x: body.minX + 62 - Look.width(of: number), y: y + 20), in: context)
            let typed = runningLine == nil && index == writing.line ? writing.typed : 1
            let end = FilmKit.code(code[index], typed: typed, at: CGPoint(x: body.minX + 80, y: y + 20), font: font, in: context)
            if runningLine == nil, index == writing.line, Int(time * 2) % 2 == 0 || typed < 1 {
                context.setFillColor(Look.accent)
                context.fill(CGRect(x: end + 2, y: y + 5, width: 2, height: 20))
            }
        }
        context.restoreGState()

        // "Go to definition", over the panel while the jump is on.
        if jump > 0.01 {
            let y = body.minY + 8 + (CGFloat(ribbonLine) - top) * Self.lineHeight
            let label = Look.line("定義へジャンプ  ⌘クリック", font: Look.uiFont(15, bold: true), color: Look.color(0x0F1A26))
            let width = Look.width(of: label) + 28
            let box = CGRect(x: panel.maxX - width - 20, y: y - 40, width: width, height: 32)
            context.saveGState()
            context.setAlpha(jump)
            context.addPath(Look.roundedRect(box, radius: 8))
            context.setFillColor(Look.accent)
            context.fillPath()
            Look.draw(label, at: CGPoint(x: box.minX + 14, y: box.minY + 22), in: context)
            context.restoreGState()
        }
    }

    private func drawStatus(at time: Double, in context: CGContext) {
        let bar = Look.statusBar
        context.setFillColor(Look.teal)
        context.fill(bar)
        let line = running(at: time) ?? writing(at: time).line
        let layer = code[...line].last { $0.layer != nil }?.layer ?? "背景"
        let left = Look.line("◆ \(layer)    \(line + 1) / \(code.count) 手", font: Look.uiFont(15, bold: true), color: Look.color(0xFFFFFF))
        Look.draw(left, at: CGPoint(x: 20, y: bar.minY + 21), in: context)
        let right = Look.line("\(Int(canvasSize.width)) × \(Int(canvasSize.height))    journal v4", font: Look.codeFont(14), color: Look.color(0xE8F6F4))
        Look.draw(right, at: CGPoint(x: bar.maxX - 20 - Look.width(of: right), y: bar.minY + 20), in: context)
    }

    // MARK: Overlays

    private func drawOverlays(at time: Double, in context: CGContext) {
        let t = times
        let rect = restingCanvasRect

        // The layer being drawn on, while drawing and while replaying.
        if (time >= t.drawStart && time < t.openStart) || (time >= t.replayStart && time < t.whiteStart) {
            let line = running(at: time) ?? writing(at: time).line
            if let layer = code[...line].last(where: { $0.layer != nil })?.layer {
                badge("レイヤー  \(layer)", at: CGPoint(x: 32, y: 72), in: context)
            }
        }
        if time >= t.replayStart, time < t.whiteStart {
            badge("▶  16×  描いた順に再生", at: CGPoint(x: Look.canvasArea.maxX - 32, y: 72), alignRight: true, accent: true, in: context)
        }

        // Clicking the ribbon: it lights up and opens.
        let selected = Ease.ramp(time, t.openStart + 1.35, 0.25) * (1 - Ease.ramp(time, t.recolorStart, 0.3))
        if selected > 0 {
            let box = view(ribbonBox, in: rect).insetBy(dx: -12, dy: -12)
            let pulse = 0.8 + 0.2 * sin(time * 5)
            context.saveGState()
            context.setAlpha(selected * pulse)
            context.setShadow(offset: .zero, blur: 22, color: Look.accent)
            context.addPath(Look.roundedRect(box, radius: 12))
            context.setStrokeColor(Look.accent)
            context.setLineWidth(3.5)
            context.strokePath()
            context.restoreGState()
            context.saveGState()
            context.setAlpha(selected)
            context.addPath(Look.roundedRect(box.insetBy(dx: 6, dy: 6), radius: 8))
            context.setStrokeColor(Look.color(0xFFFFFF, alpha: 0.8))
            context.setLineWidth(1.5)
            context.setLineDash(phase: CGFloat(time * 20), lengths: [6, 5])
            context.strokePath()
            context.restoreGState()
            let label = Look.line("塗り #\(picture.ribbon)", font: Look.codeFont(15), color: Look.color(0x0F1A26))
            let tag = CGRect(x: box.minX, y: box.minY - 30, width: Look.width(of: label) + 20, height: 26)
            context.saveGState()
            context.setAlpha(selected)
            context.addPath(Look.roundedRect(tag, radius: 6))
            context.setFillColor(Look.accent)
            context.fillPath()
            Look.draw(label, at: CGPoint(x: tag.minX + 10, y: tag.minY + 18), in: context)
            context.restoreGState()
        }
        let inspector = Ease.ramp(time, t.openStart + 1.9, 0.3) * (1 - Ease.ramp(time, t.recolorStart, 0.3))
        if inspector > 0 {
            drawInspector(alpha: inspector, in: context)
        }
        let card = Ease.ramp(time, t.recolorStart + 0.1, 0.3) * (1 - Ease.ramp(time, t.tidyStart - 0.3, 0.3))
        if card > 0 {
            drawLayerCard(alpha: card, at: time, in: context)
        }

        // Keys for take-back and redo.
        let undo = Ease.ramp(time, t.recolorStart + 2.55, 0.15) * (1 - Ease.ramp(time, t.recolorStart + 3.9, 0.25))
        if undo > 0 { keys(["⌘", "Z"], "取り消し", alpha: undo, in: context) }
        let redo = Ease.ramp(time, t.recolorStart + 4.25, 0.15) * (1 - Ease.ramp(time, t.recolorStart + 5.8, 0.25))
        if redo > 0 { keys(["⇧", "⌘", "Z"], "やり直し", alpha: redo, in: context) }

        // The tidy button, shown while the doodles are on screen.
        let button = Ease.ramp(time, t.tidyStart + 3.0, 0.3) * (1 - Ease.ramp(time, t.tidyStart + 5.6, 0.3))
        if button > 0 {
            let pressed = time >= t.tidyStart + 4.1 && time < t.tidyStart + 4.35
            context.saveGState()
            context.setAlpha(button)
            context.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: Look.color(0x000000, alpha: 0.4))
            context.addPath(Look.roundedRect(Self.tidyButton, radius: 12))
            context.setFillColor(pressed ? Look.accent : Look.color(0x2A2F3A))
            context.fillPath()
            context.restoreGState()
            context.saveGState()
            context.setAlpha(button)
            Look.draw(
                "〰  整える", font: Look.uiFont(20, bold: true), color: pressed ? Look.color(0x0F1A26) : Look.text,
                centeredAt: CGPoint(x: Self.tidyButton.midX, y: Self.tidyButton.midY), in: context
            )
            context.restoreGState()
        }

        drawPointer(at: time, in: context)
    }

    private func badge(_ text: String, at point: CGPoint, alignRight: Bool = false, accent: Bool = false, in context: CGContext) {
        FilmKit.badge(text, at: point, alignRight: alignRight, accent: accent, in: context)
    }

    private func keys(_ caps: [String], _ label: String, alpha: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setAlpha(alpha)
        let capWidth: CGFloat = 54
        let text = Look.line(label, font: Look.uiFont(22, bold: true), color: Look.text)
        let total = CGFloat(caps.count) * (capWidth + 10) + 16 + Look.width(of: text)
        var x = Look.canvasArea.midX - total / 2
        let y: CGFloat = 96
        let back = CGRect(x: x - 24, y: y - 18, width: total + 48, height: 90)
        context.addPath(Look.roundedRect(back, radius: 18))
        context.setFillColor(Look.color(0x000000, alpha: 0.7))
        context.fillPath()
        for cap in caps {
            let box = CGRect(x: x, y: y, width: capWidth, height: 54)
            context.addPath(Look.roundedRect(box, radius: 10))
            context.setFillColor(Look.color(0xF2F4F7))
            context.fillPath()
            Look.draw(cap, font: Look.uiFont(26, bold: true), color: Look.color(0x1F2430), centeredAt: CGPoint(x: box.midX, y: box.midY), in: context)
            x += capWidth + 10
        }
        Look.draw(text, at: CGPoint(x: x + 6, y: y + 36), in: context)
        context.restoreGState()
    }

    /// How the shadow layer is blended at this moment of the film.
    private func shadowBlend(at time: Double) -> BlendMode {
        if case .step(let index) = shot(at: time), index == picture.drawnUpTo || index == picture.drawnUpTo + 2 {
            return .multiply
        }
        return time >= times.tidyStart ? .multiply : .normal
    }

    private func card(_ rect: CGRect, alpha: CGFloat, in context: CGContext) {
        FilmKit.card(rect, alpha: alpha, in: context)
    }

    private func drawInspector(alpha: CGFloat, in context: CGContext) {
        let rect = inspectorRect
        card(rect, alpha: alpha, in: context)
        context.saveGState()
        context.setAlpha(alpha)
        Look.draw(Look.line("塗り #\(picture.ribbon)", font: Look.uiFont(22, bold: true), color: Look.text), at: CGPoint(x: rect.minX + 22, y: rect.minY + 40), in: context)
        Look.draw(Look.line("レイヤー「下塗り」· リボン", font: Look.uiFont(15), color: Look.dim), at: CGPoint(x: rect.minX + 22, y: rect.minY + 68), in: context)
        let swatch = CGRect(x: rect.minX + 22, y: rect.minY + 90, width: 34, height: 34)
        context.addPath(Look.roundedRect(swatch, radius: 7))
        context.setFillColor(Palette.ribbon.cgColor)
        context.fillPath()
        Look.draw(Look.line("色  " + CodeLine.hex(Palette.ribbon), font: Look.codeFont(19), color: Look.text), at: CGPoint(x: swatch.maxX + 14, y: swatch.minY + 24), in: context)
        Look.draw(Look.line("(\(Int(ribbonBox.midX)), \(Int(ribbonBox.midY))) をクリックした塗り", font: Look.uiFont(14), color: Look.dim), at: CGPoint(x: rect.minX + 22, y: rect.minY + 160), in: context)
        context.restoreGState()
    }

    private func drawLayerCard(alpha: CGFloat, at time: Double, in context: CGContext) {
        let t = times
        let rect = Self.layerCard
        card(rect, alpha: alpha, in: context)
        context.saveGState()
        context.setAlpha(alpha)
        Look.draw(Look.line("レイヤー「影」", font: Look.uiFont(22, bold: true), color: Look.text), at: CGPoint(x: rect.minX + 22, y: rect.minY + 42), in: context)
        Look.draw(Look.line("☑ 下のレイヤーではみ出さない", font: Look.uiFont(15), color: Look.dim), at: CGPoint(x: rect.minX + 22, y: rect.minY + 76), in: context)
        Look.draw(Look.line("重ね方", font: Look.uiFont(17, bold: true), color: Look.text), at: CGPoint(x: rect.minX + 22, y: Self.blendBox.midY + 6), in: context)
        let box = Self.blendBox
        context.addPath(Look.roundedRect(box, radius: 9))
        context.setFillColor(Look.color(0x31353F))
        context.fillPath()
        let blend = shadowBlend(at: time)
        Look.draw(Look.line(blend.title + "   ▾", font: Look.uiFont(18, bold: true), color: blend == .multiply ? Look.accent : Look.text),
                  at: CGPoint(x: box.minX + 16, y: box.midY + 7), in: context)
        // The menu, open just before the choice.
        if time >= t.recolorStart + 0.75, time < t.recolorStart + 1.05 {
            let items = BlendMode.allCases
            let menu = CGRect(x: box.minX, y: box.maxY + 4, width: box.width, height: CGFloat(items.count) * 40 + 4)
            context.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: Look.color(0x000000, alpha: 0.5))
            context.addPath(Look.roundedRect(menu, radius: 9))
            context.setFillColor(Look.color(0x2B2F38))
            context.fillPath()
            context.setShadow(offset: .zero, blur: 0, color: nil)
            for (index, mode) in items.enumerated() {
                let item = Self.blendItem(index)
                if mode == .multiply {
                    context.addPath(Look.roundedRect(item.insetBy(dx: 4, dy: 2), radius: 6))
                    context.setFillColor(Look.accent)
                    context.fillPath()
                }
                Look.draw(Look.line(mode.title, font: Look.uiFont(17, bold: true), color: mode == .multiply ? Look.color(0x0F1A26) : Look.text),
                          at: CGPoint(x: item.minX + 16, y: item.midY + 6), in: context)
            }
        }
        context.restoreGState()
    }

    private func drawPointer(at time: Double, in context: CGContext) {
        let t = times
        let rect = restingCanvasRect
        let rest = CGPoint(x: Look.canvasArea.maxX - 120, y: Look.canvasArea.maxY - 200)
        let ribbon = view(ribbonPoint, in: rect)
        let dropdown = CGPoint(x: Self.blendBox.midX, y: Self.blendBox.midY)
        let multiply = CGPoint(x: Self.blendItem(1).midX, y: Self.blendItem(1).midY)
        let tidy = CGPoint(x: Self.tidyButton.midX + 30, y: Self.tidyButton.midY)
        var point: CGPoint
        var visible: CGFloat = 1
        var click: Double?
        switch time {
        case t.openStart..<(t.openStart + 2.4):
            point = Ease.mix(rest, ribbon, Ease.inOut(Ease.ramp(time, t.openStart + 0.1, 1.1)))
            visible = Ease.ramp(time, t.openStart, 0.3)
            click = t.openStart + 1.3
        case (t.openStart + 2.4)..<(t.recolorStart + 0.75):
            point = Ease.mix(ribbon, dropdown, Ease.inOut(Ease.ramp(time, t.recolorStart + 0.1, 0.55)))
            click = t.recolorStart + 0.7
        case (t.recolorStart + 0.75)..<(t.recolorStart + 2.0):
            point = Ease.mix(dropdown, multiply, Ease.inOut(Ease.ramp(time, t.recolorStart + 0.75, 0.2)))
            click = t.recolorStart + 1.0
            visible = 1 - Ease.ramp(time, t.recolorStart + 1.6, 0.3)
        case (t.tidyStart + 3.4)..<(t.tidyStart + 5.0):
            point = Ease.mix(CGPoint(x: 700, y: 520), tidy, Ease.inOut(Ease.ramp(time, t.tidyStart + 3.4, 0.6)))
            visible = Ease.ramp(time, t.tidyStart + 3.4, 0.2) * (1 - Ease.ramp(time, t.tidyStart + 4.7, 0.3))
            click = t.tidyStart + 4.1
        default:
            return
        }
        guard visible > 0 else { return }
        context.saveGState()
        context.setAlpha(visible)
        if let click {
            Look.drawRipple(at: point, progress: CGFloat((time - click) / 0.5), in: context)
        }
        let pressed = click.map { time >= $0 && time < $0 + 0.15 } ?? false
        Look.drawPointer(at: point, pressed: pressed, in: context)
        context.restoreGState()
    }

    // MARK: Captions

    private func caption(at time: Double) -> (String, CGFloat)? {
        let t = times
        let captions: [(String, Double, Double)] = [
            ("絵を、ソースコードとして見てみる。", 0.6, t.drawStart),
            ("1 本の線は、1 行のコード。", t.drawStart + 0.4, t.openStart),
            ("どの線も、あとから開ける。", t.openStart + 0.3, t.recolorStart),
            ("光と影も、書き換えられる。", t.recolorStart + 0.3, t.tidyStart),
            ("整形も、ワンクリック。", t.tidyStart + 0.3, t.replayStart),
        ]
        for (text, start, end) in captions where time >= start && time < end {
            let alpha = min(Ease.ramp(time, start, 0.35), 1 - Ease.ramp(time, end - 0.35, 0.35))
            return (text, alpha)
        }
        return nil
    }

    private func drawCaption(at time: Double, in context: CGContext) {
        guard let (text, alpha) = caption(at: time) else { return }
        FilmKit.caption(text, alpha: alpha, center: CGPoint(x: Look.canvasArea.midX, y: Look.canvasArea.maxY - 78), in: context)
    }
}

/// Time slots for a run of steps, each as long as its weight, filling a
/// stretch of the film.
struct Slots {
    let steps: [Int]
    let start: Double
    private let ends: [Double]

    init(steps: [Int], start: Double, length: Double, weight: (Int) -> Double) {
        self.steps = steps
        self.start = start
        let weights = steps.map(weight)
        let total = max(weights.reduce(0, +), 0.0001)
        var running = start
        ends = weights.map { w in
            running += w / total * length
            return running
        }
    }

    /// When the step at `index` in this run ends.
    func endTime(of index: Int) -> Double {
        ends[index]
    }

    /// The last step finished by `time`, if any.
    func lastStep(at time: Double) -> Int? {
        guard let index = ends.lastIndex(where: { $0 <= time }) else { return nil }
        return steps[index]
    }

    /// What the canvas shows at `time`: a line part way, or the picture
    /// after the last finished step (`before` if none has finished).
    func shot(at time: Double, before: Int, replay: Replay) -> Film.Shot {
        guard let index = ends.firstIndex(where: { $0 > time }) else {
            return .step(steps.last ?? before)
        }
        let slotStart = index == 0 ? start : ends[index - 1]
        let share = (time - slotStart) / (ends[index] - slotStart)
        let step = steps[index]
        if replay.strokeDrawn(at: step) != nil {
            return .partial(step, max(0.02, share))
        }
        // Anything but a line shows at once.
        return .step(step)
    }
}
