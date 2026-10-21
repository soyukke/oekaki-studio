import CoreGraphics
import Foundation

/// Picks the Japanese or English wording for the user's language.
public func L(_ ja: String, _ en: String) -> String {
    Localization.isJapanese ? ja : en
}

public enum Localization {
    /// Set `OEKAKI_LANG=en` or `ja` to override the system language.
    public static let isJapanese: Bool = {
        let forced = ProcessInfo.processInfo.environment["OEKAKI_LANG"]
        let language = forced ?? Locale.preferredLanguages.first ?? "en"
        return language.hasPrefix("ja")
    }()
}

/// A colour in sRGB, components 0...1.
public struct RGBA: Codable, Equatable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: UInt32) {
        self.init(r: Double(hex >> 16 & 0xFF) / 255, g: Double(hex >> 8 & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let white = RGBA(r: 1, g: 1, b: 1)

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// One sample of a stroke, in canvas pixels with the origin at the top left.
public struct StrokePoint: Equatable {
    public var x: CGFloat
    public var y: CGFloat
    /// 0...1. A mouse reports 1 throughout.
    public var pressure: CGFloat

    public init(x: CGFloat, y: CGFloat, pressure: CGFloat = 1) {
        self.x = x
        self.y = y
        self.pressure = pressure
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
}

public struct Stroke {
    /// Unique within a document, shared with the other kinds of item. Kept so
    /// strokes can be told apart later, for example when sorting them into layers.
    public var id: Int
    public var points: [StrokePoint]
    public var color: RGBA
    /// Width in canvas pixels at full pressure.
    public var width: CGFloat
    public var isEraser: Bool
    /// How much the whole stroke covers, 0...1. Where the stroke crosses
    /// itself it does not get darker.
    public var opacity: CGFloat = 1
    /// 0 for a hard edge; up to 1 for an airbrush whose edge fades out.
    public var softness: CGFloat = 0
    /// The named colour the stroke takes its colour from, if any.
    public var colorRef: UUID?

    /// Drawn the plain way, a piece at a time straight onto the layer.
    var isPlain: Bool { opacity >= 1 && softness <= 0 }
}

/// The result of one paint-bucket fill, cropped to the area it touched.
public struct FillItem {
    /// Unique within a document; 0 until the document numbers it.
    public var id = 0
    /// Where the masks sit on the canvas, in whole pixels.
    public var rect: CGRect
    /// The filled region plus a thin ring that tucks under the outline.
    public var full: CGImage
    /// The filled region itself.
    public var interior: CGImage
    public var color: RGBA
    /// The point that was clicked. Nil in files saved before it was kept.
    public var seed: CGPoint?
    /// The named colour the fill takes its colour from, if any.
    public var colorRef: UUID?
}

/// A colour that fades into another across the whole layer.
public struct GradientItem {
    public enum Shape: String, CaseIterable {
        /// Changes along the line from `start` to `end`.
        case linear
        /// Spreads out from `start`; `end` is on the outer edge.
        case radial
    }

    public var id = 0
    public var shape: Shape
    /// Canvas points.
    public var start: CGPoint
    public var end: CGPoint
    /// The colour at `start` and at `end`; either may be transparent.
    public var from: RGBA
    public var to: RGBA
    /// The named colours the two ends take their colours from, if any.
    public var fromRef: UUID?
    public var toRef: UUID?

    public init(id: Int = 0, shape: Shape, start: CGPoint, end: CGPoint, from: RGBA, to: RGBA) {
        self.id = id
        self.shape = shape
        self.start = start
        self.end = end
        self.from = from
        self.to = to
    }
}

/// Items kept together as they were on a layer, for example a layer merged
/// into the one below. The items stay editable; the alpha is the opacity
/// the layer had.
public struct GroupItem {
    public var id = 0
    public var name: String
    public var items: [LayerItem]
    public var alpha: CGFloat
}

/// Where a part is put on the canvas: centred on `center`, scaled, turned
/// `rotation` degrees clockwise, and mirrored left to right if `flipped`.
public struct Placement: Equatable {
    public var center: CGPoint
    public var scale: CGFloat = 1
    public var rotation: CGFloat = 0
    public var flipped = false

    public init(center: CGPoint, scale: CGFloat = 1, rotation: CGFloat = 0, flipped: Bool = false) {
        self.center = center
        self.scale = scale
        self.rotation = rotation
        self.flipped = flipped
    }

    /// From the part's own coordinates, centred on (0, 0), to the canvas.
    public var transform: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotation * .pi / 180)
            .scaledBy(x: flipped ? -scale : scale, y: scale)
    }
}

/// One use of a part. What it draws is the part's items, placed and
/// coloured for this use; the document keeps them up to date when the part
/// or its colours change.
public struct InstanceItem {
    public var id = 0
    /// The part it shows.
    public var component: UUID
    public var placement: Placement
    /// Colours for this use only, by named colour.
    public var overrides: [UUID: RGBA] = [:]
    /// Which of the part's drawings it shows; nil for the first.
    public var look: UUID?
    /// The part's items as this use draws them, in the same order.
    public var content: [LayerItem] = []

    public init(id: Int = 0, component: UUID, placement: Placement, overrides: [UUID: RGBA] = [:], look: UUID? = nil, content: [LayerItem] = []) {
        self.id = id
        self.component = component
        self.placement = placement
        self.overrides = overrides
        self.look = look
        self.content = content
    }
}

/// A colour with a name, which lines, fills and gradients can take their
/// colour from, so changing it changes all of them.
public struct Swatch: Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: RGBA

    public init(id: UUID = UUID(), name: String, color: RGBA) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// A set of values for the named colours, such as evening or night.
public struct ColorTheme: Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var colors: [UUID: RGBA]

    public init(id: UUID = UUID(), name: String, colors: [UUID: RGBA]) {
        self.id = id
        self.name = name
        self.colors = colors
    }
}

/// One drawing of a part, such as its front, its side or its smile.
public struct ComponentLook: Identifiable {
    public var id: UUID
    /// Empty for a part's first drawing until it is given a name.
    public var name: String
    public var items: [LayerItem]

    public init(id: UUID = UUID(), name: String = "", items: [LayerItem]) {
        self.id = id
        self.name = name
        self.items = items
    }

    /// The name to show.
    public var title: String { name.isEmpty ? L("もと", "Original") : name }
}

/// A part: items drawn once, which can be put on the canvas many times.
/// It may hold several drawings of the same thing, like a character sheet;
/// each use shows one of them. Its items are in its own coordinates,
/// centred on (0, 0).
public struct Component: Identifiable {
    public var id: UUID
    public var name: String
    /// Never empty. A use shows the first unless it picks another.
    public var looks: [ComponentLook]

    public init(id: UUID = UUID(), name: String, items: [LayerItem]) {
        self.init(id: id, name: name, looks: [ComponentLook(items: items)])
    }

    public init(id: UUID = UUID(), name: String, looks: [ComponentLook]) {
        self.id = id
        self.name = name
        self.looks = looks.isEmpty ? [ComponentLook(items: [])] : looks
    }

    /// Where the drawing `look` is, or the first when there is no such drawing.
    public func lookIndex(_ look: UUID?) -> Int {
        look.flatMap { id in looks.firstIndex { $0.id == id } } ?? 0
    }

    /// The items of the drawing `look`, or of the first.
    public func items(for look: UUID?) -> [LayerItem] {
        looks[lookIndex(look)].items
    }

    /// The items of every drawing.
    public var allItems: [LayerItem] { looks.flatMap(\.items) }
}

/// What a picture keeps besides its layers: named colours, colour sets, parts.
public struct Library {
    public var swatches: [Swatch] = []
    public var themes: [ColorTheme] = []
    public var components: [Component] = []
    /// The colour set last chosen, if any.
    public var currentTheme: UUID?
    /// Changes whenever anything in it changes.
    var revision = 0

    public init() {}

    public var isEmpty: Bool { swatches.isEmpty && themes.isEmpty && components.isEmpty }

    public func swatch(_ id: UUID) -> Swatch? { swatches.first { $0.id == id } }
    public func component(_ id: UUID) -> Component? { components.first { $0.id == id } }
}

/// What a layer is made of, in the order it was drawn.
///
/// Like the lines of a program, every item can be found, read and changed
/// after it was made; the layer's pixels are only the result of running them.
public enum LayerItem {
    case stroke(Stroke)
    /// A canvas-sized picture that has no steps behind it, such as the result
    /// of tidying colour or a picture from the assistant.
    case bitmap(CGImage, alpha: CGFloat, id: Int = 0)
    case fill(FillItem)
    case group(GroupItem)
    case gradient(GradientItem)
    /// One use of a part.
    case instance(InstanceItem)

    public var id: Int {
        switch self {
        case .stroke(let stroke): return stroke.id
        case .bitmap(_, _, let id): return id
        case .fill(let fill): return fill.id
        case .group(let group): return group.id
        case .gradient(let gradient): return gradient.id
        case .instance(let instance): return instance.id
        }
    }

    /// The colour, for the kinds of item that have one.
    public var color: RGBA? {
        get {
            switch self {
            case .stroke(let stroke): return stroke.isEraser ? nil : stroke.color
            case .fill(let fill): return fill.color
            case .gradient(let gradient): return gradient.from
            case .bitmap, .group, .instance: return nil
            }
        }
        set {
            guard let newValue else { return }
            switch self {
            // A colour given directly replaces the named colour it came from.
            case .stroke(var stroke) where !stroke.isEraser:
                stroke.color = newValue
                stroke.colorRef = nil
                self = .stroke(stroke)
            case .fill(var fill):
                fill.color = newValue
                fill.colorRef = nil
                self = .fill(fill)
            case .gradient(var gradient):
                gradient.from = newValue
                gradient.fromRef = nil
                self = .gradient(gradient)
            default:
                break
            }
        }
    }

    /// The opacity, for pictures, groups, and strokes drawn see-through.
    public var alpha: CGFloat? {
        get {
            switch self {
            case .bitmap(_, let alpha, _): return alpha
            case .group(let group): return group.alpha
            case .stroke(let stroke): return stroke.isPlain ? nil : stroke.opacity
            case .fill, .gradient, .instance: return nil
            }
        }
        set {
            guard let newValue else { return }
            let clamped = min(max(newValue, 0), 1)
            switch self {
            case .bitmap(let image, _, let id): self = .bitmap(image, alpha: clamped, id: id)
            case .group(var group):
                group.alpha = clamped
                self = .group(group)
            case .stroke(var stroke) where !stroke.isPlain:
                stroke.opacity = clamped
                self = .stroke(stroke)
            case .stroke, .fill, .gradient, .instance: break
            }
        }
    }

    /// The items inside a group or a use of a part; empty for everything else.
    public var children: [LayerItem] {
        switch self {
        case .group(let group): return group.items
        case .instance(let instance): return instance.content
        default: return []
        }
    }

    /// This item and everything inside it, front-most last.
    public var flattened: [LayerItem] {
        [self] + children.flatMap(\.flattened)
    }
}

/// How a layer's pixels are put onto the layers below it.
public enum BlendMode: String, CaseIterable, Identifiable {
    case normal
    /// Darkens: for shadows.
    case multiply
    /// Lightens softly: for light.
    case screen
    /// Lightens strongly, toward white: for glare and glowing light.
    case add
    /// Deepens contrast: darkens the dark and lightens the light.
    case overlay

    public var id: String { rawValue }

    /// What the mode does to the colours below, with its usual name after it
    /// for people who know it. Named by what it does, not by what it is often
    /// used for, so it stays true whatever it is used for.
    public var title: String {
        switch self {
        case .normal: return L("通常", "Normal")
        case .multiply: return L("暗く重ねる（乗算）", "Darken (Multiply)")
        case .screen: return L("明るく重ねる（スクリーン）", "Lighten (Screen)")
        case .add: return L("足して明るく（加算）", "Add Up (Add)")
        case .overlay: return L("明暗を残して混ぜる（オーバーレイ）", "Mix, Keeping Light and Dark (Overlay)")
        }
    }

    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .add: return .plusLighter
        case .overlay: return .overlay
        }
    }
}

/// How a layer is shown, apart from what is drawn on it.
public struct LayerStyle: Equatable {
    public var blend: BlendMode = .normal
    /// Shows only where the nearest unclipped layer below has paint.
    public var isClipped = false
    /// How far the layer's light spreads around it, in canvas pixels; 0 for none.
    public var glow: CGFloat = 0
    /// How far the layer is blurred, in canvas pixels; 0 for sharp. With layers
    /// clipped to it, the blur takes them too, like things out of focus.
    public var blur: CGFloat = 0
    /// How far apart the dots are when the layer's paint is turned into dots,
    /// like the screen tone of comics, in canvas pixels; 0 for no dots. The
    /// darker the paint, the bigger the dots. With layers clipped to it, they
    /// turn into dots too.
    public var tone: CGFloat = 0

    public init(blend: BlendMode = .normal, isClipped: Bool = false, glow: CGFloat = 0, blur: CGFloat = 0, tone: CGFloat = 0) {
        self.blend = blend
        self.isClipped = isClipped
        self.glow = glow
        self.blur = blur
        self.tone = tone
    }
}

public struct Layer: Identifiable {
    public let id: UUID
    public var name: String
    public var isVisible = true
    public var opacity: Double = 1
    /// A sheet for planning the picture: its lines show while drawing and in
    /// the picture made for a commission, but not in the finished picture.
    public var isComposition = false
    public var style = LayerStyle()
    public var items: [LayerItem] = []
    /// Changes whenever `items` changes; equal revisions mean equal pixels.
    var revision = 0

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public enum Tool: String, CaseIterable, Identifiable {
    /// Clicking something on the canvas finds the item that drew it.
    case select
    case brush
    /// A soft brush whose edge fades out.
    case airbrush
    case eraser
    case fill
    /// Drag round an area to fill it, without lines: the lasso fill.
    case shape
    /// Drag from where one colour starts to where it fades out.
    case gradient
    case eyedropper
    /// Posing the guide doll.
    case figure

    public var id: String { rawValue }
}
