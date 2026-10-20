import CoreGraphics
import CoreImage
import ImageIO
import Foundation
import OekakiKit

/// The promotional film for Oekaki Studio: 「一口食べる？」 made from a blank
/// page to the finished picture. The making is played back from the picture's
/// own journal, beside it written out as code; then the finished picture, up close.
final class BitePV {
    static let fps = 30
    /// The frame's size.
    private let W = CGFloat(Look.width), H = CGFloat(Look.height)

    /// When each scene starts, in seconds.
    struct Times {
        var open = 0.0
        var teaser = 3.6
        var rough = 7.4
        var lines = 12.4
        var flats = 20.0
        var shadows = 27.0
        var background = 33.5
        var light = 40.0
        var jump = 45.5
        var versions = 50.5
        var replay = 56.0
        var showcase = 59.6
        /// The picture opened in the app itself.
        var app = 67.6
        var ending = 70.6
        var end = 75.0
    }

    let times = Times()
    let picture: Bite.Result
    let replay: Replay
    let code: [CodeLine]
    private let wordmark = Logo.dropOnly().flatMap { BrandArt.dropWordmark($0, withTagline: false) }

    // The steps each scene plays, given time slots by how long each takes to draw.
    private var slots: [Bite.Phase: Slots] = [:]
    private let rerun: Slots
    /// The fill of the hair, made by drawing round it, and the scoop's fill, jumped to.
    private var hairStep = 0
    private var hairOutline: [CGPoint] = []
    private var scoopStep = 0
    private var scoopLine = 0
    private var scoopBox = CGRect.zero

    // Pictures made ahead.
    private var finished: CGImage?
    private var finishedSoft: CGImage?
    private var looks: [(name: String, picture: CGImage)] = []
    private var blurFrames: [CGImage] = []
    private let maxBlur = 9

    /// The app's own window with the picture open in it, if a picture of it was taken.
    private let appWindow: CGImage?

    init(unit: CGFloat = 1, finishUnit: CGFloat = 2, appWindow: URL? = nil) {
        self.appWindow = appWindow.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        picture = Bite.draw(Bite.mintDay, unit: unit)
        let document = picture.document
        document.flushJournal()
        replay = Replay(steps: document.journal, width: document.width, height: document.height)
        code = Code.lines(for: replay, width: document.width, height: document.height)

        let replay = self.replay
        func weight(_ index: Int) -> Double {
            if let drawn = replay.strokeDrawn(at: index) {
                return min(max(Double(drawn.stroke.points.count) / 160, 0.25), 1.2)
            }
            return 0.22
        }
        let t = times
        let ends = picture.phaseEnds
        func steps(_ phase: Bite.Phase, after previous: Bite.Phase?) -> [Int] {
            let first = previous.flatMap { ends[$0] }.map { $0 + 1 } ?? 1
            return Array(first...(ends[phase] ?? first))
        }
        let scenes: [(Bite.Phase, Bite.Phase?, Double, Double)] = [
            (.rough, nil, t.rough + 0.3, t.lines - t.rough - 0.6),
            (.lines, .rough, t.lines + 0.2, t.flats - t.lines - 0.5),
            (.flats, .lines, t.flats + 0.2, t.shadows - t.flats - 0.5),
            (.shadows, .flats, t.shadows + 0.2, t.background - t.shadows - 0.5),
            (.background, .shadows, t.background + 0.2, 2.6),
            (.light, .background, t.light + 0.2, 2.4),
            (.finish, .light, t.light + 2.7, 0.9),
        ]
        for (phase, previous, start, length) in scenes {
            slots[phase] = Slots(steps: steps(phase, after: previous), start: start, length: length, weight: weight)
        }
        rerun = Slots(steps: Array(1..<replay.count), start: t.replay + 0.2, length: t.showcase - t.replay - 0.6, weight: weight)

        findSteps()
        prepare(finishUnit: finishUnit)
    }

    var frameCount: Int { Int((times.end * Double(Self.fps)).rounded()) }

    // MARK: Getting ready

    /// The steps the film points at: the hair filled by drawing round it, the scoop's colour.
    private func findSteps() {
        let mint = Bite.mintDay
        for (index, change) in replay.changes.enumerated() {
            for (layer, item) in change.added {
                guard case .fill(let fill) = item else { continue }
                if layer == "髪", fill.color == mint.hair, hairStep == 0 { hairStep = index }
                if layer == "アイス", fill.color == mint.cream, scoopStep == 0 {
                    scoopStep = index
                    scoopBox = item.bounds(canvas: picture.document.bounds)
                }
            }
        }
        // One line of the source for each step of the journal.
        scoopLine = scoopStep
        let scale = CGFloat(picture.document.width) / Bite.sheet.width
        hairOutline = PathData.points(Head.front, spacing: 6).map { point in
            let placed = point.applying(Studio.head)
            return CGPoint(x: placed.x * scale, y: placed.y * scale)
        }
    }

    private func prepare(finishUnit: CGFloat) {
        // The finished picture, drawn larger for the close views.
        let large = Bite.draw(Bite.mintDay, unit: finishUnit)
        finished = large.document.compositeImage()
        if let finished {
            let input = CIImage(cgImage: finished)
            let soft = input.clampedToExtent().applyingGaussianBlur(sigma: 40).cropped(to: input.extent)
            finishedSoft = CIContext().createCGImage(soft, from: input.extent)
        }
        // The picture in each set of colours, for the versions.
        for colors in [Bite.mintDay, Bite.strawberryEvening, Bite.vanillaNight] {
            if let image = Bite.draw(colors, unit: 1).document.compositeImage() { looks.append((colors.name, image)) }
        }
        // The background made sharp, then blurred little by little.
        let behind = Bite.draw(Bite.mintDay, unit: 1, through: .background).document
        let blurred = behind.layers.filter { $0.style.blur > 0 }.map { ($0.id, $0.style.blur) }
        for step in 0...maxBlur {
            for (id, radius) in blurred {
                behind.setLayerBlur(id, radius * CGFloat(step) / CGFloat(maxBlur))
            }
            if let image = behind.compositeImage() { blurFrames.append(image) }
        }
    }

    // MARK: What the canvas shows

    enum Shot: Equatable {
        case step(Int)
        case partial(Int, Double)
    }

    private func phase(at time: Double) -> Bite.Phase? {
        let t = times
        switch time {
        case t.rough..<t.lines: return .rough
        case t.lines..<t.flats: return .lines
        case t.flats..<t.shadows: return .flats
        case t.shadows..<t.background: return .shadows
        case t.background..<t.light: return .background
        case t.light..<(t.light + 2.65): return .light
        case (t.light + 2.65)..<t.jump: return .finish
        default: return nil
        }
    }

    /// The step before `phase` began.
    private func before(_ phase: Bite.Phase) -> Int {
        guard let index = Bite.Phase.allCases.firstIndex(of: phase), index > 0 else { return 0 }
        return picture.phaseEnds[Bite.Phase.allCases[index - 1]] ?? 0
    }

    /// While the hair is filled by drawing round it, the replay waits.
    private var lassoTimes: (start: Double, end: Double) {
        guard let flats = slots[.flats], let index = flats.steps.firstIndex(of: hairStep) else { return (0, 0) }
        let slotStart = flats.start(of: index)
        return (slotStart, slotStart + 2.2)
    }

    func shot(at time: Double) -> Shot? {
        let t = times
        if time >= t.replay, time < t.showcase {
            return rerun.filmShot(at: time, before: 0, replay: replay)
        }
        guard let phase = phase(at: time), let slots = slots[phase] else { return nil }
        // The lasso fill: the hair waits unfilled while the outline is drawn round it.
        let lasso = lassoTimes
        if phase == .flats, time >= lasso.start {
            let shifted = time < lasso.end ? lasso.start - 0.001 : time - (lasso.end - lasso.start)
            return slots.filmShot(at: shifted, before: before(phase), replay: replay)
        }
        return slots.filmShot(at: time, before: before(phase), replay: replay)
    }

    private var cached: (Shot, CGImage)?

    func image(for shot: Shot) -> CGImage? {
        if let cached, cached.0 == shot { return cached.1 }
        var image: CGImage?
        let side = max(picture.document.width, picture.document.height)
        switch shot {
        case .step(let index):
            replay.seek(to: index)
            image = replay.frame(maxSide: side)
        case .partial(let index, let share):
            guard let drawn = replay.strokeDrawn(at: index) else { return nil }
            replay.seek(to: index - 1)
            image = replay.frame(maxSide: side, partial: (drawn.layerID, drawn.stroke, share))
        }
        if let image { cached = (shot, image) }
        return image
    }

    // MARK: Where things are

    var canvasSize: CGSize { CGSize(width: picture.document.width, height: picture.document.height) }

    var restingRect: CGRect {
        let area = Look.canvasArea.insetBy(dx: 24, dy: 24)
        let scale = min(area.width / canvasSize.width, area.height / canvasSize.height)
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// The canvas zoomed onto a region given on the sheet.
    func zoomed(on region: CGRect) -> CGRect {
        let area = Look.canvasArea
        let scale = min(area.width * 0.9 / region.width, area.height * 0.9 / region.height) / (canvasSize.width / Bite.sheet.width)
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        let focus = CGPoint(x: region.midX / Bite.sheet.width * size.width, y: region.midY / Bite.sheet.height * size.height)
        return CGRect(x: area.midX - focus.x, y: area.midY - focus.y, width: size.width, height: size.height)
    }

    func canvasRect(at time: Double) -> CGRect {
        let t = times
        // In on the face while its lines are drawn, then out again.
        let face = zoomed(on: CGRect(x: 200, y: 250, width: 520, height: 470))
        let faceIn = Ease.inOut(Ease.ramp(time, t.lines + 2.0, 0.9)) * (1 - Ease.inOut(Ease.ramp(time, t.flats - 1.6, 0.9)))
        // In on the ice cream while it is jumped to.
        let scoop = zoomed(on: CGRect(x: 230, y: 760, width: 560, height: 420))
        let scoopIn = Ease.inOut(Ease.ramp(time, t.jump + 0.2, 0.8)) * (1 - Ease.inOut(Ease.ramp(time, t.versions - 0.8, 0.7)))
        var rect = Ease.mix(restingRect, face, faceIn)
        rect = Ease.mix(rect, scoop, scoopIn)
        return rect
    }

    func view(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x / canvasSize.width * rect.width, y: rect.minY + point.y / canvasSize.height * rect.height)
    }

    func view(_ box: CGRect, in rect: CGRect) -> CGRect {
        let origin = view(box.origin, in: rect)
        let end = view(CGPoint(x: box.maxX, y: box.maxY), in: rect)
        return CGRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
    }

    // MARK: Drawing a frame

    func draw(at time: Double, in context: CGContext) {
        let t = times
        switch time {
        case ..<t.teaser:
            drawOpening(at: time, in: context)
        case ..<t.rough:
            drawTeaser(at: time, in: context)
        case ..<t.showcase:
            drawStudio(at: time, in: context)
        case ..<t.app:
            drawShowcase(at: time, in: context)
        case ..<t.ending:
            drawApp(at: time, in: context)
        default:
            drawEnding(at: time, in: context)
        }
        // Soft cuts between the big parts of the film: through black, or into the white ending.
        for cut in [t.teaser, t.rough, t.showcase, t.app, t.ending] {
            let distance = abs(time - cut)
            guard distance < 0.3 else { continue }
            context.setFillColor(CGColor(gray: cut == t.ending ? 1 : 0, alpha: 1 - CGFloat(distance / 0.3)))
            context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
    }

    // MARK: The opening

    private func drawOpening(at time: Double, in context: CGContext) {
        context.setFillColor(Look.color(0x0E1014))
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let words = Ease.out(Ease.ramp(time, 0.4, 0.9)) * (1 - Ease.ramp(time, 3.0, 0.5))
        if words > 0 {
            context.saveGState()
            context.setAlpha(words)
            context.setShadow(offset: .zero, blur: 30, color: Look.color(0x5AB4FF, alpha: 0.5))
            Look.draw(BrandArt.tagline, font: Look.uiFont(66, bold: true), color: Look.color(0xFFFFFF),
                      centeredAt: CGPoint(x: 960, y: 520 - (1 - words) * 14), in: context)
            context.restoreGState()
        }
        let small = Ease.out(Ease.ramp(time, 1.5, 0.7)) * (1 - Ease.ramp(time, 3.0, 0.5))
        if small > 0 {
            context.saveGState()
            context.setAlpha(small)
            Look.draw("Oekaki Studio", font: Look.uiFont(26), color: Look.dim, centeredAt: CGPoint(x: 960, y: 612), in: context)
            context.restoreGState()
        }
    }

    // MARK: The teaser

    /// The finished picture across the whole frame: sharp in the middle, a soft copy of itself to the sides.
    private func drawPicture(_ image: CGImage?, soft: CGImage?, zoom: CGFloat, focus: CGPoint, in context: CGContext) {
        let frame = CGRect(x: 0, y: 0, width: W, height: H)
        if let soft {
            let scale = W / CGFloat(soft.width)
            let height = CGFloat(soft.height) * scale
            Look.draw(soft, in: CGRect(x: 0, y: (H - height) / 2, width: W, height: height), context: context)
            context.setFillColor(Look.color(0x000000, alpha: 0.25))
            context.fill(frame)
        }
        guard let image else { return }
        let base = H / CGFloat(image.height)
        let scale = base * zoom
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        // `focus` (0…1 across the picture) sits at the middle of the frame, as far as the picture allows.
        var x = W / 2 - focus.x * size.width
        var y = H / 2 - focus.y * size.height
        y = min(0, max(H - size.height, y))
        if size.width > W { x = min(0, max(W - size.width, x)) }
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 10), blur: 40, color: Look.color(0x000000, alpha: 0.5))
        Look.draw(image, in: rect, context: context)
        context.restoreGState()
    }

    private func drawTeaser(at time: Double, in context: CGContext) {
        let t = times
        let progress = CGFloat((time - t.teaser) / (t.rough - t.teaser))
        drawPicture(finished, soft: finishedSoft, zoom: 1.9 - 0.25 * progress, focus: CGPoint(x: 0.44, y: 0.36), in: context)
        let title = Ease.out(Ease.ramp(time, t.teaser + 0.5, 0.7)) * (1 - Ease.ramp(time, t.rough - 0.6, 0.4))
        guard title > 0 else { return }
        context.saveGState()
        context.setAlpha(title)
        context.setFillColor(Look.color(0x000000, alpha: 0.35))
        context.fill(CGRect(x: 0, y: 760, width: W, height: 220))
        context.setShadow(offset: CGSize(width: 0, height: 4), blur: 18, color: Look.color(0x000000, alpha: 0.6))
        Look.draw("「一口食べる？」", font: Look.uiFont(76, bold: true), color: Look.color(0xFFFFFF), centeredAt: CGPoint(x: 960, y: 842), in: context)
        Look.draw("ができるまで", font: Look.uiFont(34, bold: true), color: Look.color(0xD6F5EE), centeredAt: CGPoint(x: 960, y: 922), in: context)
        context.restoreGState()
    }

    // MARK: The studio

    private func drawStudio(at time: Double, in context: CGContext) {
        let t = times
        FilmKit.chrome(title: "一口食べる？.\(DocumentFile.fileExtension) — Oekaki Studio", in: context)
        drawCanvas(at: time, in: context)
        switch time {
        case t.shadows..<t.background:
            drawLayers(at: time, in: context)
        case t.versions..<t.replay:
            drawVersionsPanel(at: time, in: context)
        default:
            drawSource(at: time, in: context)
        }
        drawStudioStatus(at: time, in: context)
        drawOverlays(at: time, in: context)
        drawStudioCaption(at: time, in: context)
    }

    private func drawCanvas(at time: Double, in context: CGContext) {
        let t = times
        let rect = canvasRect(at: time)
        context.saveGState()
        context.clip(to: Look.canvasArea)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 8), blur: 30, color: Look.color(0x000000, alpha: 0.5))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.restoreGState()
        switch time {
        case (t.background + 2.9)..<t.light:
            // The background, sharp and then out of focus as the slider goes.
            let amount = Ease.inOut(Ease.ramp(time, t.background + 3.4, 2.0))
            let index = min(blurFrames.count - 1, Int((amount * CGFloat(maxBlur)).rounded()))
            if blurFrames.indices.contains(index) { Look.draw(blurFrames[index], in: rect, context: context) }
        case (t.light + 3.7)..<t.versions:
            // Before the light and after it, wiped across; then the finished picture.
            if let after = looks.first?.picture {
                Look.draw(after, in: rect, context: context)
                let wipe = 1 - Ease.inOut(Ease.ramp(time, t.light + 3.8, 1.2))
                if wipe > 0, let before = blurFrames.last {
                    context.saveGState()
                    context.clip(to: CGRect(x: rect.minX, y: rect.minY, width: rect.width * wipe, height: rect.height))
                    Look.draw(before, in: rect, context: context)
                    context.restoreGState()
                    context.setFillColor(Look.color(0xFFFFFF, alpha: 0.9))
                    context.fill(CGRect(x: rect.minX + rect.width * wipe - 1.5, y: rect.minY, width: 3, height: rect.height))
                }
            }
        case t.versions..<t.replay:
            drawComparison(at: time, in: rect, context: context)
        default:
            if let shot = shot(at: time), let image = image(for: shot) {
                Look.draw(image, in: rect, context: context)
            } else if time >= t.jump, let after = looks.first?.picture {
                Look.draw(after, in: rect, context: context)
            }
        }
        context.restoreGState()
    }

    // MARK: The source

    static let lineHeight: CGFloat = 29

    /// The line being written, and how much of it is typed, while steps are played.
    private func writing(at time: Double) -> (line: Int, typed: CGFloat)? {
        guard let shot = shot(at: time) else { return nil }
        switch shot {
        case .partial(let index, let share): return (index, CGFloat(min(1, share * 1.6)))
        case .step(let index): return (index, 1)
        }
    }

    private func drawSource(at time: Double, in context: CGContext) {
        let t = times
        let body = FilmKit.panel("ソース", note: "1 手 = 1 行", in: context)
        let visible = Int(body.height / Self.lineHeight)
        var current = writing(at: time) ?? (0, 0)
        // Jumping to the ice cream's line.
        let jump = Ease.inOut(Ease.ramp(time, t.jump + 1.3, 0.5)) * (1 - Ease.ramp(time, t.versions - 0.4, 0.3))
        if time >= t.jump, time < t.versions { current = (code.count - 1, 1) }
        let follow = max(0, CGFloat(current.line) + current.typed - CGFloat(visible - 5))
        let target = max(0, CGFloat(scoopLine) - CGFloat(visible) / 2)
        let top = Ease.mix(follow, target, jump)
        context.saveGState()
        context.clip(to: body)
        let first = max(0, Int(top.rounded(.down)))
        let font = Look.codeFont(16.5)
        let last = time >= t.jump ? code.count - 1 : current.line
        if first <= last {
            for index in first...min(last, first + visible + 2) {
                let y = body.minY + 8 + (CGFloat(index) - top) * Self.lineHeight
                let isCurrent = index == current.line && time < t.jump
                if index == scoopLine, jump > 0 {
                    context.setFillColor(Look.color(0x2D4A6E, alpha: jump))
                    context.fill(CGRect(x: body.minX + 1, y: y, width: body.width, height: Self.lineHeight))
                    context.setFillColor(Look.accent.copy(alpha: jump)!)
                    context.fill(CGRect(x: body.minX + 1, y: y, width: 4, height: Self.lineHeight))
                } else if isCurrent {
                    context.setFillColor(Look.color(time >= t.replay ? 0x2B4440 : 0x2A2F3A))
                    context.fill(CGRect(x: body.minX + 1, y: y, width: body.width, height: Self.lineHeight))
                }
                let number = Look.line("\(index + 1)", font: Look.codeFont(14), color: isCurrent ? Look.text : Look.color(0x4B5263))
                Look.draw(number, at: CGPoint(x: body.minX + 62 - Look.width(of: number), y: y + 20), in: context)
                let typed = isCurrent ? current.typed : 1
                let end = FilmKit.code(code[index], typed: typed, at: CGPoint(x: body.minX + 80, y: y + 20), font: font, in: context)
                if isCurrent, time < t.replay, Int(time * 2) % 2 == 0 || typed < 1 {
                    context.setFillColor(Look.accent)
                    context.fill(CGRect(x: end + 2, y: y + 5, width: 2, height: 20))
                }
            }
        }
        context.restoreGState()
        if jump > 0.01 {
            let y = body.minY + 8 + (CGFloat(scoopLine) - top) * Self.lineHeight
            let label = Look.line("定義へジャンプ  ⌘クリック", font: Look.uiFont(15, bold: true), color: Look.color(0x0F1A26))
            let width = Look.width(of: label) + 28
            let box = CGRect(x: Look.panel.maxX - width - 20, y: y - 40, width: width, height: 32)
            context.saveGState()
            context.setAlpha(jump)
            context.addPath(Look.roundedRect(box, radius: 8))
            context.setFillColor(Look.accent)
            context.fillPath()
            Look.draw(label, at: CGPoint(x: box.minX + 14, y: box.minY + 22), in: context)
            context.restoreGState()
        }
    }

    // MARK: Layers

    /// The layers of the part being worked on, top first, with how each is put on the ones below.
    private func drawLayers(at time: Double, in context: CGContext) {
        let body = FilmKit.panel("レイヤー", note: "重ね方で、影と光", in: context)
        let line = writing(at: time)?.line ?? 0
        let active = code[...min(line, code.count - 1)].last { $0.layer != nil }?.layer ?? ""
        let part = Self.partName(of: active)
        let layers = picture.document.layers.reversed().filter { Self.partName(of: $0.name) == part }
        var y = body.minY + 20
        Look.draw(Look.line("パーツ「\(part)」", font: Look.uiFont(16, bold: true), color: Look.dim), at: CGPoint(x: body.minX + 24, y: y + 14), in: context)
        y += 36
        for layer in layers {
            let row = CGRect(x: body.minX + 16, y: y, width: body.width - 32, height: 58)
            let isActive = layer.name == active
            context.addPath(Look.roundedRect(row, radius: 10))
            context.setFillColor(isActive ? Look.color(0x2D4A6E) : Look.color(0x262A32))
            context.fillPath()
            if isActive {
                context.setFillColor(Look.accent)
                context.fill(CGRect(x: row.minX, y: row.minY + 8, width: 4, height: row.height - 16))
            }
            Look.draw(Look.line(layer.style.isClipped ? "  ↳ \(layer.name)" : layer.name, font: Look.uiFont(19, bold: true), color: Look.text), at: CGPoint(x: row.minX + 18, y: row.minY + 26), in: context)
            let blend = layer.style.blend == .normal ? "通常" : layer.style.blend.title
            Look.draw(Look.line(blend, font: Look.uiFont(14), color: layer.style.blend == .normal ? Look.dim : Look.accent), at: CGPoint(x: row.minX + 18, y: row.minY + 47), in: context)
            y += 66
        }
    }

    /// 「髪の影」 → 「髪」; the eye's layers are all 「目」.
    static func partName(of layer: String) -> String {
        if ["白目", "白目の影", "瞳", "瞳の影", "瞳の光", "目の輝き"].contains(layer) { return "目" }
        for suffix in ["の線", "の陰", "の影", "の濃い影", "の光", "の透け", "の毛先", "の陰影"] where layer.hasSuffix(suffix) {
            return String(layer.dropLast(suffix.count))
        }
        return layer
    }

    // MARK: Versions

    private var versionCards: [CGRect] {
        (0..<3).map { CGRect(x: Look.panel.minX + 24, y: Look.panel.minY + 76 + CGFloat($0) * 236, width: Look.panel.width - 48, height: 220) }
    }

    private func drawVersionsPanel(at time: Double, in context: CGContext) {
        let t = times
        FilmKit.panel("案", note: "色の組を変えて、もう一枚", in: context)
        let chosen = time >= t.versions + 4.3
        for (index, card) in versionCards.enumerated() where looks.indices.contains(index) {
            let appear = Ease.out(Ease.ramp(time, t.versions + 0.2 + Double(index) * 0.25, 0.4))
            guard appear > 0 else { continue }
            let isMain = index == 0 && chosen
            FilmKit.card(card, alpha: appear, in: context)
            context.saveGState()
            context.setAlpha(appear)
            let thumb = CGRect(x: card.minX + 16, y: card.minY + 16, width: 150, height: 188)
            context.saveGState()
            context.addPath(Look.roundedRect(thumb, radius: 8))
            context.clip()
            Look.draw(looks[index].picture, in: thumb, context: context)
            context.restoreGState()
            Look.draw(Look.line(looks[index].name, font: Look.uiFont(24, bold: true), color: Look.text), at: CGPoint(x: thumb.maxX + 24, y: card.minY + 56), in: context)
            Look.draw(Look.line(index == 0 ? "本番の絵" : "案 \(index)", font: Look.uiFont(15), color: Look.dim), at: CGPoint(x: thumb.maxX + 24, y: card.minY + 86), in: context)
            if isMain {
                let tag = CGRect(x: thumb.maxX + 24, y: card.minY + 120, width: 150, height: 40)
                context.addPath(Look.roundedRect(tag, radius: 10))
                context.setFillColor(Look.accent)
                context.fillPath()
                Look.draw("✓ これにする", font: Look.uiFont(17, bold: true), color: Look.color(0x0F1A26), centeredAt: CGPoint(x: tag.midX, y: tag.midY), in: context)
            }
            context.restoreGState()
        }
    }

    /// Two versions side by side on the canvas, the line between them sliding across.
    private func drawComparison(at time: Double, in rect: CGRect, context: CGContext) {
        let t = times
        guard looks.count == 3 else { return }
        // Mint against strawberry, then against the night, then mint alone.
        let other = time < t.versions + 2.4 ? 1 : 2
        let sweep = time < t.versions + 2.4 ? Ease.ramp(time, t.versions + 0.6, 1.6) : Ease.ramp(time, t.versions + 2.5, 1.5)
        let split = time >= t.versions + 4.1 ? 1 : 0.85 - 0.7 * sin(.pi * sweep) * 0.5 - 0.15
        Look.draw(looks[other].picture, in: rect, context: context)
        context.saveGState()
        context.clip(to: CGRect(x: rect.minX, y: rect.minY, width: rect.width * split, height: rect.height))
        Look.draw(looks[0].picture, in: rect, context: context)
        context.restoreGState()
        if split < 1 {
            let x = rect.minX + rect.width * split
            context.setFillColor(Look.color(0xFFFFFF))
            context.fill(CGRect(x: x - 1.5, y: rect.minY, width: 3, height: rect.height))
            context.fillEllipse(in: CGRect(x: x - 14, y: rect.midY - 14, width: 28, height: 28))
            FilmKit.badge(looks[0].name, at: CGPoint(x: rect.minX + 16, y: rect.minY + 16), in: context)
            FilmKit.badge(looks[other].name, at: CGPoint(x: rect.maxX - 16, y: rect.minY + 16), alignRight: true, in: context)
        }
    }

    // MARK: Overlays

    private func drawStudioStatus(at time: Double, in context: CGContext) {
        let line = writing(at: time)?.line ?? (code.count - 1)
        let layer = code[...min(line, code.count - 1)].last { $0.layer != nil }?.layer ?? "背景"
        FilmKit.status(left: "◆ \(layer)    \(line + 1) / \(code.count) 手", right: "\(picture.document.width) × \(picture.document.height)    journal v6", in: context)
    }

    private func drawOverlays(at time: Double, in context: CGContext) {
        let t = times
        let rect = canvasRect(at: time)
        if let phase = phase(at: time) {
            FilmKit.badge("◆ \(phase.rawValue)", at: CGPoint(x: 32, y: 72), in: context)
        }
        if time >= t.replay, time < t.showcase {
            FilmKit.badge("▶  描いた順に再生", at: CGPoint(x: Look.canvasArea.maxX - 32, y: 72), alignRight: true, accent: true, in: context)
        }
        drawLasso(at: time, rect: rect, in: context)
        drawBlurCard(at: time, in: context)
        drawJump(at: time, rect: rect, in: context)
        if time >= t.light + 3.7, time < t.light + 5.2 {
            let alpha = Ease.ramp(time, t.light + 3.7, 0.3) * (1 - Ease.ramp(time, t.light + 4.9, 0.3))
            context.saveGState()
            context.setAlpha(alpha)
            FilmKit.badge("光を足す前", at: CGPoint(x: rect.minX + 16, y: rect.minY + 16), in: context)
            FilmKit.badge("光を足したあと", at: CGPoint(x: rect.maxX - 16, y: rect.minY + 16), alignRight: true, accent: true, in: context)
            context.restoreGState()
        }
    }

    /// The pointer draws round the hair; the outline follows it, then the hair fills.
    private func drawLasso(at time: Double, rect: CGRect, in context: CGContext) {
        let lasso = lassoTimes
        guard lasso.end > lasso.start, time >= lasso.start - 0.4, time < lasso.end + 0.4, !hairOutline.isEmpty else { return }
        let drawn = Ease.inOut(Ease.ramp(time, lasso.start, 1.7))
        let count = max(2, Int(CGFloat(hairOutline.count) * drawn))
        let points = hairOutline.prefix(count).map { view($0, in: rect) }
        if time < lasso.end, drawn > 0 {
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(Look.color(0x82DCCB, alpha: 0.35))
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(Look.accent)
            context.setLineWidth(2.5)
            context.setLineDash(phase: CGFloat(time * 30), lengths: [9, 6])
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
        // The pointer, and the tool's name.
        let visible = Ease.ramp(time, lasso.start - 0.4, 0.3) * (1 - Ease.ramp(time, lasso.end, 0.3))
        if visible > 0, let tip = points.last {
            context.saveGState()
            context.setAlpha(visible)
            Look.drawPointer(at: tip, pressed: time < lasso.end - 0.4, in: context)
            FilmKit.badge("◯ 囲んで塗る", at: CGPoint(x: Look.canvasArea.maxX - 32, y: 72), alignRight: true, accent: true, in: context)
            context.restoreGState()
        }
    }

    /// The layer's blur slider, dragged from nothing to the full blur.
    private func drawBlurCard(at time: Double, in context: CGContext) {
        let t = times
        let alpha = Ease.ramp(time, t.background + 2.9, 0.3) * (1 - Ease.ramp(time, t.light - 0.4, 0.3))
        guard alpha > 0 else { return }
        let card = CGRect(x: 40, y: 140, width: 470, height: 170)
        FilmKit.card(card, alpha: alpha, in: context)
        let amount = Ease.inOut(Ease.ramp(time, t.background + 3.4, 2.0))
        context.saveGState()
        context.setAlpha(alpha)
        Look.draw(Look.line("レイヤー「店」「窓の外」", font: Look.uiFont(22, bold: true), color: Look.text), at: CGPoint(x: card.minX + 24, y: card.minY + 42), in: context)
        Look.draw(Look.line("ぼかし", font: Look.uiFont(18, bold: true), color: Look.text), at: CGPoint(x: card.minX + 24, y: card.minY + 98), in: context)
        let value = Int((amount * CGFloat(maxBlur * 2)).rounded())
        Look.draw(Look.line(value == 0 ? "なし" : "\(value)px", font: Look.codeFont(18), color: Look.accent), at: CGPoint(x: card.maxX - 90, y: card.minY + 98), in: context)
        let track = CGRect(x: card.minX + 24, y: card.minY + 124, width: card.width - 48, height: 6)
        context.addPath(Look.roundedRect(track, radius: 3))
        context.setFillColor(Look.color(0x3A3F4A))
        context.fillPath()
        context.addPath(Look.roundedRect(CGRect(x: track.minX, y: track.minY, width: track.width * amount, height: track.height), radius: 3))
        context.setFillColor(Look.accent)
        context.fillPath()
        let knob = CGPoint(x: track.minX + track.width * amount, y: track.midY)
        context.setFillColor(Look.color(0xFFFFFF))
        context.fillEllipse(in: CGRect(x: knob.x - 11, y: knob.y - 11, width: 22, height: 22))
        let dragging = time >= t.background + 3.2 && time < t.background + 5.6
        if dragging {
            Look.drawPointer(at: CGPoint(x: knob.x + 2, y: knob.y + 4), pressed: true, in: context)
        }
        context.restoreGState()
    }

    /// ⌘-click on the ice cream: it lights up, and the source jumps to its line.
    private func drawJump(at time: Double, rect: CGRect, in context: CGContext) {
        let t = times
        guard time >= t.jump, time < t.versions else { return }
        let box = view(scoopBox, in: rect).insetBy(dx: -10, dy: -10)
        let target = CGPoint(x: box.midX + box.width * 0.1, y: box.midY - box.height * 0.1)
        let start = CGPoint(x: Look.canvasArea.maxX - 160, y: Look.canvasArea.maxY - 140)
        let move = Ease.inOut(Ease.ramp(time, t.jump + 0.3, 0.8))
        let point = Ease.mix(start, target, move)
        let click = t.jump + 1.15
        let picked = Ease.ramp(time, click, 0.2) * (1 - Ease.ramp(time, t.versions - 0.5, 0.3))
        if picked > 0 {
            let pulse = 0.8 + 0.2 * sin(time * 5)
            context.saveGState()
            context.setAlpha(picked * pulse)
            context.setShadow(offset: .zero, blur: 22, color: Look.accent)
            context.addPath(Look.roundedRect(box, radius: 14))
            context.setStrokeColor(Look.accent)
            context.setLineWidth(3.5)
            context.strokePath()
            context.restoreGState()
            context.saveGState()
            context.setAlpha(picked)
            let label = Look.line("塗り #\(code[scoopLine].itemID ?? 0)  アイス", font: Look.codeFont(15), color: Look.color(0x0F1A26))
            let tag = CGRect(x: box.minX, y: box.minY - 32, width: Look.width(of: label) + 20, height: 26)
            context.addPath(Look.roundedRect(tag, radius: 6))
            context.setFillColor(Look.accent)
            context.fillPath()
            Look.draw(label, at: CGPoint(x: tag.minX + 10, y: tag.minY + 18), in: context)
            context.restoreGState()
        }
        let visible = Ease.ramp(time, t.jump + 0.2, 0.3) * (1 - Ease.ramp(time, t.jump + 2.6, 0.3))
        if visible > 0 {
            context.saveGState()
            context.setAlpha(visible)
            Look.drawRipple(at: point, progress: CGFloat((time - click) / 0.5), in: context)
            Look.drawPointer(at: point, pressed: time >= click && time < click + 0.15, in: context)
            context.restoreGState()
        }
    }

    // MARK: Captions

    private func caption(at time: Double) -> (String, CGFloat)? {
        let t = times
        let lasso = lassoTimes
        let captions: [(String, Double, Double)] = [
            ("ラフも、1 本ずつコードになる。", t.rough + 0.4, t.lines),
            ("線画。1 本の線が、1 行。", t.lines + 0.3, t.flats),
            ("下塗り。色を置いていく。", t.flats + 0.3, lasso.start - 0.2),
            ("囲んで塗る。線がなくても塗れる。", lasso.start - 0.1, lasso.end + 0.6),
            ("影は「暗く重ねる」、光は「明るく重ねる」。", t.shadows + 0.3, t.background),
            ("背景を描いて、", t.background + 0.3, t.background + 2.8),
            ("ぼかしで、奥行きを。", t.background + 2.9, t.light),
            ("逆光、ふちの光、光の粒。", t.light + 0.3, t.jump),
            ("どの塗りも、そのコードへジャンプ。", t.jump + 0.3, t.versions),
            ("色の組を変えて、案を並べる。", t.versions + 0.3, t.replay),
            ("描いた順に、最初から再生。", t.replay + 0.3, t.showcase),
        ]
        for (text, start, end) in captions where time >= start && time < end {
            return (text, min(Ease.ramp(time, start, 0.35), 1 - Ease.ramp(time, end - 0.35, 0.35)))
        }
        return nil
    }

    private func drawStudioCaption(at time: Double, in context: CGContext) {
        guard let (text, alpha) = caption(at: time) else { return }
        FilmKit.caption(text, alpha: alpha, center: CGPoint(x: Look.canvasArea.midX, y: Look.canvasArea.maxY - 78), in: context)
    }

    // MARK: The showcase

    private func drawShowcase(at time: Double, in context: CGContext) {
        let t = times
        // From her eyes down to the spoon she holds out, then back to the whole picture.
        let share = CGFloat((time - t.showcase) / (t.app - t.showcase))
        let keys: [(at: CGFloat, zoom: CGFloat, focus: CGPoint)] = [
            (0, 2.3, CGPoint(x: 0.45, y: 0.37)), (0.45, 1.75, CGPoint(x: 0.47, y: 0.56)), (1, 1.05, CGPoint(x: 0.5, y: 0.52)),
        ]
        let after = keys.firstIndex { $0.at >= share } ?? keys.count - 1
        let from = keys[max(after - 1, 0)], to = keys[after]
        let step = Ease.inOut(to.at > from.at ? min(1, max(0, (share - from.at) / (to.at - from.at))) : 1)
        let zoom = from.zoom + (to.zoom - from.zoom) * step
        let focus = Ease.mix(from.focus, to.focus, step)
        drawPicture(finished, soft: finishedSoft, zoom: zoom, focus: focus, in: context)
        drawFloatingLight(at: time, in: context)
        // Her words, written down the right side, one character at a time.
        let words = "一口、食べる？".map(String.init)
        for (index, character) in words.enumerated() {
            let shown = Ease.out(Ease.ramp(time, t.app - 3.8 + Double(index) * 0.12, 0.5)) * (1 - Ease.ramp(time, t.app - 0.45, 0.35))
            guard shown > 0 else { continue }
            context.saveGState()
            context.setAlpha(shown)
            context.setShadow(offset: CGSize(width: 0, height: 3), blur: 18, color: Look.color(0x1E4A50, alpha: 0.9))
            let punctuation = character == "、"
            let center = CGPoint(x: 1640 + (punctuation ? 22 : 0), y: 300 + CGFloat(index) * 82 - (punctuation ? 22 : 0) - (1 - shown) * 12)
            Look.draw(character, font: Look.uiFont(68, bold: true), color: Look.color(0xFFFFFF), centeredAt: center, in: context)
            context.restoreGState()
        }
    }

    /// Specks of light drifting up through the frame, twinkling.
    private func drawFloatingLight(at time: Double, in context: CGContext) {
        var random = SplitMix(seed: 99)
        context.saveGState()
        context.setBlendMode(.plusLighter)
        for _ in 0..<60 {
            let x0 = random.next() * W, y0 = random.next() * H
            let speed = 12 + random.next() * 30
            let phase = random.next() * 6.28
            let size = 1.5 + random.next() * 4
            let y = (y0 - CGFloat(time) * speed).truncatingRemainder(dividingBy: H + 40)
            let x = x0 + sin(CGFloat(time) * 0.6 + phase) * 18
            let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(CGFloat(time) * 2.4 + phase))
            let point = CGPoint(x: x, y: y < -20 ? y + H + 40 : y)
            context.setFillColor(Look.color(0xFFF2D8, alpha: 0.7 * twinkle))
            context.setShadow(offset: .zero, blur: size * 4, color: Look.color(0xFFE2A8, alpha: twinkle))
            context.fillEllipse(in: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2))
        }
        context.restoreGState()
    }

    // MARK: The app

    /// The picture as it opens in Oekaki Studio itself, its layers beside it.
    private func drawApp(at time: Double, in context: CGContext) {
        let t = times
        context.setFillColor(Look.color(0x0E1014))
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        guard let window = appWindow else {
            drawShowcase(at: time, in: context)
            return
        }
        let grow = Ease.out(Ease.ramp(time, t.app, 2.8))
        let scale = min(W * 0.92 / CGFloat(window.width), H * 0.86 / CGFloat(window.height)) * (0.96 + 0.04 * grow)
        let size = CGSize(width: CGFloat(window.width) * scale, height: CGFloat(window.height) * scale)
        let rect = CGRect(x: (W - size.width) / 2, y: (H - size.height) / 2 - 20, width: size.width, height: size.height)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 16), blur: 50, color: Look.color(0x000000, alpha: 0.6))
        context.addPath(Look.roundedRect(rect, radius: 14))
        context.clip()
        Look.draw(window, in: rect, context: context)
        context.restoreGState()
        let alpha = min(Ease.ramp(time, t.app + 0.4, 0.4), 1 - Ease.ramp(time, t.ending - 0.4, 0.3))
        FilmKit.caption("描いたままの手順で、あとから開いて直せる。", alpha: alpha, center: CGPoint(x: W / 2, y: H - 60), size: 32, in: context)
    }

    // MARK: The ending

    private func drawEnding(at time: Double, in context: CGContext) {
        let t = times
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let words = Ease.out(Ease.ramp(time, t.ending + 0.3, 0.7))
        if words > 0 {
            context.saveGState()
            context.setAlpha(words)
            Look.draw(BrandArt.tagline, font: Look.uiFont(64, bold: true), color: Look.color(0x1F2430), centeredAt: CGPoint(x: 960, y: 420 + (1 - words) * 18), in: context)
            context.restoreGState()
        }
        let name = Ease.out(Ease.ramp(time, t.ending + 1.0, 0.6))
        if name > 0, let wordmark {
            context.saveGState()
            context.setAlpha(name)
            let height: CGFloat = 200
            let width = height * CGFloat(wordmark.width) / CGFloat(wordmark.height)
            Look.draw(wordmark, in: CGRect(x: 960 - width / 2, y: 540 + (1 - name) * 12, width: width, height: height), context: context)
            context.restoreGState()
        }
    }
}

extension Slots {
    /// When the step at `index` in this run begins.
    func start(of index: Int) -> Double {
        index == 0 ? start : endTime(of: index - 1)
    }

    /// What the canvas shows at `time`, as the promotional film counts its shots.
    func filmShot(at time: Double, before: Int, replay: Replay) -> BitePV.Shot {
        switch shot(at: time, before: before, replay: replay) {
        case .step(let index): return .step(index)
        case .partial(let index, let share): return .partial(index, share)
        case .blend(_, let index, _): return .step(index)
        }
    }
}
