import CoreGraphics
import Foundation
import OekakiKit

/// The light: the window behind her, on the hair and every edge it reaches,
/// the shine on things, the air full of light, then the finish over everything.
extension Studio {
    func light() {
        dim()
        hairLight()
        faceLight()
        onNear { nearLight() }
        bounce()
        rimLight()
        air()
    }

    // MARK: The room's dimness

    /// She sits with the window behind her: everything of her a step darker and
    /// cooler than the day outside, her face and the ice cream a little less so.
    private func dim() {
        // Each part darkened in its own hue, so it loses light but not colour.
        let shades: [(String, RGBA)] = [
            ("後ろ髪", RGBA(hex: 0xC4D6D6)), ("体", RGBA(hex: 0xEADCCE)), ("顔", RGBA(hex: 0xF8EAE2)), ("髪", RGBA(hex: 0xC2DED6)),
            ("腕", RGBA(hex: 0xECDFD2)), ("スプーン", RGBA(hex: 0xDCE0EA)), ("指", RGBA(hex: 0xF8EAE2)), ("袖口", RGBA(hex: 0xECDFD2)),
            ("アイス", RGBA(hex: 0xF0FAF5)), ("下の手", RGBA(hex: 0xF8EAE2)), ("スプーンの縁", RGBA(hex: 0xDCE0EA)), ("しずく", RGBA(hex: 0xF0FAF5)),
        ]
        // She sits against the window, so all of her is in half-shadow: a cool
        // veil over her, lightest on her face and on the spoon held out in the light.
        let veil: [String: RGBA] = [
            "顔": RGBA(hex: 0xF8F4F6), "スプーン": RGBA(hex: 0xF8F4F6), "スプーンの縁": RGBA(hex: 0xF8F4F6), "アイス": RGBA(hex: 0xF8F4F6),
            "しずく": RGBA(hex: 0xF8F4F6), "指": RGBA(hex: 0xF8F4F6), "下の手": RGBA(hex: 0xF8F4F6), "髪": RGBA(hex: 0xF2EDEF),
        ]
        for (part, ambient) in shades {
            guard let layer = layer(of: part, "陰") else { continue }
            a.use(layer)
            let cool = veil[part] ?? RGBA(hex: 0xEBE2E6)
            let shade = RGBA(r: ambient.r * cool.r, g: ambient.g * cool.g, b: ambient.b * cool.b, a: 1)
            // At night only the lamp lights her, and the room is darker and bluer.
            a.shape("M -20 -20 L 1020 -20 L 1020 1270 L -20 1270 Z", c.night ? shade.mixed(with: RGBA(hex: 0x8A84B8), 0.4) : shade)
        }
        // The face keeps a warm light from the room in front of her.
        if let light = parts["顔"]?.light {
            a.use(light)
            onHead {
                a.line("M -120 60 C -60 40, 60 40, 140 70", Pen(width: 190, color: RGBA(hex: 0xFFE6D6), start: 0.3, end: 0.3, floor: 0.3, opacity: 0.4, softness: 1))
            }
        }
    }

    /// Light thrown back up from the white table: under the chin, under the scoop and the sleeve.
    private func bounce() {
        let warm = RGBA(hex: 0xFFDCC4)
        if let face = parts["顔"]?.light {
            a.use(face)
            onHead {
                a.line("M -150 176 C -110 214, -60 230, -20 230 C 30 226, 80 208, 120 180", Pen(width: 34, color: warm, start: 0.3, end: 0.3, floor: 0.3, opacity: 0.3, softness: 1))
            }
        }
        onNear {
            if let fingers = parts["指"]?.light {
                a.use(fingers)
                for joints in [Near.indexJoints, Near.middleJoints] {
                    a.line(joints, Pen(width: 22, color: warm, start: 0.2, end: 0.2, floor: 0.4, opacity: 0.25, softness: 1))
                }
            }
            if let other = parts["下の手"]?.light {
                a.use(other)
                a.line(Near.otherThumbJoints, Pen(width: 22, color: warm, start: 0.2, end: 0.2, floor: 0.4, opacity: 0.25, softness: 1))
            }
        }
        if let light = parts["体"]?.light {
            a.use(light)
            onBody { a.line("M -60 286 C -20 296, 30 294, 56 284", Pen(width: 26, color: warm, start: 0.3, end: 0.3, floor: 0.2, opacity: 0.5, softness: 1)) }
        }
        onNear {
            if let light = parts["アイス"]?.light {
                a.use(light)
                let foot = Near.half(near: true, inset: 12)
                a.line(foot.map { CGPoint(x: $0.x, y: $0.y - 6) }, Pen(width: 18, color: warm, start: 0.3, end: 0.3, floor: 0.2, opacity: 0.4, softness: 1))
            }

        }
    }

    // MARK: Hair

    private func hairLight() {
        guard let light = parts["髪"]?.light else { return }
        a.use(light)
        onHead {
            // The ring of light round the crown: a broad band, its lower edge
            // broken into points running down the locks.
            let ring = { (x: CGFloat) -> CGPoint in CGPoint(x: x, y: -232 + 0.0021 * x * x) }
            let band = stride(from: -214, through: 236, by: 2).map(ring)
            // One band of shine, its lower edge broken into points down the locks.
            let shine = c.hairLight.mixed(with: c.hair, 0.55)
            a.ribbon(band, shine.withAlpha(0.7), width: Ribbon.leaf(22, at: 0.62))
            var random = SplitMix(seed: 12)
            for x in stride(from: -186, through: 214, by: 26) as StrideThrough<CGFloat> {
                let base = ring(x)
                // Down along the hair, away from the crown.
                let away = CGPoint(x: base.x - Head.whorl.x * 0.4, y: base.y + 300)
                let reach = hypot(away.x, away.y)
                let length = 22 + random.next() * 34
                let tip = CGPoint(x: base.x + away.x / reach * length, y: base.y + away.y / reach * length)
                let strength = 0.45 + 0.4 * (x + 186) / 400
                a.ribbon([base, tip], shine.withAlpha(strength), width: Ribbon.taper(11 + random.next() * 5, holding: 0.1))
                let up = CGPoint(x: base.x - away.x / reach * length * 0.4, y: base.y - away.y / reach * length * 0.4)
                a.ribbon([base, up], shine.withAlpha(strength * 0.8), width: Ribbon.taper(8, holding: 0.1))
            }
            // Where the window shines through the hair at its edge, it glows warm.
            a.line("M 300 260 C 296 200, 300 120, 296 40 C 290 -60, 260 -170, 180 -240", Pen(width: 46, color: RGBA(hex: 0xFFE9A8), start: 0.2, end: 0.3, floor: 0.2, opacity: 0.55, softness: 1))
        }
    }

    // MARK: Face

    private func faceLight() {
        guard let face = parts["顔"], let shade = face.shade, let light = face.light else { return }
        // Blush across the cheeks and the bridge of the nose, with fine hatching.
        a.use(shade)
        onHead {
            let blush = c.blush.over(c.skin)
            a.line("M 60 140 C 90 132, 130 132, 160 140", Pen(width: 54, color: blush, start: 0.3, end: 0.3, floor: 0.3, opacity: 0.5, softness: 1))
            a.line("M -170 134 C -150 128, -120 128, -100 136", Pen(width: 46, color: blush, start: 0.3, end: 0.3, floor: 0.3, opacity: 0.45, softness: 1))
            a.line("M -60 112 C -46 108, -30 108, -18 112", Pen(width: 22, color: blush, start: 0.3, end: 0.3, floor: 0.3, opacity: 0.35, softness: 1))
            let hatch = RGBA(hex: 0xE8707E).over(c.skin).withAlpha(0.6)
            for (index, x) in [86.0, 104, 122].enumerated() {
                a.ribbon("M \(x) \(144 - CGFloat(index % 2) * 2) L \(x + 7) \(128 - CGFloat(index % 2) * 2)", hatch, width: Ribbon.leaf(2.6))
            }
            for x in [-156.0, -140] {
                a.ribbon("M \(x) 142 L \(x + 6) 128", hatch, width: Ribbon.leaf(2.2))
            }
        }
        a.use(light)
        onHead {
            // A shine on the nose, the near cheek and the lower lip.

            a.shape(PathData.arc(center: CGPoint(x: -38, y: 203), rx: 4, ry: 2, from: 0, to: 360, spacing: 0.8), RGBA(hex: 0xFFE4EA))
        }
    }

    // MARK: The spoon, the ice cream, the hand

    private func nearLight() {
        guard let scoop = parts["アイス"]?.light, let fingers = parts["指"]?.light else { return }
        a.use(scoop)
        // Matte, so no shine on it; only a soft breath of the window on its top.
        let top = Near.scoopTop
        a.line([CGPoint(x: top.x + 14, y: top.y + 18), CGPoint(x: top.x + 15, y: top.y + 19)],
               Pen(width: 54, color: RGBA(hex: 0xFFFFFF), start: 0, end: 0, floor: 1, opacity: 0.18, softness: 1))
        a.use(fingers)
        // A shine on the thumbnail.
        let nail = Near.thumbNail
        a.shape(PathData.arc(center: nail[nail.count / 8], rx: 3, ry: 2, from: 0, to: 360, spacing: 0.6), RGBA(hex: 0xFFFFFF).withAlpha(0.9))
        if let other = parts["下の手"]?.light {
            a.use(other)
            // The little pool in her palm, glossy.
            a.shape(Near.puddle, c.creamLight.screened(over: c.cream).withAlpha(0.35))
            a.line(Near.other("M -8 -2 C -5 0, -1 0, 2 -1"), Pen(width: 2.2, color: RGBA(hex: 0xFFFFFF), start: 0.3, end: 0.3, floor: 0.2, opacity: 0.95))
        }
    }

    // MARK: The light from behind

    private func rimLight() {
        // The window behind her: light spilling round her head.
        a.layer("逆光", style: LayerStyle(blend: .add))
        var clear = c.glow
        clear.a = 0
        // At night the window is dark, and only the lamp glows.
        a.gradient(.radial, from: CGPoint(x: 860, y: 120), to: CGPoint(x: 860 + 460, y: 120), c.glow.withAlpha(c.night ? 0.3 : 0.85), clear)
        // Where it spills round the edge of her hair, toward the window.
        onHead {
            a.line("M 330 250 C 334 190, 320 120, 314 60 C 306 -20, 290 -100, 250 -170", Pen(width: 70, color: c.glow, start: 0.2, end: 0.2, floor: 0.3, opacity: c.night ? 0.15 : 0.35, softness: 1))
        }
        // Rims of light along every edge that faces the window, each inside its
        // own part's lines, so nothing glows outside them.
        let rim = RGBA(hex: 0xFFF3E3)
        if let hair = parts["髪"]?.light {
            a.use(hair)
            onHead {
                a.ribbon("M 320 244 C 322 200, 308 150, 304 90 C 300 30, 292 -30, 278 -70 C 266 -150, 226 -216, 158 -256", rim, width: Ribbon.leaf(14, at: 0.45))
                a.ribbon("M 160 -262 C 100 -286, 20 -294, -60 -288", rim.withAlpha(0.7), width: Ribbon.leaf(8))
                a.ribbon(PathData.points(Head.ahogeSpine, spacing: 1.5).map { CGPoint(x: $0.x + 6, y: $0.y - 1) }, rim, width: Ribbon.leaf(6))
            }
        }
        if let face = parts["顔"]?.light {
            a.use(face)
            onHead {
                a.ribbon("M 204 60 C 190 110, 154 150, 110 180", rim.withAlpha(0.7), width: Ribbon.leaf(8))
            }
        }
        if let body = parts["体"]?.light {
            a.use(body)
            onBody {
                a.ribbon("M 220 318 C 268 334, 300 368, 318 420 C 330 470, 338 560, 342 720", rim.withAlpha(0.75), width: Ribbon.leaf(12, at: 0.3))
            }
        }
        onNear {
            if let scoop = parts["アイス"]?.light {
                a.use(scoop)
                let top = Near.scoopTop
                let lit = Near.scoop.filter { $0.x > top.x - 10 && $0.y < Near.bowl.y - 10 }.sorted { $0.y < $1.y }
                if lit.count > 4 { a.ribbon(lit, rim.withAlpha(0.8), width: Ribbon.leaf(9)) }
            }
            if let fingers = parts["指"]?.light {
                a.use(fingers)
                let thumb = Near.thumb
                a.ribbon(Array(thumb.prefix(thumb.count / 2)), rim.withAlpha(0.6), width: Ribbon.leaf(7))
            }
        }
    }

    // MARK: The air

    private func air() {
        // Beams of daylight in the room behind her, under the figure.
        let behindHer = document.layers.firstIndex { $0.name == "後ろ髪" }.map { document.layers[$0].id }
        a.layer("光の筋", style: LayerStyle(blend: .add, blur: 8), below: behindHer)
        for (start, end, width) in [((1020.0, 60.0), (560.0, 760.0), 90.0), ((1020, 260), (700, 900), 50), ((900, -20), (420, 600), 40)] as [((CGFloat, CGFloat), (CGFloat, CGFloat), CGFloat)] {
            a.line("M \(start.0) \(start.1) L \(end.0) \(end.1)", Pen(width: width, color: c.glow, start: 0.1, end: 0.7, floor: 0.2, opacity: 0.16, softness: 1))
        }
        // Dust in the light from the window: one shaft, specks of every size, none over her face.
        a.layer("光の粒", style: LayerStyle(blend: .add, glow: 8))
        var random = SplitMix(seed: 77)
        var made = 0
        while made < 46 {
            let along = random.next(), across = random.next() - 0.5
            let p = CGPoint(x: 1000 - along * 520 + across * 200, y: 40 + along * 600 + across * 120)
            let face = CGPoint(x: 470, y: 440)
            guard hypot(p.x - face.x, p.y - face.y) > 260, p.x < 990, p.x > 10 else { continue }
            made += 1
            let r = 0.8 + pow(random.next(), 2) * 5
            a.shape(PathData.arc(center: p, rx: r, ry: r, from: 0, to: 360, spacing: 0.6), c.glow.withAlpha(0.35 + 0.6 * random.next()))
        }
    }

    // MARK: Finish

    func finish() {
        // Warm toward the window, cool in the corner away from it, over everything.
        a.layer("色調", opacity: 0.18, style: LayerStyle(blend: .overlay))
        a.gradient(.linear, from: CGPoint(x: 900, y: 80), to: CGPoint(x: 120, y: 1200), RGBA(hex: 0xFFC27A), RGBA(hex: 0xB9A6C6))
        // The corners fall away, so the eye stays on her face and the spoon.
        a.layer("周辺減光", style: LayerStyle(blend: .multiply))
        var clear = c.deep
        clear.a = 0
        a.gradient(.radial, from: CGPoint(x: 680, y: 420), to: CGPoint(x: 680 + 900, y: 420), clear, c.deep.mixed(with: RGBA(hex: 0x7A5050), 0.3).withAlpha(0.55))
        // Light gathered where the eye should go: her face and the spoon she holds out.
        a.layer("見せ場の光", style: LayerStyle(blend: .screen))
        var soft = c.glow
        soft.a = 0
        a.gradient(.radial, from: CGPoint(x: 470, y: 640), to: CGPoint(x: 470 + 330, y: 640), c.glow.withAlpha(0.16), soft)
        // A last bloom of the brightest light, from the window's corner.
        a.layer("光のにじみ", style: LayerStyle(blend: .screen))
        var warm = c.sun
        warm.a = 0
        a.gradient(.radial, from: CGPoint(x: 1000, y: 0), to: CGPoint(x: 1000 + 480, y: 0), c.sun.withAlpha(0.42), warm)
    }
}
