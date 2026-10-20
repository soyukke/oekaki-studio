import CoreGraphics
import Foundation
import OekakiKit

/// 「一口食べる？」: a girl in a family restaurant leans across the table and
/// holds a spoon of mint chocolate-chip ice cream out to the viewer.
///
/// Drawn the way an illustrator works: the rough, then the lines, the flat
/// colours, the shadows, the background, the light, and the finish. Each part
/// of the figure has layers of its own, nearer parts over farther ones, so a
/// part is coloured with only its own lines showing.
///
/// The script is written on a 1000 × 1250 sheet and drawn `unit` times larger.
enum Bite {
    static let sheet = CGSize(width: 1000, height: 1250)

    /// The phases of the making, in order, for the film.
    enum Phase: String, CaseIterable {
        case rough = "ラフ"
        case lines = "線画"
        case flats = "下塗り"
        case shadows = "影"
        case background = "背景"
        case light = "光"
        case finish = "仕上げ"
    }

    struct Result {
        let document: CanvasDocument
        /// The journal step that ends each phase, counted after flushing.
        var phaseEnds: [Phase: Int] = [:]
        var problems: [String] = []
    }

    // MARK: Colours

    /// Every colour of the picture, by what it is for.
    struct Colors {
        var name = "ミントの昼"
        // Hair: mint, deeper inside.
        var hair = RGBA(hex: 0x8CE2CB)
        var hairShade = RGBA(hex: 0x56B8AC)
        var hairDeep = RGBA(hex: 0x3B8E98)
        var hairLight = RGBA(hex: 0xEAFFF9)
        var inner = RGBA(hex: 0x2A6B66)
        var innerShade = RGBA(hex: 0x1F524E)
        var hairLine = RGBA(hex: 0x2C5B62)
        // Skin.
        var skin = RGBA(hex: 0xFFEAE0)
        var skinShade = RGBA(hex: 0xF7BDB0)
        var skinDeep = RGBA(hex: 0xE8908A)
        var blush = RGBA(hex: 0xFF8A9C)
        var skinLine = RGBA(hex: 0x8C4A44)
        // Eyes.
        var iris = RGBA(hex: 0x2FA6A6)
        var irisDeep = RGBA(hex: 0x16485A)
        var irisLight = RGBA(hex: 0xA8F5DC)
        var eyeWhite = RGBA(hex: 0xFFFDFB)
        var eyeLine = RGBA(hex: 0x2B2230)
        var mouth = RGBA(hex: 0xC04E62)
        var tongue = RGBA(hex: 0xF2919C)
        // Clothes.
        var blouse = RGBA(hex: 0xFFFFFF)
        var blouseShade = RGBA(hex: 0xD7E4EE)
        var knit = RGBA(hex: 0xFBF1E1)
        var knitShade = RGBA(hex: 0xE3CDB4)
        var ribbon = RGBA(hex: 0x6E4636)
        var clothLine = RGBA(hex: 0x6B5650)
        // The spoon and the ice cream.
        var metal = RGBA(hex: 0xE8EDF2)
        var metalShade = RGBA(hex: 0xB5BCC6)
        var metalWarm = RGBA(hex: 0xFFD8A6)
        var metalLine = RGBA(hex: 0x6F7884)
        var cream = RGBA(hex: 0xB4E4CC)
        var creamShade = RGBA(hex: 0x86C2A9)
        /// The top of the scoop, toward the light.
        var creamLight = RGBA(hex: 0xD6F2E4)
        /// Where it has begun to melt, at its foot.
        var creamMelt = RGBA(hex: 0xD9F3E7)
        var chip = RGBA(hex: 0x3B2419)
        var chipEdge = RGBA(hex: 0x5C3B2A)
        var creamLine = RGBA(hex: 0x5F9E88)
        // The restaurant and the light.
        var wall = RGBA(hex: 0xF4E4CF)
        var wallShade = RGBA(hex: 0xC9A88E)
        var booth = RGBA(hex: 0x7C3C47)
        var boothShade = RGBA(hex: 0x4E1824)
        var wood = RGBA(hex: 0xB9825A)
        var table = RGBA(hex: 0xFFF8EE)
        var tableShade = RGBA(hex: 0xD9C6B4)
        var sky = RGBA(hex: 0xDDF2FF)
        var skyTop = RGBA(hex: 0x9CD4F5)
        var skyLow = RGBA(hex: 0xFFF9EC)
        var treeShade = RGBA(hex: 0x6FB07A)
        var treeLight = RGBA(hex: 0xB7E08A)
        /// Night outside: the town's lights instead of trees in the sun.
        var night = false
        var leaves = RGBA(hex: 0x9FD08A)
        /// A cherry soda: its pink answers the mint without fighting it.
        var soda = RGBA(hex: 0xF58FA8)
        var sun = RGBA(hex: 0xFFE7B8)
        var glow = RGBA(hex: 0xFFF6E2)
        var lamp = RGBA(hex: 0xFFD08A)
        var deep = RGBA(hex: 0x5A4660)
        var sketch = RGBA(hex: 0x5E9CD6)
    }

    static let mintDay = Colors()

    /// Strawberry milk in the evening sun.
    static let strawberryEvening: Colors = {
        var c = Colors()
        c.name = "いちごの夕方"
        c.hair = RGBA(hex: 0xF7AFC4); c.hairShade = RGBA(hex: 0xDB7C9E); c.hairDeep = RGBA(hex: 0xB0507A); c.hairLight = RGBA(hex: 0xFFEAF2)
        c.inner = RGBA(hex: 0x7A3A44); c.innerShade = RGBA(hex: 0x52222E); c.hairLine = RGBA(hex: 0x7A3450)
        c.iris = RGBA(hex: 0xE2648C); c.irisDeep = RGBA(hex: 0x7A1F42); c.irisLight = RGBA(hex: 0xFFD2DE)
        c.cream = RGBA(hex: 0xF7B8C8); c.creamShade = RGBA(hex: 0xE08AA4); c.creamLight = RGBA(hex: 0xFFE0E8); c.creamMelt = RGBA(hex: 0xFFEAF0); c.chip = RGBA(hex: 0xC2304F); c.chipEdge = RGBA(hex: 0xE8708A); c.creamLine = RGBA(hex: 0x9A3A5A)
        c.ribbon = RGBA(hex: 0xC94A6A)
        c.skyTop = RGBA(hex: 0xF6A07A); c.skyLow = RGBA(hex: 0xFFE7BC); c.treeShade = RGBA(hex: 0xB0806A); c.treeLight = RGBA(hex: 0xF0C08C)
        c.sun = RGBA(hex: 0xFFC690); c.glow = RGBA(hex: 0xFFE4C8); c.lamp = RGBA(hex: 0xFFC27A); c.deep = RGBA(hex: 0x6A3A5A)
        c.soda = RGBA(hex: 0x9AD86E); c.metalWarm = RGBA(hex: 0xFFC79E)
        return c
    }()

    /// Vanilla at night, by the lamp, the town's lights in the window.
    static let vanillaNight: Colors = {
        var c = Colors()
        c.name = "夜のバニラ"
        c.hair = RGBA(hex: 0xB9AAF0); c.hairShade = RGBA(hex: 0x8C7DD2); c.hairDeep = RGBA(hex: 0x6252A8); c.hairLight = RGBA(hex: 0xF2EEFF)
        c.inner = RGBA(hex: 0x4A3A6A); c.innerShade = RGBA(hex: 0x2E2448); c.hairLine = RGBA(hex: 0x3A2E6A)
        c.iris = RGBA(hex: 0xE0A040); c.irisDeep = RGBA(hex: 0x7A4310); c.irisLight = RGBA(hex: 0xFFE7A8)
        c.cream = RGBA(hex: 0xF4E2BC); c.creamShade = RGBA(hex: 0xD8B482); c.creamLight = RGBA(hex: 0xFFF6E0); c.creamMelt = RGBA(hex: 0xFFF8EA); c.chip = RGBA(hex: 0x3A2418); c.chipEdge = RGBA(hex: 0x6E4B36); c.creamLine = RGBA(hex: 0x8A6A3A)
        c.ribbon = RGBA(hex: 0x5A4A8A)
        c.wall = RGBA(hex: 0xB8A09A); c.wallShade = RGBA(hex: 0x5A4A66); c.booth = RGBA(hex: 0x6A2238); c.boothShade = RGBA(hex: 0x340E22)
        c.table = RGBA(hex: 0xF2E8EE); c.tableShade = RGBA(hex: 0xB8A4B8)
        c.skyTop = RGBA(hex: 0x1C2150); c.skyLow = RGBA(hex: 0x4E3E80); c.treeShade = RGBA(hex: 0x252C4E); c.treeLight = RGBA(hex: 0x3A4470)
        c.night = true
        c.sun = RGBA(hex: 0xFFD49A); c.glow = RGBA(hex: 0xFFE8C8); c.lamp = RGBA(hex: 0xFFC478); c.deep = RGBA(hex: 0x1E1838)
        c.soda = RGBA(hex: 0x6AB8F0); c.metalWarm = RGBA(hex: 0xFFD49A)
        return c
    }()

    // MARK: Parts

    /// One part of the figure on layers of its own: the flat colours at the
    /// bottom, shadows and light clipped to them, the lines on top.
    struct Part {
        let name: String
        let lines: UUID
        var base: UUID?
        var shade: UUID?
        var deep: UUID?
        var light: UUID?
    }

    /// Draws the picture in `colors`, written on the sheet and drawn `unit` times
    /// larger, as far as the end of `last`.
    static func draw(_ colors: Colors = mintDay, unit: CGFloat = 2, through last: Phase = .finish) -> Result {
        let width = Int(sheet.width * unit), height = Int(sheet.height * unit)
        let document = CanvasDocument(width: width, height: height)
        let a = Artist(document: document)
        a.unit = unit
        let studio = Studio(a: a, c: colors)
        studio.make(through: last)
        var result = Result(document: document)
        result.phaseEnds = studio.phaseEnds
        result.problems = a.problems
        return result
    }
}

/// The making of the picture, phase by phase.
final class Studio {
    let a: Artist
    let c: Bite.Colors
    var document: CanvasDocument { a.document }
    private(set) var phaseEnds: [Bite.Phase: Int] = [:]
    var parts: [String: Bite.Part] = [:]
    private let paper: UUID

    init(a: Artist, c: Bite.Colors) {
        self.a = a
        self.c = c
        paper = a.document.activeLayerID
        a.document.renameLayer(paper, to: "背景")
    }

    /// Where the head sits: written around the middle of the skull, leaning.
    static let head = CGAffineTransform(translationX: 470, y: 520).rotated(by: -10 * .pi / 180).scaledBy(x: 1.18, y: 1.18)
    /// The body leans a little less than the head, its shoulders drawn up as she leans in.
    static let body = CGAffineTransform(translationX: 468, y: 452).rotated(by: -6 * .pi / 180).scaledBy(x: 1.06, y: 1.0)

    func onHead(_ body: () -> Void) {
        let saved = a.transform
        a.transform = Self.head
        body()
        a.transform = saved
    }

    func onBody(_ body: () -> Void) {
        let saved = a.transform
        a.transform = Self.body
        body()
        a.transform = saved
    }

    /// What she holds out, drawn larger the nearer it comes (see `Near.lens`).
    func onNear(_ body: () -> Void) {
        let saved = a.warp
        a.warp = Near.lens
        body()
        a.warp = saved
    }

    private func end(_ phase: Bite.Phase) {
        document.flushJournal()
        phaseEnds[phase] = document.journal.count - 1
    }

    func make(through last: Bite.Phase = .finish) {
        let steps: [(Bite.Phase, () -> Void)] = [
            (.rough, rough), (.lines, lines), (.flats, flats), (.shadows, shadows),
            (.background, background), (.light, light), (.finish, finish),
        ]
        for (phase, work) in steps {
            work()
            end(phase)
            if phase == last { return }
        }
    }

    // MARK: Background

    /// Adds a layer just above the paper and the background layers made before it.
    private func behind(_ name: String, style: LayerStyle = LayerStyle()) -> UUID {
        let above = document.layers.firstIndex { $0.name == "ラフ" } ?? 1
        return a.layer(name, style: style, below: document.layers[above].id)
    }

    func background() {
        let outside = behind("窓の外", style: LayerStyle(blur: 9))
        a.use(outside)
        Room.outside(a, c)
        a.use(behind("店", style: LayerStyle(blur: 5)))
        Room.room(a, c)
        a.use(behind("店の影", style: LayerStyle(blend: .multiply, isClipped: true)))
        Room.shading(a, c)
        a.use(behind("店の光", style: LayerStyle(blend: .screen, isClipped: true)))
        Room.lights(a, c)
        a.use(behind("ボケ", style: LayerStyle(blend: .add, blur: 3)))
        Room.bokeh(a, c)
        // The table in front of her body, behind all she holds out.
        guard let nearest = parts["下の手"]?.base else { return }
        a.use(a.layer("テーブル", style: LayerStyle(blur: 2.5), below: nearest))
        Room.table(a, c)
        a.use(a.layer("テーブルの陰影", style: LayerStyle(isClipped: true), below: nearest))
        Room.tableShading(a, c)
    }

    // MARK: Rough

    private var roughLayer: UUID?

    func rough() {
        roughLayer = a.layer("ラフ", opacity: 0.85)
        let loose = Pen(width: 2.2, color: c.sketch, start: 0.2, end: 0.3, floor: 0.3, opacity: 0.9)
        let guide = loose.with(width: 1.4, opacity: 0.55)
        onHead {
            // The skull, the middle of the face turned toward the left, the line of the eyes.
            a.line(PathData.arc(center: .zero, rx: 215, ry: 225, from: 0, to: 360), guide, wobble: 2)
            a.line("M -40 -230 C -70 -120, -62 80, -42 246", guide, wobble: 1.5)
            a.line("M -230 58 C -100 70, 60 66, 230 40", guide, wobble: 1.5)
            for path in Head.faceOutline + [Head.nearEye.lash, Head.farEye.lash, Head.mouthTop, Head.mouthBottom] {
                a.line(path, loose, wobble: 2.5)
            }
            for path in Head.hairOutline + Head.bangLocks {
                a.line(path, loose, wobble: 3)
            }
        }
        onBody {
            for path in Body.roughLines { a.line(path, loose, wobble: 3) }
        }
        onNear {
            for points in Near.roughLines { a.line(points, loose, wobble: 3) }
        }
        for path in Room.roughLines { a.line(path, loose, wobble: 3) }
    }

    // MARK: Lines

    /// Makes the part's line layer on top, or returns it.
    @discardableResult
    func part(_ name: String) -> Bite.Part {
        if let part = parts[name] { return part }
        let made = Bite.Part(name: name, lines: a.layer("\(name)の線"))
        parts[name] = made
        return made
    }

    /// Makes the part's colour layer under its lines, with its shadow and
    /// light layers clipped to it, all at once so they stay in this order.
    @discardableResult
    func colors(_ name: String, extra: [(String, BlendMode)] = []) -> Bite.Part {
        var part = self.part(name)
        if let base = part.base { return part }
        let base = a.layer(name, below: part.lines)
        part.base = base
        // The room's dimness over the whole part, so the light can be added back where it falls.
        a.layer("\(name)の陰", style: LayerStyle(blend: .multiply, isClipped: true), below: part.lines)
        part.shade = a.layer("\(name)の影", style: LayerStyle(blend: .multiply, isClipped: true), below: part.lines)
        part.deep = a.layer("\(name)の濃い影", style: LayerStyle(blend: .multiply, isClipped: true), below: part.lines)
        for (layer, blend) in extra {
            a.layer("\(name)の\(layer)", style: LayerStyle(blend: blend, isClipped: true), below: part.lines)
        }
        part.light = a.layer("\(name)の光", style: LayerStyle(blend: .screen, isClipped: true), below: part.lines)
        parts[name] = part
        a.use(base)
        return part
    }

    /// A layer of the part by its own name, such as 「髪の透け」.
    func layer(of part: String, _ name: String) -> UUID? {
        document.layers.first { $0.name == "\(part)の\(name)" }?.id
    }

    func flats() {
        colors("後ろ髪")
        onHead { Head.backFlats(a, c) }
        colors("体")
        onBody { Body.flats(a, c) }
        let face = colors("顔")
        onHead { Head.faceFlats(a, c) }
        // The eyes on layers of their own, over the skin and under the face's lines:
        // the white with the lid's shadow on it, then the iris cut to the white,
        // with its own darks and lights.
        a.layer("白目", below: face.lines)
        onHead { Head.whites(a, c) }
        a.layer("白目の影", style: LayerStyle(blend: .multiply, isClipped: true), below: face.lines)
        a.layer("瞳", below: face.lines)
        onHead { Head.irises(a, c) }
        a.layer("瞳の影", style: LayerStyle(blend: .multiply, isClipped: true), below: face.lines)
        a.layer("瞳の光", style: LayerStyle(blend: .screen, isClipped: true), below: face.lines)
        a.layer("目の輝き", below: face.lines)
        let hair = colors("髪", extra: [("毛先", .normal), ("透け", .normal)])
        onHead { Head.hairFlats(a, c) }
        // The brows just over the fringe's lines, faint, so they show through it.
        if let lines = document.index(ofLayer: hair.lines) {
            a.layer("眉", opacity: 0.6, below: document.layers[lines + 1].id)
        }
        onHead {
            for eye in [Head.nearEye, Head.farEye] {
                a.ribbon(eye.brow, c.hairLine.mixed(with: c.hairDeep, 0.3), width: Ribbon.leaf(3.4 * eye.weight, at: 0.35))
            }
        }
        colors("下の手")
        onNear { Near.otherFlats(a, c) }
        colors("腕")
        onNear { Near.armFlats(a, c) }
        colors("袖口")
        onNear { Near.cuffFlats(a, c) }
        colors("スプーン")
        onNear { Near.spoonFlats(a, c) }
        colors("指")
        onNear { Near.fingerFlats(a, c) }
        colors("アイス")
        onNear { Near.scoopFlats(a, c) }
        colors("スプーンの縁")
        onNear { Near.lipFlats(a, c) }
        colors("しずく")
        onNear { Near.dripFlats(a, c) }
    }

    func lines() {
        // The figure, back to front: the hair behind, the body, the face, the hair in front.
        let back = part("後ろ髪")
        a.use(back.lines)
        onHead { Head.backHairLines(a, c) }
        let body = part("体")
        a.use(body.lines)
        onBody { Body.lines(a, c) }
        let face = part("顔")
        a.use(face.lines)
        onHead { Head.faceLines(a, c) }
        let hair = part("髪")
        a.use(hair.lines)
        onHead { Head.hairLines(a, c) }
        // Nearest of all: her other hand waiting under the spoon, the arm reaching
        // out, the spoon, the thumb on it, the cuff, the ice cream.
        onNear {
            a.use(part("下の手").lines)
            Near.otherLines(a, c)
            a.use(part("腕").lines)
            Near.armLines(a, c)
            a.use(part("袖口").lines)
            Near.cuffLines(a, c)
            a.use(part("スプーン").lines)
            Near.spoonLines(a, c)
            a.use(part("指").lines)
            Near.fingerLines(a, c)
            a.use(part("アイス").lines)
            Near.scoopLines(a, c)
            a.use(part("スプーンの縁").lines)
            Near.lipLines(a, c)
            a.use(part("しずく").lines)
            Near.dripLines(a, c)
        }
        if let roughLayer { document.setLayerVisible(roughLayer, false) }
    }
}
