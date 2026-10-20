import CoreGraphics
import Foundation

/// Working on many items at once, the way a code editor works with many
/// cursors: whatever is done to one selected item is done to all of them,
/// and taken back in one step.
extension CanvasDocument {
    /// Where an item sits inside a use of a part: the part and the item's place in it.
    func partItem(_ id: Int) -> (component: UUID, index: Int)? {
        for layer in layers {
            for item in layer.items.flatMap(\.flattened) {
                guard case .instance(let instance) = item,
                      let index = instance.content.firstIndex(where: { $0.flattened.contains { $0.id == id } })
                else { continue }
                return (instance.component, index)
            }
        }
        return nil
    }

    /// The use of a part that holds the item `id`, if any.
    func instanceHolding(_ id: Int) -> Int? {
        for layer in layers {
            for item in layer.items.flatMap(\.flattened) {
                if case .instance(let instance) = item, instance.content.contains(where: { $0.flattened.contains { $0.id == id } }) {
                    return instance.id
                }
            }
        }
        return nil
    }

    /// Changes several items in place as one step. A change to an item inside
    /// a use of a part changes the part itself, and so every use of it.
    public func updateItems(_ ids: [Int], coalescing key: String? = nil, _ change: (inout LayerItem) -> Void) {
        guard liveStroke == nil, !ids.isEmpty else { return }
        var changed = layers
        var changedLayers = Set<Int>()
        var parts = library
        var changedParts = Set<UUID>()
        for id in ids {
            if let place = partItem(id), let index = parts.components.firstIndex(where: { $0.id == place.component }),
               parts.components[index].items.indices.contains(place.index) {
                change(&parts.components[index].items[place.index])
                changedParts.insert(place.component)
                continue
            }
            for layerIndex in changed.indices {
                var items = changed[layerIndex].items
                if Self.modify(&items, id: id, change) {
                    changed[layerIndex].items = items
                    changedLayers.insert(layerIndex)
                    break
                }
            }
        }
        guard !changedLayers.isEmpty || !changedParts.isEmpty else { return }
        pushUndo(coalescing: key)
        for index in changedLayers {
            revisionCounter += 1
            changed[index].revision = revisionCounter
        }
        layers = changed
        for id in ids {
            if let index = layers.firstIndex(where: { $0.items.contains { $0.flattened.contains { $0.id == id } } }) {
                touch(id, inLayerAt: index)
            }
        }
        if !changedParts.isEmpty {
            parts.revision += 1
            library = parts
            changedParts.forEach(refreshUses)
        }
        syncCaches()
        invalidate(nil)
    }

    /// The items to move as wholes for a selection: an item inside a use of
    /// a part moves the use, and an item inside a selected group moves with it.
    func movableItems(_ ids: [Int]) -> [Int] {
        var result: [Int] = []
        for id in ids {
            let whole = instanceHolding(id) ?? id
            if !result.contains(whole) { result.append(whole) }
        }
        // Drop anything inside another selected item.
        return result.filter { id in
            !result.contains { other in other != id && item(other).map { $0.item.children.flatMap(\.flattened).contains { $0.id == id } } == true }
        }
    }

    /// Moves, scales or turns the items by `transform` (canvas coordinates).
    public func transformItems(_ ids: [Int], by transform: CGAffineTransform, coalescing key: String? = nil, words: String? = nil) {
        let movable = movableItems(ids)
        let parts = library.components
        let lines = loneLines(movable)
        let before = strokes(lines)
        updateItems(movable, coalescing: key) { item in
            item = item.transformed(by: transform)
            // A use is placed afresh from its part, so it stays exact.
            if case .instance(var instance) = item, let part = parts.first(where: { $0.id == instance.component }) {
                instance.content = Self.placed(part, instance, colors: library.colors)
                item = .instance(instance)
            }
        }
        let followed = followLines(lines, before: before, moved: movable)
        nextStepNote = (words ?? L("\(describe(movable))を動かした", "Moved \(describe(movable))")) + followedWords(followed)
    }

    /// Scales the items about the middle of all of them.
    public func scaleItems(_ ids: [Int], by factor: CGFloat, coalescing key: String? = nil) {
        guard let middle = selectionBounds(ids).map({ CGPoint(x: $0.midX, y: $0.midY) }) else { return }
        let transform = CGAffineTransform(translationX: middle.x, y: middle.y).scaledBy(x: factor, y: factor).translatedBy(x: -middle.x, y: -middle.y)
        transformItems(ids, by: transform, coalescing: key, words: L("\(describe(movableItems(ids)))の大きさを変えた", "Resized \(describe(movableItems(ids)))"))
    }

    /// Makes the strokes among the items wavier (over 1) or calmer (under 1).
    public func changeWaviness(_ ids: [Int], by factor: CGFloat, coalescing key: String? = nil) {
        let lines = loneLines(ids)
        let before = strokes(lines)
        updateItems(ids, coalescing: key) { $0 = $0.withWaviness(factor) }
        let followed = followLines(lines, before: before, moved: ids)
        nextStepNote = L("\(describe(ids))のうねりを変えた", "Changed the wobble of \(describe(ids))") + followedWords(followed)
    }

    /// The lines among the items, inside groups too, but not those inside a
    /// use of a part: those change the part.
    private func loneLines(_ ids: [Int]) -> [Int] {
        ids.flatMap { id -> [Int] in
            guard instanceHolding(id) == nil, let found = item(id)?.item else { return [] }
            if case .instance = found { return [] }
            return found.flattened.compactMap { item in
                if case .stroke(let stroke) = item, !stroke.isEraser { return stroke.id }
                return nil
            }
        }
    }

    private func followedWords(_ count: Int) -> String {
        count == 0 ? "" : L("（塗り \(count) つも線に合わせた）", " (and refilled \(count) fills to match)")
    }

    /// After lines changed shape, paints again the fills they bound, from the
    /// points the fills were made from, so each fill follows its outline as
    /// if the lines had been drawn that way to begin with. Only fills made
    /// after one of the lines count: an older fill was not bounded by them.
    /// A fill whose outline opened up, so that its paint would run out, stays
    /// as it was. Part of the step already begun. Returns how many changed.
    @discardableResult
    func followLines(_ lines: [Int], before: [Stroke], moved: [Int]) -> Int {
        guard let oldest = lines.min(), let after = selectionBounds(lines) else { return 0 }
        let skip = Set(moved.flatMap { id in item(id)?.item.flattened.map(\.id) ?? [] })
        let area = before.reduce(after) { $0.union(LayerItem.stroke($1).bounds(canvas: bounds)) }
        // A fill may change only where its lines passed through on the way.
        let allowed = Raster.makeLayerContext(width: width, height: height)
        allowed.setFillColor(CGColor(gray: 1, alpha: 1))
        allowed.setStrokeColor(CGColor(gray: 1, alpha: 1))
        for (old, new) in zip(before, strokes(lines)) {
            for stroke in [old, new] {
                allowed.setLineWidth(stroke.width + 8)
                allowed.addLines(between: stroke.points.map(\.point))
                allowed.strokePath()
            }
            guard old.points.count == new.points.count else {
                allowed.fill(LayerItem.stroke(old).bounds(canvas: bounds).union(LayerItem.stroke(new).bounds(canvas: bounds)))
                continue
            }
            for index in old.points.indices.dropLast() {
                allowed.addLines(between: [old.points[index].point, old.points[index + 1].point, new.points[index + 1].point, new.points[index].point])
                allowed.closePath()
            }
            allowed.fillPath()
        }
        return refillAround(area, madeAfter: oldest, skipping: skip, allowed: allowed)
    }

    private func strokes(_ ids: [Int]) -> [Stroke] {
        ids.compactMap { id in
            if case .stroke(let stroke)? = item(id)?.item { return stroke }
            return nil
        }
    }

    /// Takes lines out and lets the fills they bound spread into where they
    /// were, as if they had never been drawn, such as the white of an old
    /// eye once its outline is gone. The fills spread only inside `areas`. One step.
    public func eraseLines(_ ids: [Int], within areas: [CGRect]) {
        let area = areas.reduce(CGRect.null) { $0.union($1) }
        let lines = strokes(ids).map(\.id)
        guard let oldest = lines.min() else { return deleteItems(ids) }
        let allowed = Raster.makeLayerContext(width: width, height: height)
        allowed.setFillColor(CGColor(gray: 1, alpha: 1))
        areas.forEach { allowed.fill($0.insetBy(dx: -4, dy: -4)) }
        transaction {
            deleteItems(ids)
            refillAround(area, madeAfter: oldest, skipping: [], allowed: allowed)
        }
    }

    /// Paints again, from where they were made, the fills made after item
    /// `oldest` that reach into `area`, except those in `skip`. A fill whose
    /// new shape differs from the old outside `allowed` would have run out
    /// through an opening, and is left as it was.
    @discardableResult
    private func refillAround(_ area: CGRect, madeAfter oldest: Int, skipping skip: Set<Int>, allowed: CGContext) -> Int {
        let reach = area.insetBy(dx: -4, dy: -4)
        var targets: [Int: FillItem] = [:]
        func collect(_ items: [LayerItem]) {
            for item in items {
                switch item {
                case .fill(let fill) where fill.seed != nil && fill.id > oldest && !skip.contains(fill.id) && fill.rect.intersects(reach):
                    targets[fill.id] = fill
                case .group(let group):
                    collect(group.items)
                default:
                    break
                }
            }
        }
        layers.filter { !$0.isComposition }.forEach { collect($0.items) }
        guard !targets.isEmpty else { return 0 }
        // The picture without those fills, to paint them again from.
        let kept = layers
        revisionCounter += 1
        for index in layers.indices {
            let items = targets.keys.reduce(layers[index].items) { Self.removing($1, from: $0) }
            guard items.count != layers[index].items.count || items.flatMap(\.flattened).count != layers[index].items.flatMap(\.flattened).count else { continue }
            layers[index].items = items
            layers[index].revision = revisionCounter
        }
        syncCaches()
        let picture = compositeContext(background: .white)
        layers = kept
        var fresh: [Int: FillItem] = [:]
        for (id, old) in targets {
            guard let seed = old.seed, var fill = BucketFill.run(picture: picture, seed: seed, color: old.color, scratch: fillScratch),
                  stays(old, fill, inside: allowed)
            else { continue }
            fill.id = id
            fill.seed = seed
            fill.colorRef = old.colorRef
            fresh[id] = fill
        }
        revisionCounter += 1
        for index in layers.indices {
            var items = layers[index].items
            let changed = fresh.filter { id, fill in Self.modify(&items, id: id) { $0 = .fill(fill) } }
            // Every layer the fills were lifted from is drawn again.
            if !changed.isEmpty || layers[index].items.contains(where: { $0.flattened.contains { targets[$0.id] != nil } }) {
                layers[index].items = items
                layers[index].revision = revisionCounter
            }
            changed.keys.forEach { touch($0, inLayerAt: index) }
        }
        syncCaches()
        invalidate(nil)
        return fresh.count
    }

    /// Whether the new fill differs from the old only inside `allowed`.
    private func stays(_ old: FillItem, _ new: FillItem, inside allowed: CGContext) -> Bool {
        let a = Raster.makeLayerContext(width: width, height: height)
        let b = Raster.makeLayerContext(width: width, height: height)
        Raster.draw(.fill(old), in: a)
        Raster.draw(.fill(new), in: b)
        guard let pa = a.data, let pb = b.data, let pm = allowed.data else { return false }
        let row = a.bytesPerRow
        let area = old.rect.union(new.rect).intersection(bounds).integral
        var outside = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                let offset = y * row + x * 4 + 3
                let filled = pa.load(fromByteOffset: offset, as: UInt8.self) > 127
                let fills = pb.load(fromByteOffset: offset, as: UInt8.self) > 127
                if filled != fills, pm.load(fromByteOffset: offset, as: UInt8.self) == 0 {
                    outside += 1
                    if outside > 40 { return false }
                }
            }
        }
        return true
    }

    /// Takes the items out, as one step. One inside a use of a part goes from
    /// the part, and so from every use.
    public func deleteItems(_ ids: [Int]) {
        let inParts = ids.filter { partItem($0) != nil }
        transaction {
            if !inParts.isEmpty { removeFromComponent(inParts) }
            ids.filter { !inParts.contains($0) }.forEach(deleteItem)
        }
    }

    /// Whether any of the items is inside a use of a part.
    public func reachesIntoPart(_ ids: [Int]) -> Bool {
        ids.contains { partItem($0) != nil }
    }

    /// The area all the items cover.
    public func selectionBounds(_ ids: [Int]) -> CGRect? {
        let area = ids.compactMap { item($0)?.item.bounds(canvas: bounds) }.reduce(CGRect.null) { $0.union($1) }
        return area.isNull ? nil : area
    }

    /// The items drawn wholly inside `rect` on the visible layers, back to
    /// front. Pictures and gradients cover the canvas, so they are left out.
    public func items(in rect: CGRect) -> [Int] {
        layers.filter { $0.isVisible && !$0.isComposition }.flatMap { layer in
            layer.items.filter { item in
                switch item {
                case .bitmap, .gradient: return false
                case .stroke(let stroke) where stroke.isEraser: return false
                default: return rect.contains(item.bounds(canvas: bounds))
                }
            }.map(\.id)
        }
    }

    /// Every line and fill painted in `color`, like selecting every
    /// occurrence of a word.
    public func items(coloured color: RGBA) -> [Int] {
        func same(_ a: RGBA) -> Bool {
            abs(a.r - color.r) < 0.004 && abs(a.g - color.g) < 0.004 && abs(a.b - color.b) < 0.004
        }
        return layers.filter { !$0.isComposition }.flatMap { $0.items.flatMap(\.flattened) }.compactMap { item in
            switch item {
            case .stroke(let stroke) where !stroke.isEraser && same(stroke.color): return item.id
            case .fill(let fill) where same(fill.color): return item.id
            case .gradient(let gradient) where same(gradient.from): return item.id
            default: return nil
            }
        }
    }

    /// What the items are, in words: "線 3 本と塗り 2 つ".
    func describe(_ ids: [Int]) -> String {
        var lines = 0, fills = 0, others = 0
        for id in ids {
            switch item(id)?.item {
            case .stroke?: lines += 1
            case .fill?: fills += 1
            default: others += 1
            }
        }
        var parts: [String] = []
        if lines > 0 { parts.append(L("線 \(lines) 本", "\(lines) lines")) }
        if fills > 0 { parts.append(L("塗り \(fills) つ", "\(fills) fills")) }
        if others > 0 { parts.append(L("ほか \(others) 個", "\(others) other items")) }
        return parts.joined(separator: L("と", " and "))
    }
}
