import CoreGraphics
import Foundation
import OekakiKit

/// The colours of the picture: warm evening light, cool shadows.
enum Palette {
    static let ink = RGBA(hex: 0x3A2430)
    static let sketch = RGBA(hex: 0x6FA8DC)
    static let skin = RGBA(hex: 0xFFE4D6)
    static let mouth = RGBA(hex: 0xC85A66)
    static let hair = RGBA(hex: 0x7A4A48)
    static let backHair = RGBA(hex: 0x5E3A40)
    static let iris = RGBA(hex: 0x2F9AA8)
    static let eyeWhite = RGBA(hex: 0xFBF6F4)
    static let navy = RGBA(hex: 0x2E3A64)
    static let blouse = RGBA(hex: 0xF4F1F2)
    static let ribbon = RGBA(hex: 0xE0484F)
    static let white = RGBA(hex: 0xFFFFFF)
    static let skyTop = RGBA(hex: 0x3B3F86)
    static let skyLow = RGBA(hex: 0xFF9E6B)
    static let sun = RGBA(hex: 0xFFE2A8)
    // Used by the film's inspector.
    static let coral = RGBA(hex: 0xEE6F73)
    static let blush = RGBA(hex: 0xF79A9A)
    static let hairLight = RGBA(hex: 0xD9B0A0)
}

/// What the rest of the film needs to know about the picture.
struct Picture {
    let document: CanvasDocument
    /// Journal steps that end each part of the making, counted after flushing.
    var drawnUpTo = 0
    var recoloredUpTo = 0
    var tidiedUpTo = 0
    /// The fill clicked in the film.
    var ribbon = 0
    var ribbonShadows: [Int] = []
    /// The shadow layer whose blend mode the film changes.
    var shadowLayer: UUID?
    /// Where the doodles for tidying sit on the canvas.
    var doodleArea = CGRect.zero
    var problems: [String] = []
}

/// The script of the picture: a girl in a sailor collar looking back over
/// her shoulder into an evening wind, drawn the way a person would, sketch
/// first and light last.
enum Portrait {
    static let canvasWidth = 1080
    static let canvasHeight = 1200
    /// Where the face's centre sits on the canvas; the script is written around (0, 0).
    static let faceCenter = CGPoint(x: 500, y: 400)
    static let scale: CGFloat = 1.25
    /// The whole figure leans this many degrees, top toward the wind.
    static let tilt: CGFloat = -12
    /// The body is drawn this much higher than written, for a shorter neck.
    static let bodyLift: CGFloat = -36

    enum Stage: Int, Comparable {
        case drawn, recolored, tidied
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    static func draw(through stage: Stage = .tidied) -> Picture {
        let document = CanvasDocument(width: canvasWidth, height: canvasHeight)
        let artist = Artist(document: document)
        artist.transform = CGAffineTransform(translationX: faceCenter.x, y: faceCenter.y)
            .rotated(by: tilt * .pi / 180)
            .scaledBy(x: scale, y: scale)
        var picture = Picture(document: document)

        let paper = document.activeLayerID
        document.renameLayer(paper, to: "背景")
        let sketchLayer = artist.layer("下描き", opacity: 0.55)
        sketch(artist)
        let lines = artist.layer("線画")
        lineArt(artist)
        document.setLayerVisible(sketchLayer, false)
        artist.layer("下塗り", below: lines)
        picture.ribbon = baseColors(artist)
        artist.use(paper)
        background(artist)

        // Shadow starts as plain paint; the film switches it to multiply.
        let shadowLayer = artist.layer("影", style: LayerStyle(isClipped: true), below: lines)
        picture.shadowLayer = shadowLayer
        shadows(artist)
        artist.layer("影2", style: LayerStyle(blend: .multiply, isClipped: true), below: lines)
        deepShadows(artist)
        artist.layer("光", style: LayerStyle(blend: .screen, isClipped: true), below: lines)
        light(artist)
        artist.layer("瞳", below: lines)
        irises(artist)
        artist.layer("瞳の影", style: LayerStyle(blend: .multiply, isClipped: true), below: lines)
        irisShade(artist)
        artist.layer("瞳の光", style: LayerStyle(blend: .add, isClipped: true), below: lines)
        irisLight(artist)
        artist.layer("線の色", style: LayerStyle(isClipped: true))
        lineColor(artist)
        artist.layer("ハイライト")
        highlights(artist)
        artist.layer("リムライト", style: LayerStyle(blend: .add, glow: 24))
        rimLight(artist)
        artist.layer("光の粒", style: LayerStyle(blend: .add, glow: 30))
        particles(artist)
        artist.layer("逆光", style: LayerStyle(blend: .add))
        backlight(artist)
        let dusk = artist.layer("周辺減光", style: LayerStyle(blend: .multiply))
        vignette(artist)
        document.flushJournal()
        picture.drawnUpTo = document.journal.count

        if stage >= .recolored {
            document.setLayerBlend(shadowLayer, .multiply)
            document.undo()
            document.redo()
            document.flushJournal()
        }
        picture.recoloredUpTo = document.journal.count

        if stage >= .tidied {
            artist.layer("風", style: LayerStyle(blend: .add, glow: 16), below: dusk)
            picture.doodleArea = windLines(artist)
            document.tidyLines()
            document.flushJournal()
        }
        picture.tidiedUpTo = document.journal.count
        picture.problems = artist.problems
        return picture
    }

    // MARK: Lines

    static let outline = Pen(width: 6, color: Palette.ink, start: 0.08, end: 0.08, floor: 0.35)
    static let inner = Pen(width: 4, color: Palette.ink, start: 0.15, end: 0.15, floor: 0.25)
    /// Hair edges, drawn from the root and lifted off at the tip.
    static let strand = Pen(width: 5.5, color: Palette.ink, start: 0.1, end: 0.55, floor: 0.08)
    static let fine = Pen(width: 2.6, color: Palette.ink, start: 0.2, end: 0.4, floor: 0.1)

    // The lashes, also used to clip the irises.
    static let nearLash = "M -16 10 C -38 -30, -112 -44, -152 -4"
    static let farLash = "M 58 14 C 70 -16, 118 -30, 152 -6"
    static let nearIris = (center: CGPoint(x: -66, y: 26), rx: CGFloat(41), ry: CGFloat(52))
    static let farIris = (center: CGPoint(x: 118, y: 26), rx: CGFloat(26), ry: CGFloat(43))

    static func lineArt(_ a: Artist) {
        // Face, turned toward the right: the far cheek hugs the far eye.
        a.line("M -226 -70 C -236 30, -222 100, -178 150 C -120 205, 20 230, 95 222", outline)
        a.line("M 95 222 C 132 205, 158 170, 164 128 C 168 96, 172 72, 168 50 C 180 22, 182 0, 178 -14", outline)
        eyes(a)
        a.line("M 150 96 Q 160 106, 150 112", fine.with(width: 3))
        a.line("M 74 152 Q 94 158, 112 150", inner.with(width: 3.5))
        a.line("M 74 152 Q 92 172, 112 150", inner.with(width: 3))

        // The crown, from the right temple over the top and down the back to the shoulder.
        a.line("M 200 -90 C 220 -200, 120 -330, -40 -345 C -200 -352, -350 -250, -372 -100 C -384 0, -366 100, -330 200 C -312 255, -300 310, -289 360", outline)
        // The fringe, blown to the right: each clump sweeps toward its right root.
        let roots: [(CGFloat, CGFloat)] = [(-226, -70), (-170, -118), (-104, -130), (-34, -136), (36, -130), (104, -118), (160, -100)]
        let tips: [(CGFloat, CGFloat)] = [(-182, -40), (-118, -52), (-50, -56), (20, -54), (90, -50), (150, -42), (214, -26)]
        for (index, tip) in tips.enumerated() {
            var ends = [roots[index]]
            if index + 1 < roots.count { ends.append(roots[index + 1]) }
            for root in ends {
                let drop = tip.1 - root.1
                let near = tip.0 + (root.0 - tip.0) * 0.25
                a.line("M \(root.0) \(root.1) C \(root.0 + (tip.0 - root.0) * 0.1) \(root.1 + drop * 0.5), \(near) \(tip.1 - drop * 0.35), \(tip.0) \(tip.1)", strand)
            }
        }
        a.line("M 214 -26 Q 196 -16, 178 -14", strand.with(start: 0.4, end: 0.1))
        let strands = [
            "M -170 -118 Q -190 -170, -230 -210", "M -104 -130 Q -120 -190, -150 -240",
            "M -34 -136 Q -40 -200, -70 -260", "M 36 -130 Q 40 -200, 20 -270",
            "M 104 -118 Q 120 -180, 110 -240", "M -300 -60 Q -310 40, -290 130",
            "M -250 20 Q -262 120, -240 200",
        ]
        strands.forEach { a.line($0, strand.with(width: 3.5, start: 0.05, end: 0.7)) }

        // Three locks streaming out to the right in the wind, sky between them.
        a.line("M 196 -84 C 300 -100, 420 -96, 580 -80", strand.with(width: 6, end: 0.2))
        a.line("M 214 -26 C 310 -10, 430 20, 600 50", strand.with(width: 6, end: 0.2))
        // A lock from behind the far cheek.
        a.line("M 169 58 C 280 82, 420 96, 600 116", strand.with(width: 6, end: 0.2))
        a.line("M 200 110 C 300 140, 420 160, 520 170", strand.with(width: 3.2, start: 0.3, end: 0.6))
        a.line("M 250 -56 C 330 -62, 420 -58, 520 -48", strand.with(width: 3.2, start: 0.3, end: 0.6))
        a.line("M 198 -157 C 300 -160, 420 -150, 580 -130", strand.with(width: 6, end: 0.2))
        a.line("M 160 -238 C 280 -262, 420 -266, 580 -252", strand.with(width: 6, end: 0.2))
        a.line("M 230 -214 C 310 -226, 410 -228, 520 -220", strand.with(width: 3.2, start: 0.3, end: 0.6))
        a.line("M 86 -304 C 220 -332, 380 -342, 580 -330", strand.with(width: 6, end: 0.2))

        // Neck, shoulder, and the back of the sailor collar, a little up so the neck is short.
        a.line("M 29 222 C 30 244, 26 266, 20 286", inner)
        a.line("M -93 197 C -95 230, -102 260, -112 286", inner)
        let body = a.transform
        a.transform = body.translatedBy(x: 0, y: bodyLift)
        a.line("M 20 322 C -20 338, -80 338, -112 322", inner)
        a.line("M -112 322 C -200 345, -340 410, -580 580", outline)
        a.line("M 0 330 C 30 400, 34 460, 16 510", inner.with(width: 5))
        a.line("M 16 510 C -150 560, -360 620, -600 700", inner.with(width: 5))
        a.line("M 4 516 C 30 600, 56 690, 80 860", outline)
        // The collar's two white stripes.
        let stripe = Pen(width: 7, color: Palette.white, start: 0.02, end: 0.02, floor: 0.9)
        a.line("M -14 352 C 10 410, 14 456, 0 486 C -150 532, -360 590, -600 668", stripe)
        a.line("M -34 372 C -10 420, -8 448, -22 466 C -160 508, -360 562, -600 638", stripe.with(width: 5))

        // Hair behind the neck, streaming to the right.
        a.transform = body
        a.line("M 134 194 C 240 240, 360 232, 540 196", strand.with(width: 6, start: 0.2, end: 0.2))
        a.transform = body.translatedBy(x: 0, y: bodyLift)
        a.line("M 160 262 C 260 292, 380 290, 500 270", strand.with(width: 3.2, start: 0.3, end: 0.5))
        a.line("M 130 480 C 230 500, 360 510, 500 524", strand.with(width: 3.2, start: 0.3, end: 0.5))

        // The scarf's knot and its tails flying out.
        a.line("M 30 330 C 26 346, 32 362, 48 369 C 68 372, 82 360, 84 344 C 80 330, 60 324, 30 330", inner)
        a.line("M 82 338 C 160 316, 270 324, 380 304 L 352 336 L 400 346 C 300 370, 190 368, 84 352", inner)
        a.line("M 76 364 C 140 398, 250 424, 370 422 L 338 450 L 390 464 C 270 468, 150 440, 62 370", inner)
        a.transform = body
    }

    /// Runs `body` with the body parts' coordinates, which sit a little higher
    /// than they are written.
    static func onBody(_ a: Artist, _ body: () -> Void) {
        let saved = a.transform
        a.transform = saved.translatedBy(x: 0, y: bodyLift)
        body()
        a.transform = saved
    }

    static func eyes(_ a: Artist) {
        let lash = Pen(width: 13, color: Palette.ink, start: 0.35, end: 0.08, floor: 0.25)
        let side = fine.with(width: 2.6, start: 0.1, end: 0.1, floor: 0.6)
        // The near eye, on the left.
        a.line(nearLash, lash)
        a.line("M -142 -10 Q -156 -14, -166 -28", lash.with(width: 7, start: 0.1, end: 0.6))
        a.line("M -152 -4 C -156 22, -150 52, -134 72", side)
        a.line("M -136 72 Q -86 90, -36 76", inner.with(width: 3.5))
        a.line("M -16 10 C -14 37, -22 60, -36 76", side)
        // Lashes at the outer corner and below.
        let flick = Pen(width: 4, color: Palette.ink, start: 0.1, end: 0.7, floor: 0.05)
        a.line("M -150 -2 Q -166 2, -176 -6", flick)
        a.line("M -146 12 Q -162 18, -170 14", flick.with(width: 3.4))
        a.line("M -124 74 Q -132 82, -140 84", flick.with(width: 2.6))
        a.line("M -96 82 Q -100 90, -106 94", flick.with(width: 2.4))
        // The far eye, narrower because the face is turned.
        a.line(farLash, lash.with(width: 11, start: 0.3, end: 0.1))
        a.line("M 146 -10 Q 158 -16, 164 -28", lash.with(width: 6, start: 0.1, end: 0.6))
        a.line("M 152 -6 C 156 18, 150 44, 138 62", side)
        a.line("M 138 62 Q 104 78, 72 68", inner.with(width: 3.2))
        a.line("M 58 14 C 56 36, 62 56, 72 68", side)
        a.line("M 152 0 Q 164 4, 170 -2", flick.with(width: 3.4))
        a.line("M 128 70 Q 132 78, 136 80", flick.with(width: 2.4))
        a.line(irisArc(lash: nearLash, center: nearIris.center, rx: nearIris.rx, ry: nearIris.ry), side.with(width: 2.8, floor: 0.7))
        a.line(irisArc(lash: farLash, center: farIris.center, rx: farIris.rx, ry: farIris.ry), side.with(width: 2.8, floor: 0.7))
    }

    /// The part of an iris outline below the upper lash.
    static func irisArc(lash data: String, center: CGPoint, rx: CGFloat, ry: CGFloat) -> [CGPoint] {
        let lash = PathData.points(data)
        func lashY(_ x: CGFloat) -> CGFloat? {
            lash.min { abs($0.x - x) < abs($1.x - x) }.flatMap { abs($0.x - x) < 4 ? $0.y : nil }
        }
        let ring = PathData.arc(center: center, rx: rx, ry: ry, from: -90, to: 270, spacing: 1)
        let below = ring.filter { point in lashY(point.x).map { point.y > $0 - 5 } ?? false }
        return PathData.resampled(below, spacing: 2.5)
    }

    // MARK: Colour

    /// Returns the ribbon's fill.
    static func baseColors(_ a: Artist) -> Int {
        let big: CGFloat = 600_000
        a.fill("顔", -100, 120, Palette.skin, limit: big)
        a.fill("首", -40, 270, Palette.skin, limit: big)
        a.fill("口", 92, 159, Palette.mouth, limit: 3000)
        for (x, y) in [(-140, 30), (-24, 40), (66, 40), (146, 30)] {
            a.fill("白目", CGFloat(x), CGFloat(y), Palette.eyeWhite, limit: 9000)
        }
        a.fill("髪", -100, -250, Palette.hair, limit: big)
        a.fill("流れる髪", 400, -45, Palette.hair, limit: big)
        a.fill("頬の後ろの髪", 400, 160, Palette.hair, limit: big)
        a.fill("流れる髪", 400, -205, Palette.hair, limit: big)
        a.fill("流れる髪", 200, -345, Palette.hair, limit: big)
        var ribbon = 0
        onBody(a) {
            // One region: it runs on past the ends of the ribbon.
            a.fill("首の後ろの髪", 300, 270, Palette.backHair, limit: big)
            a.fill("襟", -100, 420, Palette.navy, limit: big)
            a.fill("服", -60, 600, Palette.blouse, limit: big)
            a.fill("リボンの結び目", 56, 348, Palette.ribbon, limit: 5000)
            a.fill("リボン", 230, 420, Palette.ribbon, limit: 60000)
            ribbon = a.fill("リボン", 220, 340, Palette.ribbon, limit: 60000) ?? 0
        }
        return ribbon

    }

    static func background(_ a: Artist) {
        a.withCanvasCoordinates {
            a.gradient(.linear, from: CGPoint(x: 900, y: 0), to: CGPoint(x: 300, y: 1200), Palette.skyTop, Palette.skyLow)
            var clear = Palette.sun
            clear.a = 0
            a.gradient(.radial, from: CGPoint(x: 90, y: 160), to: CGPoint(x: 600, y: 160), Palette.sun, clear)
        }
    }
}

extension Artist {
    /// Runs `body` with the script written in canvas pixels.
    func withCanvasCoordinates(_ body: () -> Void) {
        let saved = (transform, mirrored)
        transform = .identity
        mirrored = false
        body()
        (transform, mirrored) = saved
    }
}
