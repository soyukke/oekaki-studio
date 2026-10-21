import CoreGraphics
import Foundation

/// Parts: items drawn once and put on the canvas many times, like a function
/// called from many places. Changing the part changes every use of it.
extension CanvasDocument {
    /// What a use of `part` draws: the items of the drawing it shows, placed
    /// and coloured for it. Keeps the numbers the use's items already have.
    static func placed(_ part: Component, _ use: InstanceItem, colors: [UUID: RGBA]) -> [LayerItem] {
        let own = colors.merging(use.overrides) { _, mine in mine }
        let transform = use.placement.transform
        return part.items(for: use.look).enumerated().map { index, item in
            let drawn = item.transformed(by: transform).recolored(own)
            // A new use's items get numbers of their own when it is put down.
            return use.content.indices.contains(index) ? Self.renumbered(drawn, like: use.content[index]) : Self.renumbered(drawn, like: nil)
        }
    }

    /// `item` carrying the numbers of `old`, item for item, or none (0) without it.
    private static func renumbered(_ item: LayerItem, like old: LayerItem?) -> LayerItem {
        var numbers = (old?.flattened.map(\.id) ?? []).makeIterator()
        func next(_ item: LayerItem) -> LayerItem {
            let id = numbers.next() ?? 0
            switch item {
            case .stroke(var stroke): stroke.id = id; return .stroke(stroke)
            case .fill(var fill): fill.id = id; return .fill(fill)
            case .gradient(var gradient): gradient.id = id; return .gradient(gradient)
            case .bitmap(let image, let alpha, _): return .bitmap(image, alpha: alpha, id: id)
            case .group(var group): group.id = id; group.items = group.items.map(next); return .group(group)
            case .instance(var instance): instance.id = id; instance.content = instance.content.map(next); return .instance(instance)
            }
        }
        return next(item)
    }

    /// Draws every use of a part again from the part. Part of the step already begun.
    func refreshUses(of partID: UUID) {
        guard let part = library.component(partID) else { return }
        let colors = library.colors
        for index in layers.indices {
            var touched: [Int] = []
            let items = layers[index].items.map { item -> LayerItem in
                guard case .instance(var use) = item, use.component == partID else { return item }
                use.content = Self.placed(part, use, colors: colors)
                use.content = use.content.map { Self.numbered($0, counter: &itemCounter) }
                touched.append(use.id)
                return .instance(use)
            }
            guard !touched.isEmpty else { continue }
            revisionCounter += 1
            layers[index].items = items
            layers[index].revision = revisionCounter
            touched.forEach { touchedItems.insert($0) }
        }
        syncCaches()
        invalidate(nil)
    }

    /// Turns the selected items into a part named `name`, used once where they
    /// were. The items leave their layers and become the part. Returns the use.
    @discardableResult
    public func makeComponent(from ids: [Int], named name: String) -> Int? {
        // Whole items only: the outermost item holding each selected one.
        var picked: [(layer: Int, position: Int, item: LayerItem)] = []
        for (layerIndex, layer) in layers.enumerated() {
            for (position, item) in layer.items.enumerated() where ids.contains(where: { id in item.flattened.contains { $0.id == id } }) {
                if case .instance = item { continue }
                picked.append((layerIndex, position, item))
            }
        }
        guard let first = picked.first else { return nil }
        let area = picked.map { $0.item.bounds(canvas: bounds) }.reduce(CGRect.null) { $0.union($1) }
        // A whole-pixel centre, so fills move without being redrawn.
        let center = CGPoint(x: area.midX.rounded(), y: area.midY.rounded())
        let toPart = CGAffineTransform(translationX: -center.x, y: -center.y)
        let part = Component(name: name, items: picked.map { $0.item.transformed(by: toPart) })
        var use = InstanceItem(component: part.id, placement: Placement(center: center))
        use.content = Self.placed(part, use, colors: library.colors)
        transaction {
            changeLibrary { $0.components.append(part) }
            let taken = Set(picked.map { $0.item.id })
            for index in layers.indices where picked.contains(where: { $0.layer == index }) {
                revisionCounter += 1
                layers[index].items.removeAll { taken.contains($0.id) }
                layers[index].revision = revisionCounter
            }
            var numbered = Self.numbered(.instance(use), counter: &itemCounter)
            if case .instance(let made) = numbered { use = made }
            numbered = .instance(use)
            revisionCounter += 1
            layers[first.layer].items.insert(numbered, at: min(first.position, layers[first.layer].items.count))
            layers[first.layer].revision = revisionCounter
        }
        activeLayerID = layers[first.layer].id
        syncCaches()
        invalidate(nil)
        return use.id
    }

    /// Puts another use of the part on the active layer, centred on `point`.
    @discardableResult
    public func placeComponent(_ partID: UUID, at point: CGPoint, scale: CGFloat = 1) -> Int? {
        guard liveStroke == nil, let part = library.component(partID),
              let index = layers.firstIndex(where: { $0.id == activeLayerID }), layers[index].isVisible
        else { return nil }
        var use = InstanceItem(component: partID, placement: Placement(center: point, scale: scale))
        use.content = Self.placed(part, use, colors: library.colors)
        pushUndo()
        nextStepNote = L("部品「\(part.name)」を置いた", "Placed the part \"\(part.name)\"")
        appendItem(.instance(use), toLayerAt: index, alreadyDrawn: false)
        invalidate(nil)
        return layers[index].items.last?.id
    }

    /// Moves, sizes, turns or mirrors one use of a part.
    public func setPlacement(_ useID: Int, _ placement: Placement, coalescing key: String? = nil) {
        let parts = library.components
        let colors = library.colors
        updateItems([useID], coalescing: key) { item in
            guard case .instance(var use) = item, let part = parts.first(where: { $0.id == use.component }) else { return }
            use.placement = placement
            use.content = Self.placed(part, use, colors: colors)
            item = .instance(use)
        }
    }

    /// Gives one use of a part its own colour for a named colour, or takes
    /// it away with nil.
    public func setOverride(_ useID: Int, swatch swatchID: UUID, _ color: RGBA?, coalescing key: String? = nil) {
        let parts = library.components
        let colors = library.colors
        let name = library.swatch(swatchID)?.name ?? ""
        defer { nextStepNote = L("ここに置いた 1 つだけ「\(name)」の色を変えた", "Changed \"\(name)\" for one copy only") }
        updateItems([useID], coalescing: key) { item in
            guard case .instance(var use) = item, let part = parts.first(where: { $0.id == use.component }) else { return }
            use.overrides[swatchID] = color.map { RGBA(r: $0.r, g: $0.g, b: $0.b) }
            use.content = Self.placed(part, use, colors: colors)
            item = .instance(use)
        }
    }

    /// Cuts one use loose from its part: it becomes a group of its own items,
    /// which no longer follow the part.
    public func detach(_ useID: Int) {
        let names = library.components
        updateItems([useID]) { item in
            guard case .instance(let use) = item else { return }
            let name = names.first { $0.id == use.component }?.name ?? L("部品", "Part")
            item = .group(GroupItem(id: use.id, name: name, items: use.content, alpha: 1))
        }
    }

    /// The use of a part the items reach into, as the use itself or an item
    /// inside it, when they reach into just one; and the items outside every part.
    public func partAndOthers(_ ids: [Int]) -> (use: Int, part: UUID, others: [Int])? {
        var uses = Set<Int>()
        var others: [Int] = []
        for id in ids {
            if let use = instanceHolding(id) {
                uses.insert(use)
            } else if case .instance? = item(id)?.item {
                uses.insert(id)
            } else if item(id) != nil {
                others.append(id)
            }
        }
        guard uses.count == 1, let use = uses.first, case .instance(let found)? = item(use)?.item else { return nil }
        return (use, found.component, others)
    }

    /// Puts the items into the drawing of the part that `useID` shows, where
    /// they are now on the canvas, so every use showing it gains them. They
    /// leave their layers.
    public func addToComponent(_ ids: [Int], joining useID: Int) {
        guard liveStroke == nil, case .instance(let use)? = item(useID)?.item,
              let partIndex = library.components.firstIndex(where: { $0.id == use.component })
        else { return }
        // Whole items only, and not parts themselves.
        var picked: [(layer: Int, item: LayerItem)] = []
        for (layerIndex, layer) in layers.enumerated() {
            for item in layer.items where ids.contains(where: { id in item.flattened.contains { $0.id == id } }) {
                if case .instance = item { continue }
                picked.append((layerIndex, item))
            }
        }
        guard !picked.isEmpty else { return }
        let toPart = use.placement.transform.inverted()
        let name = library.components[partIndex].name
        let look = library.components[partIndex].lookIndex(use.look)
        let words = describe(picked.map(\.item.id))
        transaction {
            changeLibrary { $0.components[partIndex].looks[look].items += picked.map { $0.item.transformed(by: toPart) } }
            let taken = Set(picked.map(\.item.id))
            for index in Set(picked.map(\.layer)) {
                revisionCounter += 1
                layers[index].items.removeAll { taken.contains($0.id) }
                layers[index].revision = revisionCounter
            }
            refreshUses(of: use.component)
        }
        nextStepNote = L("部品「\(name)」に\(words)を足した", "Added \(words) to the part \"\(name)\"")
    }

    /// Takes the items, which are inside uses of a part, out of the drawing
    /// those uses show, so they go from every use showing it. A drawing keeps
    /// at least one item.
    public func removeFromComponent(_ ids: [Int]) {
        guard liveStroke == nil else { return }
        struct Drawing: Hashable { var part: UUID; var look: Int }
        var gone: [Drawing: Set<Int>] = [:]
        for id in ids {
            if let place = partItem(id), let part = library.component(place.component) {
                gone[Drawing(part: place.component, look: part.lookIndex(place.look)), default: []].insert(place.index)
            }
        }
        guard gone.count == 1, let (drawing, indices) = gone.first,
              let partIndex = library.components.firstIndex(where: { $0.id == drawing.part }),
              indices.count < library.components[partIndex].looks[drawing.look].items.count
        else { return }
        let partID = drawing.part
        let part = library.components[partIndex]
        let name = part.name
        let words = describe(ids.filter { partItem($0) != nil })
        transaction {
            changeLibrary { library in
                let items = library.components[partIndex].looks[drawing.look].items
                library.components[partIndex].looks[drawing.look].items = items.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
            }
            // Each use showing it lets go of the same items, so the rest keep their numbers.
            for index in layers.indices {
                layers[index].items = layers[index].items.map { item in
                    guard case .instance(var use) = item, use.component == partID, part.lookIndex(use.look) == drawing.look else { return item }
                    use.content = use.content.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
                    return .instance(use)
                }
            }
            refreshUses(of: partID)
        }
        nextStepNote = L("部品「\(name)」から\(words)を消した", "Took \(words) out of the part \"\(name)\"")
    }

    /// Gives the part that `useID` shows another drawing, a copy of the one
    /// shown there, and shows the copy there, ready to be changed: a smile
    /// drawn over a copy of the plain face. The other uses stay as they were.
    /// Returns the new drawing.
    @discardableResult
    public func addLook(copying useID: Int, named name: String) -> UUID? {
        guard liveStroke == nil, case .instance(let use)? = item(useID)?.item,
              let partIndex = library.components.firstIndex(where: { $0.id == use.component })
        else { return nil }
        let part = library.components[partIndex]
        let look = ComponentLook(name: name, items: part.items(for: use.look))
        transaction {
            changeLibrary { $0.components[partIndex].looks.append(look) }
            show(look.id, at: useID)
        }
        nextStepNote = L("部品「\(part.name)」に描き分け「\(look.title)」を足した", "Added the variation \"\(look.title)\" to the part \"\(part.name)\"")
        return look.id
    }

    /// Shows the part's drawing `look` at this one use only.
    public func setLook(_ useID: Int, _ look: UUID) {
        guard liveStroke == nil, case .instance(let use)? = item(useID)?.item,
              let part = library.component(use.component), part.lookIndex(use.look) != part.lookIndex(look),
              let shown = part.looks.first(where: { $0.id == look })
        else { return }
        transaction { show(look, at: useID) }
        nextStepNote = L("ここに置いた「\(part.name)」を「\(shown.title)」にした", "Showed \"\(shown.title)\" for this copy of \"\(part.name)\"")
    }

    /// Draws the use `useID` from its part's drawing `look`. Part of the step already begun.
    private func show(_ look: UUID, at useID: Int) {
        guard let part = item(useID).flatMap({ found -> Component? in
            guard case .instance(let use) = found.item else { return nil }
            return library.component(use.component)
        }) else { return }
        let colors = library.colors
        for index in layers.indices {
            var items = layers[index].items
            let changed = Self.modify(&items, id: useID) { item in
                guard case .instance(var use) = item else { return }
                use.look = part.lookIndex(look) == 0 ? nil : look
                use.content = Self.placed(part, use, colors: colors)
                item = .instance(use)
            }
            guard changed else { continue }
            // A drawing with more items than the last one gives the new ones numbers.
            layers[index].items = items.map { Self.numbered($0, counter: &itemCounter) }
            revisionCounter += 1
            layers[index].revision = revisionCounter
            touch(useID, inLayerAt: index)
            break
        }
        syncCaches()
        invalidate(nil)
    }

    /// Renames one of a part's drawings.
    public func renameLook(_ partID: UUID, _ look: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let partIndex = library.components.firstIndex(where: { $0.id == partID }),
              let lookIndex = library.components[partIndex].looks.firstIndex(where: { $0.id == look }),
              library.components[partIndex].looks[lookIndex].name != trimmed
        else { return }
        changeLibrary { $0.components[partIndex].looks[lookIndex].name = trimmed }
        nextStepNote = L("描き分けの名前を「\(trimmed)」にした", "Renamed a variation to \"\(trimmed)\"")
    }

    /// Takes one of a part's drawings away. The uses that showed it show the
    /// first drawing instead. A part keeps at least one drawing.
    public func removeLook(_ partID: UUID, _ look: UUID) {
        guard liveStroke == nil, let partIndex = library.components.firstIndex(where: { $0.id == partID }),
              library.components[partIndex].looks.count > 1,
              let lookIndex = library.components[partIndex].looks.firstIndex(where: { $0.id == look })
        else { return }
        let title = library.components[partIndex].looks[lookIndex].title
        transaction {
            changeLibrary { $0.components[partIndex].looks.remove(at: lookIndex) }
            for index in layers.indices {
                layers[index].items = layers[index].items.map { item in
                    guard case .instance(var use) = item, use.component == partID, use.look == look else { return item }
                    use.look = nil
                    return .instance(use)
                }
            }
            refreshUses(of: partID)
        }
        nextStepNote = L("描き分け「\(title)」を消した", "Deleted the variation \"\(title)\"")
    }

    /// Renames a part.
    public func renameComponent(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = library.components.firstIndex(where: { $0.id == id }) else { return }
        changeLibrary { $0.components[index].name = trimmed }
    }

    /// Every use of a part that shows its drawing `look`, by number.
    public func uses(of partID: UUID, showing look: UUID) -> [Int] {
        guard let part = library.component(partID) else { return [] }
        let wanted = part.lookIndex(look)
        return layers.flatMap { $0.items.flatMap(\.flattened) }.compactMap { item in
            if case .instance(let use) = item, use.component == partID, part.lookIndex(use.look) == wanted { return use.id }
            return nil
        }
    }

    /// Every use of a part, by number.
    public func uses(of partID: UUID) -> [Int] {
        layers.flatMap { $0.items.flatMap(\.flattened) }.compactMap { item in
            if case .instance(let use) = item, use.component == partID { return use.id }
            return nil
        }
    }
}
