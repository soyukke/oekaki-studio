import CoreGraphics
import Foundation
import OekakiKit

/// "Want a bite?": a girl leans in toward the viewer and holds out a spoon of
/// ice cream, the spoon close and large at the bottom of the picture. Drawn
/// back to front, one part at a time, each part on layers of its own so the
/// nearer parts cover the farther ones, then lit from behind.
enum Treat {
    static let width = 1080
    static let height = 1350

    /// One look of the picture: the girl's colours and the light around her.
    struct Look {
        var name: String
        var hair: RGBA
        var hairShade: RGBA
        var hairLight: RGBA
        var iris: RGBA
        var irisDeep: RGBA
        var cloth: RGBA
        var clothShade: RGBA
        var ribbon: RGBA
        var cream: RGBA
        var creamShade: RGBA
        var creamLight: RGBA
        var bits: RGBA
        var skyTop: RGBA
        var skyLow: RGBA
        var light: RGBA
        var spark: RGBA
        var ink: RGBA
        /// Soft round lights in the background, for the night.
        var bokeh = false
        /// The hair clip that marks the character.
        var clip: Clip = .strawberry
        var clipColor = RGBA(hex: 0xE5404F)
        /// The family restaurant around her.
        var room = Room()
        /// The colour the edges of the picture sink into.
        var deep = RGBA(hex: 0xB0607A, a: 0.6)
    }

    enum Clip { case strawberry, star, moon }

    /// A booth by the window in a family restaurant.
    struct Room {
        var wall = RGBA(hex: 0xFFF0DC)
        var wallShade = RGBA(hex: 0xE9C9A8)
        var wood = RGBA(hex: 0xC08A5E)
        var booth = RGBA(hex: 0xD2505A)
        var boothShade = RGBA(hex: 0x9A2E3E)
        var table = RGBA(hex: 0xFFF9F0)
        var soda = RGBA(hex: 0x8EDB6A)
        var lampShade = RGBA(hex: 0xF4C86A)
        var poster = RGBA(hex: 0xFFE3E8)
        var leaf = RGBA(hex: 0x7DBE6E)
        /// Daylight through the window: trees outside and beams of light. At night, the town's lights.
        var isDay = true
    }

    static let strawberry = Look(
        name: "いちごミルク",
        hair: RGBA(hex: 0xF4A9BC), hairShade: RGBA(hex: 0xC4708C), hairLight: RGBA(hex: 0xFFE6EE),
        iris: RGBA(hex: 0xE0577E), irisDeep: RGBA(hex: 0x7E2346),
        cloth: RGBA(hex: 0xFFF8F2), clothShade: RGBA(hex: 0xE7C9C6), ribbon: RGBA(hex: 0xE0577E),
        cream: RGBA(hex: 0xFFC6D3), creamShade: RGBA(hex: 0xE88EA6), creamLight: RGBA(hex: 0xFFF5F8), bits: RGBA(hex: 0xC93A5E),
        skyTop: RGBA(hex: 0xFFE4BE), skyLow: RGBA(hex: 0xFFC9C0), light: RGBA(hex: 0xFFE2A6), spark: RGBA(hex: 0xFFF4D6),
        ink: RGBA(hex: 0x5A2F3C), clip: .strawberry, clipColor: RGBA(hex: 0xE5404F),
        room: Room()
    )

    static let mint = Look(
        name: "ミントの夏",
        hair: RGBA(hex: 0x7ED3C8), hairShade: RGBA(hex: 0x3F9A98), hairLight: RGBA(hex: 0xE4FFF8),
        iris: RGBA(hex: 0x2E9FBF), irisDeep: RGBA(hex: 0x16466B),
        cloth: RGBA(hex: 0xFFFFFF), clothShade: RGBA(hex: 0xBFD7E6), ribbon: RGBA(hex: 0x3B7BD6),
        cream: RGBA(hex: 0xA2E8CC), creamShade: RGBA(hex: 0x62BC9E), creamLight: RGBA(hex: 0xEAFFF6), bits: RGBA(hex: 0x4A2E26),
        skyTop: RGBA(hex: 0x5DB8F5), skyLow: RGBA(hex: 0xE6F7FF), light: RGBA(hex: 0xFFFBE0), spark: RGBA(hex: 0xFFFFFF),
        ink: RGBA(hex: 0x24414F), clip: .star, clipColor: RGBA(hex: 0xFFD44D),
        room: Room(
            wall: RGBA(hex: 0xF6FBF7), wallShade: RGBA(hex: 0xC9DDD6), wood: RGBA(hex: 0xD9A46A),
            booth: RGBA(hex: 0xE9874A), boothShade: RGBA(hex: 0xB0552C), table: RGBA(hex: 0xFFFFFF),
            soda: RGBA(hex: 0x8FD7F7), lampShade: RGBA(hex: 0xF6C445), poster: RGBA(hex: 0xFFF3C8), leaf: RGBA(hex: 0x5FB45E)
        ),
        deep: RGBA(hex: 0x3F6F98, a: 0.5)
    )

    static let vanillaNight = Look(
        name: "夜のバニラ",
        hair: RGBA(hex: 0x3A4170), hairShade: RGBA(hex: 0x1E2244), hairLight: RGBA(hex: 0x9AA8F0),
        iris: RGBA(hex: 0xF2B84B), irisDeep: RGBA(hex: 0x8A4A12),
        cloth: RGBA(hex: 0xF3EEF8), clothShade: RGBA(hex: 0x9C93C2), ribbon: RGBA(hex: 0xD9434F),
        cream: RGBA(hex: 0xFFF2D2), creamShade: RGBA(hex: 0xD9B47C), creamLight: RGBA(hex: 0xFFFDF4), bits: RGBA(hex: 0x3B2A20),
        skyTop: RGBA(hex: 0x14163A), skyLow: RGBA(hex: 0x4A3C7E), light: RGBA(hex: 0xFFC879), spark: RGBA(hex: 0xFFE7B0),
        ink: RGBA(hex: 0x231C34), bokeh: true, clip: .moon, clipColor: RGBA(hex: 0xFFE08A),
        room: Room(
            wall: RGBA(hex: 0xC9AFA0), wallShade: RGBA(hex: 0x6E5670), wood: RGBA(hex: 0x8A5A3E),
            booth: RGBA(hex: 0x9E3048), boothShade: RGBA(hex: 0x5A1A30), table: RGBA(hex: 0xEDE3EA),
            soda: RGBA(hex: 0x7CD46A), lampShade: RGBA(hex: 0xF2B85A), poster: RGBA(hex: 0xF0D9B8), leaf: RGBA(hex: 0x4E8E5A),
            isDay: false
        ),
        deep: RGBA(hex: 0x2A2050, a: 0.65)
    )

    static let skin = RGBA(hex: 0xFFE6DA)
    static let skinShade = RGBA(hex: 0xF0B4A8)
    /// A lighter shade for the face, so its shadows stay soft in colour though crisp in shape.
    static let faceShade = RGBA(hex: 0xF4D2CC)
    static let blush = RGBA(hex: 0xFF8E9A)
    static let mouth = RGBA(hex: 0xB8405A)
    static let tongue = RGBA(hex: 0xF08A98)
    static let eyeWhite = RGBA(hex: 0xFFFBF8)
    static let metal = RGBA(hex: 0xE4E8F0)
    static let metalShade = RGBA(hex: 0xA6AEC2)
    static let sketchBlue = RGBA(hex: 0x6FA8DC)
    static let vanilla = RGBA(hex: 0xFFF8EC)
    static let cherry = RGBA(hex: 0xE23A4A)

    /// `a` moved toward `b` by `t`.
    static func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        RGBA(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: a.a + (b.a - a.a) * t)
    }

    /// The head is written around (0, 0) and placed here, leaning in.
    static let head = CGAffineTransform(translationX: 520, y: 470).rotated(by: -12 * .pi / 180).scaledBy(x: 1.45, y: 1.45)

    struct Result {
        let document: CanvasDocument
        /// The rough alone, before the clean lines and colour.
        let rough: CGImage?
        let problems: [String]
    }

    static func draw(_ look: Look) -> Result {
        currentClip = look.clip
        let document = CanvasDocument(width: width, height: height)
        let a = Artist(document: document)
        let paper = document.activeLayerID
        document.renameLayer(paper, to: "背景")

        // The rough: the whole composition in loose blue lines.
        let sketchLayer = a.layer("ラフ", opacity: 0.8)
        roughSketch(a)
        let rough = document.compositeImage()
        document.setLayerVisible(sketchLayer, false)

        a.use(paper)
        background(a, look)

        // Back to front. Each part fills with only its own lines showing, so
        // the lines of nearer and farther parts do not cut its regions.
        let pen = Pens(ink: look.ink)
        /// A part on layers of its own. With `sharing`, it is coloured inside another
        /// part's lines, which then move up to stay on top of it.
        @discardableResult
        func part(_ name: String, sharing: UUID? = nil, lines: (Artist) -> Void, fills: (Artist) -> Void, shading: (Artist) -> Void, details: (Artist) -> Void = { _ in }) -> UUID {
            let base = a.layer(name)
            let shadeLayer = a.layer("\(name)の影", style: LayerStyle(blend: .multiply, isClipped: true))
            let lightLayer = a.layer("\(name)の光", style: LayerStyle(blend: .screen, isClipped: true))
            let lineLayer = sharing ?? a.layer("\(name)の線")
            lines(a)
            // Only this part's lines and its own colours show while filling.
            let shown = document.layers.filter(\.isVisible).map(\.id)
            for layer in document.layers where layer.id != lineLayer && layer.id != base {
                document.setLayerVisible(layer.id, false)
            }
            a.use(base)
            fills(a)
            for id in shown { document.setLayerVisible(id, true) }
            // What sits on top of the colour without cutting it, such as leaves.
            a.use(lineLayer)
            details(a)
            a.use(shadeLayer)
            shading(a)
            a.use(lightLayer)
            partLight(name, a, look)
            if sharing != nil {
                while let index = document.index(ofLayer: lineLayer), index < document.layers.count - 1 {
                    document.moveLayer(lineLayer, by: 1)
                }
            }
            return lineLayer
        }

        // The restaurant is drawn in softer lines, so it stays behind her.
        let far = Pens(ink: mix(look.ink, look.room.wallShade, 0.45))
        part("店", lines: { roomLines($0, far) }, fills: { roomFills($0, look) }, shading: { roomShade($0, look) }, details: { roomDetails($0, look) })
        part("体", lines: { bodyLines($0, pen) }, fills: { bodyFills($0, look) }, shading: { bodyShade($0, look) })
        // The face and the hair share the head's lines, each with shadows and light of its own.
        let headLineLayer = part("顔", lines: { headLines($0, pen) }, fills: { faceFills($0, look) }, shading: { faceShading($0, look) })
        part("髪", sharing: headLineLayer, lines: { _ in }, fills: { hairFills($0, look) }, shading: { hairShading($0, look) })
        part("テーブル", lines: { $0.line(tableEdge, pen.inner) }, fills: { $0.fill("テーブル", 60, 1310, look.room.table, limit: 200_000) }, shading: { tableShade($0, look) })
        part("ソーダ", lines: { sodaLines($0, pen) }, fills: { sodaFills($0, look) }, shading: { sodaShade($0, look) }, details: { sodaDetails($0, look) })
        part("袖", lines: { sleeveLines($0, pen) }, fills: { sleeveFills($0, look) }, shading: { sleeveShade($0, look) })
        part("スプーン", lines: { spoonLines($0, pen) }, fills: { spoonFills($0) }, shading: { spoonShade($0) })
        part("手", lines: { handLines($0, pen) }, fills: { handFills($0, look) }, shading: { handShade($0, look) })
        part("アイス", lines: { scoopLines($0, pen) }, fills: { scoopFills($0, look) }, shading: { scoopShade($0, look) })

        // Light over everything: shine, the light from behind, sparkles.
        a.layer("まわりの影", style: LayerStyle(blend: .multiply))
        vignette(a, look)
        a.layer("ランプの光", style: LayerStyle(blend: .add, glow: 30))
        lampLight(a, look)
        a.layer("ハイライト")
        highlights(a, look)
        a.layer("ふち光", style: LayerStyle(blend: .add, glow: 16))
        rimLight(a, look)
        a.layer("きらめき", style: LayerStyle(blend: .add, glow: 26))
        sparkles(a, look)
        a.layer("逆光", style: LayerStyle(blend: .add))
        backlight(a, look)
        if look.room.isDay {
            a.layer("窓の光", style: LayerStyle(blend: .add))
            beams(a, look)
        }
        return Result(document: document, rough: rough, problems: a.problems)
    }

    struct Pens {
        let outline: Pen
        let inner: Pen
        let fine: Pen
        let strand: Pen
        let lash: Pen

        init(ink: RGBA) {
            outline = Pen(width: 6, color: ink, start: 0.08, end: 0.08, floor: 0.4)
            inner = Pen(width: 4, color: ink, start: 0.15, end: 0.15, floor: 0.3)
            fine = Pen(width: 2.6, color: ink, start: 0.2, end: 0.3, floor: 0.15)
            strand = Pen(width: 4.5, color: ink, start: 0.1, end: 0.6, floor: 0.08)
            lash = Pen(width: 13, color: ink, start: 0.3, end: 0.1, floor: 0.3)
        }
    }

    // MARK: Shapes

    // The head, written around the face's centre; the right side is the left mirrored.
    /// The fringe's tips and the hollows between them, from the left temple
    /// to the right: long locks at the sides, short tips over the eyes, and
    /// one thin lock falling between them.
    static let fringe: [(x: CGFloat, y: CGFloat)] = [
        (-212, -10), (-178, 62), (-158, -40), (-128, -2), (-104, -62), (-70, -8), (-46, -70),
        (-10, 38), (6, -62), (40, -6), (70, -66), (106, -4), (130, -44), (178, 62), (212, -10),
    ]

    /// The fringe's lower edge, each tip a curved, tapering lock, moved down by `drop`.
    static func fringeEdge(drop: CGFloat = 0, shift: CGFloat = 0) -> String {
        var path = "M \(fringe[0].x + shift) \(fringe[0].y + drop)"
        for (from, to) in zip(fringe, fringe.dropFirst()) {
            let down = to.y > from.y
            // A lock swells from its hollow and narrows to its tip; back up, it hugs the next lock.
            let first = down ? (from.x + (to.x - from.x) * 0.1, from.y + (to.y - from.y) * 0.6) : (from.x + (to.x - from.x) * 0.25, from.y - 12)
            let second = down ? (to.x - (to.x - from.x) * 0.35, to.y - (to.y - from.y) * 0.25) : (to.x - (to.x - from.x) * 0.15, to.y + (from.y - to.y) * 0.55)
            path += " C \(first.0 + shift) \(first.1 + drop), \(second.0 + shift) \(second.1 + drop), \(to.x + shift) \(to.y + drop)"
        }
        return path
    }

    /// The fringe and the crown, full and rounded above the head.
    static let bangs = fringeEdge() + " C 250 -60, 266 -140, 258 -200 C 248 -270, 180 -330, 90 -342 C 40 -348, -40 -348, -90 -340 C -186 -322, -254 -262, -262 -190 C -266 -120, -250 -50, -212 -10"
    /// The lock in front of the ear, flicking outward at its end.
    static let lockOuter = "M -212 -10 C -252 80, -256 190, -232 290 C -218 350, -232 396, -270 424"
    static let lockInner = "M -270 424 C -232 418, -204 396, -190 362 C -170 312, -154 240, -148 175 C -150 130, -160 92, -178 62"
    /// The hair behind, from the crown's widest point, falling wide and ending in two tips.
    static let backHair = "M -263 -148 C -312 -50, -338 40, -336 130 C -350 150, -364 168, -382 176 C -356 196, -344 240, -342 300 C -340 360, -350 410, -384 452 C -350 450, -330 440, -318 424 C -320 470, -326 500, -356 530 C -318 520, -298 498, -290 470 C -286 504, -274 530, -252 546 C -262 506, -262 462, -270 424"
    static let jaw = "M -148 175 C -110 215, -50 232, 0 234"
    static let neck = "M -63 224 C -60 250, -62 278, -66 300"
    // The body, written with the head.
    static let neckline = "M -66 300 C -40 332, 40 332, 66 300"
    static let shoulder = "M -66 300 C -120 310, -230 330, -290 380 C -340 420, -360 520, -365 640"
    static let upperLash = "M -142 42 C -124 4, -50 -4, -20 32"
    static let iris = (center: CGPoint(x: -80, y: 64), rx: CGFloat(36), ry: CGFloat(50))

    // The hand and the spoon, near the viewer, in canvas pixels.
    // The spoon faces the viewer; its handle runs up and back to her hand.
    static let sleeve = "M 880 820 C 930 790, 1020 790, 1080 810 L 1080 1040 C 1030 1050, 960 1035, 905 1000 C 925 950, 915 870, 880 820"
    /// The back of the hand, then the four curled fingers one bump each, then the wrist.
    static let fist = "M 902 880 C 880 840, 820 815, 760 822 C 718 826, 692 855, 694 890 C 670 905, 668 945, 695 962 C 676 980, 684 1012, 715 1020 C 712 1040, 735 1058, 765 1052 C 820 1048, 880 1010, 905 960 C 915 935, 912 905, 902 880"
    /// The thumb lies over the handle, its tip pressing down.
    static let thumb = "M 856 832 C 818 850, 780 875, 760 905 C 752 920, 760 934, 777 927 C 796 919, 810 902, 824 890"
    static let fingerGaps = ["M 694 890 Q 718 895, 742 897", "M 695 962 Q 746 966, 796 950", "M 715 1020 Q 760 1018, 802 1000"]

    // The spoon lies along a line from its bowl, near the viewer, up to her fist:
    // `u` runs along it toward the hand, `v` across it, down and to the right.
    static let bowlCenter = CGPoint(x: 380, y: 1150)
    static let along = CGPoint(x: 0.863, y: -0.505)
    static let across = CGPoint(x: 0.505, y: 0.863)
    /// Half the bowl's length and width.
    static let bowlLength: CGFloat = 150
    static let bowlWidth: CGFloat = 104
    /// Where the handle ends, hidden in her fist.
    static let handleEnd: CGFloat = 470

    static func onSpoon(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: bowlCenter.x + along.x * u + across.x * v, y: bowlCenter.y + along.y * u + across.y * v)
    }

    /// A point round the bowl, `t` 0 at the neck: an egg, wide at the tip.
    /// `inset` moves it inward, `scale` shrinks the egg, `shift` moves it along.
    static func bowlPoint(_ t: CGFloat, inset: CGFloat = 0, scale: CGFloat = 1, shift: CGFloat = 0) -> CGPoint {
        onSpoon(shift + (bowlLength * scale - inset) * cos(t), (bowlWidth * scale - inset) * sin(t) * (1 - 0.25 * cos(t)))
    }

    /// Half the handle's width: thin at the neck, wider toward the hand.
    static func handleWidth(_ u: CGFloat) -> CGFloat {
        let neck = bowlLength + 60
        if u <= neck { return 12 - 3 * (u - bowlLength) / 60 }
        let t = min(max((u - neck) / (handleEnd - neck), 0), 1)
        return 9 + 17 * t * t * (3 - 2 * t)
    }

    /// The whole spoon in one line: round the bowl, out along the handle, round its end and back.
    static let spoonOutline: [CGPoint] = {
        let neck: CGFloat = 0.17
        var points = (0...200).map { bowlPoint(neck + (2 * .pi - 2 * neck) * CGFloat($0) / 200) }
        points += stride(from: bowlLength, through: handleEnd, by: 4).map { onSpoon($0, -handleWidth($0)) }
        let r = handleWidth(handleEnd)
        points += (0...16).map { i -> CGPoint in
            let angle = -CGFloat.pi / 2 + .pi * CGFloat(i) / 16
            return onSpoon(handleEnd + r * cos(angle), r * sin(angle))
        }
        points += stride(from: handleEnd, through: bowlLength, by: -4).map { onSpoon($0, handleWidth($0)) }
        points.append(points[0])
        return PathData.resampled(points, spacing: 2.5)
    }()

    /// The lip of the bowl, its thickness showing round the tip.
    static let bowlLip = PathData.resampled((0...80).map { bowlPoint(2.1 + 2.1 * CGFloat($0) / 80, inset: 15) }, spacing: 2.5)

    /// One scoop sitting in the bowl: a ball in soft lumps, its bottom flattened
    /// into the wavy rim a scoop leaves. `dome` runs over the top from right to left.
    static let scoop: (outline: [CGPoint], left: CGPoint, right: CGPoint, top: CGPoint, dome: [CGPoint]) = {
        let center = CGPoint(x: 352, y: 1124), radius: CGFloat = 112
        let floor = center.y + radius * 0.6
        let outline = (0...360).map { i -> CGPoint in
            let angle = CGFloat(i) / 360 * 2 * .pi
            let r = radius * (1 + 0.025 * sin(angle * 6))
            let point = CGPoint(x: center.x + r * cos(angle), y: center.y - r * sin(angle))
            return CGPoint(x: point.x, y: min(point.y, floor + 7 * sin(point.x / 12)))
        }
        let dome = Array(outline[0...180])
        return (PathData.resampled(outline, spacing: 2.5), outline[180], outline[0], outline[90], dome)
    }()

    static func onHead(_ a: Artist, mirrored: Bool = false, _ body: () -> Void) {
        let saved = (a.transform, a.mirrored)
        a.transform = head
        a.mirrored = mirrored
        body()
        (a.transform, a.mirrored) = saved
    }

    static func bothSides(_ a: Artist, _ body: () -> Void) {
        onHead(a, body)
        onHead(a, mirrored: true, body)
    }

    // MARK: Rough

    static func roughSketch(_ a: Artist) {
        let loose = Pen(width: 3, color: sketchBlue, start: 0.2, end: 0.3, floor: 0.3, opacity: 0.9)
        // Guides: the head's circle and the line of the eyes, then the shapes.
        onHead(a) {
            a.line(PathData.arc(center: CGPoint(x: 0, y: -20), rx: 215, ry: 250, from: 0, to: 360), loose.with(width: 2, opacity: 0.5), wobble: 3)
            a.line("M -230 64 L 230 64", loose.with(width: 2, opacity: 0.5), wobble: 2)
            a.line("M 0 -300 L 0 260", loose.with(width: 2, opacity: 0.5), wobble: 2)
        }
        bothSides(a) {
            for path in [lockOuter, lockInner, backHair, jaw, neck, upperLash] { a.line(path, loose, wobble: 4) }
            a.line(PathData.arc(center: iris.center, rx: iris.rx, ry: iris.ry, from: 0, to: 360), loose, wobble: 2)
        }
        onHead(a) {
            a.line(bangs, loose, wobble: 3)
            a.line("M -34 150 Q 0 143, 34 150 Q 20 182, 0 184 Q -20 182, -34 150", loose, wobble: 2)
        }
        bothSides(a) { a.line(shoulder, loose, wobble: 4) }
        onHead(a) { a.line(neckline, loose, wobble: 2) }
        for path in [sleeve, fist, thumb] + fingerGaps { a.line(path, loose, wobble: 3) }
        a.line(spoonOutline, loose, wobble: 4)
        a.line(scoop.outline, loose, wobble: 3)
        // Where she sits: the window, the booth, the table and a float on it.
        let room = loose.with(width: 2.4, opacity: 0.6)
        for path in ["M 640 0 L 640 600", "M 858 0 L 858 600", capTop, capBottom, tableEdge, glass, floatScoop] { a.line(path, room, wobble: 3) }
        a.line("M \(lamp.x - 64) \(lamp.y) C \(lamp.x - 58) 140, \(lamp.x + 58) 140, \(lamp.x + 64) \(lamp.y)", room, wobble: 2)
        // The direction of the light: from the window behind her, upper right.
        let note = Pen(width: 4, color: RGBA(hex: 0xF2A23A), start: 0, end: 0.2, floor: 0.6)
        a.line("M 1000 120 L 820 260", note)
        a.line("M 820 260 L 852 258", note)
        a.line("M 820 260 L 832 232", note)
    }

    // MARK: The restaurant

    // The wall with its window, and the top of the booth's back behind her, in canvas pixels.
    static let capTop = "M -20 606 C 300 590, 780 590, 1100 606"
    static let capBottom = "M -20 640 C 300 626, 780 626, 1100 640"
    static let tableEdge = "M -20 1238 C 300 1226, 780 1226, 1100 1238"
    static let lamp = CGPoint(x: 120, y: 196)

    static func roomLines(_ a: Artist, _ p: Pens) {
        // The window frame, with a bar down the middle, standing on the booth.
        for x in [640.0, 662, 850, 866] as [CGFloat] { a.line("M \(x) -20 L \(x) 600", p.inner.with(width: 3)) }
        a.line(capTop, p.inner)
        a.line(capBottom, p.inner)
        // The booth's back is padded in long rolls.
        a.line("M 72 640 C 66 820, 68 1050, 74 1360", p.fine.with(width: 3))
        a.line("M 1006 640 C 1012 820, 1010 1050, 1004 1360", p.fine.with(width: 3))
        // A lamp hanging over the table.
        a.line("M \(lamp.x) -20 L \(lamp.x) 120", p.fine)
        a.line("M \(lamp.x - 64) \(lamp.y) C \(lamp.x - 58) 140, \(lamp.x - 30) 120, \(lamp.x) 120 C \(lamp.x + 30) 120, \(lamp.x + 58) 140, \(lamp.x + 64) \(lamp.y) Q \(lamp.x) \(lamp.y + 14), \(lamp.x - 64) \(lamp.y)", p.inner.with(width: 3.4))
        // A poster of the ice cream of the season.
        a.line("M 16 300 L 122 300 L 122 446 L 16 446 L 16 300", p.inner.with(width: 3))
        a.line(PathData.arc(center: CGPoint(x: 69, y: 364), rx: 22, ry: 22, from: 0, to: 360), p.fine)
        a.line("M 50 378 L 69 424 L 88 378", p.fine)
        // A pot on the booth, for the plant drawn over it.
        a.line("M 40 556 L 140 556 L 128 598 L 52 598 L 40 556", p.inner.with(width: 3))
    }

    static func roomFills(_ a: Artist, _ look: Look) {
        let room = look.room
        a.fill("壁", 300, 300, room.wall, limit: 400_000)
        a.fill("窓わく", 651, 300, room.wood, limit: 20_000)
        a.fill("窓わく", 858, 300, room.wood, limit: 20_000)
        a.fill("ソファの縁", 300, 616, room.wood, limit: 60_000)
        a.fill("ソファ", 30, 900, room.booth, limit: 120_000)
        a.fill("ソファ", 500, 900, room.booth, limit: 900_000)
        a.fill("ソファ", 1045, 900, room.booth, limit: 120_000)
        a.fill("かさ", lamp.x, 160, room.lampShade, limit: 20_000)
        a.fill("ポスター", 26, 310, room.poster, limit: 20_000)
        a.fill("ポスターのアイス", 69, 360, look.cream, limit: 3000)
        a.fill("ポスターのコーン", 69, 396, RGBA(hex: 0xE8B26A), limit: 3000)
        a.fill("鉢", 90, 576, RGBA(hex: 0xF4F1EC), limit: 6000)
    }

    static func roomShade(_ a: Artist, _ look: Look) {
        let room = look.room
        // Away from the window the wall darkens, and the booth's rolls round off.
        a.line("M -40 -20 L -40 620", Pen.airbrush(260, room.wallShade, opacity: 0.7))
        a.line("M 680 -20 L 680 590", Pen.airbrush(40, room.wallShade, opacity: 0.5))
        a.line("M -20 662 C 300 648, 780 648, 1100 662", Pen.airbrush(50, room.boothShade, opacity: 0.8))
        for x in [72.0, 1006] as [CGFloat] { a.line("M \(x) 650 L \(x) 1360", Pen.airbrush(34, room.boothShade, opacity: 0.6)) }
        // Her shadow on the booth, cast away from the window: all behind her, and down her left.
        a.line("M 560 640 L 560 1360", Pen(width: 520, color: room.boothShade, start: 0.02, end: 0.02, floor: 1, opacity: 0.55))
        a.line("M 150 680 C 140 900, 150 1100, 170 1360", Pen.airbrush(150, room.boothShade, opacity: 0.75))
        a.line("M -20 1360 L 1100 1360", Pen.airbrush(160, room.boothShade, opacity: 0.6))
        a.line("M 70 590 Q 90 600, 120 590", Pen.airbrush(30, room.wallShade, opacity: 0.8))
    }

    static func roomDetails(_ a: Artist, _ look: Look) {
        let room = look.room
        // The plant: each leaf one tapering stroke, with a darker middle.
        let leaf = Pen(width: 26, color: room.leaf, start: 0.35, end: 0.6, floor: 0.05)
        let vein = Pen(width: 2.4, color: mix(room.leaf, look.ink, 0.35), start: 0.2, end: 0.6, floor: 0.1)
        for path in ["M 84 556 C 70 520, 44 498, 22 492", "M 88 556 C 82 510, 74 480, 58 456", "M 94 556 C 98 506, 108 476, 126 452", "M 98 556 C 116 524, 140 506, 160 500", "M 90 556 C 90 524, 92 500, 94 470"] {
            a.line(path, leaf)
            a.line(path, vein)
        }
    }

    static func tableShade(_ a: Artist, _ look: Look) {
        let room = look.room
        // Her shadow where she leans over the table, and the glass's.
        a.line("M 120 1248 C 400 1240, 700 1240, 1000 1248", Pen.airbrush(60, room.wallShade, opacity: 0.8))
        a.line("M 20 1306 L 120 1306", Pen.airbrush(26, room.wallShade, opacity: 0.8))
    }

    // A float on the table: a scoop of vanilla on a glass of soda, a cherry on top.
    static let glass = "M 24 1000 C 30 1100, 40 1220, 48 1296 C 70 1312, 118 1312, 140 1296 C 148 1220, 158 1100, 166 1000"
    static let floatScoop = "M 24 1000 C 18 958, 54 928, 92 930 C 132 926, 170 954, 166 1000 C 130 1016, 60 1016, 24 1000"
    static let glassBottom = "M 46 1272 C 74 1286, 114 1286, 142 1272"

    static func sodaLines(_ a: Artist, _ p: Pens) {
        a.line(glass, p.inner)
        a.line(floatScoop, p.inner)
        a.line(glassBottom, p.fine)
    }

    static func sodaFills(_ a: Artist, _ look: Look) {
        a.fill("ソーダ", 95, 1150, look.room.soda, limit: 60_000)
        a.fill("グラスの底", 95, 1292, mix(look.room.soda, RGBA(hex: 0xFFFFFF), 0.6), limit: 6000)
        a.fill("バニラ", 95, 970, vanilla, limit: 12_000)
    }

    static func sodaShade(_ a: Artist, _ look: Look) {
        a.line("M 150 1020 L 140 1280", Pen.airbrush(40, mix(look.room.soda, look.ink, 0.4), opacity: 0.6))
        a.line("M 30 1004 C 70 1020, 120 1020, 160 1004", Pen.airbrush(26, look.creamShade, opacity: 0.6))
    }

    static func sodaDetails(_ a: Artist, _ look: Look) {
        // A straw in the soda, and the cherry, drawn over the colour.
        a.line("M 128 1240 L 150 870", Pen(width: 13, color: look.ink, start: 0, end: 0, floor: 1))
        a.line("M 128 1240 L 150 870", Pen(width: 8, color: RGBA(hex: 0xF25A6A), start: 0, end: 0, floor: 1))
        a.line("M 70 908 Q 76 884, 92 872", Pen(width: 3, color: look.ink, start: 0.1, end: 0.3, floor: 0.4))
        a.dot(66, 922, diameter: 34, color: look.ink)
        a.dot(66, 922, diameter: 28, color: cherry)
        a.dot(60, 915, diameter: 8, color: RGBA(hex: 0xFFFFFF))
    }

    // MARK: Body

    static func bodyLines(_ a: Artist, _ p: Pens) {
        bothSides(a) {
            a.line(shoulder, p.outline)
            // A bow at the neckline.
            a.line("M 0 352 C -20 332, -42 340, -38 356 C -34 371, -15 367, 0 352", p.inner.with(width: 3.4))
            a.line("M -4 356 Q -12 382, -24 398", p.inner.with(width: 3))
            a.line("M -200 420 Q -215 500, -205 600", p.fine)
        }
        onHead(a) { a.line(neckline, p.inner) }
    }

    static func bodyFills(_ a: Artist, _ look: Look) {
        onHead(a) { a.fill("服", 0, 460, look.cloth, limit: 1_200_000) }
        bothSides(a) { a.fill("リボン", -22, 354, look.ribbon, limit: 6000) }
    }

    static func bodyShade(_ a: Artist, _ look: Look) {
        let shade = Pen.airbrush(110, look.clothShade, opacity: 0.8)
        onHead(a) {
            // Under the chin and the hair, and down the sides.
            a.line("M -90 330 Q 0 380, 90 330", shade)
            a.line("M -120 318 Q 0 400, 120 318", Pen(width: 44, color: look.clothShade, start: 0.05, end: 0.05, floor: 1))
            a.line("M -300 400 Q -330 500, -330 640", shade.with(width: 140))
            a.line("M 300 400 Q 330 500, 330 640", shade.with(width: 140))
        }
        // The spoon's handle and the fist cast their shadows down and away from the window.
        let cast = CGPoint(x: -26, y: 58)
        a.line(PathData.resampled(stride(from: bowlLength + 30, through: 420, by: 4).map { u -> CGPoint in
            let point = onSpoon(u, 0)
            return CGPoint(x: point.x + cast.x, y: point.y + cast.y)
        }, spacing: 2.5), Pen(width: 30, color: look.clothShade, start: 0.3, end: 0, floor: 0.4))
        a.line("M 700 1080 C 760 1100, 860 1080, 920 1030", Pen(width: 54, color: look.clothShade, start: 0.3, end: 0.3, floor: 0.2))
    }

    // MARK: Head

    static func headLines(_ a: Artist, _ p: Pens) {
        onHead(a) {
            a.line(bangs, p.outline)
            // Strands in the fringe, from the crown toward the tips, and a lock standing up.
            // The fringe's locks, bowing out over the round of the head from the crown.
            for strand in [
                "M -20 -330 C -96 -296, -134 -200, -140 -96", "M 6 -326 C -56 -280, -84 -192, -92 -112",
                "M 30 -322 C 2 -262, -20 -192, -30 -124", "M 56 -320 C 70 -262, 76 -190, 70 -120",
                "M 92 -324 C 172 -302, 212 -204, 202 -96",
                "M -150 -300 C -214 -254, -238 -160, -232 -86", "M 150 -306 C 214 -256, 238 -170, 230 -96",
            ] {
                a.line(strand, p.strand.with(width: 3.2, start: 0.05, end: 0.7))
            }
        }
        bothSides(a) {
            a.line(lockOuter, p.strand.with(width: 5.5, end: 0.1))
            a.line(lockInner, p.strand.with(width: 5, start: 0.1, end: 0.05))
            a.line(backHair, p.outline.with(end: 0.2))
            a.line(jaw, p.outline)
            a.line(neck, p.inner)
            a.line("M -226 60 Q -236 200, -214 320", p.strand.with(width: 3))
            a.line("M -300 210 Q -322 330, -310 420", p.strand.with(width: 3))
            a.line("M -318 330 Q -320 420, -332 490", p.strand.with(width: 2.6))
            eye(a, p)
        }
        onHead(a) {
            // Mouth open, saying "aah".
            a.line("M -34 150 Q 0 143, 34 150", p.inner.with(width: 3.6))
            a.line("M -34 150 Q -20 182, 0 184 Q 20 182, 34 150", p.inner.with(width: 3.2))
            a.line("M -16 178 Q 0 168, 16 178", p.fine)
            a.line("M 4 118 Q 9 126, 1 130", p.fine.with(width: 3))
        }
        onHead(a) {
            // The neck meets the clothes.
            a.line(neckline, p.inner)
            clipLines(a, p)
        }
    }

    static func eye(_ a: Artist, _ p: Pens) {
        a.line(upperLash, p.lash)
        a.line("M -138 36 Q -152 30, -164 14", p.lash.with(width: 7, start: 0.1, end: 0.7))
        a.line("M -142 42 C -144 72, -138 94, -130 110", p.fine.with(floor: 0.6))
        a.line("M -130 110 Q -82 126, -36 104", p.inner.with(width: 3))
        a.line("M -20 32 C -18 62, -26 88, -36 104", p.fine.with(floor: 0.6))
        a.line(Portrait.irisArc(lash: upperLash, center: iris.center, rx: iris.rx, ry: iris.ry), p.fine.with(width: 2.8, floor: 0.7))
        let flick = Pen(width: 3.4, color: p.fine.color, start: 0.1, end: 0.7, floor: 0.05)
        a.line("M -140 50 Q -156 56, -164 50", flick)
        a.line("M -118 116 Q -124 124, -132 126", flick.with(width: 2.4))
    }

    static func faceFills(_ a: Artist, _ look: Look) {
        bothSides(a) {
            a.fill("白目", -130, 72, eyeWhite, limit: 20_000)
            a.fill("白目", -31, 66, eyeWhite, limit: 20_000)
            a.fill("瞳", -80, 74, look.iris, limit: 20_000)
        }
        onHead(a) {
            a.fill("髪どめ", clipCenter.x + (look.clip == .moon ? -22 : 0), clipCenter.y, look.clipColor, limit: 30_000)
            a.fill("顔", 0, 90, skin, limit: 400_000)
            a.fill("首", 0, 280, skin, limit: 100_000)
            a.fill("口", 0, 158, mouth, limit: 6000)
            a.fill("舌", 0, 180, tongue, limit: 3000)
        }
    }

    static func hairFills(_ a: Artist, _ look: Look) {
        bothSides(a) {
            a.fill("後ろ髪", -296, 250, look.hair, limit: 400_000)
            a.fill("横の髪", -195, 250, look.hair, limit: 200_000)
        }
        onHead(a) { a.fill("前髪", -60, -200, look.hair, limit: 600_000) }
    }

    static func faceShading(_ a: Artist, _ look: Look) {
        onHead(a) {
            // The fringe's shadow, the same shape, cast down and away from the window.
            a.line(fringeEdge(drop: 16, shift: -10), Pen(width: 24, color: faceShade, start: 0.02, end: 0.02, floor: 1))
            // The whole neck in the chin's shadow, with a crisp edge.
            a.line("M -72 282 Q 0 306, 72 282", Pen(width: 110, color: skinShade, start: 0.02, end: 0.02, floor: 1))
            // The irises darken toward the top.
            a.line("M -112 30 Q -80 14, -48 30", Pen.airbrush(40, look.irisDeep, opacity: 0.9))
            a.line("M 112 30 Q 80 14, 48 30", Pen.airbrush(40, look.irisDeep, opacity: 0.9))
        }
    }

    /// The fringe's hollows, between its tips.
    static var fringeHollows: [CGPoint] {
        stride(from: 2, to: fringe.count - 1, by: 2).map { CGPoint(x: fringe[$0].x, y: fringe[$0].y) }
    }

    static func hairShading(_ a: Artist, _ look: Look) {
        let hairDark = mix(look.hairShade, RGBA(hex: 0xFFFFFF), 0.3)
        onHead(a) {
            // Darker toward the ends, so the crown stands out round.
            var clear = hairDark
            clear.a = 0
            a.gradient(.linear, from: CGPoint(x: 0, y: -170), to: CGPoint(x: 0, y: 440), clear, hairDark)
            // The crown's far side, away from the window.
            a.line("M -150 -400 C -290 -330, -330 -200, -306 -40", Pen(width: 120, color: hairDark, start: 0.05, end: 0.3, floor: 0.2))
            // Each lock of the fringe rounds off: a pointed shadow rising from each parting between the tips.
            let whorl = CGPoint(x: 30, y: -340)
            for (index, hollow) in fringeHollows.enumerated() {
                let toward = CGPoint(x: whorl.x - hollow.x, y: whorl.y - hollow.y)
                let reach = hypot(toward.x, toward.y)
                let length: CGFloat = index % 2 == 0 ? 170 : 120
                let tip = CGPoint(x: hollow.x + toward.x / reach * length, y: hollow.y + toward.y / reach * length)
                let bend = CGPoint(x: (hollow.x + tip.x) / 2 + (hollow.x < 0 ? -14 : 14), y: (hollow.y + tip.y) / 2)
                a.line("M \(hollow.x) \(hollow.y - 2) Q \(bend.x) \(bend.y), \(tip.x) \(tip.y)", Pen(width: 26, color: hairDark, start: 0, end: 1, floor: 0.02))
            }
            // The hair behind, and the side locks along the face.
            a.line("M -300 60 C -280 200, -330 380, -380 560", Pen(width: 150, color: hairDark, start: 0.05, end: 0.05, floor: 1))
            for x in [-1.0, 1.0] as [CGFloat] {
                a.line("M \(x * 172) 90 Q \(x * 162) 240, \(x * 186) 370", Pen(width: 26, color: hairDark, start: 0.2, end: 0.3, floor: 0.1))
            }
        }
    }

    // MARK: Spoon, hand, ice cream

    static func spoonLines(_ a: Artist, _ p: Pens) {
        a.line(spoonOutline, p.outline)
        a.line(bowlLip, p.fine.with(width: 3, start: 0.3, end: 0.3, floor: 0.05))
    }

    static func spoonFills(_ a: Artist) {
        let tip = onSpoon(-120, 0), stem = onSpoon(330, 0)
        a.fill("スプーン", tip.x, tip.y, metal, limit: 320_000)
        a.fill("柄", stem.x, stem.y, metal, limit: 320_000)
    }

    static func spoonShade(_ a: Artist) {
        // Metal shows what is around it: a dark band in the hollow and down the handle's far side.
        let dark = Pen(width: 30, color: metalShade, start: 0.15, end: 0.2, floor: 0.2)
        a.line(PathData.resampled((0...60).map { bowlPoint(0.6 + 2.0 * CGFloat($0) / 60, inset: 30) }, spacing: 2.5), dark)
        a.line(PathData.resampled(stride(from: bowlLength + 10, through: handleEnd, by: 4).map { onSpoon($0, handleWidth($0)) }, spacing: 2.5), Pen(width: 18, color: metalShade, start: 0.1, end: 0, floor: 0.4))
        // The scoop's shadow in the hollow.
        a.line("M \(scoop.left.x + 20) \(scoop.left.y + 76) Q \(scoop.top.x) \(scoop.left.y + 112), \(scoop.right.x - 10) \(scoop.right.y + 66)", Pen(width: 34, color: metalShade, start: 0.3, end: 0.3, floor: 0.1))
        // The rim at the tip turns away from the window.
        a.line(PathData.resampled((0...60).map { bowlPoint(1.6 + 1.6 * CGFloat($0) / 60) }, spacing: 2.5), Pen(width: 22, color: metalShade, start: 0.3, end: 0.3, floor: 0.1, opacity: 0.8))
    }

    static func sleeveLines(_ a: Artist, _ p: Pens) {
        a.line(sleeve, p.outline)
        a.line("M 940 850 Q 980 880, 1020 870", p.fine)
        a.line("M 935 960 Q 980 990, 1030 985", p.fine)
    }

    static func sleeveFills(_ a: Artist, _ look: Look) {
        a.fill("袖", 1000, 900, look.cloth, limit: 80_000)
    }

    static func sleeveShade(_ a: Artist, _ look: Look) {
        a.line("M 905 1010 Q 990 1050, 1080 1030", Pen.airbrush(70, look.clothShade, opacity: 0.9))
    }

    static func handLines(_ a: Artist, _ p: Pens) {
        a.line(fist, p.outline)
        a.line(thumb, p.inner)
        fingerGaps.forEach { a.line($0, p.fine.with(width: 3.2, start: 0.05, end: 0.6)) }
        // The thumbnail, and the knuckles on the back of the hand.
        a.line("M 758 914 Q 766 904, 778 910", p.fine.with(width: 2.4))
        a.line("M 806 842 Q 816 850, 814 862", p.fine.with(width: 2.2))
        a.line("M 860 858 Q 870 866, 868 878", p.fine.with(width: 2.2))
    }

    static func handFills(_ a: Artist, _ look: Look) {
        a.fill("手", 840, 950, skin, limit: 80_000)
    }

    static func handShade(_ a: Artist, _ look: Look) {
        // Under each curled finger, and the palm side away from the light.
        for gap in fingerGaps { a.line(gap, Pen.airbrush(22, skinShade, opacity: 0.8)) }
        a.line("M 740 1050 Q 830 1050, 900 970", Pen.airbrush(50, skinShade, opacity: 0.9))
        a.line("M 760 930 Q 790 945, 830 905", Pen.airbrush(24, skinShade, opacity: 0.6))
    }

    static func scoopLines(_ a: Artist, _ p: Pens) {
        a.line(scoop.outline, p.outline)
    }

    static func scoopFills(_ a: Artist, _ look: Look) {
        let inside = CGPoint(x: (scoop.left.x + scoop.right.x) / 2, y: (scoop.left.y + scoop.right.y) / 2 + 10)
        a.fill("アイス", inside.x, inside.y, look.cream, limit: 200_000)
    }

    static func scoopShade(_ a: Artist, _ look: Look) {
        // A crescent of shadow: everything outside a circle moved toward the window.
        let lit = CGPoint(x: scoop.top.x + 26, y: (scoop.left.y + scoop.top.y) / 2 - 10)
        let radius = (scoop.right.x - scoop.left.x) / 2
        a.line(PathData.arc(center: lit, rx: radius + 40, ry: radius + 40, from: 0, to: 360), Pen(width: 80, color: look.creamShade, start: 0, end: 0, floor: 1))
        // Bits in the ice cream.
        var random = SplitMix(seed: 11)
        for _ in 0..<16 {
            let x = scoop.left.x + 30 + random.next() * (scoop.right.x - scoop.left.x - 60)
            let y = scoop.top.y + 30 + random.next() * (scoop.left.y + 50 - scoop.top.y)
            a.dot(x, y, diameter: 5 + random.next() * 6, color: look.bits)
        }
    }

    /// Soft light on each part, on its screen layer.
    static func partLight(_ name: String, _ a: Artist, _ look: Look) {
        switch name {
        case "髪":
            onHead(a) {
                // The hair's ring of light: a broad band round the head, with points along the hair.
                let ring = { (x: CGFloat) -> CGPoint in CGPoint(x: x, y: -236 + 0.0024 * x * x) }
                let strength = { (x: CGFloat) -> CGFloat in 0.6 + 0.35 * (x + 190) / 390 }
                a.line(stride(from: -190, through: 200, by: 2.5).map(ring), Pen(width: 26, color: look.hairLight, start: 0.3, end: 0.2, floor: 0.05, opacity: 0.85))
                for (index, x) in stride(from: -160, through: 170, by: 44).enumerated() {
                    let base = ring(CGFloat(x))
                    let away = CGPoint(x: base.x - 20, y: base.y + 340)
                    let reach = hypot(away.x, away.y)
                    let down: CGFloat = index % 2 == 0 ? 58 : 36
                    let shine = Pen(width: 22, color: look.hairLight, start: 0, end: 1, floor: 0.02, opacity: strength(CGFloat(x)))
                    a.line(PathData.resampled([base, CGPoint(x: base.x + away.x / reach * down, y: base.y + away.y / reach * down)], spacing: 2.5), shine)
                    a.line(PathData.resampled([base, CGPoint(x: base.x - away.x / reach * 24, y: base.y - away.y / reach * 24)], spacing: 2.5), shine.with(width: 16))
                }
            }
            // Strands catching the window's light down the near side.
            onHead(a, mirrored: true) {
                let strand = Pen(width: 12, color: look.hairLight, start: 0.4, end: 0.5, floor: 0.02, opacity: 0.7)
                a.line("M -232 40 Q -246 170, -228 290", strand)
                a.line("M -312 120 Q -330 260, -320 400", strand)
            }
        case "顔":
            onHead(a) {
                a.line("M -110 100 Q -90 110, -70 104", Pen.airbrush(40, RGBA(hex: 0xFFF4EC), opacity: 0.6))
            }
        case "アイス":
            // The side toward the window glows.
            a.line("M \(scoop.top.x - 10) \(scoop.top.y + 40) Q \(scoop.right.x - 40) \(scoop.top.y + 40), \(scoop.right.x - 30) \(scoop.left.y)", Pen.airbrush(60, look.creamLight, opacity: 0.8))
        case "店":
            // The window's light along the booth's edge and down the rolls, and a pool under the lamp.
            a.line("M 640 600 C 800 590, 960 592, 1100 604", Pen(width: 8, color: look.light, start: 0.3, end: 0.1, floor: 0.2, opacity: 0.8))
            a.line("M 1044 690 L 1046 1300", Pen.airbrush(24, RGBA(hex: 0xFFFFFF), opacity: 0.35))
            a.line("M 36 700 L 38 1300", Pen.airbrush(18, RGBA(hex: 0xFFFFFF), opacity: 0.2))
            a.line("M \(lamp.x - 70) 260 L \(lamp.x + 70) 260", Pen.airbrush(160, look.light, opacity: look.room.isDay ? 0.35 : 0.6))
        case "テーブル":
            a.line("M 1100 1262 C 980 1290, 900 1320, 860 1360", Pen.airbrush(60, RGBA(hex: 0xFFFFFF), opacity: 0.6))
        case "ソーダ":
            a.line("M 38 1030 C 42 1120, 50 1200, 58 1260", Pen(width: 6, color: RGBA(hex: 0xFFFFFF), start: 0.3, end: 0.3, floor: 0.1, opacity: 0.85))
            var random = SplitMix(seed: 31)
            for _ in 0..<14 {
                a.dot(60 + random.next() * 80, 1030 + random.next() * 230, diameter: 3 + random.next() * 6, color: RGBA(r: 1, g: 1, b: 1, a: 0.85))
            }
            a.line("M 40 968 Q 60 944, 92 940", Pen.airbrush(18, RGBA(hex: 0xFFFFFF), opacity: 0.8))
        case "スプーン":
            // A bright streak along the handle and round the near lip.
            let white = Pen(width: 9, color: RGBA(hex: 0xFFFFFF), start: 0.3, end: 0.3, floor: 0.05, opacity: 0.95)
            a.line(PathData.resampled(stride(from: bowlLength + 30, through: handleEnd - 40, by: 4).map { onSpoon($0, -handleWidth($0) * 0.35) }, spacing: 2.5), white)
            a.line(PathData.resampled((0...60).map { bowlPoint(1.9 + 1.2 * CGFloat($0) / 60, inset: 9) }, spacing: 2.5), white.with(width: 8))
        default:
            break
        }
    }

    // MARK: The hair clip

    static let clipCenter = CGPoint(x: 120, y: -150)

    /// The clip on the right of the fringe: a strawberry, a star or a moon.
    static func clipLines(_ a: Artist, _ p: Pens) {
        let c = clipCenter
        switch currentClip {
        case .strawberry:
            a.line("M \(c.x) \(c.y - 26) C \(c.x + 34) \(c.y - 34), \(c.x + 38) \(c.y + 4), \(c.x) \(c.y + 34) C \(c.x - 38) \(c.y + 4), \(c.x - 34) \(c.y - 34), \(c.x) \(c.y - 26)", p.inner)
            a.line("M \(c.x - 14) \(c.y - 30) Q \(c.x) \(c.y - 18), \(c.x + 14) \(c.y - 30)", p.inner.with(width: 3))
        case .star:
            let points = (0..<10).map { i -> String in
                let angle = (CGFloat(i) * 36 - 90) * .pi / 180
                let r: CGFloat = i % 2 == 0 ? 36 : 16
                return "\(c.x + r * cos(angle)) \(c.y + r * sin(angle))"
            }
            a.line("M " + points.joined(separator: " L ") + " L " + points[0], p.inner)
        case .moon:
            a.line("M \(c.x + 6) \(c.y - 34) C \(c.x - 40) \(c.y - 28), \(c.x - 40) \(c.y + 28), \(c.x + 6) \(c.y + 34) C \(c.x - 18) \(c.y + 16), \(c.x - 18) \(c.y - 16), \(c.x + 6) \(c.y - 34)", p.inner)
        }
    }

    /// The clip of the look being drawn.
    static var currentClip: Clip = .strawberry

    // MARK: Light

    static func background(_ a: Artist, _ look: Look) {
        a.gradient(.linear, from: CGPoint(x: 540, y: 0), to: CGPoint(x: 540, y: 1350), look.skyTop, look.skyLow)
        var clear = look.light
        clear.a = 0
        // By day the sun outside; by night only a faint glow over the town.
        var sun = look.light
        sun.a = look.room.isDay ? 1 : 0.3
        a.gradient(.radial, from: CGPoint(x: 980, y: 140), to: CGPoint(x: 980 + 700, y: 140), sun, clear)
        if look.room.isDay {
            // Trees across the street, pale with distance.
            var random = SplitMix(seed: 9)
            let far = mix(look.room.leaf, look.skyLow, 0.55)
            for index in 0..<30 {
                let x = 650 + random.next() * 440
                let y = 470 + random.next() * 110
                let size = 60 + random.next() * 70
                a.dot(x, y, diameter: size, color: index % 3 == 0 ? mix(far, RGBA(hex: 0xFFFFFF), 0.3) : far)
            }
        }
        if look.bokeh {
            // The town's lights through the window.
            var random = SplitMix(seed: 5)
            for _ in 0..<18 {
                let x = 660 + random.next() * 420
                let y = random.next() * 590
                let size = 40 + random.next() * 90
                a.dot(x, y, diameter: size, color: RGBA(r: look.light.r, g: look.light.g, b: look.light.b, a: 0.35))
            }
        }
    }

    static func highlights(_ a: Artist, _ look: Look) {
        bothSides(a) {
            // Catchlights in the eyes, and a shine on the lower lid.
            a.dot(-62, 38, diameter: 22, color: RGBA(hex: 0xFFFFFF))
            a.dot(-96, 90, diameter: 9, color: RGBA(hex: 0xFFFFFF))
            // Blush.
            a.line("M -120 132 Q -95 128, -70 132", Pen.airbrush(70, blush, opacity: 0.45))
            for x in stride(from: -116, through: -82, by: 12) {
                a.line("M \(x) 140 L \(x + 8) 126", Pen(width: 2.4, color: RGBA(hex: 0xE86A7A), start: 0.2, end: 0.2, floor: 0.3, opacity: 0.8))
            }
        }
        onHead(a) {
            a.dot(-8, 156, diameter: 6, color: RGBA(r: 1, g: 1, b: 1, a: 0.8))
        }
        // Shine on the ice cream and the spoon.
        let shine = CGPoint(x: scoop.top.x + 40, y: scoop.top.y + 36)
        a.dot(shine.x, shine.y, diameter: 22, color: RGBA(r: 1, g: 1, b: 1, a: 0.95))
        a.dot(shine.x + 28, shine.y + 10, diameter: 10, color: RGBA(r: 1, g: 1, b: 1, a: 0.9))
        let glint = bowlPoint(2.5, inset: 9)
        a.dot(glint.x, glint.y, diameter: 16, color: RGBA(hex: 0xFFFFFF))
    }

    static func rimLight(_ a: Artist, _ look: Look) {
        let rim = Pen(width: 10, color: look.light, start: 0.3, end: 0.4, floor: 0.05, opacity: 1)
        // Light from behind on the right: the hair's edge, the face, the hand, the ice cream's top.
        onHead(a, mirrored: true) {
            a.line("M -60 -344 C -186 -322, -254 -262, -262 -190 C -266 -120, -250 -50, -212 -10", rim)
            a.line("M -263 -148 C -312 -50, -338 40, -336 130 C -350 150, -364 168, -382 176", rim)
            a.line("M -356 196 C -344 240, -342 300, -342 300 C -340 360, -350 410, -384 452", rim)
        }
        a.line("M 760 820 C 800 812, 860 825, 900 870", rim.with(width: 9))
        a.line("M 900 812 C 950 795, 1030 795, 1080 810", rim.with(width: 9))
        a.line(Array(scoop.dome[4...60]), rim.with(width: 7, opacity: 0.8))
        a.line(PathData.resampled(stride(from: bowlLength + 20, through: handleEnd - 60, by: 4).map { onSpoon($0, -handleWidth($0)) }, spacing: 2.5), rim.with(width: 6))
    }

    static func sparkles(_ a: Artist, _ look: Look) {
        let ray = Pen(width: 4, color: look.spark, start: 0.5, end: 0.5, floor: 0.02)
        let glint = bowlPoint(2.5, inset: 9)
        for (x, y, size) in [(930.0, 260.0, 40.0), (990, 600, 26), (140, 330, 30), (glint.x, glint.y, 44), (scoop.right.x + 10, scoop.top.y + 30, 22), (110, 760, 20)] {
            a.line("M \(x - size) \(y) L \(x + size) \(y)", ray)
            a.line("M \(x) \(y - size) L \(x) \(y + size)", ray)
            a.dot(x, y, diameter: size * 0.35, color: look.spark)
        }
        var random = SplitMix(seed: 23)
        for _ in 0..<40 {
            a.dot(random.next() * 1080, random.next() * 900, diameter: 3 + random.next() * 6, color: RGBA(r: look.spark.r, g: look.spark.g, b: look.spark.b, a: 0.8))
        }
    }

    static func vignette(_ a: Artist, _ look: Look) {
        var clear = look.deep
        clear.a = 0
        a.gradient(.radial, from: CGPoint(x: 480, y: 880), to: CGPoint(x: 480 + 1000, y: 880), clear, look.deep)
        // Light gathers on the ice cream.
        var glow = look.light
        glow.a = 0
        a.layer("アイスの光", style: LayerStyle(blend: .add))
        var bright = look.light
        bright.a = 0.2
        a.gradient(.radial, from: CGPoint(x: scoop.top.x, y: scoop.top.y + 80), to: CGPoint(x: scoop.top.x + 300, y: scoop.top.y + 80), bright, glow)
    }

    static func lampLight(_ a: Artist, _ look: Look) {
        var clear = look.light
        clear.a = 0
        var warm = look.light
        warm.a = look.room.isDay ? 0.25 : 0.5
        a.dot(lamp.x, lamp.y + 2, diameter: 34, color: look.spark)
        a.gradient(.radial, from: CGPoint(x: lamp.x, y: lamp.y + 20), to: CGPoint(x: lamp.x + 320, y: lamp.y + 20), warm, clear)
    }

    /// Beams of daylight slanting in from the window.
    static func beams(_ a: Artist, _ look: Look) {
        for (start, end, width, strength) in [((1100.0, 60.0), (330.0, 1220.0), 150.0, 0.09)] {
            a.line("M \(start.0) \(start.1) L \(end.0) \(end.1)", Pen(width: width, color: look.light, start: 0.1, end: 0.5, floor: 0.3, opacity: strength, softness: 0.7))
        }
    }

    static func backlight(_ a: Artist, _ look: Look) {
        var clear = look.light
        clear.a = 0
        var soft = look.light
        soft.a = look.room.isDay ? 0.32 : 0.25
        a.gradient(.radial, from: CGPoint(x: 1000, y: 160), to: CGPoint(x: 1000 + 520, y: 160), soft, clear)
    }
}

private extension RGBA {
    init(hex: UInt32, a: Double) {
        self.init(hex: hex)
        self.a = a
    }
}
