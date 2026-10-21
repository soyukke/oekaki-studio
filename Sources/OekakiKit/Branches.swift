import CoreGraphics
import Foundation

/// Another version of the picture, kept beside it, like a branch of code.
public struct BranchInfo: Identifiable, Equatable {
    public let id: UUID
    public var name: String
    /// What the version changed, in a few words, when it came from a proposal.
    public var note: String?
    /// The named colours it changed, each before and after.
    public var colorChanges: [ColorChange] = []

    public init(id: UUID, name: String, note: String? = nil, colorChanges: [ColorChange] = []) {
        self.id = id
        self.name = name
        self.note = note
        self.colorChanges = colorChanges
    }
}

extension RGBA {
    /// The colour to the nearest of 256 levels, for telling whether two are the same.
    public var hexKey: Int { Int((r * 255).rounded()) << 16 | Int((g * 255).rounded()) << 8 | Int((b * 255).rounded()) }
}

/// A named colour as it was and as a version has it.
public struct ColorChange: Equatable {
    public var name: String
    public var before: RGBA
    public var after: RGBA

    public init(name: String, before: RGBA, after: RGBA) {
        self.name = name
        self.before = before
        self.after = after
    }
}

/// A version of the picture that is not the one being worked on: everything
/// needed to pick it up again where it was left.
struct BranchState {
    var snapshot: CanvasDocument.Snapshot
    var journal: [JournalStep]
    var undo: [CanvasDocument.Snapshot]
    var redo: [CanvasDocument.Snapshot]
}

/// A line the assistant proposes to draw, in canvas pixels.
public struct ProposedLine: Equatable {
    public var points: [CGPoint]
    public var width: CGFloat
    public var color: RGBA

    public init(points: [CGPoint], width: CGFloat, color: RGBA) {
        self.points = points
        self.width = width
        self.color = color
    }
}

/// A change to try on a version of its own: new values for named colours,
/// layers to show or hide, and lines to draw on a layer of their own (such
/// as a different mouth). The assistant's ideas come as these.
public struct Proposal: Equatable {
    public var name: String
    /// New colours, by the colour's name.
    public var colors: [String: RGBA]
    public var hiddenLayers: [String]
    public var shownLayers: [String]
    /// Lines drawn on a new layer on top, as ordinary lines that can be changed.
    public var lines: [ProposedLine] = []
    /// Areas, in canvas pixels, whose lines and fills are taken out first,
    /// such as the old mouth before a new one is drawn.
    public var erasedAreas: [CGRect] = []
    /// Where the idea came from, such as the assistant, in a few words.
    public var origin: String?

    /// What trying it changes, in a few words, such as "色: 空・影 ／ レイヤー「逆光」を隠す".
    public var summary: String {
        var parts: [String] = []
        if !colors.isEmpty {
            // The colours by name, so the change can be read without opening it.
            let names = colors.keys.sorted()
            let shown = names.prefix(4).joined(separator: L("・", ", "))
            let more = names.count > 4 ? L(" ほか \(names.count - 4)", " and \(names.count - 4) more") : ""
            parts.append(L("色: ", "colours: ") + shown + more)
        }
        if !hiddenLayers.isEmpty {
            parts.append(L("レイヤー「\(hiddenLayers.joined(separator: "」「"))」を隠す", "hides the layer \(hiddenLayers.joined(separator: ", "))"))
        }
        if !shownLayers.isEmpty {
            parts.append(L("レイヤー「\(shownLayers.joined(separator: "」「"))」を出す", "shows the layer \(shownLayers.joined(separator: ", "))"))
        }
        if !erasedAreas.isEmpty, !lines.isEmpty {
            parts.append(L("元の線を消して、線を \(lines.count) 本描き直す", "erases the old lines and draws \(lines.count) new ones"))
        } else if !erasedAreas.isEmpty {
            parts.append(L("線を消す", "erases lines"))
        } else if !lines.isEmpty {
            parts.append(L("上に線を \(lines.count) 本描き足す", "draws \(lines.count) lines on top"))
        }
        return parts.joined(separator: L(" ／ ", " / "))
    }

    public init(
        name: String, colors: [String: RGBA] = [:], hiddenLayers: [String] = [], shownLayers: [String] = [], lines: [ProposedLine] = [],
        erasedAreas: [CGRect] = []
    ) {
        self.name = name
        self.colors = colors
        self.hiddenLayers = hiddenLayers
        self.shownLayers = shownLayers
        self.lines = lines
        self.erasedAreas = erasedAreas
    }
}

/// Versions: make one from the picture as it is, move between them, compare
/// them, and take one as the main picture. Each version keeps its own history.
extension CanvasDocument {
    /// The version the picture started as.
    public var mainBranch: UUID { branches[0].id }

    /// Keeps the version being worked on, so it can be picked up again.
    private func shelveCurrent() {
        flushJournal()
        branchStates[currentBranch] = BranchState(snapshot: snapshot, journal: journal, undo: undoStack, redo: redoStack)
    }

    private func takeUp(_ id: UUID) {
        guard let state = branchStates.removeValue(forKey: id) else { return }
        currentBranch = id
        restore(state.snapshot)
        journal = state.journal
        journalBase = pictureState
        undoStack = state.undo
        redoStack = state.redo
        journalPending = false
        touchedItems = []
        updateUndoFlags()
    }

    /// Starts a new version from the picture as it is now and returns it.
    /// It shares the history so far; from here each keeps its own.
    @discardableResult
    public func makeBranch(named name: String, switchingTo: Bool = true) -> UUID {
        flushJournal()
        let branch = BranchInfo(id: UUID(), name: name)
        branches.append(branch)
        branchStates[branch.id] = BranchState(snapshot: snapshot, journal: journal, undo: undoStack, redo: redoStack)
        if switchingTo { switchBranch(branch.id) }
        return branch.id
    }

    /// Moves to another version.
    public func switchBranch(_ id: UUID) {
        guard liveStroke == nil, id != currentBranch, branchStates[id] != nil else { return }
        shelveCurrent()
        takeUp(id)
    }

    public func renameBranch(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = branches.firstIndex(where: { $0.id == id }) else { return }
        branches[index].name = trimmed
        hasUnsavedChanges = true
    }

    /// Throws a version away. Not the main one, nor the one in hand.
    public func deleteBranch(_ id: UUID) {
        guard id != mainBranch, id != currentBranch else { return }
        branches.removeAll { $0.id == id }
        branchStates[id] = nil
        hasUnsavedChanges = true
    }

    /// Makes the main picture look like the version `id`, as one step on the
    /// main picture that can be taken back. Moves to the main picture.
    public func adoptBranch(_ id: UUID) {
        guard id != mainBranch else { return }
        if currentBranch != mainBranch { switchBranch(mainBranch) }
        guard let chosen = branchStates[id]?.snapshot ?? (id == currentBranch ? snapshot : nil) else { return }
        pushUndo()
        let taken = branches.first { $0.id == id }
        let name = taken?.name ?? ""
        // Say so when it was the assistant's idea.
        let fromAssistant = taken?.note?.hasPrefix(L("AI の案", "Assistant's idea")) == true
        nextStepNote = fromAssistant
            ? L("AI の案「\(name)」を本番にした", "Took the assistant's idea \"\(name)\" as the main picture")
            : L("案「\(name)」を本番にした", "Took \"\(name)\" as the main picture")
        revisionCounter += 1
        layers = chosen.layers.map { layer in
            var copy = layer
            copy.revision = revisionCounter
            return copy
        }
        figure = chosen.figure
        notes = chosen.notes
        var adopted = chosen.library
        adopted.revision = library.revision + 1
        library = adopted
        activeLayerID = layers.contains { $0.id == chosen.activeLayerID } ? chosen.activeLayerID : layers[layers.count - 1].id
        // Items keep their numbers but may have changed, so the journal must spell them out.
        layers.forEach { layer in layer.items.forEach { touchedItems.insert($0.id) } }
        syncCaches()
        invalidate(nil)
    }

    /// The picture of a version, on white unless `background` is nil.
    public func picture(ofBranch id: UUID, background: RGBA? = .white) -> CGImage? {
        if id == currentBranch { return compositeImage(background: background) }
        guard let state = branchStates[id] else { return nil }
        let pictureContext = Raster.makeContext(width: width, height: height)
        if let background {
            pictureContext.setFillColor(background.cgColor)
            pictureContext.fill(bounds)
        }
        let page = state.snapshot.library.page
        let sheets = state.snapshot.layers.filter { !$0.isComposition }.map { layer -> SheetPicture in
            let sheet = Raster.makeLayerContext(width: width, height: height)
            let clips = page?.clips(for: layer.style, in: bounds) ?? []
            layer.items.forEach { Raster.draw($0, in: sheet, panels: clips) }
            return SheetPicture(id: layer.id, image: sheet.makeImage(), isVisible: layer.isVisible, opacity: layer.opacity, style: layer.style, revision: 0)
        }
        let frames = page?.frameSheet(width: width, height: height, revision: 0)
        Compositor(width: width, height: height).flatten(sheets.withFrames(frames), onto: pictureContext)
        return pictureContext.makeImage()
    }

    /// Makes a new version from the picture as it is, with the proposal
    /// tried on it, and stays on the picture in hand. Returns the version.
    @discardableResult
    /// Where the idea came from, such as "AI の案", is put before what the version changed.
    public func branch(trying proposal: Proposal, origin: String? = nil) -> UUID {
        let origin = origin ?? proposal.origin
        let home = currentBranch
        let changes = library.swatches.compactMap { swatch -> ColorChange? in
            // Only the colours that really change.
            guard let new = proposal.colors[swatch.name], new.hexKey != swatch.color.hexKey else { return nil }
            return ColorChange(name: swatch.name, before: swatch.color, after: RGBA(r: new.r, g: new.g, b: new.b))
        }
        // The lines and fills wholly inside the areas to erase, on the visible layers.
        let erased = proposal.erasedAreas.flatMap(items(in:)).filter { id in
            switch item(id)?.item {
            case .stroke?, .fill?: return true
            default: return false
            }
        }
        let id = makeBranch(named: proposal.name)
        if let index = branches.firstIndex(where: { $0.id == id }) {
            // Name only the colours that really change, and erasing only when something goes.
            var said = proposal
            said.colors = said.colors.filter { name, _ in changes.contains { $0.name == name } }
            if erased.isEmpty { said.erasedAreas = [] }
            let what = said.summary.isEmpty ? L("変わる所なし", "no change") : said.summary
            branches[index].note = [origin, what].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            branches[index].colorChanges = changes
        }
        for (name, color) in proposal.colors {
            if let swatch = library.swatches.first(where: { $0.name == name }) {
                setSwatchColor(swatch.id, color)
            }
        }
        for name in proposal.hiddenLayers {
            if let layer = layers.first(where: { $0.name == name }) { setLayerVisible(layer.id, false) }
        }
        for name in proposal.shownLayers {
            if let layer = layers.first(where: { $0.name == name }) { setLayerVisible(layer.id, true) }
        }
        if !erased.isEmpty {
            eraseLines(Array(Set(erased)).sorted(), within: proposal.erasedAreas)
        }
        if !proposal.lines.isEmpty {
            // On a layer of their own on top, drawn one by one like any lines.
            let layer = insertLayer(named: L("AI の線", "Assistant's lines"), items: [], at: layers.count)
            for line in proposal.lines where !line.points.isEmpty {
                let points = line.points.map { StrokePoint(x: $0.x, y: $0.y) }
                guard beginStroke(at: points[0], color: line.color, width: line.width, isEraser: false, on: layer) else { continue }
                points.dropFirst().forEach(continueStroke)
                endStroke()
            }
        }
        switchBranch(home)
        return id
    }

    /// The colour sets as proposals, for when the assistant is not at hand.
    public var themeProposals: [Proposal] {
        library.themes.map { theme in
            var proposal = Proposal(name: L("\(theme.name)の色", "\(theme.name) colours"), colors: Dictionary(uniqueKeysWithValues: library.swatches.compactMap { swatch in
                theme.colors[swatch.id].map { (swatch.name, $0) }
            }))
            proposal.origin = L("色の組から", "From a colour set")
            return proposal
        }
    }
}
