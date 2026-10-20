import CoreGraphics
import Foundation

/// Named colours: lines, fills and gradients can take their colour from a
/// name, like code using a variable, so changing the name's colour changes
/// all of them in one step.
extension CanvasDocument {
    /// Gives a colour a name and returns it.
    @discardableResult
    public func addSwatch(named name: String, color: RGBA) -> UUID {
        let swatch = Swatch(name: name, color: RGBA(r: color.r, g: color.g, b: color.b))
        changeLibrary { $0.swatches.append(swatch) }
        return swatch.id
    }

    public func renameSwatch(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = library.swatches.firstIndex(where: { $0.id == id }), library.swatches[index].name != trimmed else { return }
        changeLibrary { $0.swatches[index].name = trimmed }
    }

    /// Takes the name away. Whatever used it keeps the colour it has.
    public func removeSwatch(_ id: UUID) {
        guard library.swatch(id) != nil else { return }
        changeLibrary { library in
            library.swatches.removeAll { $0.id == id }
            for index in library.themes.indices { library.themes[index].colors[id] = nil }
        }
    }

    /// Changes a named colour, and with it everything that uses it. A drag
    /// on a colour picker is one undo step.
    public func setSwatchColor(_ id: UUID, _ color: RGBA, coalescing key: String? = nil) {
        guard let index = library.swatches.firstIndex(where: { $0.id == id }) else { return }
        let opaque = RGBA(r: color.r, g: color.g, b: color.b)
        guard library.swatches[index].color != opaque else { return }
        changeLibrary(coalescing: key) { $0.swatches[index].color = opaque }
        recolorEverything()
    }

    /// Makes the items take their colour from the named colour. Items inside
    /// a use of a part change the part.
    public func bind(_ ids: [Int], to swatchID: UUID, gradientEnd: LayerItem.GradientEnd = .both) {
        guard let swatch = library.swatch(swatchID) else { return }
        updateItems(ids) { $0 = $0.bound(to: swatch, gradientEnd: gradientEnd) }
    }

    /// Keeps the current colours of every name as a colour set.
    @discardableResult
    public func saveTheme(named name: String) -> UUID {
        let theme = ColorTheme(name: name, colors: library.colors)
        changeLibrary { library in
            library.themes.append(theme)
            library.currentTheme = theme.id
        }
        return theme.id
    }

    /// Sets every named colour to its value in the colour set.
    public func applyTheme(_ id: UUID) {
        guard let theme = library.themes.first(where: { $0.id == id }) else { return }
        changeLibrary { library in
            for index in library.swatches.indices {
                if let color = theme.colors[library.swatches[index].id] { library.swatches[index].color = color }
            }
            library.currentTheme = id
        }
        recolorEverything()
    }

    /// Changes the colour set's value for one name, without applying it.
    public func setThemeColor(_ themeID: UUID, swatch swatchID: UUID, _ color: RGBA) {
        guard let index = library.themes.firstIndex(where: { $0.id == themeID }) else { return }
        changeLibrary { $0.themes[index].colors[swatchID] = RGBA(r: color.r, g: color.g, b: color.b) }
    }

    /// One undoable change to the named colours, colour sets or parts.
    func changeLibrary(coalescing key: String? = nil, _ change: (inout Library) -> Void) {
        guard liveStroke == nil else { return }
        pushUndo(coalescing: key)
        var changed = library
        change(&changed)
        changed.revision += 1
        library = changed
    }

    /// Gives every item that uses a named colour that colour again, inside
    /// parts and their uses too. Part of the step already begun.
    func recolorEverything() {
        let colors = library.colors
        for index in library.components.indices {
            library.components[index].items = library.components[index].items.map { $0.recolored(colors) }
        }
        for index in layers.indices {
            let named = layers[index].items.filter { !$0.colorRefs.isEmpty }
            guard !named.isEmpty else { continue }
            revisionCounter += 1
            layers[index].items = layers[index].items.map { $0.colorRefs.isEmpty ? $0 : $0.recolored(colors) }
            layers[index].revision = revisionCounter
            named.forEach { touchedItems.insert($0.id) }
        }
        syncCaches()
        invalidate(nil)
    }
}

/// The colour part of a STYLE.md: the named colours and the colour sets,
/// so the picture's style can be read and kept with its other notes.
public enum StyleColors {
    static let begin = "<!-- oekaki-studio:colors -->"
    static let end = "<!-- /oekaki-studio:colors -->"

    static func hex(_ color: RGBA) -> String {
        String(format: "#%02X%02X%02X", Int((color.r * 255).rounded()), Int((color.g * 255).rounded()), Int((color.b * 255).rounded()))
    }

    /// The colours as a Markdown section.
    public static func section(for library: Library) -> String {
        var lines = [begin, "## " + L("色の名前", "Colour names"), "", "| " + L("名前", "Name") + " | " + L("色", "Colour") + " |", "|---|---|"]
        for swatch in library.swatches {
            lines.append("| \(swatch.name) | `\(hex(swatch.color))` |")
        }
        for theme in library.themes {
            lines += ["", "### " + L("色の組「\(theme.name)」", "Colour set \"\(theme.name)\""), ""]
            for swatch in library.swatches {
                if let color = theme.colors[swatch.id] { lines.append("- \(swatch.name): `\(hex(color))`") }
            }
        }
        lines.append(end)
        return lines.joined(separator: "\n")
    }

    /// `existing` STYLE.md text with its colour section replaced, or the
    /// section added at the end when it has none. The rest is left alone.
    public static func merged(_ library: Library, into existing: String) -> String {
        let section = section(for: library)
        if let start = existing.range(of: begin), let stop = existing.range(of: end, range: start.upperBound..<existing.endIndex) {
            return existing.replacingCharacters(in: start.lowerBound..<stop.upperBound, with: section)
        }
        let base = existing.isEmpty ? "# STYLE\n" : existing
        return base + (base.hasSuffix("\n") ? "\n" : "\n\n") + section + "\n"
    }
}
