import CoreGraphics
import Foundation

/// Reading and writing documents as a single JSON file.
///
/// Strokes are stored as points so they stay editable; fills and merged
/// layers are stored as PNG pictures inside the file.
public enum DocumentFile {
    public static let fileExtension = "oekakistudio"
    /// Written at the top of every file, so other JSON is not taken for a picture.
    static let formatName = "oekaki-studio"
    /// 2 numbers every item, keeps where fills were clicked, and keeps merged layers as groups.
    /// 3 keeps the journal of how the picture was made.
    /// 4 adds blend modes, clipping and glow on layers, see-through and soft
    /// strokes, and gradients.
    /// 5 adds named colours, colour sets, parts and their uses, and versions.
    /// 6 adds blur on layers.
    /// 7 adds dots (screen tone) on layers.
    /// 8 adds parts with several drawings (variations).
    static let currentVersion = 8

    public enum Failure: LocalizedError {
        case notADocument
        case newerVersion(Int)
        case damaged

        public var errorDescription: String? {
            switch self {
            case .notADocument:
                return L("このファイルは Oekaki Studio の絵ではありません。", "This file is not an Oekaki Studio picture.")
            case .newerVersion(let version):
                return L(
                    "このファイルは新しいバージョン(形式 \(version))で保存されています。アプリを更新してください。",
                    "This file was saved by a newer version (format \(version)). Please update the app."
                )
            case .damaged:
                return L("ファイルが壊れていて開けません。", "The file is damaged and cannot be opened.")
            }
        }
    }

    private struct File: Codable {
        var format: String
        var version: Int
        var width: Int
        var height: Int
        var activeLayer: Int
        var strokeCounter: Int
        var layers: [FileLayer]
        var figure: Figure?
        var notes: [Note]?
        var journal: [FileStep]?
        var library: FileLibrary?
        /// Every version, in order; the one in the file's layers is `currentBranch`.
        var branchList: [FileBranchInfo]?
        var currentBranch: UUID?
        /// The versions other than the one in the file's layers.
        var branches: [FileBranch]?
    }

    private struct FileBranchInfo: Codable {
        var id: UUID
        var name: String
        var note: String?
        var colorChanges: [FileColorChange]?
    }

    private struct FileColorChange: Codable {
        var name: String
        var before: RGBA
        var after: RGBA
    }

    private struct FileBranch: Codable {
        var id: UUID
        var layers: [FileLayer]
        var activeLayer: Int
        var figure: Figure?
        var notes: [Note]?
        var library: FileLibrary?
        var journal: [FileStep]?
    }

    private struct FileLibrary: Codable {
        var swatches: [FileSwatch]
        var themes: [FileTheme]
        var components: [FileComponent]
        var currentTheme: UUID?
    }

    private struct FileSwatch: Codable {
        var id: UUID
        var name: String
        var color: RGBA
    }

    private struct FileTheme: Codable {
        var id: UUID
        var name: String
        var colors: [String: RGBA]
    }

    private struct FileComponent: Codable {
        var id: UUID
        var name: String
        /// The first drawing's items.
        var items: [FileItem]
        /// Every drawing, when there is more than the first or it has a name.
        /// The first one's items are `items`.
        var looks: [FileLook]?
    }

    private struct FileLook: Codable {
        var id: UUID
        var name: String
        var items: [FileItem]?
    }

    private struct FileInstance: Codable {
        var component: UUID
        /// Centre x, y, then scale and rotation.
        var placement: [Double]
        var flipped: Bool?
        var overrides: [String: RGBA]?
        /// The drawing of the part it shows, if not the first.
        var look: UUID?
    }

    private struct FileStep: Codable {
        /// Seconds since 1970.
        var time: Double
        var kind: String
        var layers: [FileJournalLayer]?
        var figureChanged: Bool?
        var figure: Figure?
        var notes: [Note]?
        var library: FileLibrary?
        var note: String?
    }

    private struct FileJournalLayer: Codable {
        var id: UUID
        var name: String
        var visible: Bool
        var opacity: Double
        var composition: Bool?
        var blend: String?
        var clip: Bool?
        var glow: Double?
        var blur: Double?
        var tone: Double?
        /// "same", "append" or "list".
        var change: String
        var ids: [Int]?
        var items: [FileItem]?
    }

    private struct FileLayer: Codable {
        var name: String
        var visible: Bool
        var opacity: Double
        var composition: Bool?
        var blend: String?
        var clip: Bool?
        var glow: Double?
        var blur: Double?
        var tone: Double?
        var items: [FileItem]
    }

    /// A layer's style as written: nothing at all for the plain style, so
    /// files without these fields read as plain layers.
    private static func written(_ style: LayerStyle) -> (blend: String?, clip: Bool?, glow: Double?, blur: Double?, tone: Double?) {
        (
            style.blend == .normal ? nil : style.blend.rawValue, style.isClipped ? true : nil,
            style.glow > 0 ? Double(style.glow) : nil, style.blur > 0 ? Double(style.blur) : nil,
            style.tone > 0 ? Double(style.tone) : nil
        )
    }

    private static func style(blend: String?, clip: Bool?, glow: Double?, blur: Double?, tone: Double?) throws -> LayerStyle {
        var style = LayerStyle()
        if let blend {
            guard let mode = BlendMode(rawValue: blend) else { throw Failure.damaged }
            style.blend = mode
        }
        style.isClipped = clip ?? false
        style.glow = CGFloat(glow ?? 0)
        style.blur = CGFloat(blur ?? 0)
        style.tone = CGFloat(tone ?? 0)
        return style
    }

    private struct FileItem: Codable {
        var kind: String
        var id: Int?
        var stroke: FileStroke?
        var image: Data?
        var alpha: Double?
        var rect: [Int]?
        var full: Data?
        var interior: Data?
        var color: RGBA?
        /// Where a fill was clicked, x then y.
        var seed: [Double]?
        var name: String?
        var items: [FileItem]?
        var gradient: FileGradient?
        var instance: FileInstance?
        /// The named colour a stroke or fill takes its colour from.
        var ref: UUID?
    }

    private struct FileGradient: Codable {
        var shape: String
        /// x, y of the start, then of the end.
        var points: [Double]
        var from: RGBA
        var to: RGBA
        var fromRef: UUID?
        var toRef: UUID?
    }

    /// Journal items that are still in the picture unchanged are written as
    /// a reference to it, so the file holds them once.
    private struct Pool {
        var items: [Int: LayerItem] = [:]

        init(_ layers: [Layer]) {
            add(layers)
        }

        mutating func add(_ layers: [Layer]) {
            for item in layers.flatMap({ $0.items.flatMap(\.flattened) }) where items[item.id] == nil {
                items[item.id] = item
            }
        }

        func holds(_ item: LayerItem) -> Bool {
            items[item.id].map { Self.same($0, item) } ?? false
        }

        static func same(_ a: LayerItem, _ b: LayerItem) -> Bool {
            switch (a, b) {
            case (.stroke(let x), .stroke(let y)):
                return x.id == y.id && x.color == y.color && x.width == y.width && x.isEraser == y.isEraser
                    && x.opacity == y.opacity && x.softness == y.softness && x.colorRef == y.colorRef && x.points == y.points
            case (.gradient(let x), .gradient(let y)):
                return x.id == y.id && x.shape == y.shape && x.start == y.start && x.end == y.end && x.from == y.from && x.to == y.to
                    && x.fromRef == y.fromRef && x.toRef == y.toRef
            case (.instance(let x), .instance(let y)):
                return x.id == y.id && x.component == y.component && x.placement == y.placement && x.overrides == y.overrides && x.look == y.look
                    && x.content.count == y.content.count && zip(x.content, y.content).allSatisfy { same($0, $1) }
            case (.fill(let x), .fill(let y)):
                return x.id == y.id && x.full === y.full && x.color == y.color && x.rect == y.rect && x.colorRef == y.colorRef
            case (.bitmap(let x, let xa, let xid), .bitmap(let y, let ya, let yid)):
                return xid == yid && x === y && xa == ya
            case (.group(let x), .group(let y)):
                return x.id == y.id && x.name == y.name && x.alpha == y.alpha && x.items.count == y.items.count
                    && zip(x.items, y.items).allSatisfy { same($0, $1) }
            default:
                return false
            }
        }
    }

    private struct FileStroke: Codable {
        var id: Int
        var color: RGBA
        var width: Double
        var eraser: Bool
        var opacity: Double?
        var softness: Double?
        /// x, y, pressure for each point, one after another.
        var points: [Float]
    }

    public static func encode(_ document: CanvasDocument) throws -> Data {
        document.flushJournal()
        // Journal items still in some version of the picture are written once.
        var pool = Pool(document.layers)
        for state in document.branchStates.values { pool.add(state.snapshot.layers) }
        let journal = try document.journal.map { try encode($0, pool: pool) }
        let branches = try document.branches.filter { $0.id != document.currentBranch }.compactMap { info -> FileBranch? in
            guard let state = document.branchStates[info.id] else { return nil }
            let snapshot = state.snapshot
            return FileBranch(
                id: info.id, layers: try encode(snapshot.layers),
                activeLayer: snapshot.layers.firstIndex { $0.id == snapshot.activeLayerID } ?? 0,
                figure: snapshot.figure, notes: snapshot.notes.isEmpty ? nil : snapshot.notes,
                library: try encode(snapshot.library), journal: try state.journal.map { try encode($0, pool: pool) }
            )
        }
        let file = File(
            format: formatName, version: currentVersion, width: document.width, height: document.height,
            activeLayer: document.layers.firstIndex { $0.id == document.activeLayerID } ?? 0,
            strokeCounter: document.itemCounter, layers: try encode(document.layers), figure: document.figure,
            notes: document.notes.isEmpty ? nil : document.notes, journal: journal,
            library: try encode(document.library),
            branchList: document.branches.count > 1 ? document.branches.map { FileBranchInfo(
                id: $0.id, name: $0.name, note: $0.note,
                colorChanges: $0.colorChanges.isEmpty ? nil : $0.colorChanges.map { FileColorChange(name: $0.name, before: $0.before, after: $0.after) }
            ) } : nil,
            currentBranch: document.branches.count > 1 ? document.currentBranch : nil,
            branches: branches.isEmpty ? nil : branches
        )
        return try JSONEncoder().encode(file)
    }

    private static func encode(_ layers: [Layer]) throws -> [FileLayer] {
        try layers.map { layer in
            let style = written(layer.style)
            return FileLayer(
                name: layer.name, visible: layer.isVisible, opacity: layer.opacity,
                composition: layer.isComposition ? true : nil, blend: style.blend, clip: style.clip, glow: style.glow, blur: style.blur, tone: style.tone,
                items: try layer.items.map(encode)
            )
        }
    }

    private static func decode(_ saved: [FileLayer]) throws -> [Layer] {
        try saved.map { saved -> Layer in
            var layer = Layer(name: saved.name)
            layer.isVisible = saved.visible
            layer.opacity = saved.opacity
            layer.isComposition = saved.composition ?? false
            layer.style = try style(blend: saved.blend, clip: saved.clip, glow: saved.glow, blur: saved.blur, tone: saved.tone)
            layer.items = try saved.items.map(decode)
            return layer
        }
    }

    /// Nothing at all for an empty library, so files without one read as empty.
    private static func encode(_ library: Library) throws -> FileLibrary? {
        guard !library.isEmpty else { return nil }
        return FileLibrary(
            swatches: library.swatches.map { FileSwatch(id: $0.id, name: $0.name, color: $0.color) },
            themes: library.themes.map { theme in
                FileTheme(id: theme.id, name: theme.name, colors: Dictionary(uniqueKeysWithValues: theme.colors.map { ($0.key.uuidString, $0.value) }))
            },
            components: try library.components.map(encode),
            currentTheme: library.currentTheme
        )
    }

    private static func decode(_ saved: FileLibrary?) throws -> Library {
        var library = Library()
        guard let saved else { return library }
        library.swatches = saved.swatches.map { Swatch(id: $0.id, name: $0.name, color: $0.color) }
        library.themes = saved.themes.map { theme in
            ColorTheme(id: theme.id, name: theme.name, colors: Dictionary(uniqueKeysWithValues: theme.colors.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            }))
        }
        library.components = try saved.components.map(decode)
        library.currentTheme = saved.currentTheme
        return library
    }

    private static func encode(_ part: Component) throws -> FileComponent {
        let first = part.looks[0]
        var saved = FileComponent(id: part.id, name: part.name, items: try first.items.map(encode))
        if part.looks.count > 1 || !first.name.isEmpty {
            saved.looks = try part.looks.enumerated().map { index, look in
                FileLook(id: look.id, name: look.name, items: index == 0 ? nil : try look.items.map(encode))
            }
        }
        return saved
    }

    private static func decode(_ saved: FileComponent) throws -> Component {
        let first = try saved.items.map(decode)
        guard let looks = saved.looks, !looks.isEmpty else { return Component(id: saved.id, name: saved.name, items: first) }
        return Component(id: saved.id, name: saved.name, looks: try looks.enumerated().map { index, look in
            guard index == 0 || look.items != nil else { throw Failure.damaged }
            return ComponentLook(id: look.id, name: look.name, items: index == 0 ? first : try (look.items ?? []).map(decode))
        })
    }

    public static func decode(_ data: Data) throws -> CanvasDocument {
        struct Header: Codable {
            var format: String
            var version: Int
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == formatName else {
            throw Failure.notADocument
        }
        guard header.version <= currentVersion else { throw Failure.newerVersion(header.version) }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.width > 0, file.height > 0 else {
            throw Failure.damaged
        }
        let layers = try decode(file.layers)
        let library = try decode(file.library)
        // The other versions, each a picture of its own.
        var branchLayers: [UUID: [Layer]] = [:]
        for branch in file.branches ?? [] { branchLayers[branch.id] = try decode(branch.layers) }
        // A damaged journal costs the history, not the picture.
        var pool = Pool(layers)
        branchLayers.values.forEach { pool.add($0) }
        let journal = (try? (file.journal ?? []).map { try decode($0, pool: pool) }) ?? []
        let document = CanvasDocument(
            width: file.width, height: file.height, layers: layers,
            activeIndex: file.activeLayer, itemCounter: file.strokeCounter, figure: file.figure,
            notes: file.notes ?? [], library: library, journal: journal
        )
        if let list = file.branchList, let current = file.currentBranch, list.contains(where: { $0.id == current }) {
            document.branches = list.map { saved in
                BranchInfo(
                    id: saved.id, name: saved.name, note: saved.note,
                    colorChanges: (saved.colorChanges ?? []).map { ColorChange(name: $0.name, before: $0.before, after: $0.after) }
                )
            }
            document.currentBranch = current
            for branch in file.branches ?? [] {
                guard let saved = branchLayers[branch.id], !saved.isEmpty else { continue }
                // New items are numbered after every version's items.
                let highest = saved.flatMap { $0.items.flatMap(\.flattened) }.map(\.id).max() ?? 0
                document.itemCounter = max(document.itemCounter, highest)
                let numbered = saved
                let snapshot = CanvasDocument.Snapshot(
                    layers: numbered, activeLayerID: numbered[min(max(branch.activeLayer, 0), numbered.count - 1)].id,
                    figure: branch.figure, notes: branch.notes ?? [], library: try decode(branch.library)
                )
                let steps = (try? (branch.journal ?? []).map { try decode($0, pool: pool) }) ?? []
                document.branchStates[branch.id] = BranchState(snapshot: snapshot, journal: steps + [.full(.opened, PictureState(
                    layers: numbered, figure: snapshot.figure, notes: snapshot.notes, library: snapshot.library
                ))], undo: [], redo: [])
            }
            // Versions that could not be read are dropped from the list.
            document.branches.removeAll { $0.id != current && document.branchStates[$0.id] == nil }
        }
        return document
    }

    private static func encode(_ step: JournalStep, pool: Pool) throws -> FileStep {
        func items(_ list: [LayerItem]) throws -> [FileItem] {
            try list.map { pool.holds($0) ? FileItem(kind: "ref", id: $0.id) : try encode($0) }
        }
        let layers = try step.layers.map { layer -> FileJournalLayer in
            let style = written(layer.style)
            var saved = FileJournalLayer(
                id: layer.id, name: layer.name, visible: layer.isVisible, opacity: layer.opacity,
                composition: layer.isComposition ? true : nil, blend: style.blend, clip: style.clip, glow: style.glow, blur: style.blur, tone: style.tone,
                change: "same"
            )
            switch layer.items {
            case .same:
                break
            case .appended(let added):
                saved.change = "append"
                saved.items = try items(added)
            case .list(let ids, let contents):
                saved.change = "list"
                saved.ids = ids
                saved.items = try items(contents)
            }
            return saved
        }
        return FileStep(
            time: step.time.timeIntervalSince1970, kind: step.kind.rawValue, layers: layers.isEmpty ? nil : layers,
            figureChanged: step.figureChanged ? true : nil, figure: step.figure, notes: step.notes,
            library: try step.library.flatMap { try encode($0) }, note: step.note
        )
    }

    private static func decode(_ saved: FileStep, pool: Pool) throws -> JournalStep {
        guard let kind = JournalStep.Kind(rawValue: saved.kind) else { throw Failure.damaged }
        func items(_ list: [FileItem]?) throws -> [LayerItem] {
            try (list ?? []).map { item in
                if item.kind == "ref" {
                    guard let id = item.id, let found = pool.items[id] else { throw Failure.damaged }
                    return found
                }
                return try decode(item)
            }
        }
        var step = JournalStep(time: Date(timeIntervalSince1970: saved.time), kind: kind)
        step.layers = try (saved.layers ?? []).map { layer in
            let change: JournalItems
            switch layer.change {
            case "same": change = .same
            case "append": change = .appended(try items(layer.items))
            case "list": change = .list(ids: layer.ids ?? [], contents: try items(layer.items))
            default: throw Failure.damaged
            }
            return JournalLayer(
                id: layer.id, name: layer.name, isVisible: layer.visible, opacity: layer.opacity,
                isComposition: layer.composition ?? false, items: change,
                style: try style(blend: layer.blend, clip: layer.clip, glow: layer.glow, blur: layer.blur, tone: layer.tone)
            )
        }
        step.figureChanged = saved.figureChanged ?? false
        step.figure = saved.figure
        step.notes = saved.notes
        step.note = saved.note
        if saved.library != nil || kind == .start || kind == .opened {
            step.library = try decode(saved.library)
        }
        return step
    }

    private static func encode(_ item: LayerItem) throws -> FileItem {
        switch item {
        case .stroke(let stroke):
            var points: [Float] = []
            points.reserveCapacity(stroke.points.count * 3)
            for point in stroke.points {
                points.append(Float(point.x))
                points.append(Float(point.y))
                points.append(Float(point.pressure))
            }
            let saved = FileStroke(
                id: stroke.id, color: stroke.color, width: Double(stroke.width), eraser: stroke.isEraser,
                opacity: stroke.opacity < 1 ? Double(stroke.opacity) : nil, softness: stroke.softness > 0 ? Double(stroke.softness) : nil,
                points: points
            )
            return FileItem(kind: "stroke", stroke: saved, ref: stroke.colorRef)
        case .instance(let use):
            let saved = FileInstance(
                component: use.component,
                placement: [use.placement.center.x, use.placement.center.y, use.placement.scale, use.placement.rotation].map(Double.init),
                flipped: use.placement.flipped ? true : nil,
                overrides: use.overrides.isEmpty ? nil : Dictionary(uniqueKeysWithValues: use.overrides.map { ($0.key.uuidString, $0.value) }),
                look: use.look
            )
            return FileItem(kind: "instance", id: use.id, items: try use.content.map(encode), instance: saved)
        case .gradient(let gradient):
            let saved = FileGradient(
                shape: gradient.shape.rawValue,
                points: [gradient.start.x, gradient.start.y, gradient.end.x, gradient.end.y].map(Double.init),
                from: gradient.from, to: gradient.to, fromRef: gradient.fromRef, toRef: gradient.toRef
            )
            return FileItem(kind: "gradient", id: gradient.id, gradient: saved)
        case .bitmap(let image, let alpha, let id):
            guard let png = ImageCoding.png(from: image) else { throw Failure.damaged }
            return FileItem(kind: "bitmap", id: id, image: png, alpha: Double(alpha))
        case .fill(let fill):
            guard let full = ImageCoding.png(from: fill.full), let interior = ImageCoding.png(from: fill.interior) else {
                throw Failure.damaged
            }
            let rect = [Int(fill.rect.minX), Int(fill.rect.minY), Int(fill.rect.width), Int(fill.rect.height)]
            let seed = fill.seed.map { [Double($0.x), Double($0.y)] }
            return FileItem(kind: "fill", id: fill.id, rect: rect, full: full, interior: interior, color: fill.color, seed: seed, ref: fill.colorRef)
        case .group(let group):
            return FileItem(kind: "group", id: group.id, alpha: Double(group.alpha), name: group.name, items: try group.items.map(encode))
        }
    }

    private static func decode(_ item: FileItem) throws -> LayerItem {
        switch item.kind {
        case "stroke":
            guard let saved = item.stroke, saved.points.count % 3 == 0 else { throw Failure.damaged }
            let points = stride(from: 0, to: saved.points.count, by: 3).map { index in
                StrokePoint(x: CGFloat(saved.points[index]), y: CGFloat(saved.points[index + 1]), pressure: CGFloat(saved.points[index + 2]))
            }
            var stroke = Stroke(id: saved.id, points: points, color: saved.color, width: CGFloat(saved.width), isEraser: saved.eraser)
            stroke.opacity = CGFloat(saved.opacity ?? 1)
            stroke.softness = CGFloat(saved.softness ?? 0)
            stroke.colorRef = item.ref
            return .stroke(stroke)
        case "gradient":
            guard let saved = item.gradient, let shape = GradientItem.Shape(rawValue: saved.shape), saved.points.count == 4 else {
                throw Failure.damaged
            }
            var gradient = GradientItem(
                id: item.id ?? 0, shape: shape, start: CGPoint(x: saved.points[0], y: saved.points[1]),
                end: CGPoint(x: saved.points[2], y: saved.points[3]), from: saved.from, to: saved.to
            )
            gradient.fromRef = saved.fromRef
            gradient.toRef = saved.toRef
            return .gradient(gradient)
        case "instance":
            guard let saved = item.instance, saved.placement.count == 4, let content = item.items else { throw Failure.damaged }
            let placement = Placement(
                center: CGPoint(x: saved.placement[0], y: saved.placement[1]), scale: CGFloat(saved.placement[2]),
                rotation: CGFloat(saved.placement[3]), flipped: saved.flipped ?? false
            )
            let overrides = Dictionary(uniqueKeysWithValues: (saved.overrides ?? [:]).compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
            return .instance(InstanceItem(
                id: item.id ?? 0, component: saved.component, placement: placement, overrides: overrides, look: saved.look,
                content: try content.map(decode)
            ))
        case "bitmap":
            guard let data = item.image, let image = ImageCoding.image(fromPNG: data) else { throw Failure.damaged }
            return .bitmap(image, alpha: CGFloat(item.alpha ?? 1), id: item.id ?? 0)
        case "fill":
            guard let rect = item.rect, rect.count == 4, let color = item.color,
                  let full = item.full.flatMap(ImageCoding.mask), let interior = item.interior.flatMap(ImageCoding.mask)
            else { throw Failure.damaged }
            let area = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            let seed = item.seed.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            return .fill(FillItem(id: item.id ?? 0, rect: area, full: full, interior: interior, color: color, seed: seed, colorRef: item.ref))
        case "group":
            guard let items = item.items else { throw Failure.damaged }
            return .group(GroupItem(id: item.id ?? 0, name: item.name ?? "", items: try items.map(decode), alpha: CGFloat(item.alpha ?? 1)))
        default:
            throw Failure.damaged
        }
    }
}
