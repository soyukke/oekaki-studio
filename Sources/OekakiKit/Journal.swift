import CoreGraphics
import Foundation

/// One step in how a picture was made: what changed in one action that can
/// be taken back, or a take-back itself. Played in order from the first step,
/// the steps rebuild the picture, the way the history of a program rebuilds
/// its source.
public struct JournalStep {
    public enum Kind: String {
        /// A new, empty picture. Holds every layer.
        case start
        /// The picture as it was when it was opened from a file. Holds every
        /// layer, and the take-back history starts over from here.
        case opened
        /// One action. Holds only what it changed.
        case edit
        case undo
        case redo
    }

    public var time: Date
    public var kind: Kind
    /// Every layer after the step, back to front. Empty for undo and redo.
    var layers: [JournalLayer] = []
    /// True when the doll was placed, moved or removed.
    var figureChanged = false
    var figure: Figure?
    /// The notes after the step, when they changed.
    var notes: [Note]?
    /// The named colours, colour sets and parts after the step, when they changed.
    var library: Library?
    /// What the step was, in words, when the change alone cannot say, such
    /// as taking a version as the main picture.
    var note: String?
}

/// Everything the journal keeps track of, as it is at one moment.
struct PictureState {
    var layers: [Layer] = []
    var figure: Figure?
    var notes: [Note] = []
    var library = Library()
}

/// A layer as a journal step leaves it.
struct JournalLayer {
    var id: UUID
    var name: String
    var isVisible: Bool
    var opacity: Double
    var isComposition: Bool
    var items: JournalItems
    var style = LayerStyle()
}

/// How a layer's items changed in one step.
enum JournalItems {
    case same
    /// New items on top; the ones below stayed as they were.
    case appended([LayerItem])
    /// The items in order by number. Only the ones that are new to this
    /// layer, or were changed in place, are spelled out.
    case list(ids: [Int], contents: [LayerItem])
}

extension JournalStep {
    /// A step holding the whole picture, for the start of a journal.
    static func full(_ kind: Kind, _ picture: PictureState) -> JournalStep {
        var step = JournalStep(time: Date(), kind: kind)
        step.layers = picture.layers.map { layer in
            JournalLayer(
                id: layer.id, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity,
                isComposition: layer.isComposition, items: .list(ids: layer.items.map(\.id), contents: layer.items), style: layer.style
            )
        }
        step.figureChanged = true
        step.figure = picture.figure
        step.notes = picture.notes
        step.library = picture.library
        return step
    }

    /// The change from one state of the picture to the next. `touched` holds
    /// the numbers of top-level items that were changed in place.
    static func edit(from old: PictureState, to new: PictureState, touched: Set<Int>) -> JournalStep {
        var step = JournalStep(time: Date(), kind: .edit)
        step.layers = new.layers.map { layer in
            JournalLayer(
                id: layer.id, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity,
                isComposition: layer.isComposition, items: change(from: old.layers.first { $0.id == layer.id }, to: layer, touched: touched),
                style: layer.style
            )
        }
        if old.figure != new.figure {
            step.figureChanged = true
            step.figure = new.figure
        }
        if old.notes != new.notes {
            step.notes = new.notes
        }
        if old.library.revision != new.library.revision {
            step.library = new.library
        }
        return step
    }

    private static func change(from old: Layer?, to new: Layer, touched: Set<Int>) -> JournalItems {
        guard let old else { return .list(ids: new.items.map(\.id), contents: new.items) }
        if old.revision == new.revision { return .same }
        let oldIDs = old.items.map(\.id)
        let newIDs = new.items.map(\.id)
        let changedHere = touched.intersection(newIDs)
        if changedHere.isEmpty, newIDs.count >= oldIDs.count, Array(newIDs.prefix(oldIDs.count)) == oldIDs {
            return .appended(Array(new.items.dropFirst(oldIDs.count)))
        }
        let known = Set(oldIDs)
        return .list(ids: newIDs, contents: new.items.filter { !known.contains($0.id) || changedHere.contains($0.id) })
    }
}

/// Plays a journal back: rebuilds the picture as it was after any step and
/// draws it, a line at a time if wanted.
public final class Replay {
    public let width: Int
    public let height: Int
    public let steps: [JournalStep]
    /// What each step did, in words.
    public private(set) var titles: [String] = []
    /// What each step did, item by item.
    public private(set) var changes: [StepChange] = []
    /// The step the picture is at now; -1 before the first.
    public private(set) var position = -1

    struct Sheet {
        var id: UUID
        var name: String
        var isVisible: Bool
        var opacity: Double
        var items: [LayerItem]
        var style = LayerStyle()
    }

    struct State {
        var sheets: [Sheet] = []
        var figure: Figure?
        var notes: [Note] = []
        var library = Library()
        var undo: [State] = []
        var redo: [State] = []
    }

    /// How a sheet's pixels need to change after a step.
    enum Redraw {
        case add([LayerItem])
        case all
    }

    private var state = State()
    private var pixels: [UUID: CGContext] = [:]
    /// Counts each sheet's redraws, so a glow is made again only when needed.
    private var revisions: [UUID: Int] = [:]
    private lazy var compositor = Compositor(width: width, height: height)
    /// The way the page was divided when the sheets were last drawn.
    private var drawnPage: PanelLayout?
    /// Whether each sheet lay over the frames when it was last drawn.
    private var drawnOver: [UUID: Bool] = [:]
    private var framesRevision = 0

    public init(steps: [JournalStep], width: Int, height: Int) {
        self.steps = steps
        self.width = width
        self.height = height
        // A dry run without drawing, to put each step into words.
        var dry = State()
        for step in steps {
            let before = dry
            _ = Self.apply(step, to: &dry)
            titles.append(Self.describe(step, before: before, after: dry))
            changes.append(StepChange(step, before: before, after: dry))
        }
    }

    public var count: Int { steps.count }

    /// Moves the picture to just after step `index`.
    public func seek(to index: Int) {
        let target = min(max(index, -1), steps.count - 1)
        if target < position {
            state = State()
            pixels = [:]
            drawnPage = nil
            drawnOver = [:]
            position = -1
        }
        while position < target {
            position += 1
            let redraws = Self.apply(steps[position], to: &state)
            draw(redraws)
        }
    }

    /// The single line that step `index` adds, if that is all it does, so
    /// it can be shown being drawn.
    public func strokeDrawn(at index: Int) -> (layerID: UUID, stroke: Stroke)? {
        guard steps.indices.contains(index), steps[index].kind == .edit else { return nil }
        var found: (UUID, Stroke)?
        for layer in steps[index].layers {
            switch layer.items {
            case .same: continue
            case .appended(let items):
                guard found == nil, items.count == 1, case .stroke(let stroke) = items[0], !stroke.isEraser else { return nil }
                found = (layer.id, stroke)
            case .list:
                return nil
            }
        }
        return found
    }

    /// The picture at the current step, as the canvas shows it: the doll,
    /// the layers and the notes on white. With `partial`, that line is added
    /// on its layer, drawn as far as `share` (0...1) of its points.
    public func frame(maxSide: Int = 1600, partial: (layerID: UUID, stroke: Stroke, share: Double)? = nil) -> CGImage? {
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(width, height)))
        let picture = Raster.makeLayerContext(width: Int(CGFloat(width) * scale), height: Int(CGFloat(height) * scale))
        picture.scaleBy(x: scale, y: scale)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        picture.setFillColor(CGColor(gray: 1, alpha: 1))
        picture.fill(bounds)
        if let figure = state.figure, figure.isVisible {
            figure.draw(in: picture)
        }
        let sheets = state.sheets.map { sheet -> SheetPicture in
            var image = pixels[sheet.id].flatMap(Raster.liveImage)
            var revision = revisions[sheet.id] ?? 0
            if let partial, partial.layerID == sheet.id, let context = pixels[sheet.id] {
                image = Self.adding(partial.stroke, share: partial.share, to: context)
                revision = -1 - revision
            }
            return SheetPicture(
                id: sheet.id, image: sheet.isVisible ? image : nil, isVisible: sheet.isVisible,
                opacity: sheet.opacity, style: sheet.style, revision: revision
            )
        }
        let layers = Raster.makeContext(width: width, height: height)
        let frames = state.library.page?.frameSheet(width: width, height: height, revision: framesRevision)
        compositor.flatten(sheets.withFrames(frames), onto: layers)
        if let together = layers.makeImage() {
            Raster.upright(bounds, in: picture) { picture.draw(together, in: bounds) }
        }
        NoteRenderer.draw(state.notes, in: picture)
        return picture.makeImage()
    }

    private static func adding(_ stroke: Stroke, share: Double, to context: CGContext) -> CGImage? {
        guard let base = Raster.liveImage(of: context) else { return nil }
        let copy = Raster.makeLayerContext(width: context.width, height: context.height)
        let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        Raster.upright(bounds, in: copy) { copy.draw(base, in: bounds) }
        let shown = max(1, Int((Double(stroke.points.count) * min(max(share, 0), 1)).rounded()))
        var part = stroke
        part.points = Array(stroke.points.prefix(shown))
        if stroke.isPlain {
            for index in part.points.indices {
                StrokeRenderer.drawPiece(of: part, endingAt: index, in: copy)
            }
        } else {
            StrokeRenderer.draw(part, in: copy)
        }
        return copy.makeImage()
    }

    private func draw(_ redraws: [UUID: Redraw]) {
        var redraws = redraws
        // Another way of dividing the page may keep every item to another panel.
        if state.library.page != drawnPage {
            drawnPage = state.library.page
            framesRevision += 1
            state.sheets.forEach { redraws[$0.id] = .all }
        }
        // So may laying a sheet over the frames, or taking it back.
        for sheet in state.sheets where drawnOver[sheet.id] != sheet.style.overPanels {
            if drawnOver[sheet.id] != nil { redraws[sheet.id] = .all }
            drawnOver[sheet.id] = sheet.style.overPanels
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let ids = Set(state.sheets.map(\.id))
        pixels = pixels.filter { ids.contains($0.key) }
        for sheet in state.sheets {
            if pixels[sheet.id] == nil || redraws[sheet.id] != nil {
                revisions[sheet.id, default: 0] += 1
            }
            let clips = state.library.page?.clips(for: sheet.style, in: bounds) ?? []
            if let context = pixels[sheet.id] {
                switch redraws[sheet.id] {
                case nil:
                    continue
                case .add(let items):
                    items.forEach { Raster.draw($0, in: context, panels: clips) }
                case .all:
                    Raster.clear(context)
                    sheet.items.forEach { Raster.draw($0, in: context, panels: clips) }
                }
            } else {
                let context = Raster.makeLayerContext(width: width, height: height)
                sheet.items.forEach { Raster.draw($0, in: context, panels: clips) }
                pixels[sheet.id] = context
            }
        }
    }

    // MARK: Playing a step

    static let undoLimit = CanvasDocument.undoLimit

    /// Applies one step and says which sheets need drawing again.
    static func apply(_ step: JournalStep, to state: inout State) -> [UUID: Redraw] {
        func everything() -> [UUID: Redraw] {
            Dictionary(uniqueKeysWithValues: state.sheets.map { ($0.id, .all) })
        }
        switch step.kind {
        case .start, .opened:
            state = State()
            applyChanges(of: step, to: &state)
            return everything()
        case .edit:
            var before = state
            before.undo = []
            before.redo = []
            state.undo.append(before)
            if state.undo.count > undoLimit {
                state.undo.removeFirst(state.undo.count - undoLimit)
            }
            state.redo.removeAll()
            return applyChanges(of: step, to: &state)
        case .undo:
            guard var previous = state.undo.popLast() else { return [:] }
            var current = state
            current.undo = []
            current.redo = []
            previous.undo = state.undo
            previous.redo = state.redo + [current]
            state = previous
            return everything()
        case .redo:
            guard var next = state.redo.popLast() else { return [:] }
            var current = state
            current.undo = []
            current.redo = []
            next.undo = state.undo + [current]
            next.redo = state.redo
            state = next
            return everything()
        }
    }

    @discardableResult
    private static func applyChanges(of step: JournalStep, to state: inout State) -> [UUID: Redraw] {
        var redraws: [UUID: Redraw] = [:]
        let old = state.sheets
        state.sheets = step.layers.map { layer in
            let previous = old.first { $0.id == layer.id }
            var sheet = Sheet(
                id: layer.id, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity, items: previous?.items ?? [], style: layer.style
            )
            switch layer.items {
            case .same:
                break
            case .appended(let items):
                sheet.items += items
                redraws[layer.id] = .add(items)
            case .list(let ids, let contents):
                var known: [Int: LayerItem] = [:]
                // Spelled-out items first, then this layer's own, then any other layer's.
                for item in old.flatMap(\.items) { known[item.id] = item }
                for item in previous?.items ?? [] { known[item.id] = item }
                for item in contents { known[item.id] = item }
                sheet.items = ids.compactMap { known[$0] }
                redraws[layer.id] = .all
            }
            return sheet
        }
        if step.figureChanged {
            state.figure = step.figure
        }
        if let notes = step.notes {
            state.notes = notes
        }
        if let library = step.library {
            state.library = library
        }
        return redraws
    }

    // MARK: Words

    static func describe(_ step: JournalStep, before: State, after: State) -> String {
        switch step.kind {
        case .start: return L("白い紙", "Blank paper")
        case .opened: return L("ファイルを開いた", "Opened the file")
        case .undo: return L("取り消した", "Undo")
        case .redo: return L("やり直した", "Redo")
        case .edit: break
        }
        if let note = step.note { return note }
        // Changes to the named colours or parts say what they mean, though
        // they also recolour or move items.
        if let change = after.library.change(from: before.library) { return change }
        let oldIDs = Set(before.sheets.flatMap(\.items).map(\.id))
        let newItems = after.sheets.flatMap(\.items)
        let newIDs = Set(newItems.map(\.id))
        let added = newItems.filter { !oldIDs.contains($0.id) }
        let removed = before.sheets.flatMap(\.items).filter { !newIDs.contains($0.id) }
        let addedSheets = after.sheets.filter { sheet in !before.sheets.contains { $0.id == sheet.id } }
        let removedSheets = before.sheets.filter { sheet in !after.sheets.contains { $0.id == sheet.id } }

        if let merged = removedSheets.first, removedSheets.count == 1, added.count == 1, case .group = added[0] {
            return L("「\(merged.name)」を下と合体", "Merged \"\(merged.name)\" down")
        }
        if let sheet = addedSheets.first {
            return sheet.items.isEmpty
                ? L("「\(sheet.name)」を追加", "Added \"\(sheet.name)\"")
                : L("「\(sheet.name)」を作った", "Made \"\(sheet.name)\"")
        }
        if let sheet = removedSheets.first {
            return L("「\(sheet.name)」を消した", "Deleted \"\(sheet.name)\"")
        }
        if added.count == 1, case .stroke = added[0] { return L("\(added[0].title) を描いた", "Drew \(added[0].title)") }
        if added.count == 1 { return L("\(added[0].title) を追加", "Added \(added[0].title)") }
        if added.count > 1 { return L("\(added.count) 個を描いた", "Drew \(added.count) items") }
        if removed.count == 1 { return L("\(removed[0].title) を消した", "Deleted \(removed[0].title)") }
        if removed.count > 1 { return L("\(removed.count) 個を消した", "Deleted \(removed.count) items") }
        let changed = step.layers.flatMap { layer -> [LayerItem] in
            if case .list(_, let contents) = layer.items { return contents.filter { oldIDs.contains($0.id) } }
            return []
        }
        if changed.count > 1 { return L("\(changed.count) 個をまとめて直した", "Changed \(changed.count) items together") }
        if let first = changed.first { return L("\(first.title) を直した", "Changed \(first.title)") }
        for sheet in after.sheets {
            guard let old = before.sheets.first(where: { $0.id == sheet.id }), old.style != sheet.style else { continue }
            if old.style.blend != sheet.style.blend {
                return L("「\(sheet.name)」の重ね方を「\(sheet.style.blend.title)」にした", "Set \"\(sheet.name)\" to \(sheet.style.blend.title)")
            }
            if old.style.isClipped != sheet.style.isClipped {
                return sheet.style.isClipped
                    ? L("「\(sheet.name)」を下でクリップ", "Clipped \"\(sheet.name)\" to the layer below")
                    : L("「\(sheet.name)」のクリップを外した", "Unclipped \"\(sheet.name)\"")
            }
            if old.style.blur != sheet.style.blur {
                return sheet.style.blur > 0
                    ? L("「\(sheet.name)」をぼかした", "Blurred \"\(sheet.name)\"")
                    : L("「\(sheet.name)」のぼかしを外した", "Made \"\(sheet.name)\" sharp")
            }
            if old.style.overPanels != sheet.style.overPanels {
                return sheet.style.overPanels
                    ? L("「\(sheet.name)」をコマの上に重ねた", "Laid \"\(sheet.name)\" over the panels")
                    : L("「\(sheet.name)」をコマの中に戻した", "Put \"\(sheet.name)\" back inside the panels")
            }
            if old.style.tone != sheet.style.tone {
                return sheet.style.tone > 0
                    ? L("「\(sheet.name)」を点で塗った", "Turned \"\(sheet.name)\" into dots")
                    : L("「\(sheet.name)」の点を外した", "Took the dots off \"\(sheet.name)\"")
            }
            return L("「\(sheet.name)」を光らせた", "Made \"\(sheet.name)\" glow")
        }
        if step.figureChanged { return L("ドールを動かした", "Posed the doll") }
        if step.notes != nil { return L("メモを書いた", "Wrote a note") }
        return L("レイヤーを変えた", "Changed a layer")
    }
}

/// What one step changed, item by item, for showing a step as a line of code.
public struct StepChange {
    public var kind: JournalStep.Kind
    /// New items, with the name of the layer each went on.
    public var added: [(layer: String, item: LayerItem)] = []
    /// Items changed in place, as they are after the step.
    public var changed: [(layer: String, item: LayerItem)] = []
    public var removed: [LayerItem] = []
    /// Layers that appeared, in order back to front, and how each is shown.
    public var addedLayers: [String] = []
    public var addedLayerStyles: [LayerStyle] = []
    public var hiddenLayers: [String] = []
    public var shownLayers: [String] = []
    public var renamedLayers: [(from: String, to: String)] = []
    /// Layers whose blend mode, clipping, glow, blur or dots changed, with the style after.
    public var restyledLayers: [(name: String, style: LayerStyle)] = []
    /// What changed in the named colours, colour sets or parts, in words.
    public var libraryChange: String?

    init(_ step: JournalStep, before: Replay.State, after: Replay.State) {
        kind = step.kind
        guard step.kind == .edit else { return }
        let oldItems = Dictionary(before.sheets.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for sheet in after.sheets {
            for item in sheet.items {
                if oldItems[item.id] == nil {
                    added.append((sheet.name, item))
                }
            }
            guard let old = before.sheets.first(where: { $0.id == sheet.id }) else {
                addedLayers.append(sheet.name)
                addedLayerStyles.append(sheet.style)
                continue
            }
            if old.name != sheet.name { renamedLayers.append((old.name, sheet.name)) }
            if old.style != sheet.style { restyledLayers.append((sheet.name, sheet.style)) }
            if old.isVisible, !sheet.isVisible { hiddenLayers.append(sheet.name) }
            if !old.isVisible, sheet.isVisible { shownLayers.append(sheet.name) }
        }
        for layer in step.layers {
            guard case .list(_, let contents) = layer.items, let sheet = after.sheets.first(where: { $0.id == layer.id }) else { continue }
            for item in contents where oldItems[item.id] != nil {
                changed.append((sheet.name, item))
            }
        }
        let newIDs = Set(after.sheets.flatMap(\.items).map(\.id))
        removed = before.sheets.flatMap(\.items).filter { !newIDs.contains($0.id) }
        libraryChange = after.library.change(from: before.library)
    }
}

extension LayerItem {
    /// A short name such as "Line #12".
    public var title: String {
        switch self {
        case .stroke(let stroke):
            return stroke.isEraser ? L("消した跡 #\(id)", "Erased #\(id)") : L("線 #\(id)", "Line #\(id)")
        case .fill: return L("塗り #\(id)", "Fill #\(id)")
        case .bitmap: return L("画像 #\(id)", "Picture #\(id)")
        case .group(let group): return "\(group.name) #\(id)"
        case .gradient: return L("グラデーション #\(id)", "Gradient #\(id)")
        case .instance: return L("部品 #\(id)", "Part #\(id)")
        case .balloon(let balloon):
            let words = balloon.text.replacingOccurrences(of: "\n", with: "")
            if balloon.shape == .sound { return L("効果音「\(words.prefix(12))」", "Sound effect \"\(words.prefix(12))\"") }
            return L("吹き出し「\(words.prefix(12))」", "Balloon \"\(words.prefix(12))\"")
        }
    }
}
