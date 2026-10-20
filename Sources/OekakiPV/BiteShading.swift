import CoreGraphics
import Foundation
import OekakiKit

extension RGBA {
    /// The colour that, laid over `base` to lighten it (screen), gives this colour.
    func screened(over base: RGBA) -> RGBA {
        func share(_ want: Double, _ have: Double) -> Double { max(0, min(1, have < 0.999 ? 1 - (1 - want) / (1 - have) : 0)) }
        return RGBA(r: share(r, base.r), g: share(g, base.g), b: share(b, base.b), a: a)
    }

    /// The colour that, laid over `base` to darken it (multiply), gives this colour.
    func over(_ base: RGBA) -> RGBA {
        func share(_ want: Double, _ have: Double) -> Double { min(1, have > 0.001 ? want / have : 1) }
        return RGBA(r: share(r, base.r), g: share(g, base.g), b: share(b, base.b), a: a)
    }
}

/// Shapes for shading, built from the lines of the figure.
enum Shade {
    /// The points of `data`, each moved by `offset`.
    static func moved(_ data: String, _ offset: CGPoint) -> [CGPoint] {
        PathData.points(data, spacing: 1.5).map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }

    /// The shape under an edge: the edge moved by `offset`, closed far beyond it
    /// on the side `away` (where the part above hides it).
    static func cast(_ edge: String, by offset: CGPoint, away: CGPoint) -> [CGPoint] {
        let line = moved(edge, offset)
        guard let first = line.first, let last = line.last else { return [] }
        return line + [CGPoint(x: last.x + away.x, y: last.y + away.y), CGPoint(x: first.x + away.x, y: first.y + away.y)]
    }

    /// A crescent inside an outline: between `edge` and the same edge moved by
    /// `inward`, meeting it at both ends.
    static func band(_ edge: String, inward: CGPoint) -> [CGPoint] {
        let outer = PathData.points(edge, spacing: 1.5)
        let count = max(outer.count - 1, 1)
        let inner = outer.enumerated().map { index, point -> CGPoint in
            let swell = sin(.pi * CGFloat(index) / CGFloat(count))
            return CGPoint(x: point.x + inward.x * swell, y: point.y + inward.y * swell)
        }
        return outer + inner.reversed()
    }
}

extension Shade {
    /// A path through the points, for the shapes that take one.
    static func pointsPath(_ points: [CGPoint]) -> String {
        points.enumerated().map { "\($0.offset == 0 ? "M" : "L") \($0.element.x) \($0.element.y)" }.joined(separator: " ")
    }
}

extension Studio {
    func shadows() {
        faceShadows()
        eyeShading()
        hairShadows()
        bodyShadows()
        nearShadows()
    }

    // MARK: Face

    private func faceShadows() {
        guard let face = parts["顔"], let shade = face.shade, let deep = face.deep else { return }
        let one = RGBA(hex: 0xF2B8AE).over(c.skin)
        let two = RGBA(hex: 0xDE8E88).over(c.skin)
        a.use(shade)
        onHead {
            // The fringe's shadow falls down and to the left, away from the window.
            a.shape(Shade.cast(Head.fringeEdge, by: CGPoint(x: -9, y: 17), away: CGPoint(x: 0, y: -260)), one)
            // The near side lock shades the cheek beside it.
            a.shape(Shade.cast("M 196 58 C 204 110, 204 170, 194 214 C 188 236, 180 252, 168 268", by: CGPoint(x: -16, y: 6), away: CGPoint(x: 120, y: 0)), one)
            // The far side of the face turns away.
            a.shape(Shade.band(Head.farCheek, inward: CGPoint(x: 34, y: -4)), one)
            a.shape(Shade.cast("M -176 52 C -180 110, -176 160, -160 210 C -150 240, -140 256, -136 268", by: CGPoint(x: 10, y: 4), away: CGPoint(x: -120, y: 0)), one)
            // Under the nose.
            a.shape("M -36 120 C -30 128, -32 136, -42 139 C -46 134, -44 126, -36 120 Z", one)
        }
        // A blush of warmth where the shadow begins.
        onHead {
            a.line(Shade.moved(Head.fringeEdge, CGPoint(x: -9, y: 30)), Pen(width: 12, color: RGBA(hex: 0xFF9A8A).withAlpha(1), start: 0.1, end: 0.1, floor: 1, opacity: 0.18, softness: 1))
        }
    }

    // MARK: Eyes

    private func eyeShading() {
        guard let lidShade = layer(named: "白目の影"), let irisShade = layer(named: "瞳の影"), let irisLight = layer(named: "瞳の光"),
              let sparkle = layer(named: "目の輝き") else { return }
        a.use(lidShade)
        onHead {
            for eye in [Head.nearEye, Head.farEye] {
                // The lid's shadow over the top of the white, cool grey-blue.
                a.shape(Shade.cast(eye.lash, by: CGPoint(x: -2, y: 16 * eye.weight), away: CGPoint(x: 0, y: -80)), RGBA(hex: 0xC9D4E6))
            }
        }
        a.use(irisShade)
        onHead {
            for eye in [Head.nearEye, Head.farEye] {
                let center = eye.iris.center
                // Dark at the top, under the lid, fading down.
                var clear = c.irisDeep.over(c.iris)
                let dark = clear
                clear.a = 0
                a.gradient(.linear, from: CGPoint(x: center.x, y: center.y - eye.iris.ry), to: CGPoint(x: center.x, y: center.y + eye.iris.ry * 0.35), dark, clear)
                // The rim of the iris, darker.
                a.line(PathData.arc(center: center, rx: eye.iris.rx - 2, ry: eye.iris.ry - 2, from: 0, to: 360, spacing: 1.5), Pen(width: 5 * eye.weight, color: RGBA(hex: 0x6E9AA6), start: 0, end: 0, floor: 1))
                // Fine lines from the pupil outward.
                for k in 0..<14 {
                    let angle = CGFloat(k) / 14 * 2 * .pi + 0.2
                    let from = CGPoint(x: center.x + cos(angle) * eye.pupil.rx * 1.3, y: center.y + 4 + sin(angle) * eye.pupil.ry * 1.2)
                    let to = CGPoint(x: center.x + cos(angle) * eye.iris.rx * 0.82, y: center.y + 4 + sin(angle) * eye.iris.ry * 0.8)
                    a.ribbon([from, to], RGBA(hex: 0x9CC2C8), width: Ribbon.leaf(3 * eye.weight))
                }
            }
        }
        a.use(irisLight)
        onHead {
            for eye in [Head.nearEye, Head.farEye] {
                let center = eye.iris.center
                // The bottom of the iris lit, as by light through the eye.
                var clear = c.irisLight
                clear.a = 0
                a.gradient(.radial, from: CGPoint(x: center.x + 4, y: center.y + eye.iris.ry * 0.75), to: CGPoint(x: center.x + 4 + eye.iris.rx * 1.1, y: center.y + eye.iris.ry * 0.75), c.irisLight, clear)
                // A crescent of reflected light along the bottom.
                a.ribbon(PathData.arc(center: center, rx: eye.iris.rx * 0.78, ry: eye.iris.ry * 0.78, from: 30, to: 150, spacing: 1.5), RGBA(hex: 0xD8FFF0), width: Ribbon.leaf(7 * eye.weight))
            }
        }
        a.use(sparkle)
        onHead {
            for eye in [Head.nearEye, Head.farEye] {
                let center = eye.iris.center, w = eye.weight
                // The window's reflection: a big soft-cornered highlight up and to the right, a small one low left.
                a.shape(PathData.arc(center: CGPoint(x: center.x + 16 * w, y: center.y - 22 * w), rx: 13 * w, ry: 16 * w, from: 0, to: 360, spacing: 1), RGBA(hex: 0xFFFFFF))
                a.shape(PathData.arc(center: CGPoint(x: center.x - 18 * w, y: center.y + 26 * w), rx: 6 * w, ry: 6 * w, from: 0, to: 360, spacing: 1), RGBA(hex: 0xFFFFFF))
                a.shape(PathData.arc(center: CGPoint(x: center.x + 26 * w, y: center.y + 14 * w), rx: 3.5 * w, ry: 3.5 * w, from: 0, to: 360, spacing: 1), RGBA(hex: 0xFFFFFF).withAlpha(0.9))
                // A little four-pointed sparkle, and a mint glint low in the iris.
                let star = CGPoint(x: center.x - 26 * w, y: center.y - 10 * w)
                a.ribbon("M \(star.x - 9 * w) \(star.y) L \(star.x + 9 * w) \(star.y)", RGBA(hex: 0xFFFFFF), width: Ribbon.leaf(2.6 * w))
                a.ribbon("M \(star.x) \(star.y - 9 * w) L \(star.x) \(star.y + 9 * w)", RGBA(hex: 0xFFFFFF), width: Ribbon.leaf(2.6 * w))
                a.shape(PathData.arc(center: CGPoint(x: center.x + 4 * w, y: center.y + 38 * w), rx: 9 * w, ry: 3 * w, from: 0, to: 360, spacing: 1), RGBA(hex: 0xC8FFF0).withAlpha(0.85))
            }
        }
    }

    // MARK: Hair

    private func hairShadows() {
        guard let hair = parts["髪"], let shade = hair.shade, let deep = hair.deep, let back = parts["後ろ髪"], let backShade = back.shade else { return }
        let one = c.hairShade.over(c.hair)
        let two = c.hairDeep.over(c.hair)
        a.use(shade)
        onHead {
            // Darker toward the ends, so the crown stands out round.
            var clear = one
            clear.a = 0
            var half = one
            half.a = 0.75
            a.gradient(.linear, from: CGPoint(x: 0, y: -170), to: CGPoint(x: 0, y: 120), clear, half)
            // The far side of the head, away from the window.
            a.shape("M -120 -320 C -230 -270, -300 -170, -296 -40 C -296 60, -300 160, -320 300 L -380 300 L -380 -320 Z", one)
            a.ribbon("M -150 -268 C -230 -220, -262 -120, -258 -20", one, width: Ribbon.leaf(40))
            // Each lock of the fringe rounds off: a pointed shadow rising from each parting between the tips.
            // Each one its own length, width and bend, and a thinner one beside some.
            let wedges: [(length: CGFloat, width: CGFloat, bend: CGFloat)] = [(96, 18, -12), (64, 12, 8), (110, 20, -6), (76, 14, 10), (90, 16, 4), (58, 11, -8)]
            for (number, index) in stride(from: 1, to: Head.fringe.count - 1, by: 2).enumerated() {
                let hollow = Head.fringe[index]
                let style = wedges[number % wedges.count]
                let toward = CGPoint(x: Head.whorl.x - hollow.x, y: Head.whorl.y - hollow.y)
                let reach = hypot(toward.x, toward.y)
                let tip = CGPoint(x: hollow.x + toward.x / reach * style.length, y: hollow.y + toward.y / reach * style.length)
                let bend = CGPoint(x: (hollow.x + tip.x) / 2 + style.bend, y: (hollow.y + tip.y) / 2)
                a.ribbon("M \(hollow.x) \(hollow.y - 2) Q \(bend.x) \(bend.y), \(tip.x) \(tip.y)", one, width: Ribbon.taper(style.width, holding: 0.12))
                if number % 2 == 0 {
                    let side = CGPoint(x: hollow.x + 16, y: hollow.y + 4)
                    a.ribbon("M \(side.x) \(side.y) Q \(bend.x + 18) \(bend.y + 20), \(tip.x + 14) \(tip.y + style.length * 0.35)", one, width: Ribbon.taper(7, holding: 0.1))
                }
            }
            // The side locks hang in front of the bob and shade it; the bob's lower half turns under.
            a.shape(Shade.cast("M 232 160 C 226 190, 214 230, 190 262", by: CGPoint(x: 14, y: 0), away: CGPoint(x: -60, y: 0)), one)
            a.ribbon("M 296 200 C 290 150, 296 90, 292 40", one, width: Ribbon.leaf(30))
            a.ribbon("M 210 70 C 218 130, 214 190, 196 240", one, width: Ribbon.leaf(22))
            a.ribbon("M -196 70 C -204 130, -198 190, -182 240", one, width: Ribbon.leaf(22))
        }
        a.use(deep)
        onHead {
            // Deepest under the side locks by the jaw, and in each parting.
            a.ribbon("M 200 120 C 204 170, 200 210, 186 248", two, width: Ribbon.leaf(10))
            a.ribbon("M -186 110 C -190 160, -184 210, -170 244", two, width: Ribbon.leaf(10))
            for index in stride(from: 1, to: Head.fringe.count - 1, by: 2) {
                let hollow = Head.fringe[index]
                a.ribbon("M \(hollow.x) \(hollow.y) C \(hollow.x + 2) \(hollow.y - 14), \(hollow.x + 3) \(hollow.y - 26), \(hollow.x + 4) \(hollow.y - 38)", two.withAlpha(0.45), width: Ribbon.taper(6))
            }
        }
        a.use(backShade)
        onHead {
            // The hair behind the neck sits in shadow, deepest by the neck.
            a.shape(Head.back, RGBA(hex: 0xC6D8DA))
            a.line("M -110 160 C -100 260, -100 330, -110 400", Pen(width: 70, color: RGBA(hex: 0xA8C0C6), start: 0.1, end: 0.1, floor: 1, opacity: 0.8, softness: 1))
            a.line("M 90 170 C 86 260, 88 330, 96 400", Pen(width: 70, color: RGBA(hex: 0xA8C0C6), start: 0.1, end: 0.1, floor: 1, opacity: 0.8, softness: 1))
        }
        // The fringe's tips are thin enough to let the skin show through.
        if let through = layer(of: "髪", "透け") {
            a.use(through)
            onHead {
                // Only the last bit of each tip takes the skin's colour.
                for index in stride(from: 0, to: Head.fringe.count, by: 2) {
                    let tip = Head.fringe[index]
                    a.ribbon("M \(tip.x + (Head.middle - tip.x) * 0.02) \(tip.y - 46) L \(tip.x) \(tip.y)", c.hair.mixed(with: c.skin, 0.65).withAlpha(0.55), width: Ribbon.between(0, 14))
                }
            }
        }
    }

    // MARK: Body

    private func bodyShadows() {
        guard let body = parts["体"], let shade = body.shade, let deep = body.deep else { return }
        a.use(shade)
        let cool = c.blouseShade.over(c.blouse)
        let knit = c.knitShade.over(c.knit)
        let skin = RGBA(hex: 0xF0B0A6).over(c.skin)
        onBody {
            // The neck in the chin's shadow, cut across where the light reaches.
            a.shape("M -120 180 C -60 250, 40 260, 100 200 L 100 360 L -120 360 Z", skin)
            // Under the collar and the bow, on the blouse.
            a.shape(Shade.cast("M -150 404 C -100 420, -40 410, -10 376 C 20 404, 70 414, 120 400", by: CGPoint(x: -6, y: 12), away: CGPoint(x: 0, y: -60)), cool)
            a.shape(Shade.cast(Body.tailLeft, by: CGPoint(x: -6, y: 8), away: .zero), cool)
            // The hair's ends shade the shoulders; the far side turns away.
            a.shape("M -110 330 C -170 340, -232 360, -276 392 C -260 420, -220 430, -170 410 C -140 396, -120 380, -110 360 Z", knit)
            a.shape("M 86 328 C 150 338, 210 352, 252 376 C 236 404, 196 410, 150 396 C 120 386, 100 370, 86 356 Z", knit)
            a.shape("M -306 500 C -280 560, -260 650, -250 760 L -330 760 L -330 480 Z", knit)
            a.shape(Shade.band(Body.knitFar, inward: CGPoint(x: -26, y: 0)), knit)
            a.shape(Shade.band(Body.knitNear, inward: CGPoint(x: 24, y: 0)), knit)
            // The knit's ribs running down, and folds where she leans on her elbows.
            for x in stride(from: -320, through: -150, by: 18) as StrideThrough<CGFloat> {
                a.ribbon("M \(x) \(370 + (x + 320) * 0.1) C \(x + 4) 470, \(x + 2) 600, \(x - 2) 760", knit.withAlpha(0.45), width: Ribbon.leaf(4))
            }
            for x in stride(from: 130, through: 320, by: 18) as StrideThrough<CGFloat> {
                a.ribbon("M \(x) \(360 + (320 - x) * 0.05) C \(x - 2) 470, \(x) 600, \(x + 4) 760", knit.withAlpha(0.45), width: Ribbon.leaf(4))
            }
            a.ribbon("M -320 520 C -280 560, -250 620, -244 700", knit, width: Ribbon.leaf(16))
            a.ribbon("M -260 600 C -230 640, -214 690, -212 740", knit, width: Ribbon.leaf(12))
        }
        a.use(deep)
        onBody {
            // Just under the jaw, a little deeper.
            a.shape("M -110 196 C -60 246, 40 256, 90 204 C 70 236, 20 250, -40 248 C -80 244, -104 226, -110 196 Z", RGBA(hex: 0xE8A49C).over(c.skin))
        }
    }

    // MARK: The arm, the spoon and the ice cream

    /// The shape under a line of points: the line moved by `offset`, closed far beyond it on the side `away`.
    private func cast(_ edge: [CGPoint], by offset: CGPoint, away: CGPoint) -> [CGPoint] {
        let line = edge.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        guard let first = line.first, let last = line.last else { return [] }
        return line + [CGPoint(x: last.x + away.x, y: last.y + away.y), CGPoint(x: first.x + away.x, y: first.y + away.y)]
    }

    /// The points of a path moved by `offset`.
    private func moved(_ points: [CGPoint], _ offset: CGPoint) -> [CGPoint] {
        points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }

    private func nearShadows() {
        onNear {
            spoonShading()
            scoopShading()
            fistShading()
            sleeveShading()
            otherHandShading()
        }
    }

    /// Metal shows what is round it, with hard edges: the far wall of the bowl
    /// dark with the room, its floor bright with the window, the handle dark
    /// along its turned-down edge, and the lip bright on top and dark below.
    private func spoonShading() {
        guard let spoon = parts["スプーン"], let shade = spoon.shade, let deep = spoon.deep, let light = spoon.light else { return }
        let dark = c.metalShade.over(c.metal)
        let darker = RGBA(hex: 0x6E7A8E).over(c.metal)
        a.use(shade)
        // Inside the bowl it darkens up the far wall, which mirrors the room behind the viewer.
        a.line(Near.half(near: false, inset: 18), Pen(width: 46, color: dark, start: 0.15, end: 0.15, floor: 0.4, opacity: 0.85, softness: 1))
        let handleNear = (0...60).map { Near.handleSpot(CGFloat($0) / 60, side: 1.2) }
        let handleMid = (0...60).map { Near.handleSpot(CGFloat($0) / 60, side: 0.15) }
        a.shape(PathData.resampled(handleNear + handleMid.reversed(), spacing: 1.5), dark)
        a.use(deep)
        a.line(Near.half(near: false, inset: 4), Pen(width: 9, color: darker, start: 0.25, end: 0.25, floor: 0.2, opacity: 0.6, softness: 0.8))
        a.use(light)
        // A hard white highlight on the far wall, and beside it the mint of the
        // ice cream, reflected in the metal.
        let wall = Near.half(near: false, inset: 24)
        a.ribbon(Array(wall[(wall.count / 6)..<(wall.count / 2)]), RGBA(hex: 0xFFFFFF), width: Ribbon.leaf(5))
        let mirror = Near.half(near: false, inset: 36)
        a.ribbon(Array(mirror[(mirror.count / 2)..<(mirror.count * 5 / 6)]), c.cream.screened(over: c.metal.mixed(with: c.metalShade, 0.4)).withAlpha(0.8), width: Ribbon.leaf(9))
        let warmRim = Near.half(near: true, inset: 4)
        a.ribbon(Array(warmRim.suffix(warmRim.count / 3)), RGBA(hex: 0xFFF1DA), width: Ribbon.leaf(4))
        let streak = (0...60).map { Near.handleSpot(0.08 + 0.9 * CGFloat($0) / 60, side: -0.45) }
        a.ribbon(streak, RGBA(hex: 0xFFFFFF), width: Ribbon.leaf(3.6))

        guard let lip = parts["スプーンの縁"], let lipShade = lip.shade, let lipLight = lip.light else { return }
        a.use(lipShade)
        a.shape(PathData.resampled(Near.half(near: true, inset: -2) + Near.half(near: true, inset: 3).reversed(), spacing: 1.5), dark)
        a.use(lipLight)
        let edge = Near.half(near: true, inset: 5)
        a.ribbon(Array(edge.prefix(edge.count * 2 / 5)), RGBA(hex: 0xFFFFFF), width: Ribbon.leaf(3))
        a.ribbon(Array(edge.suffix(edge.count / 3)), c.metalWarm, width: Ribbon.leaf(3))
    }

    /// The scoop, lit from behind: the side toward the viewer in a soft shade
    /// that deepens toward its foot, each ridge with its shadow under it, and a
    /// crisp dark line where it sinks into the bowl.
    private func scoopShading() {
        guard let scoop = parts["アイス"], let shade = scoop.shade, let deep = scoop.deep, let light = scoop.light else { return }
        let shadow = c.creamShade.over(c.cream)
        a.use(shade)
        // Matte and opaque: the side away from the window in one cel shade with a wavy edge.
        a.shape(Near.scoopShadow, shadow)
        for ridge in Near.ridges where ridge.count > 4 {
            a.ribbon(moved(ridge, CGPoint(x: -1, y: 6)), shadow.withAlpha(0.85), width: Ribbon.leaf(9))
        }
        document.setLayerBlur(shade, 1.2 * a.unit)
        a.use(deep)
        for pit in Near.pits {
            a.ribbon(pit, shadow.withAlpha(0.4), width: Ribbon.leaf(2))
        }
        // Where it sinks into the bowl.
        let foot = Near.half(near: true, inset: 8)
        a.shape(cast(foot, by: CGPoint(x: 0, y: -8), away: CGPoint(x: 0, y: 60)), shadow.mixed(with: RGBA(hex: 0x5E7E96), 0.3))
        a.use(light)
        // Its top, toward the light, a plane of paler mint; the curls' upper edges.
        a.shape(Near.scoopTopPlane, c.creamLight.screened(over: c.cream))
        for ridge in Near.ridges where ridge.count > 4 {
            a.ribbon(moved(ridge, CGPoint(x: 0, y: -3)), c.creamLight.screened(over: c.cream), width: Ribbon.leaf(4))
        }
        // Beginning to melt where it meets the metal: a thin wet line.
        let rim = Near.half(near: true, inset: 10)
        a.ribbon(moved(Array(rim.prefix(rim.count * 2 / 3)), CGPoint(x: 0, y: -3)), RGBA(hex: 0xFFFFFF).withAlpha(0.6), width: Ribbon.leaf(1.4))
        if let drip = parts["しずく"], let dripShade = drip.shade, let dripLight = drip.light {
            a.use(dripShade)
            let side = Near.drip
            a.line(Array(side.prefix(side.count / 2)), Pen(width: 6, color: shadow, start: 0.2, end: 0.3, floor: 0.2, opacity: 0.9, softness: 0.6))
            a.use(dripLight)
            let other = Array(side.suffix(side.count / 2))
            a.ribbon(moved(Array(other.prefix(other.count * 3 / 4)), CGPoint(x: 2, y: 0)), c.creamLight.screened(over: c.cream).withAlpha(0.7), width: Ribbon.leaf(2.4))
        }
    }

    /// Her fist: each finger shaded along its underside, darker where it comes
    /// out of the cuff, flushed at the tips.
    private func fistShading() {
        guard let fingers = parts["指"], let shade = fingers.shade, let deep = fingers.deep else { return }
        let skin = RGBA(hex: 0xF8D4C8).over(c.skin)
        let skinDeep = RGBA(hex: 0xEDB8AC).over(c.skin)
        a.use(shade)
        a.shape(Near.fingerStrip(Near.thumbJoints, Near.thumbWidths, from: -0.6, to: -0.05), skin)
        a.shape(Near.fingerStrip(Near.indexJoints, Near.indexWidths, from: -0.6, to: 0.0), skin)
        a.shape(Near.fingerStrip(Near.middleJoints, Near.middleWidths, from: -0.6, to: 0.25), skin)
        a.shape(PathData.points(Near.fist, spacing: 1.5), skin)
        // Where they come out of the cuff, in its shadow.
        a.line(Near.hand([CGPoint(x: -44, y: 40), CGPoint(x: -48, y: 0), CGPoint(x: -46, y: -40), CGPoint(x: -36, y: -76)]), Pen(width: 26, color: skin, start: 0.1, end: 0.1, floor: 1, opacity: 0.9, softness: 0.8))
        for tip in [Near.thumbJoints.last!, Near.indexJoints.last!, Near.middleJoints.last!] {
            a.line([tip, CGPoint(x: tip.x + 0.5, y: tip.y + 0.5)], Pen(width: 24, color: c.blush.over(c.skin), start: 0, end: 0, floor: 1, opacity: 0.3, softness: 1))
        }
        a.use(deep)
        _ = skinDeep
    }

    /// The sleeve running back from the cuff to her shoulder, in her body's
    /// shade; the knit's ribs along it; the cuff's band lit on top, its
    /// opening dark, the wrist inside it darker still.
    private func sleeveShading() {
        guard let arm = parts["腕"], let shade = arm.shade else { return }
        let knit = c.knitShade.over(c.knit)
        let knitDeep = RGBA(hex: 0xCDB29C).over(c.knit)
        a.use(shade)
        a.shape(Near.sleeveOutline, knit.withAlpha(0.6))
        let sides = Near.sleeveSides
        for rib in Near.ribs(sides.one, sides.other, count: 7) {
            a.ribbon(rib, knit.withAlpha(0.5), width: Ribbon.leaf(3.2))
        }
        if let cuff = parts["袖口"], let cuffShade = cuff.shade, let cuffDeep = cuff.deep {
            a.use(cuffShade)
            // The cuff's lower half turns from the window, into shade.
            let ring = Near.ring(63, 22)
            a.line(Array(ring[0...80]), Pen(width: 20, color: knit, start: 0.2, end: 0.2, floor: 0.4, opacity: 0.85, softness: 0.8))
            // The knit's ribs round the band.
            for k in stride(from: 0, to: 160, by: 6) {
                let outer = Near.ring(69, 25)[k], inner = Near.ring(58, 18)[k]
                a.line([outer, inner], Pen(width: 2, color: knitDeep, start: 0.3, end: 0.3, floor: 0.2, opacity: 0.45))
            }
            a.use(cuffDeep)
            a.line(Near.ring(58, 18), Pen(width: 5, color: knitDeep, start: 0, end: 0, floor: 1, opacity: 0.7, softness: 0.6))
        }
    }

    /// Her cupped hand: the hollow of the palm, the undersides of the fingers
    /// and the thumb, the cuff's shadow on the heel of it, the fingertips flushed.
    private func otherHandShading() {
        guard let other = parts["下の手"], let shade = other.shade, let deep = other.deep else { return }
        let skin = RGBA(hex: 0xF6C6B8).over(c.skin)
        let skinDeep = RGBA(hex: 0xE6A69C).over(c.skin)
        let knit = c.knitShade.over(c.knit)
        a.use(shade)
        a.shape(cast(PathData.points(Near.otherForearmBottom, spacing: 1.5), by: CGPoint(x: 0, y: -26), away: CGPoint(x: 60, y: 60)), knit)
        for fold in Near.otherFolds { a.ribbon(moved(PathData.points(fold, spacing: 1.5), CGPoint(x: 3, y: 5)), knit, width: Ribbon.leaf(10)) }
        for rib in Near.ribs(PathData.points(Near.otherForearmTop, spacing: 1.5), PathData.points(Near.otherForearmBottom, spacing: 1.5), count: 7) {
            a.ribbon(rib, knit.withAlpha(0.45), width: Ribbon.leaf(3.2))
        }
        for (joints, widths) in zip(Near.otherFingerJoints, Near.otherFingerWidths) {
            a.shape(Near.fingerStrip(joints, widths, from: -0.6, to: -0.25), skin.withAlpha(0.6))
        }
        a.shape(Near.fingerStrip(Near.otherThumbJoints, Near.otherThumbWidths, from: -0.6, to: -0.2), skin.withAlpha(0.7))
        // The hollow of the palm, toward the cuff.
        a.shape(PathData.points(Near.hollow, spacing: 1.5), RGBA(hex: 0xEDC3B4).over(c.skin).withAlpha(0.6))
        for joints in Near.otherFingerJoints + [Near.otherThumbJoints] {
            let tip = joints.last!
            a.line([tip, CGPoint(x: tip.x + 0.5, y: tip.y + 0.5)], Pen(width: 18, color: c.blush.over(c.skin), start: 0, end: 0, floor: 1, opacity: 0.3, softness: 1))
        }
        a.use(deep)
        a.line(PathData.points(Near.otherCuffRim, spacing: 1.5).map { CGPoint(x: $0.x + 7, y: $0.y) }, Pen(width: 14, color: skinDeep, start: 0.2, end: 0.2, floor: 0.4, opacity: 0.4, softness: 1))
        a.line(PathData.points(Near.otherCuffBand, spacing: 1.5).map { CGPoint(x: $0.x - 6, y: $0.y + 6) }, Pen(width: 20, color: RGBA(hex: 0xCDB29C).over(c.knit), start: 0.2, end: 0.2, floor: 0.4, opacity: 0.8, softness: 1))
    }

    func layer(named name: String) -> UUID? {
        document.layers.first { $0.name == name }?.id
    }
}
