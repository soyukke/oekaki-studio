import CoreGraphics
import Foundation
import OekakiKit

/// The painting over the lines: shadow, light, the eyes, and the evening glow.
/// Coordinates are the script's, around the face's centre, unless a step says
/// it works in canvas pixels.
extension Portrait {
    enum Paint {
        // Shadows are painted to be multiplied: cool violet.
        static let shadow = RGBA(hex: 0xB9A6D6)
        static let deepShadow = RGBA(hex: 0x8A78B8)
        static let blush = RGBA(hex: 0xF6A9A9)
        // Light is warm.
        static let warm = RGBA(hex: 0xFF9A55)
        static let glow = RGBA(hex: 0xFFD7A0)
        static let rim = RGBA(hex: 0xFF8A3A)
        static let shine = RGBA(hex: 0xE89A7A)
        static let irisDark = RGBA(hex: 0x163A63)
        static let irisLight = RGBA(hex: 0x7FF0E0)
        static let pupil = RGBA(hex: 0x10203A)
        static let lineWarm = RGBA(hex: 0x9A4A3A)
        static let lineGlow = RGBA(hex: 0xD9733F)
        static let dusk = RGBA(hex: 0x2A1E4A)
    }

    // MARK: Sketch

    static func sketch(_ a: Artist) {
        let pen = Pen(width: 3.5, color: Palette.sketch, start: 0.1, end: 0.2, floor: 0.3)
        let rough: [String] = [
            "M -226 -70 C -236 30, -222 100, -178 150 C -120 205, 20 230, 95 222 C 132 205, 168 120, 178 -14",
            "M 200 -90 C 220 -200, 120 -330, -40 -345 C -200 -352, -350 -250, -372 -100 C -384 0, -366 100, -330 200",
            "M -226 -70 Q 0 -150, 214 -26",
            "M -84 -320 Q -60 0, 40 230",
            "M -230 30 Q 0 10, 190 20",
            "M 29 222 L 20 300 L -112 300 L -93 197",
            "M -112 300 C -200 330, -340 400, -580 560",
            "M 196 -84 C 320 -100, 440 -90, 580 -70",
            "M 198 -157 C 320 -180, 440 -180, 580 -170",
            "M 134 194 C 260 240, 400 230, 580 200",
            "M 40 320 C 160 300, 300 310, 400 300",
            "M 40 340 C 160 390, 300 420, 400 430",
            "M 0 320 C 30 400, 30 470, 10 500 C -150 540, -360 600, -600 680",
        ]
        rough.forEach { a.line($0, pen, wobble: 2.5) }
        a.line(PathData.arc(center: CGPoint(x: -84, y: 26), rx: 70, ry: 56, from: 0, to: 360), pen, wobble: 2)
        a.line(PathData.arc(center: CGPoint(x: 106, y: 26), rx: 48, ry: 50, from: 0, to: 360), pen, wobble: 2)
    }

    // MARK: Eyes

    /// The irises on a layer of their own, so their gradient can be clipped to them.
    static func irises(_ a: Artist) {
        a.fill("瞳", nearIris.center.x, nearIris.center.y + 10, Palette.iris, limit: 12000)
        a.fill("瞳", farIris.center.x, farIris.center.y + 10, Palette.iris, limit: 9000)
    }

    static func irisShade(_ a: Artist) {
        for iris in [nearIris, farIris] {
            let c = iris.center
            // Dark under the lid, fading down.
            a.line("M \(c.x - iris.rx) \(c.y - iris.ry * 0.55) Q \(c.x) \(c.y - iris.ry * 0.25), \(c.x + iris.rx) \(c.y - iris.ry * 0.55)",
                   .airbrush(iris.ry * 1.2, Paint.irisDark, opacity: 0.9))
            // The pupil.
            a.line("M \(c.x + 2) \(c.y - 6) L \(c.x + 2) \(c.y + 10)", Pen(width: iris.rx * 0.6, color: Paint.pupil, start: 0, end: 0, floor: 1, opacity: 0.9))
        }
    }

    static func irisLight(_ a: Artist) {
        for iris in [nearIris, farIris] {
            let c = iris.center
            // Light gathering at the bottom of the iris, as in clear water.
            a.line("M \(c.x - iris.rx * 0.6) \(c.y + iris.ry * 0.7) Q \(c.x) \(c.y + iris.ry * 0.5), \(c.x + iris.rx * 0.6) \(c.y + iris.ry * 0.7)",
                   .airbrush(iris.rx * 1.3, Paint.irisLight, opacity: 0.8))
            // A thin ring of reflected light.
            let ring = PathData.arc(center: c, rx: iris.rx * 0.78, ry: iris.ry * 0.8, from: 20, to: 160)
            a.line(ring, Pen(width: 2.5, color: Paint.glow, start: 0.3, end: 0.3, floor: 0.1, opacity: 0.8))
        }
    }

    static func highlights(_ a: Artist) {
        let white = Palette.white
        for (iris, big) in [(nearIris, CGFloat(22)), (farIris, CGFloat(16))] {
            let c = iris.center
            a.dot(c.x + iris.rx * 0.35, c.y - iris.ry * 0.35, diameter: big, color: white)
            a.dot(c.x - iris.rx * 0.4, c.y + iris.ry * 0.38, diameter: big * 0.45, color: white)
            a.dot(c.x + iris.rx * 0.5, c.y + iris.ry * 0.3, diameter: big * 0.25, color: white)
        }
        // Wet light on the lips and the nose.
        a.line("M 88 166 Q 96 168, 104 164", Pen(width: 3, color: white, start: 0.4, end: 0.4, floor: 0.1, opacity: 0.8))
        // Light catching the ribbon as it flies.
        onBody(a) {
            a.line("M 120 336 C 200 322, 280 326, 360 312", Pen(width: 5, color: white, start: 0.4, end: 0.5, floor: 0.05, opacity: 0.7))
            a.line("M 110 388 C 170 412, 250 428, 330 428", Pen(width: 4, color: white, start: 0.4, end: 0.5, floor: 0.05, opacity: 0.55))
            a.dot(52, 340, diameter: 7, color: white)
        }
    }

    // MARK: Shadow

    /// Hard-edged shadows, outlined and filled, made to be multiplied.
    static func shadows(_ a: Artist) {
        let edge = Pen(width: 3, color: Paint.shadow, start: 0, end: 0, floor: 1)
        let big: CGFloat = 400_000
        // The fringe's shadow on the forehead, dipping under each clump.
        a.line("M -231 -30 Q -205 -20, -182 -32 Q -150 -46, -118 -40 Q -84 -48, -50 -42 Q -15 -50, 20 -40 Q 55 -48, 90 -36 Q 120 -42, 150 -28 Q 168 -24, 181 -4", edge)
        a.fill("前髪の影", -85, -70, Paint.shadow, limit: big)
        // The far cheek, turned from the light.
        a.line("M 140 64 C 150 110, 148 170, 112 214", edge)
        a.fill("頬の影", 155, 140, Paint.shadow, limit: big)
        // Under the jaw.
        a.line("M 29 246 C 0 262, -60 256, -95 230", edge)
        a.fill("首の影", -30, 232, Paint.shadow, limit: big)
        // The lower half of the hair.
        a.line("M -392 -60 C -300 -170, -120 -200, 40 -195 C 120 -192, 180 -170, 216 -126", edge)
        a.fill("髪の影", -150, -150, Paint.shadow, limit: big)
        // Under the collar.
        onBody(a) {
            a.line("M 12 541 C -150 594, -360 654, -600 736", edge)
            a.fill("襟の影", -200, 596, Paint.shadow, limit: big)
        }
    }

    /// Soft, deeper shadow where the light cannot reach, and the blush.
    static func deepShadows(_ a: Artist) {
        a.line("M 120 80 C 128 130, 120 180, 96 214", .airbrush(46, Paint.shadow, opacity: 0.5))
        a.line("M 190 -110 C 260 -100, 340 -60, 420 -40", .airbrush(120, Paint.deepShadow, opacity: 0.45))
        a.line("M 150 230 C 260 280, 380 300, 520 300", .airbrush(140, Paint.deepShadow, opacity: 0.6))
        a.line("M -300 160 Q -320 260, -290 340", .airbrush(140, Paint.deepShadow, opacity: 0.6))
        onBody(a) {
            a.line("M -60 330 C -160 380, -300 430, -480 520", .airbrush(120, Paint.deepShadow, opacity: 0.5))
            a.line("M 100 380 C 200 400, 300 420, 380 430", .airbrush(50, Paint.deepShadow, opacity: 0.5))
        }
        // Blush.
        a.line("M -150 110 L -100 118", .airbrush(80, Paint.blush, opacity: 0.7))
        a.line("M 112 112 L 140 110", .airbrush(52, Paint.blush, opacity: 0.6))
    }

    /// Warm light from the sun behind her, on the upper left.
    static func light(_ a: Artist) {
        a.line("M -340 -200 C -300 -290, -200 -340, -60 -340", .airbrush(220, Paint.warm, opacity: 0.8))
        a.line("M -370 -120 C -380 0, -360 120, -320 220", .airbrush(130, Paint.warm, opacity: 0.75))
        a.line("M -120 -300 C -40 -320, 40 -320, 120 -300", .airbrush(140, Paint.warm, opacity: 0.5))
        a.line("M -200 40 C -170 90, -130 150, -80 190", .airbrush(150, Paint.glow, opacity: 0.35))
        a.line("M -215 -40 Q -228 60, -190 140", .airbrush(70, Paint.glow, opacity: 0.8))
        onBody(a) {
            a.line("M -112 320 C -200 345, -340 410, -560 560", .airbrush(70, Paint.warm, opacity: 0.6))
        }
        // Sheen running along the hair as it streams in the wind.
        let shine = Pen(width: 10, color: Paint.shine, start: 0.45, end: 0.5, floor: 0.05, opacity: 0.8)
        let sheen = [
            "M 230 -60 C 320 -70, 420 -62, 540 -50", "M 240 -200 C 330 -214, 430 -214, 540 -206",
            "M 220 100 C 300 120, 400 136, 540 150", "M 200 260 C 300 300, 420 320, 560 330",
            "M 170 420 C 260 480, 360 540, 470 600", "M 260 360 C 340 400, 430 430, 560 450",
            "M -330 -120 C -340 -20, -326 80, -296 160",
        ]
        sheen.forEach { a.line($0, shine) }
    }

    // MARK: Finishing

    /// Lines take on the colour around them: warm in the skin, glowing at the lit edge.
    static func lineColor(_ a: Artist) {
        a.line("M -200 -20 C -180 100, -100 200, 40 230", .airbrush(120, Paint.lineWarm, opacity: 0.7))
        a.line("M -60 0 C 0 -20, 80 -10, 140 20", .airbrush(110, Paint.lineWarm, opacity: 0.5))
        a.line("M -370 -150 C -380 0, -360 120, -320 240", .airbrush(80, Paint.lineGlow, opacity: 0.8))
        a.line("M -330 -260 C -260 -330, -150 -350, -40 -350", .airbrush(80, Paint.lineGlow, opacity: 0.8))
        onBody(a) {
            a.line("M -112 320 C -200 345, -340 410, -560 560", .airbrush(50, Paint.lineGlow, opacity: 0.7))
        }
    }

    /// Thin bright light along every edge facing the sun.
    static func rimLight(_ a: Artist) {
        let rim = Pen(width: 11, color: Paint.rim, start: 0.3, end: 0.4, floor: 0.05, opacity: 0.8)
        a.line("M -60 -338 C -200 -345, -330 -250, -360 -100", rim.with(width: 9))
        a.line("M -366 -60 C -374 40, -358 120, -326 200", rim)
        a.line("M -220 -40 C -230 40, -216 100, -180 146", rim.with(width: 4))
        a.line("M 40 -336 C 100 -338, 160 -300, 190 -240", rim.with(width: 5))
        a.line("M 210 -92 C 300 -104, 420 -98, 560 -84", rim.with(width: 4))
        a.line("M 170 -244 C 290 -266, 420 -268, 560 -256", rim.with(width: 4))
        onBody(a) {
            a.line("M -120 316 C -200 340, -340 404, -560 560", rim.with(width: 8))
            a.line("M -6 334 C 22 400, 26 450, 12 494", rim.with(width: 4))
        }
    }

    /// Specks of light drifting in the evening air, in canvas pixels.
    static func particles(_ a: Artist) {
        var random = SplitMix(seed: 21)
        a.withCanvasCoordinates {
            for _ in 0..<26 {
                let x = random.next() * 1080
                let y = random.next() * 1200
                let size = 6 + random.next() * random.next() * 46
                let color = random.next() < 0.5 ? Paint.glow : Paint.rim
                a.line([CGPoint(x: x, y: y), CGPoint(x: x + 0.5, y: y + 0.5)], .airbrush(size, color, opacity: 0.55 + random.next() * 0.4))
            }
        }
    }

    /// Darker at the edges, so the eye goes to the face.
    static func vignette(_ a: Artist) {
        a.withCanvasCoordinates {
            var clear = Paint.dusk
            clear.a = 0
            var edge = Paint.dusk
            edge.a = 0.75
            a.gradient(.radial, from: CGPoint(x: 470, y: 440), to: CGPoint(x: 1400, y: 440), clear, edge)
        }
    }

    /// The low sun behind her, flooding in from the upper left over everything.
    static func backlight(_ a: Artist) {
        a.withCanvasCoordinates {
            var sun = Paint.warm
            sun.a = 0.8
            var clear = Paint.warm
            clear.a = 0
            a.gradient(.radial, from: CGPoint(x: 30, y: 60), to: CGPoint(x: 620, y: 60), sun, clear)
        }
    }

    /// Wind lines, drawn by a shaky hand to be tidied, in canvas pixels.
    /// Returns where they are.
    static func windLines(_ a: Artist) -> CGRect {
        let pen = Pen(width: 5, color: Paint.glow, start: 0.25, end: 0.4, floor: 0.1)
        var area = CGRect.null
        a.withCanvasCoordinates {
            let lines = [
                "M 760 470 C 840 440, 940 450, 1060 400",
                "M 720 560 C 820 540, 940 548, 1070 500",
                "M 800 640 C 880 620, 960 626, 1060 590",
            ]
            var random = SplitMix(seed: 5)
            for line in lines {
                // A hand that shakes: small, quick wobbles along the line.
                let smooth = PathData.points(line)
                let shaky = smooth.enumerated().map { index, point -> CGPoint in
                    let wave = sin(CGFloat(index) * 0.9) * 3.5 + (random.next() - 0.5) * 5
                    return CGPoint(x: point.x, y: point.y + wave)
                }
                a.line(shaky, pen)
                for point in smooth { area = area.union(CGRect(origin: point, size: .zero)) }
            }
        }
        return area.insetBy(dx: -40, dy: -60)
    }
}

// MARK: Named colours

extension Portrait {
    /// The picture's colours given names, kept as an evening set, with a
    /// night set beside it. The picture stays as it was, in the evening.
    /// Returns the two sets.
    @discardableResult
    static func nameColors(_ document: CanvasDocument) -> (evening: UUID, night: UUID) {
        func gradients(where test: (GradientItem) -> Bool) -> [Int] {
            document.layers.flatMap(\.items).compactMap { item in
                if case .gradient(let gradient) = item, test(gradient) { return gradient.id }
                return nil
            }
        }
        func same(_ a: RGBA, _ b: RGBA) -> Bool { abs(a.r - b.r) < 0.004 && abs(a.g - b.g) < 0.004 && abs(a.b - b.b) < 0.004 }
        // The sky's two ends are two names.
        let sky = gradients { same($0.from, Palette.skyTop) }
        let top = document.addSwatch(named: "空の上", color: Palette.skyTop)
        document.bind(sky, to: top, gradientEnd: .start)
        let low = document.addSwatch(named: "空の下", color: Palette.skyLow)
        document.bind(sky, to: low, gradientEnd: .end)
        // Every other colour of the light and the shade, wherever it is used.
        let named: [(String, RGBA, RGBA)] = [
            ("光源", Palette.sun, RGBA(hex: 0xCFE4FF)),
            ("光", Paint.warm, RGBA(hex: 0x6E8FD8)),
            ("淡い光", Paint.glow, RGBA(hex: 0xD6E6FF)),
            ("縁の光", Paint.rim, RGBA(hex: 0x8FB6FF)),
            ("影", Paint.shadow, RGBA(hex: 0x9FA8DA)),
            ("深い影", Paint.deepShadow, RGBA(hex: 0x6A70B0)),
            ("闇", Paint.dusk, RGBA(hex: 0x03061A)),
            ("線の明かり", Paint.lineGlow, RGBA(hex: 0x5A78C8)),
            ("髪のつや", Paint.shine, RGBA(hex: 0x8C9CC8)),
        ]
        var night: [(UUID, RGBA)] = [(top, RGBA(hex: 0x0B1030)), (low, RGBA(hex: 0x2A3A78))]
        for (name, color, dark) in named {
            let swatch = document.addSwatch(named: name, color: color)
            document.bind(document.items(coloured: color), to: swatch)
            night.append((swatch, dark))
        }
        let evening = document.saveTheme(named: "夕方")
        for (swatch, color) in night { document.setSwatchColor(swatch, color) }
        let nightTheme = document.saveTheme(named: "夜")
        document.applyTheme(evening)
        return (evening, nightTheme)
    }
}
