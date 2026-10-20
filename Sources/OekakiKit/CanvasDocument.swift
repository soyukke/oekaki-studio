import Combine
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One picture: its layers, their pixels, and the undo history.
///
/// Every change goes through this class on the main thread. Each layer keeps
/// the list of things drawn on it, and a bitmap that is that list rendered.
public final class CanvasDocument: ObservableObject {
    public static let defaultWidth = 1600
    public static let defaultHeight = 1200
    static let undoLimit = 100

    public let width: Int
    public let height: Int

    /// Bottom layer first.
    @Published public internal(set) var layers: [Layer]
    @Published public var activeLayerID: UUID
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false
    @Published public internal(set) var hasUnsavedChanges = false
    /// The posing doll under the picture, if one has been placed.
    @Published public internal(set) var figure: Figure?
    /// Written notes on the composition.
    @Published public internal(set) var notes: [Note] = []
    /// Named colours, colour sets and parts.
    @Published public internal(set) var library = Library()
    /// The versions of the picture, the main one first.
    @Published public internal(set) var branches: [BranchInfo]
    /// The version being worked on.
    @Published public internal(set) var currentBranch: UUID
    /// The versions not being worked on.
    var branchStates: [UUID: BranchState] = [:]

    /// Called with the canvas area that needs redrawing, or nil for all of it.
    public var onInvalidate: ((CGRect?) -> Void)?

    struct Snapshot {
        var layers: [Layer]
        var activeLayerID: UUID
        var figure: Figure?
        var notes: [Note]
        var library: Library
    }

    /// The picture as it is now, for the undo history.
    var snapshot: Snapshot {
        Snapshot(layers: layers, activeLayerID: activeLayerID, figure: figure, notes: notes, library: library)
    }

    final class LayerCache {
        let context: CGContext
        var revision: Int

        init(context: CGContext, revision: Int) {
            self.context = context
            self.revision = revision
        }
    }

    var undoStack: [Snapshot] = []
    var redoStack: [Snapshot] = []
    /// Consecutive changes with the same key share one undo step.
    var coalescingKey: String?
    var caches: [UUID: LayerCache] = [:]
    var revisionCounter = 0
    var layerCounter = 0
    private var transactionDepth = 0
    var liveStroke: Stroke?
    private var liveLayerID: UUID?
    /// For a see-through or soft stroke being drawn: the layer as it was
    /// before it, and a sheet with the stroke's marks so far.
    private var liveBase: CGImage?
    private var liveMarks: CGContext?
    private lazy var compositor = Compositor(width: width, height: height)
    /// Where the canvas view's picture is put together.
    private lazy var screen = Raster.makeContext(width: width, height: height)
    lazy var fillScratch = FillScratch(width: width, height: height)
    /// The last number given to an item; items of every kind share it.
    var itemCounter = 0

    /// How the picture was made, one step per action that can be taken back.
    public internal(set) var journal: [JournalStep] = []
    /// The picture as the last journal step left it.
    var journalBase = PictureState()
    /// Words for the step being made, when the change alone cannot say what it was.
    var nextStepNote: String?
    /// An undo step was pushed whose action has not been written down yet.
    var journalPending = false
    /// Top-level items changed in place since the last journal step.
    var touchedItems: Set<Int> = []

    public init(width: Int = CanvasDocument.defaultWidth, height: Int = CanvasDocument.defaultHeight) {
        self.width = width
        self.height = height
        let main = UUID()
        currentBranch = main
        branches = [BranchInfo(id: main, name: L("本番の絵", "Main"))]
        let first = Layer(name: L("レイヤー 1", "Layer 1"))
        layers = [first]
        activeLayerID = first.id
        layerCounter = 1
        syncCaches()
        beginJournal(.start, after: [])
    }

    /// Rebuilds a document from saved layers.
    init(
        width: Int, height: Int, layers loaded: [Layer], activeIndex: Int, itemCounter: Int, figure: Figure? = nil, notes: [Note] = [],
        library: Library = Library(), journal: [JournalStep] = []
    ) {
        self.width = width
        self.height = height
        let main = UUID()
        currentBranch = main
        branches = [BranchInfo(id: main, name: L("本番の絵", "Main"))]
        self.figure = figure
        self.notes = notes
        self.library = library
        var layers = loaded.isEmpty ? [Layer(name: L("レイヤー 1", "Layer 1"))] : loaded
        // Older files numbered only the strokes; the rest is numbered after them.
        var counter = layers.flatMap { $0.items.flatMap(\.flattened) }.map(\.id).reduce(itemCounter, max)
        for index in layers.indices {
            revisionCounter += 1
            layers[index].revision = revisionCounter
            layers[index].items = layers[index].items.map { Self.numbered($0, counter: &counter) }
        }
        self.itemCounter = counter
        self.layers = layers
        activeLayerID = layers[min(max(activeIndex, 0), layers.count - 1)].id
        layerCounter = layers.count
        syncCaches()
        beginJournal(.opened, after: journal)
    }

    // MARK: Reading

    public var size: CGSize { CGSize(width: width, height: height) }
    public var bounds: CGRect { CGRect(origin: .zero, size: size) }

    public var activeLayer: Layer? { layers.first { $0.id == activeLayerID } }

    /// True until something has been drawn.
    public var isBlank: Bool { layers.allSatisfy { $0.items.isEmpty } }

    public var isDrawing: Bool { liveStroke != nil }

    /// The layer's pixels without copying them. Use it at once, on the main
    /// thread; it goes stale as soon as the layer is drawn on.
    public func liveImage(for layerID: UUID) -> CGImage? {
        caches[layerID].flatMap { Raster.liveImage(of: $0.context) }
    }

    /// A copy of the layer's pixels, safe to keep.
    public func snapshotImage(for layerID: UUID) -> CGImage? {
        caches[layerID]?.context.makeImage()
    }

    /// All visible layers of the picture flattened. A nil background leaves
    /// it transparent. With `includingComposition`, the plan is shown too: the
    /// doll under everything, the composition layers, and the notes on top.
    public func compositeImage(background: RGBA? = .white, includingComposition: Bool = false) -> CGImage? {
        guard includingComposition else { return compositeContext(background: background).makeImage() }
        let picture = Raster.makeContext(width: width, height: height)
        if let background {
            picture.setFillColor(background.cgColor)
            picture.fill(bounds)
        }
        func downward(_ body: () -> Void) {
            picture.saveGState()
            picture.translateBy(x: 0, y: CGFloat(height))
            picture.scaleBy(x: 1, y: -1)
            body()
            picture.restoreGState()
        }
        if let figure, figure.isVisible {
            downward { figure.draw(in: picture) }
        }
        compositor.flatten(sheets(of: layers[...].filter { !$0.isComposition }), onto: picture)
        // The plan goes over the picture, so it reads even where colour is painted.
        for layer in layers.filter(\.isComposition) where layer.isVisible {
            guard let image = liveImage(for: layer.id) else { continue }
            picture.setAlpha(layer.opacity)
            picture.draw(image, in: bounds)
        }
        picture.setAlpha(1)
        downward { NoteRenderer.draw(notes, in: picture) }
        return picture.makeImage()
    }

    public func pngData(background: RGBA? = .white, includingComposition: Bool = false) -> Data? {
        guard let image = compositeImage(background: background, includingComposition: includingComposition) else { return nil }
        return ImageCoding.png(from: image)
    }

    /// True when there is a plan to show: the doll, composition lines or notes.
    public var hasComposition: Bool {
        figure != nil || !notes.isEmpty || layers.contains { $0.isComposition && !$0.items.isEmpty }
    }

    /// The colour seen at a canvas point, over white paper.
    public func pickColor(at point: CGPoint) -> RGBA? {
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let picture = compositeContext(background: .white)
        guard let data = picture.data else { return nil }
        let pixel = data.assumingMemoryBound(to: UInt8.self) + (y * width + x) * 4
        return RGBA(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
    }

    func compositeContext(background: RGBA?) -> CGContext {
        compositeContext(of: layers[...], background: background)
    }

    private func compositeContext(of layers: ArraySlice<Layer>, background: RGBA?) -> CGContext {
        let picture = Raster.makeContext(width: width, height: height)
        if let background {
            picture.setFillColor(background.cgColor)
            picture.fill(bounds)
        }
        // Composition layers are a plan, not part of the picture or its lines.
        compositor.flatten(sheets(of: layers.filter { !$0.isComposition }), onto: picture)
        return picture
    }

    private func sheets(of layers: [Layer]) -> [SheetPicture] {
        layers.map { layer in
            SheetPicture(
                id: layer.id, image: layer.isVisible ? liveImage(for: layer.id) : nil, isVisible: layer.isVisible,
                opacity: layer.opacity, style: layer.style, revision: caches[layer.id]?.revision ?? layer.revision
            )
        }
    }

    /// Every layer put together as the canvas shows it, on a transparent
    /// background, redrawn only inside `region`. Use it at once, on the main
    /// thread: it is overwritten by the next call.
    public func layersImage(region: CGRect? = nil) -> CGImage? {
        let area = region.map { CGRect(x: $0.minX, y: CGFloat(height) - $0.maxY, width: $0.width, height: $0.height).integral } ?? bounds
        screen.clear(area)
        compositor.flatten(sheets(of: layers), onto: screen, region: region)
        return Raster.liveImage(of: screen)
    }

    // MARK: Drawing

    /// Starts a stroke on the active layer, or on `layerID` when given.
    /// Returns false when that layer cannot be drawn on because it is hidden.
    @discardableResult
    public func beginStroke(
        at point: StrokePoint, color: RGBA, width: CGFloat, isEraser: Bool, on layerID: UUID? = nil,
        opacity: CGFloat = 1, softness: CGFloat = 0
    ) -> Bool {
        let target = layerID.flatMap { id in layers.first { $0.id == id } } ?? activeLayer
        guard liveStroke == nil, let layer = target, layer.isVisible, let cache = caches[layer.id] else {
            return false
        }
        itemCounter += 1
        var stroke = Stroke(id: itemCounter, points: [point], color: color, width: width, isEraser: isEraser)
        stroke.opacity = min(max(opacity, 0), 1)
        stroke.softness = min(max(softness, 0), 1)
        liveStroke = stroke
        liveLayerID = layer.id
        if stroke.isPlain {
            liveBase = nil
            liveMarks = nil
        } else {
            liveBase = cache.context.makeImage()
            liveMarks = Raster.makeLayerContext(width: self.width, height: height)
        }
        drawLive(StrokeRenderer.drawPiece(of: stroke, endingAt: 0, in: liveMarks ?? cache.context), of: stroke, in: cache.context)
        return true
    }

    /// Shows the part of a live stroke just drawn. A plain stroke is already
    /// on the layer; any other is laid from its marks over the layer as it was.
    private func drawLive(_ rect: CGRect, of stroke: Stroke, in layer: CGContext) {
        guard !rect.isNull else { return }
        if let marks = liveMarks, let base = liveBase, let image = Raster.liveImage(of: marks) {
            let area = rect.integral
            layer.saveGState()
            layer.clip(to: area)
            layer.clear(area)
            Raster.upright(bounds, in: layer) { layer.draw(base, in: bounds) }
            StrokeRenderer.lay(image, of: stroke, in: bounds, on: layer)
            layer.restoreGState()
        }
        invalidate(rect)
    }

    public func continueStroke(to point: StrokePoint) {
        guard var stroke = liveStroke, let layerID = liveLayerID, let cache = caches[layerID] else { return }
        if let last = stroke.points.last, hypot(last.x - point.x, last.y - point.y) < 0.5 {
            return
        }
        stroke.points.append(point)
        liveStroke = stroke
        drawLive(StrokeRenderer.drawPiece(of: stroke, endingAt: stroke.points.count - 1, in: liveMarks ?? cache.context), of: stroke, in: cache.context)
    }

    public func endStroke() {
        guard let stroke = liveStroke, let layerID = liveLayerID else { return }
        liveStroke = nil
        liveLayerID = nil
        guard let index = layers.firstIndex(where: { $0.id == layerID }), let cache = caches[layerID] else { return }
        drawLive(StrokeRenderer.drawTail(of: stroke, in: liveMarks ?? cache.context), of: stroke, in: cache.context)
        liveBase = nil
        liveMarks = nil
        pushUndo()
        appendItem(.stroke(stroke), toLayerAt: index, alreadyDrawn: true)
    }

    /// Lays a gradient over the active layer. Returns false when the layer
    /// cannot be drawn on.
    @discardableResult
    public func addGradient(_ gradient: GradientItem) -> Bool {
        guard liveStroke == nil, let index = layers.firstIndex(where: { $0.id == activeLayerID }), layers[index].isVisible else {
            return false
        }
        pushUndo()
        appendItem(.gradient(gradient), toLayerAt: index, alreadyDrawn: false)
        invalidate(nil)
        return true
    }

    /// Paint-bucket fill on the active layer, bounded by what is visible on
    /// every layer. Openings in the outline up to about twice `gap` pixels
    /// count as closed; a smaller gap reaches further into sharp corners.
    /// Returns false when nothing was filled.
    @discardableResult
    public func fill(at point: CGPoint, color: RGBA, gap: Int = BucketFill.defaultGap) -> Bool {
        guard liveStroke == nil, bounds.contains(point),
              let index = layers.firstIndex(where: { $0.id == activeLayerID }), layers[index].isVisible
        else { return false }
        let picture = compositeContext(background: .white)
        guard var item = BucketFill.run(picture: picture, seed: point, color: color, gap: gap, scratch: fillScratch) else {
            return false
        }
        item.seed = point
        pushUndo()
        appendItem(.fill(item), toLayerAt: index, alreadyDrawn: false)
        invalidate(item.rect)
        return true
    }

    /// Works out paint-bucket fills from several points at once, all bounded
    /// by the picture as it is now, without changing the document.
    public func makeFills(_ seeds: [(point: CGPoint, color: RGBA)]) -> [LayerItem] {
        let picture = compositeContext(background: .white)
        return seeds.compactMap { seed in
            guard bounds.contains(seed.point) else { return nil }
            guard var fill = BucketFill.run(picture: picture, seed: seed.point, color: seed.color, scratch: fillScratch) else { return nil }
            fill.seed = seed.point
            return .fill(fill)
        }
    }

    func appendItem(_ item: LayerItem, toLayerAt index: Int, alreadyDrawn: Bool) {
        revisionCounter += 1
        let item = Self.numbered(item, counter: &itemCounter)
        layers[index].items.append(item)
        layers[index].revision = revisionCounter
        if let cache = caches[layers[index].id] {
            if !alreadyDrawn {
                Raster.draw(item, in: cache.context)
            }
            cache.revision = revisionCounter
        }
    }

    // MARK: Layers

    public func addLayer() {
        pushUndo()
        layerCounter += 1
        revisionCounter += 1
        var layer = Layer(name: L("レイヤー \(layerCounter)", "Layer \(layerCounter)"))
        layer.revision = revisionCounter
        let above = (layers.firstIndex { $0.id == activeLayerID } ?? layers.count - 1) + 1
        layers.insert(layer, at: above)
        activeLayerID = layer.id
        syncCaches()
        invalidate(nil)
    }

    public func index(ofLayer id: UUID) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    /// Adds a ready-made layer at `index` (0 is the back) and returns its id.
    @discardableResult
    public func insertLayer(
        named name: String, items: [LayerItem], opacity: Double = 1, at index: Int, isComposition: Bool = false,
        style: LayerStyle = LayerStyle()
    ) -> UUID {
        pushUndo()
        layerCounter += 1
        revisionCounter += 1
        var layer = Layer(name: name)
        layer.isComposition = isComposition
        layer.style = style
        layer.items = items.map { Self.numbered($0, counter: &itemCounter) }
        layer.opacity = min(max(opacity, 0), 1)
        layer.revision = revisionCounter
        layers.insert(layer, at: min(max(index, 0), layers.count))
        syncCaches()
        invalidate(nil)
        return layer.id
    }

    /// Removes several layers in one step. At least one layer always remains.
    public func removeLayers(_ ids: Set<UUID>) {
        guard layers.contains(where: { ids.contains($0.id) }) else { return }
        pushUndo()
        layers.removeAll { ids.contains($0.id) }
        if layers.isEmpty {
            layerCounter += 1
            revisionCounter += 1
            var layer = Layer(name: L("レイヤー \(layerCounter)", "Layer \(layerCounter)"))
            layer.revision = revisionCounter
            layers = [layer]
        }
        if !layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = layers[layers.count - 1].id
        }
        syncCaches()
        invalidate(nil)
    }

    /// Removes a layer. The last remaining layer is emptied instead.
    public func deleteLayer(_ id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        if layers.count == 1 {
            revisionCounter += 1
            layers[0].items = []
            layers[0].revision = revisionCounter
        } else {
            layers.remove(at: index)
            if activeLayerID == id {
                activeLayerID = layers[max(index - 1, 0)].id
            }
        }
        syncCaches()
        invalidate(nil)
    }

    /// Moves a layer one step toward the front (+1) or the back (-1).
    public func moveLayer(_ id: UUID, by step: Int) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let target = index + step
        guard target >= 0, target < layers.count, target != index else { return }
        pushUndo()
        layers.swapAt(index, target)
        invalidate(nil)
    }

    public func canMoveLayer(_ id: UUID, by step: Int) -> Bool {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        return index + step >= 0 && index + step < layers.count
    }

    public func renameLayer(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = layers.firstIndex(where: { $0.id == id }), !trimmed.isEmpty, layers[index].name != trimmed else {
            return
        }
        pushUndo()
        layers[index].name = trimmed
    }

    public func setLayerVisible(_ id: UUID, _ isVisible: Bool) {
        guard let index = layers.firstIndex(where: { $0.id == id }), layers[index].isVisible != isVisible else { return }
        pushUndo()
        layers[index].isVisible = isVisible
        invalidate(nil)
    }

    /// Dragging a slider calls this many times; the whole drag is one undo step.
    public func setLayerOpacity(_ id: UUID, _ opacity: Double) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(opacity, 0), 1)
        guard layers[index].opacity != clamped else { return }
        pushUndo(coalescing: "opacity-\(id)")
        layers[index].opacity = clamped
        invalidate(nil)
    }

    /// How the layer is put onto the ones below it.
    public func setLayerBlend(_ id: UUID, _ blend: BlendMode) {
        restyle(id) { $0.blend = blend }
    }

    /// Whether the layer shows only where the layer below it has paint.
    public func setLayerClipped(_ id: UUID, _ isClipped: Bool) {
        restyle(id) { $0.isClipped = isClipped }
    }

    /// How far the layer's light spreads; 0 turns the glow off. A drag on a
    /// slider is one undo step.
    public func setLayerGlow(_ id: UUID, _ radius: CGFloat) {
        restyle(id, coalescing: "glow-\(id)") { $0.glow = min(max(radius, 0), 200) }
    }

    /// How far the layer is blurred; 0 makes it sharp again. A drag on a
    /// slider is one undo step.
    public func setLayerBlur(_ id: UUID, _ radius: CGFloat) {
        restyle(id, coalescing: "blur-\(id)") { $0.blur = min(max(radius, 0), 200) }
    }

    private func restyle(_ id: UUID, coalescing key: String? = nil, _ change: (inout LayerStyle) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        var style = layers[index].style
        change(&style)
        guard style != layers[index].style else { return }
        pushUndo(coalescing: key)
        layers[index].style = style
        invalidate(nil)
    }

    public func canMergeDown(_ id: UUID) -> Bool {
        (layers.firstIndex { $0.id == id } ?? 0) > 0
    }

    /// Puts a layer onto the one below it. Its items move down as one group,
    /// so they can still be found and changed one by one.
    public func mergeLayerDown(_ id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }), index > 0 else { return }
        pushUndo()
        let upper = layers.remove(at: index)
        let group = GroupItem(name: upper.name, items: upper.items, alpha: upper.opacity)
        appendItem(.group(group), toLayerAt: index - 1, alreadyDrawn: false)
        activeLayerID = layers[index - 1].id
        syncCaches()
        invalidate(nil)
    }

    // MARK: Items

    /// Gives the item, and anything inside it, a number if it has none yet,
    /// or a new one in any case when `fresh` (for copies).
    static func numbered(_ item: LayerItem, counter: inout Int, fresh: Bool = false) -> LayerItem {
        func next(_ id: Int) -> Int {
            guard fresh || id == 0 else { return id }
            counter += 1
            return counter
        }
        switch item {
        case .stroke(var stroke):
            stroke.id = next(stroke.id)
            return .stroke(stroke)
        case .bitmap(let image, let alpha, let id):
            return .bitmap(image, alpha: alpha, id: next(id))
        case .fill(var fill):
            fill.id = next(fill.id)
            return .fill(fill)
        case .group(var group):
            group.id = next(group.id)
            group.items = group.items.map { numbered($0, counter: &counter, fresh: fresh) }
            return .group(group)
        case .gradient(var gradient):
            gradient.id = next(gradient.id)
            return .gradient(gradient)
        case .instance(var instance):
            instance.id = next(instance.id)
            instance.content = instance.content.map { numbered($0, counter: &counter, fresh: fresh) }
            return .instance(instance)
        }
    }

    /// The item with this number and the layer it is on.
    public func item(_ id: Int) -> (layerID: UUID, item: LayerItem)? {
        for layer in layers {
            if let item = layer.items.lazy.flatMap(\.flattened).first(where: { $0.id == id }) {
                return (layer.id, item)
            }
        }
        return nil
    }

    /// What put the paint at `point`: the front-most visible layer with paint
    /// there, and the items from the outermost group in to the item itself.
    /// `slack` widens thin lines so they are easy to click.
    public func trace(_ point: CGPoint, slack: CGFloat = 2) -> (layerID: UUID, path: [Int])? {
        guard bounds.contains(point) else { return nil }
        for layer in layers.reversed() where layer.isVisible {
            guard let cache = caches[layer.id], Self.alpha(of: cache.context, at: point) > 0 else { continue }
            let path = LayerItem.path(to: point, in: layer.items, canvas: bounds, slack: slack)
            if !path.isEmpty { return (layer.id, path) }
        }
        return nil
    }

    /// The alpha of one pixel of a layer bitmap.
    private static func alpha(of context: CGContext, at point: CGPoint) -> UInt8 {
        guard let data = context.data else { return 0 }
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, x < context.width, y >= 0, y < context.height else { return 0 }
        return data.load(fromByteOffset: y * context.bytesPerRow + x * 4 + 3, as: UInt8.self)
    }

    /// Changes one item in place. Changes with the same `key` in a row, such
    /// as one slider drag, are taken back together.
    public func updateItem(_ id: Int, coalescing key: String? = nil, _ change: (inout LayerItem) -> Void) {
        updateItems([id], coalescing: key, change)
    }

    /// Takes one item out of the picture.
    public func deleteItem(_ id: Int) {
        // Items inside a use of a part belong to the part; the use goes as a whole.
        guard liveStroke == nil, partItem(id) == nil, let found = item(id), let index = index(ofLayer: found.layerID) else { return }
        pushUndo()
        // Taking an item out of a group changes the group in place.
        if !layers[index].items.contains(where: { $0.id == id }) {
            touch(id, inLayerAt: index)
        }
        revisionCounter += 1
        layers[index].items = Self.removing(id, from: layers[index].items)
        layers[index].revision = revisionCounter
        syncCaches()
        invalidate(nil)
    }

    static func modify(_ items: inout [LayerItem], id: Int, _ change: (inout LayerItem) -> Void) -> Bool {
        for index in items.indices {
            if items[index].id == id {
                var item = items[index]
                change(&item)
                guard item.id == id else { return false }
                items[index] = item
                return true
            }
            if case .group(var group) = items[index], modify(&group.items, id: id, change) {
                items[index] = .group(group)
                return true
            }
        }
        return false
    }

    static func removing(_ id: Int, from items: [LayerItem]) -> [LayerItem] {
        items.compactMap { item in
            if item.id == id { return nil }
            guard case .group(var group) = item else { return item }
            group.items = removing(id, from: group.items)
            return .group(group)
        }
    }

    // MARK: Tidying

    public struct TidyResult: Equatable {
        /// Pixels of colour taken away, such as paint that crossed a line.
        public var removed: Int
        /// Pixels of colour added, such as gaps left beside a line.
        public var added: Int
        /// False when there were no lines on the other layers to tidy against.
        public var foundLines: Bool
    }

    /// Tidies the rough colour on the active layer against the lines on the
    /// other visible layers. The result goes on a new layer above and the
    /// rough layer is hidden, not lost. Returns nil when there is no colour.
    @discardableResult
    public func tidyPaint(smoothing: Double = 8) -> TidyResult? {
        guard liveStroke == nil, let index = layers.firstIndex(where: { $0.id == activeLayerID }),
              layers[index].isVisible, let paint = caches[activeLayerID]?.context
        else { return nil }
        var wall = [UInt8](repeating: 0, count: width * height)
        let linesBelow = PaintTidy.markLines(in: compositeContext(of: layers[..<index], background: nil), into: &wall)
        _ = PaintTidy.markLines(in: compositeContext(of: layers[(index + 1)...], background: nil), into: &wall)
        // Colour may tuck under lines drawn above it, but must not cover lines below it.
        guard let tidied = PaintTidy.run(paint: paint, wall: wall, tuck: linesBelow == 0 ? 2 : 0, smoothing: smoothing) else { return nil }
        transaction {
            let rough = layers[index]
            let id = insertLayer(
                named: L("ととのえた塗り", "Tidied Colors"), items: [.bitmap(tidied.image, alpha: 1)],
                opacity: rough.opacity, at: index + 1
            )
            setLayerVisible(rough.id, false)
            activeLayerID = id
        }
        return TidyResult(removed: tidied.report.removed, added: tidied.report.added, foundLines: tidied.report.foundLines)
    }

    /// Steadies the brush strokes on the active layer. The result goes on a
    /// new layer above and the original is hidden, not lost. Returns false
    /// when the layer has no brush strokes to steady.
    @discardableResult
    public func tidyLines(smoothing: Double = 12) -> Bool {
        guard liveStroke == nil, let index = layers.firstIndex(where: { $0.id == activeLayerID }), layers[index].isVisible
        else { return false }
        let rough = layers[index]
        var strokes: [Stroke] = []
        for item in rough.items {
            if case .stroke(let stroke) = item { strokes.append(stroke) }
        }
        guard strokes.contains(where: { !$0.isEraser }) else { return false }
        var tidied = LineTidy.tidied(strokes, smoothing: CGFloat(smoothing)).makeIterator()
        // Fills and pictures on the layer stay as they are, in their place in the order.
        // The copies get numbers of their own, apart from the hidden originals.
        let items = rough.items.map { item -> LayerItem in
            if case .stroke = item, let stroke = tidied.next() { return Self.numbered(.stroke(stroke), counter: &itemCounter, fresh: true) }
            return Self.numbered(item, counter: &itemCounter, fresh: true)
        }
        transaction {
            let id = insertLayer(named: L("ととのえた線", "Tidied Lines"), items: items, opacity: rough.opacity, at: index + 1, style: rough.style)
            setLayerVisible(rough.id, false)
            activeLayerID = id
        }
        return true
    }

    /// How closely the lines on one layer follow the lines on another.
    ///
    /// `followed` is the share of `lines` that lies within `reach` pixels of
    /// the sketch; `kept` is the share of the sketch that the lines cover.
    public func lineFidelity(sketch: UUID, lines: UUID, reach: Int = 8) -> (followed: Double, kept: Double)? {
        guard let rough = caches[sketch]?.context, let clean = caches[lines]?.context else { return nil }
        return PaintTidy.overlap(of: clean, with: rough, reach: reach)
    }

    // MARK: Figure

    /// Places, changes or removes the posing doll. Changes with the same
    /// `key` in a row, such as one drag, are taken back together.
    public func setFigure(_ figure: Figure?, coalescing key: String? = nil) {
        guard liveStroke == nil, figure != self.figure else { return }
        pushUndo(coalescing: key)
        self.figure = figure
        self.notes = notes
        invalidate(nil)
    }

    // MARK: Notes

    /// Replaces the notes. Changes with the same `key` in a row, such as one
    /// drag, are taken back together.
    public func setNotes(_ notes: [Note], coalescing key: String? = nil) {
        guard liveStroke == nil, notes != self.notes else { return }
        pushUndo(coalescing: key)
        self.notes = notes
        invalidate(nil)
    }

    // MARK: Composition layer

    /// The sheet that composition lines are drawn on, if there is one.
    public var compositionLayerID: UUID? {
        layers.first { $0.isComposition }?.id
    }

    /// The composition sheet, made at the back of the stack when missing.
    /// The layer in use stays as it was.
    @discardableResult
    public func makeCompositionLayer() -> UUID {
        if let id = compositionLayerID { return id }
        let active = activeLayerID
        let id = insertLayer(named: L("構図", "Composition"), items: [], at: 0, isComposition: true)
        activeLayerID = active
        return id
    }

    // MARK: Undo

    /// Makes every change inside `body` a single undo step.
    public func transaction(_ body: () -> Void) {
        if transactionDepth == 0 {
            pushUndo()
        }
        transactionDepth += 1
        body()
        transactionDepth -= 1
    }

    public func undo() {
        guard liveStroke == nil, let snapshot = undoStack.popLast() else { return }
        recordPendingStep()
        redoStack.append(self.snapshot)
        restore(snapshot)
        recordStep(.undo)
    }

    public func redo() {
        guard liveStroke == nil, let snapshot = redoStack.popLast() else { return }
        recordPendingStep()
        undoStack.append(self.snapshot)
        restore(snapshot)
        recordStep(.redo)
    }

    /// Call after the document has been written to disk.
    public func markSaved() {
        hasUnsavedChanges = false
    }

    func pushUndo(coalescing key: String? = nil) {
        // Inside a transaction the step was already recorded when it began.
        guard transactionDepth == 0 else {
            coalescingKey = nil
            return
        }
        defer { coalescingKey = key }
        if let key, key == coalescingKey { return }
        recordPendingStep()
        journalPending = true
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
        redoStack.removeAll()
        updateUndoFlags()
        hasUnsavedChanges = true
    }

    func restore(_ snapshot: Snapshot) {
        coalescingKey = nil
        layers = snapshot.layers
        figure = snapshot.figure
        notes = snapshot.notes
        library = snapshot.library
        activeLayerID = layers.contains { $0.id == snapshot.activeLayerID } ? snapshot.activeLayerID : layers[layers.count - 1].id
        syncCaches()
        updateUndoFlags()
        hasUnsavedChanges = true
        invalidate(nil)
    }

    // MARK: Journal

    /// Writes down the action in progress, so the journal is complete, for
    /// example before saving or playing it back. The next change starts an
    /// undo step of its own, so the two keep in step.
    public func flushJournal() {
        recordPendingStep()
        coalescingKey = nil
    }

    /// The picture as the journal sees it.
    var pictureState: PictureState {
        PictureState(layers: layers, figure: figure, notes: notes, library: library)
    }

    func beginJournal(_ kind: JournalStep.Kind, after earlier: [JournalStep]) {
        journal = earlier + [.full(kind, pictureState)]
        journalBase = pictureState
    }

    /// Each undo step pushed gets exactly one journal step, even when it
    /// changed nothing that shows, so a replay can take steps back the same way.
    func recordPendingStep() {
        guard journalPending else { return }
        journalPending = false
        var step = JournalStep.edit(from: journalBase, to: pictureState, touched: touchedItems)
        step.note = nextStepNote
        nextStepNote = nil
        journal.append(step)
        journalBase = pictureState
        touchedItems = []
    }

    func recordStep(_ kind: JournalStep.Kind) {
        journal.append(JournalStep(time: Date(), kind: kind))
        journalBase = pictureState
        touchedItems = []
    }

    /// Notes that the top-level item holding `id` was changed in place.
    func touch(_ id: Int, inLayerAt index: Int) {
        if let top = layers[index].items.first(where: { $0.flattened.contains { $0.id == id } }) {
            touchedItems.insert(top.id)
        }
    }

    func updateUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Pixels

    /// Makes every layer's bitmap match its item list, redrawing only the
    /// layers whose contents changed.
    func syncCaches() {
        let ids = Set(layers.map(\.id))
        caches = caches.filter { ids.contains($0.key) }
        for layer in layers {
            if let cache = caches[layer.id] {
                guard cache.revision != layer.revision else { continue }
                Raster.clear(cache.context)
                layer.items.forEach { Raster.draw($0, in: cache.context) }
                cache.revision = layer.revision
            } else {
                let context = Raster.makeLayerContext(width: width, height: height)
                layer.items.forEach { Raster.draw($0, in: context) }
                caches[layer.id] = LayerCache(context: context, revision: layer.revision)
            }
        }
    }

    func invalidate(_ rect: CGRect?) {
        if let rect, rect.isNull { return }
        onInvalidate?(rect)
    }
}

enum ImageCoding {
    static func png(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func image(fromPNG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Re-reads a decoded picture as a clipping mask.
    static func mask(fromPNG data: Data) -> CGImage? {
        guard let image = image(fromPNG: data) else { return nil }
        let width = image.width
        let height = image.height
        var bytes = Data(count: width * height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Raster.maskImage(bytes: bytes, width: width, height: height) : nil
    }
}
