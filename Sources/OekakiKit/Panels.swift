import CoreGraphics
import Foundation

/// One cut of a comic page, like a ruler line across a sheet: it splits a
/// panel in two, and each half may be cut again.
public struct PanelCut: Codable, Equatable {
    /// True for a cut straight across, with one panel above the other;
    /// false for a cut down, with the two side by side.
    public var across = false
    /// Where the cut is in the panel it splits, 0...1: from the top for a cut
    /// across, from the left for a cut down.
    public var at = 0.5
    /// Empty for a panel that is not cut. Otherwise the two halves in the
    /// order they are read: the top before the bottom, the right before the left.
    public var halves: [PanelCut] = []

    public init() {}

    /// How many panels it makes.
    public var count: Int { halves.isEmpty ? 1 : halves.reduce(0) { $0 + $1.count } }
}

/// How a comic page is divided into panels, and how the frames look. The
/// panels come in reading order: right to left, top to bottom.
public struct PanelLayout: Codable, Equatable {
    /// From the edge of the page to the panels, in canvas pixels.
    public var margin: Double
    /// The gap between a panel and the one below it.
    public var gapAcross: Double
    /// The gap between panels side by side, narrower as in most comics.
    public var gapDown: Double
    /// How thick the frames are.
    public var line: Double
    public var root = PanelCut()

    /// The usual sizes for a page this wide.
    public init(width: Int) {
        let side = Double(width)
        margin = (side * 0.06).rounded()
        gapAcross = (side * 0.028).rounded()
        gapDown = (side * 0.014).rounded()
        line = max(2, (side * 0.004).rounded())
    }

    /// Every panel's rectangle in canvas coordinates, in reading order.
    public func panels(in page: CGRect) -> [CGRect] {
        var found: [CGRect] = []
        walk(root, in: frame(of: page)) { rect, _ in found.append(rect) }
        return found
    }

    /// The panel that `point` is in, as its place in reading order.
    public func panel(at point: CGPoint, in page: CGRect) -> Int? {
        panels(in: page).firstIndex { $0.contains(point) }
    }

    /// Cuts the panel the line runs through, across or down depending on
    /// which way the line mostly goes. A short line, or one that would leave
    /// a panel too small, cuts nothing. Returns whether it cut.
    public mutating func cut(from a: CGPoint, to b: CGPoint, in page: CGRect) -> Bool {
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let across = abs(b.x - a.x) >= abs(b.y - a.y)
        var path: [Int]?
        var target = CGRect.null
        walk(root, in: frame(of: page)) { rect, at in
            if rect.contains(middle) { path = at; target = rect }
        }
        guard let path else { return false }
        // Like a ruler, the line has to run over most of the panel.
        let length = across ? abs(b.x - a.x) : abs(b.y - a.y)
        guard length >= (across ? target.width : target.height) * 0.4 else { return false }
        let gap = CGFloat(across ? gapAcross : gapDown)
        let share = across ? (middle.y - target.minY) / target.height : (middle.x - target.minX) / target.width
        let room = (across ? target.height : target.width) * min(share, 1 - share) - gap / 2
        guard room >= max(24, gap) else { return false }
        var node = PanelCut()
        node.across = across
        node.at = Double(share)
        node.halves = [PanelCut(), PanelCut()]
        replace(at: path, with: node)
        return true
    }

    /// The panels the items of a layer with `style` keep to.
    func clips(for style: LayerStyle, in page: CGRect) -> [CGRect] {
        style.overPanels ? [] : panels(in: page)
    }

    /// The frames as a layer of their own, drawn afresh.
    func frameSheet(width: Int, height: Int, revision: Int) -> SheetPicture {
        let context = Raster.makeLayerContext(width: width, height: height)
        drawFrames(in: context, page: CGRect(x: 0, y: 0, width: width, height: height))
        return SheetPicture(id: CanvasDocument.framesID, image: context.makeImage(), isVisible: true, opacity: 1, style: LayerStyle(), revision: revision)
    }

    /// The frames, drawn into a canvas-coordinate context.
    func drawFrames(in context: CGContext, page: CGRect) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(CGFloat(line))
        context.setLineJoin(.miter)
        for rect in panels(in: page) {
            context.stroke(rect.insetBy(dx: CGFloat(line) / 2, dy: CGFloat(line) / 2))
        }
        context.restoreGState()
    }

    private func frame(of page: CGRect) -> CGRect {
        page.insetBy(dx: CGFloat(margin), dy: CGFloat(margin))
    }

    /// Visits every panel with its rectangle and the halves taken to reach it.
    private func walk(_ node: PanelCut, in rect: CGRect, path: [Int] = [], _ visit: (CGRect, [Int]) -> Void) {
        guard node.halves.count == 2 else { return visit(rect, path) }
        let parts = split(rect, node)
        walk(node.halves[0], in: parts.0, path: path + [0], visit)
        walk(node.halves[1], in: parts.1, path: path + [1], visit)
    }

    /// The two halves of `rect` in reading order, with the gap between them.
    private func split(_ rect: CGRect, _ node: PanelCut) -> (CGRect, CGRect) {
        if node.across {
            let half = CGFloat(gapAcross) / 2
            let y = rect.minY + rect.height * CGFloat(node.at)
            return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: y - half - rect.minY),
                    CGRect(x: rect.minX, y: y + half, width: rect.width, height: rect.maxY - y - half))
        }
        let half = CGFloat(gapDown) / 2
        let x = rect.minX + rect.width * CGFloat(node.at)
        return (CGRect(x: x + half, y: rect.minY, width: rect.maxX - x - half, height: rect.height),
                CGRect(x: rect.minX, y: rect.minY, width: x - half - rect.minX, height: rect.height))
    }

    private mutating func replace(at path: [Int], with node: PanelCut) {
        func put(_ current: inout PanelCut, _ rest: ArraySlice<Int>) {
            guard let first = rest.first else { current = node; return }
            put(&current.halves[first], rest.dropFirst())
        }
        put(&root, path[...])
    }
}

extension LayerItem {
    /// Where the item was begun: it stays inside the panel this is in.
    /// Nil for items that have no single start, such as a group, whose items
    /// each keep to their own panels.
    var start: CGPoint? {
        switch self {
        case .stroke(let stroke): return stroke.points.first?.point
        case .fill(let fill): return fill.seed ?? CGPoint(x: fill.rect.midX, y: fill.rect.midY)
        case .gradient(let gradient): return gradient.start
        case .instance(let instance): return instance.placement.center
        case .balloon(let balloon): return balloon.center
        case .bitmap, .group: return nil
        }
    }
}

/// Comic pages: cutting the page into panels. Whatever is begun inside a
/// panel stays inside it, as if the rest of the page were masked off; what
/// is begun between panels may run across them.
extension CanvasDocument {
    /// The panels of the page in reading order; empty when it is not cut.
    public var panels: [CGRect] {
        library.page?.panels(in: bounds) ?? []
    }

    /// The panels a layer's items keep to: none for the plan, or for a layer
    /// laid over the frames, such as speech balloons.
    func panelClips(for layer: Layer) -> [CGRect] {
        layer.isComposition || layer.style.overPanels ? [] : panels
    }

    /// Cuts the page along the line from `a` to `b`, splitting the panel it
    /// runs through. The first cut divides the page into panels. Returns whether it cut.
    @discardableResult
    public func cutPanel(from a: CGPoint, to b: CGPoint) -> Bool {
        var page = library.page ?? PanelLayout(width: width)
        guard liveStroke == nil, page.cut(from: a, to: b, in: bounds) else { return false }
        setPage(page)
        nextStepNote = L("コマを切った（\(page.root.count) コマ）", "Cut a panel (\(page.root.count) panels)")
        return true
    }

    /// Changes how the page is divided and how the frames look, or with nil
    /// makes it a plain picture again. A drag on a slider is one change.
    public func setPage(_ page: PanelLayout?, coalescing key: String? = nil) {
        guard liveStroke == nil, page != library.page else { return }
        let had = library.page != nil
        changeLibrary(coalescing: key) { $0.page = page }
        // Every item may now keep to another panel.
        for index in layers.indices where !layers[index].items.isEmpty {
            revisionCounter += 1
            layers[index].revision = revisionCounter
        }
        syncCaches()
        invalidate(nil)
        if page == nil, had { nextStepNote = L("コマ割りをやめた", "Stopped dividing the page") }
    }

    /// The frames as a layer of their own, put together with the others.
    func frameSheet() -> SheetPicture? {
        guard let page = library.page else { return nil }
        if framesDrawn?.page != page {
            frameRevision += 1
            framesDrawn = page.frameSheet(width: width, height: height, revision: frameRevision).image.map { (page, $0) }
        }
        return framesDrawn.map {
            SheetPicture(id: Self.framesID, image: $0.image, isVisible: true, opacity: 1, style: LayerStyle(), revision: frameRevision)
        }
    }

    static let framesID = UUID(uuidString: "6E1F0000-0000-4000-8000-0000000F2A3E")!
}

extension Array where Element == SheetPicture {
    /// The sheets with the frames put in: over every layer, but under the
    /// first one laid over the frames and everything above it.
    func withFrames(_ frames: SheetPicture?) -> [SheetPicture] {
        guard let frames else { return self }
        let at = firstIndex { $0.style.overPanels && !$0.style.isClipped } ?? count
        var sheets = self
        sheets.insert(frames, at: at)
        return sheets
    }
}

extension Raster {
    /// Draws one layer item, keeping it inside the panel it was begun in.
    static func draw(_ item: LayerItem, in context: CGContext, panels: [CGRect]) {
        guard !panels.isEmpty else { return draw(item, in: context) }
        if case .group(let group) = item {
            // Each item of the group keeps to its own panel.
            let sheet = makeLayerContext(width: context.width, height: context.height)
            group.items.forEach { draw($0, in: sheet, panels: panels) }
            guard let image = sheet.makeImage() else { return }
            return draw(.bitmap(image, alpha: group.alpha), in: context)
        }
        guard let start = item.start, let panel = panels.first(where: { $0.contains(start) }) else {
            return draw(item, in: context)
        }
        context.saveGState()
        context.clip(to: panel)
        draw(item, in: context)
        context.restoreGState()
    }
}
