import CoreGraphics
import Foundation
import OekakiKit

/// The head of 「一口食べる？」, written around the middle of the skull, which
/// is about 215 across: the face turned a little to the left, the line of the
/// eyes at y 60, the chin at y 246.
enum Head {
    // MARK: The face

    /// The far cheek, the chin and the near jaw; then a line round the
    /// forehead that the hair covers, so the skin is closed for filling.
    static let farCheek = "M -186 40 C -190 92, -176 138, -146 172 C -116 204, -78 222, -38 230"
    static let nearJaw = "M -38 230 C 6 226, 64 210, 110 180 C 154 150, 190 110, 204 60"
    static let hairline = "M 204 60 C 214 -30, 200 -110, 160 -150 C 80 -200, -80 -200, -160 -150 C -200 -110, -202 -30, -186 40"
    static let faceOutline = [farCheek, nearJaw]
    static var skin: String { PathData.join([farCheek, nearJaw, hairline]) }

    struct Eye {
        /// The upper lash line, from the inner corner to the outer.
        let lash: String
        /// The wing that flicks out past the outer corner.
        let wing: String
        let crease: String
        let lower: String
        /// The white, closed.
        let white: String
        let iris: (center: CGPoint, rx: CGFloat, ry: CGFloat)
        let pupil: (center: CGPoint, rx: CGFloat, ry: CGFloat)
        let brow: String
        /// How wide the lash line gets, for the nearer eye a little more.
        let weight: CGFloat
    }

    static let nearEye = Eye(
        lash: "M 20 64 C 24 28, 60 4, 100 4 C 124 4, 142 16, 152 36",
        wing: "M 140 16 C 152 18, 164 14, 176 4",
        crease: "M 38 8 C 64 -12, 108 -14, 142 0",
        lower: "M 148 50 C 143 62, 136 71, 124 79",
        white: "M 22 66 C 26 30, 60 10, 100 10 C 122 10, 138 20, 148 40 C 136 74, 112 92, 82 94 C 56 94, 34 84, 22 66",
        iris: (CGPoint(x: 88, y: 54), 46, 57),
        pupil: (CGPoint(x: 90, y: 56), 15, 22),
        brow: "M 40 -40 C 66 -54, 104 -56, 138 -44",
        weight: 1
    )

    static let farEye = Eye(
        lash: "M -70 64 C -74 28, -104 4, -140 4 C -160 6, -174 18, -184 36",
        wing: "M -172 16 C -182 14, -192 8, -204 -2",
        crease: "M -84 8 C -108 -12, -144 -14, -170 0",
        lower: "M -184 46 C -179 60, -171 70, -158 78",
        white: "M -70 66 C -74 30, -104 10, -140 10 C -160 12, -174 24, -182 42 C -172 76, -146 94, -118 94 C -94 94, -76 84, -70 66",
        iris: (CGPoint(x: -116, y: 54), 42, 55),
        pupil: (CGPoint(x: -114, y: 56), 14, 21),
        brow: "M -92 -38 C -116 -50, -146 -48, -170 -36",
        weight: 0.95
    )

    static let nose = "M -34 120 C -32 126, -34 131, -40 133"
    static let mouthTop = "M -70 166 C -56 171, -36 171, -22 167 C -15 165, -11 164, -8 163"
    static let mouthBottom = "M -68 170 C -64 192, -52 207, -38 207 C -24 207, -13 192, -10 167"
    static var mouth: String {
        mouthTop + " C -8 164, -9 166, -10 167 C -13 192, -24 207, -38 207 C -52 207, -64 192, -68 170 C -69 168, -70 167, -70 166"
    }
    static let tongue = "M -58 194 C -50 188, -34 187, -22 193"
    static let fang = "M -20 167 C -18 171, -17 174, -15 176 C -14 173, -14 170, -13 167"

    static func faceLines(_ a: Artist, _ c: Bite.Colors) {
        let outline = Pen(width: 3.2, color: c.skinLine, start: 0.1, end: 0.1, floor: 0.3)
        a.line(farCheek, outline.with(start: 0.3, end: 0.05))
        a.line(nearJaw, outline.with(start: 0.05, end: 0.3))
        // Under the hair; it closes the skin for filling.
        a.line(hairline, outline.with(width: 2))
        for eye in [nearEye, farEye] { eyeLines(a, c, eye) }
        a.line(nose, Pen(width: 2.2, color: c.skinLine, start: 0.4, end: 0.5, floor: 0.2))
        // The mouth, open: "aah".
        let lip = Pen(width: 2.6, color: c.skinLine, start: 0.25, end: 0.25, floor: 0.35)
        a.line(mouthTop, lip)
        a.line(mouthBottom, lip.with(width: 2.2))
        a.line(tongue, Pen(width: 1.6, color: c.skinLine, start: 0.3, end: 0.3, floor: 0.2))
        a.line(fang, Pen(width: 1.4, color: c.skinLine, start: 0.1, end: 0.1, floor: 0.6))
    }

    static let tongueShape = "M -58 194 C -50 188, -34 187, -22 193 C -26 201, -32 207, -38 207 C -48 207, -54 201, -58 194 Z"

    static func faceFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(skin, c.skin)
        a.shape(mouth, c.mouth)
        a.shape(tongueShape, c.tongue)
        a.shape(fang + " Z", c.eyeWhite)
    }

    static func whites(_ a: Artist, _ c: Bite.Colors) {
        for eye in [nearEye, farEye] { a.shape(eye.white, c.eyeWhite) }
    }

    /// The iris as it shows: its ellipse cut to the white.
    static func iris(_ eye: Eye) -> [CGPoint] {
        let ellipse = PathData.arc(center: eye.iris.center, rx: eye.iris.rx, ry: eye.iris.ry, from: 0, to: 360, spacing: 1.5)
        return PathData.clipped(ellipse, to: PathData.points(eye.white, spacing: 1.5))
    }

    static func irises(_ a: Artist, _ c: Bite.Colors) {
        for eye in [nearEye, farEye] {
            a.shape(iris(eye), c.iris)
            a.shape(PathData.clipped(PathData.arc(center: eye.pupil.center, rx: eye.pupil.rx, ry: eye.pupil.ry, from: 0, to: 360, spacing: 1.5), to: PathData.points(eye.white, spacing: 1.5)), c.irisDeep)
        }
    }

    static func eyeLines(_ a: Artist, _ c: Bite.Colors, _ eye: Eye) {
        // The lash line swells from the inner corner to the outer and comes to a point in the wing.
        a.ribbon(eye.lash, c.eyeLine) { t in (2 + 10 * pow(t, 0.7)) * eye.weight }
        a.ribbon(eye.wing, c.eyeLine) { t in 9 * eye.weight * (1 - t) + 0.5 }
        // A few lashes off the wing, and the fold of the lid above.
        let corner = eye.weight > 0.9 ? CGPoint(x: 150, y: 24) : CGPoint(x: -178, y: 34)
        let out: CGFloat = eye.weight > 0.9 ? 1 : -1
        for (dx, dy, length) in [(0.0, 0.0, 22.0), (-12.0, -8.0, 16.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let base = CGPoint(x: corner.x + dx * out, y: corner.y + dy)
            a.ribbon("M \(base.x) \(base.y) Q \(base.x + out * length * 0.6) \(base.y - length * 0.2), \(base.x + out * length) \(base.y - length * 0.7)", c.eyeLine, width: Ribbon.taper(4 * eye.weight))
        }
        a.line(eye.crease, Pen(width: 1.6, color: c.eyeLine, start: 0.4, end: 0.5, floor: 0.1, opacity: 0.8))
        a.ribbon(eye.lower, c.eyeLine) { t in 3.4 * eye.weight * (1 - t) + 0.3 }
        // The iris, under the lid: only the part inside the white is drawn later.
    }

    // MARK: The hair

    // A soft bob, longer in front: side locks along the cheeks, the ends
    // flicking outward to show the chocolate inside.

    /// The fringe, tip by tip and hollow by hollow, from the far side lock to the near.
    static let fringe: [CGPoint] = [
        CGPoint(x: -176, y: 52), CGPoint(x: -156, y: -22), CGPoint(x: -140, y: 22), CGPoint(x: -118, y: -38),
        CGPoint(x: -62, y: 46), CGPoint(x: -36, y: -44), CGPoint(x: -4, y: 30), CGPoint(x: 26, y: -48),
        CGPoint(x: 64, y: 0), CGPoint(x: 96, y: -44), CGPoint(x: 140, y: 22), CGPoint(x: 172, y: -20),
        CGPoint(x: 196, y: 58),
    ]


    /// The tips lean toward the middle of the face, as if combed there.
    static let middle: CGFloat = -40

    /// The fringe's lower edge: each lock swells from its hollow and comes to a curved point.
    static var fringeEdge: String {
        var path = "M \(fringe[0].x) \(fringe[0].y)"
        for (from, to) in zip(fringe, fringe.dropFirst()) {
            let down = to.y > from.y
            let dy = to.y - from.y
            let lean: CGFloat = (to.x < middle ? 1 : -1) * 6
            if down {
                // From a hollow down to a tip.
                path += " C \(from.x + (to.x - from.x) * 0.15) \(from.y + dy * 0.35), \(to.x - (to.x - from.x) * 0.1 + lean) \(to.y - dy * 0.45), \(to.x) \(to.y)"
            } else {
                // From a tip back up to a hollow, hugging the next lock.
                path += " C \(from.x + (to.x - from.x) * 0.08 + lean) \(from.y + dy * 0.4), \(to.x - (to.x - from.x) * 0.2) \(to.y - dy * 0.3), \(to.x) \(to.y)"
            }
        }
        return path
    }

    /// The near side lock down the cheek, curling in at the chin, then the bob's ends flicking out.
    static let nearSide = "M 196 58 C 204 110, 204 170, 194 214 C 188 236, 180 252, 168 268 C 190 266, 214 250, 228 226 C 236 212, 240 196, 242 180 C 248 200, 256 218, 266 236 C 270 226, 274 218, 278 212 C 290 232, 302 252, 316 272 C 322 252, 328 236, 330 222 C 330 190, 324 150, 320 112 C 314 106, 308 102, 302 92 C 308 30, 300 -30, 286 -70"
    static let crown = "M 286 -70 C 284 -130, 262 -190, 222 -232 C 214 -240, 206 -246, 196 -252 C 160 -278, 110 -292, 60 -296 C 0 -300, -60 -294, -112 -280 C -126 -276, -138 -270, -150 -262 C -200 -236, -246 -194, -268 -140 C -276 -120, -280 -100, -280 -80"
    static let farSide = "M -280 -80 C -284 -32, -290 8, -294 34 C -288 42, -283 48, -282 58 C -294 92, -300 132, -300 170 C -300 210, -302 240, -306 272 C -290 254, -276 238, -262 222 C -256 240, -248 254, -236 268 C -232 248, -224 230, -214 206 C -200 232, -180 254, -136 270 C -150 248, -162 220, -170 186 C -176 150, -180 110, -176 52"
    static var hairOutline: [String] { [fringeEdge, nearSide, crown, farSide] }
    static var front: String { PathData.join([fringeEdge, nearSide, crown, farSide]) }


    /// Where the hair parts, on the near side of the crown.
    static let whorl = CGPoint(x: 70, y: -258)

    /// Lines that start at each hollow and run up toward the crown, splitting the locks.
    static var bangLocks: [String] {
        stride(from: 1, to: fringe.count - 1, by: 2).map { index in
            let hollow = fringe[index]
            let reach: CGFloat = index % 4 == 1 ? 0.55 : 0.38
            let top = CGPoint(x: hollow.x + (whorl.x - hollow.x) * reach, y: hollow.y + (whorl.y - hollow.y) * reach)
            // The line bows outward, round the head.
            let bow = (hollow.x - whorl.x) * 0.18
            return "M \(hollow.x) \(hollow.y) C \(hollow.x + bow * 0.3) \(hollow.y - 40), \(top.x + bow) \(top.y + 40), \(top.x) \(top.y)"
        }
    }

    /// Strands along the locks, from near the crown, ending before the tips.
    static let strands = [
        "M 40 -252 C -40 -230, -110 -162, -132 -64", "M 18 -240 C -30 -194, -60 -126, -70 -44",
        "M 96 -244 C 132 -196, 150 -120, 158 -44", "M 140 -232 C 204 -196, 238 -116, 248 -20",
        "M -60 -262 C -156 -226, -218 -158, -236 -60", "M 214 50 C 222 110, 220 170, 206 226",
        "M -206 60 C -210 120, -206 180, -192 230", "M 262 40 C 270 110, 266 170, 258 230",
        "M -250 20 C -256 100, -254 170, -236 226",
    ]

    /// The hair behind the neck: only its chocolate inside shows, between the sides.
    static let back = "M -236 40 C -244 160, -250 300, -230 400 C -110 420, 100 420, 236 400 C 262 300, 258 160, 250 40 C 180 10, -170 10, -236 40 Z"

    /// The lock standing up from the crown, its root in the hair.
    static let ahogeSpine = "M 26 -290 C 16 -318, 24 -342, 48 -354 C 72 -366, 88 -380, 82 -398"
    /// The lock itself: a thin S, wide at its root and coming to a point.
    static var ahoge: [CGPoint] {
        Ribbon.outline(PathData.points(ahogeSpine, spacing: 1), width: { t in 26 * pow(1 - t, 0.7) + 0.8 })
    }

    static func hairFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(ahoge, c.hair)
        a.shape(front, c.hair)
    }

    static func backFlats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(back, c.inner.mixed(with: c.hairShade, 0.25))
    }

    static func backHairLines(_ a: Artist, _ c: Bite.Colors) {
        a.line(back, Pen(width: 2.6, color: c.hairLine, start: 0.1, end: 0.2, floor: 0.3))
        // Strands in the hair behind, so it reads as hair and not a hole.
        for path in ["M -200 120 C -206 200, -204 280, -190 360", "M -150 140 C -156 220, -150 300, -140 370", "M 170 120 C 176 200, 174 280, 160 360", "M 210 140 C 218 220, 214 300, 200 370"] {
            a.line(path, Pen(width: 1.6, color: c.hairLine, start: 0.3, end: 0.4, floor: 0.05, opacity: 0.6))
        }
    }

    static func hairLines(_ a: Artist, _ c: Bite.Colors) {
        let outline = Pen(width: 3.2, color: c.hairLine, start: 0.05, end: 0.05, floor: 0.4)
        a.line(fringeEdge, outline.with(width: 2.6))
        a.line(nearSide, outline)
        a.line(crown, outline.with(width: 3.6))
        a.line(farSide, outline)
        for path in bangLocks {
            a.ribbon(path, c.hairLine) { t in 2.6 * pow(1 - t, 1.5) + 0.2 }
        }
        for path in strands {
            a.line(path, Pen(width: 1.8, color: c.hairLine, start: 0.3, end: 0.6, floor: 0.05, opacity: 0.9))
        }
        // Fine hairs inside the locks.
        for path in [
            "M -10 -230 C -40 -170, -58 -100, -60 -30", "M 60 -236 C 80 -170, 92 -100, 96 -30", "M 110 -226 C 150 -170, 170 -100, 176 -20",
            "M -110 -236 C -150 -180, -172 -110, -178 -40", "M 230 60 C 240 130, 240 190, 230 250", "M -224 80 C -230 140, -226 200, -214 250",
        ] {
            a.line(path, Pen(width: 1.1, color: c.hairLine, start: 0.4, end: 0.6, floor: 0.05, opacity: 0.7))
        }

        // A lock that stands up from the crown, growing out of it.
        let lock = ahoge
        a.line(Array(lock.dropFirst(4).dropLast(4)), outline.with(width: 2.4, start: 0.04, end: 0.04))
    }
}

extension RGBA {
    func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: alpha)
    }

    /// This colour moved toward `other` by `t`.
    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }
}
