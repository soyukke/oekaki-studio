import AppKit
import Combine
import OekakiKit
import SwiftUI

/// The scrolling, zooming area that holds the canvas.
struct CanvasView: NSViewRepresentable {
    let document: CanvasDocument
    let tools: ToolState
    let controller: CanvasController

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 16
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.documentView = CanvasNSView(document: document, tools: tools)
        controller.attach(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}
}

/// Keeps the canvas in the middle when it is smaller than the window.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        if rect.width > documentView.frame.width {
            rect.origin.x = (documentView.frame.width - rect.width) / 2
        }
        if rect.height > documentView.frame.height {
            rect.origin.y = (documentView.frame.height - rect.height) / 2
        }
        return rect
    }
}

/// Draws the layers and turns mouse and pen input into strokes.
///
/// One point in this view is one canvas pixel; the scroll view does the zooming.
final class CanvasNSView: NSView {
    private let document: CanvasDocument
    private let tools: ToolState
    private var cancellables: Set<AnyCancellable> = []
    /// Two fingers tapped on the trackpad take back, three do again.
    private var fingerTaps = FingerTaps()
    private var smoothed: CGPoint?
    private var lastPressure: CGFloat = 1
    private var hover: CGPoint?
    /// The doll part being dragged, where it was held from, and the undo key of the drag.
    private var holding: (part: Figure.Part, grab: CGVector, key: String)?
    private var dragCounter = 0
    /// A note being moved, how far from its corner it was held, and whether it moved.
    private var heldNote: (id: UUID, offset: CGVector, moved: Bool, key: String)?
    /// Where an arrow for a new note was started, and where it reaches now.
    private var arrow: (start: CGPoint, end: CGPoint)?
    /// A gradient being dragged out, from where the colour starts to where it fades.
    private var gradientDrag: (start: CGPoint, end: CGPoint)?
    /// The outline being drawn round an area with the lasso fill.
    private var shapeDrag: [CGPoint]?
    /// The ruler line being drawn to cut a panel.
    private var panelDrag: (start: CGPoint, end: CGPoint)?
    /// The selection being dragged along: where the pointer was, the part of
    /// a pixel not moved yet, and the undo key of the drag.
    private var moving: (last: CGPoint, carry: CGVector, key: String)?
    /// An area being dragged out to select what lies inside it, and the item
    /// under the pointer when it began, picked instead if the pointer barely moves.
    private var lasso: (start: CGPoint, end: CGPoint, adding: Bool, clicked: Int?)?
    /// Notes the composition eraser passed over, removed when it lifts.
    private var erasedNotes: Set<UUID> = []
    /// The note being written, not yet in the document, and its text field.
    private var draft: (note: Note, isNew: Bool, field: NSTextField)?

    init(document: CanvasDocument, tools: ToolState) {
        self.document = document
        self.tools = tools
        super.init(frame: document.bounds)
        allowedTouchTypes = [.indirect]
        document.onInvalidate = { [weak self] rect in
            guard let self else { return }
            if let rect {
                self.setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
            } else {
                self.needsDisplay = true
            }
        }
        // The size ring follows the tool settings.
        Publishers.Merge3(
            tools.$tool.map { _ in () }, tools.$brushSize.map { _ in () }, tools.$eraserSize.map { _ in () }
        )
        .sink { [weak self] in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
        .store(in: &cancellables)
        tools.$selection
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.needsDisplay = true }
            }
            .store(in: &cancellables)
        Publishers.Merge(tools.$tool.map { _ in () }, tools.$planMode.map { _ in () })
            .sink { [weak self] in
                DispatchQueue.main.async { self?.finishDraft() }
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(.white)
        context.fill(bounds)
        // The doll lies on the paper, under every layer.
        if let figure = document.figure, figure.isVisible {
            figure.draw(in: context)
        }
        // The layers together, with their blend modes, clipping and glow.
        if let image = document.layersImage(region: dirtyRect.intersection(bounds)) {
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: bounds)
            context.restoreGState()
        }
        if let gradientDrag {
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2 * screenPixel)
            context.setLineDash(phase: 0, lengths: [6 * screenPixel, 4 * screenPixel])
            context.move(to: gradientDrag.start)
            context.addLine(to: gradientDrag.end)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            for point in [gradientDrag.start, gradientDrag.end] {
                let radius = 5 * screenPixel
                context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
            }
        }
        if let shapeDrag, let first = shapeDrag.first {
            // The outline so far, closed back to where it started.
            let path = CGMutablePath()
            path.addLines(between: shapeDrag)
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(tools.color.cgColor.copy(alpha: 0.35) ?? tools.color.cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5 * screenPixel)
            context.setLineDash(phase: 0, lengths: [6 * screenPixel, 4 * screenPixel])
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            let radius = 4 * screenPixel
            context.strokeEllipse(in: CGRect(x: first.x - radius, y: first.y - radius, width: 2 * radius, height: 2 * radius))
        }
        drawPanelGuide(in: context)
        NoteRenderer.draw(document.notes, in: context, skipping: draft?.note.id)
        if let arrow {
            context.setStrokeColor(NoteRenderer.ink)
            context.setLineWidth(3 * screenPixel)
            context.setLineDash(phase: 0, lengths: [8 * screenPixel, 6 * screenPixel])
            context.move(to: arrow.start)
            context.addLine(to: arrow.end)
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
        }
        drawSelection(in: context)
        drawSizeRing(in: context)
        drawFigureHandles(in: context)
    }

    // MARK: Panels

    /// With the panel tool, each panel's place in reading order, and the cut being drawn.
    private func drawPanelGuide(in context: CGContext) {
        guard tools.tool == .panel else { return }
        let accent = NSColor.controlAccentColor
        let size = 14 * screenPixel
        for (index, panel) in document.panels.enumerated() {
            let center = CGPoint(x: panel.maxX - size * 1.4, y: panel.minY + size * 1.4)
            context.setFillColor(accent.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - size, y: center.y - size, width: 2 * size, height: 2 * size))
            let label = NSAttributedString(string: "\(index + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: size * 1.1, weight: .bold), .foregroundColor: NSColor.white,
            ])
            let box = label.size()
            label.draw(at: CGPoint(x: center.x - box.width / 2, y: center.y - box.height / 2))
        }
        guard let panelDrag else { return }
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(2 * screenPixel)
        context.setLineDash(phase: 0, lengths: [8 * screenPixel, 5 * screenPixel])
        context.move(to: panelDrag.start)
        context.addLine(to: panelDrag.end)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    // MARK: Selection

    /// Picks the item that drew the spot under the pointer, like jumping from
    /// a word in a program to where it is defined. With `adding`, the item
    /// is added to the selection, or taken out if it was in, like ⌘-click
    /// placing another cursor.
    @discardableResult
    private func select(at point: CGPoint, adding: Bool = false) -> Int? {
        guard let found = document.trace(point, slack: 4 * screenPixel), let id = found.path.last else {
            if !adding { tools.selection = [] }
            return nil
        }
        document.activeLayerID = found.layerID
        if adding {
            tools.toggle(id)
        } else if !tools.selection.contains(id) {
            tools.selectedItem = id
        }
        return id
    }

    private func drawSelection(in context: CGContext) {
        for id in tools.selection {
            drawSelected(id, in: context)
        }
        if let lasso {
            let area = CGRect(x: min(lasso.start.x, lasso.end.x), y: min(lasso.start.y, lasso.end.y),
                              width: abs(lasso.end.x - lasso.start.x), height: abs(lasso.end.y - lasso.start.y))
            context.saveGState()
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor)
            context.fill(area)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5 * screenPixel)
            context.setLineDash(phase: 0, lengths: [6 * screenPixel, 4 * screenPixel])
            context.stroke(area)
            context.restoreGState()
        }
    }

    private func drawSelected(_ id: Int, in context: CGContext) {
        guard let found = document.item(id) else { return }
        let accent = NSColor.controlAccentColor.cgColor
        context.saveGState()
        // A soft glow, so many picked items read at a glance.
        context.setShadow(offset: .zero, blur: 8 * screenPixel, color: accent)
        if case .stroke(let stroke) = found.item, stroke.points.count > 1 {
            // The path of the line itself, drawn thin over it.
            context.setStrokeColor(accent)
            context.setLineWidth(1.5 * screenPixel)
            context.move(to: CGPoint(x: stroke.points[0].x, y: stroke.points[0].y))
            for point in stroke.points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            context.strokePath()
        }
        let box = found.item.bounds(canvas: bounds).insetBy(dx: -3 * screenPixel, dy: -3 * screenPixel)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(3 * screenPixel)
        context.stroke(box)
        context.setStrokeColor(accent)
        context.setLineWidth(1.5 * screenPixel)
        context.setLineDash(phase: 0, lengths: [6 * screenPixel, 4 * screenPixel])
        context.stroke(box)
        context.restoreGState()
    }

    // MARK: Trackpad taps

    override func touchesBegan(with event: NSEvent) { readFingers(event) }
    override func touchesMoved(with event: NSEvent) { readFingers(event) }
    override func touchesEnded(with event: NSEvent) { readFingers(event) }
    override func touchesCancelled(with event: NSEvent) { fingerTaps.cancel() }

    private func readFingers(_ event: NSEvent) {
        let touching = event.touches(matching: .touching, in: self).compactMap { touch -> (id: AnyHashable, position: CGPoint)? in
            guard let id = touch.identity as? NSObject else { return nil }
            return (AnyHashable(id), touch.normalizedPosition)
        }
        switch fingerTaps.update(touching: touching, at: event.timestamp) {
        case .two?:
            guard document.canUndo else { return }
            document.undo()
            tools.notice = L("取り消しました（2 本指タップ）", "Undone (two-finger tap)")
            tools.noticeIsGood = true
        case .three?:
            guard document.canRedo else { return }
            document.redo()
            tools.notice = L("やり直しました（3 本指タップ）", "Redone (three-finger tap)")
            tools.noticeIsGood = true
        case nil:
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        guard draft == nil, !tools.selection.isEmpty else {
            super.keyDown(with: event)
            return
        }
        let ids = tools.selection
        // Arrow keys nudge the selection a pixel, or ten with shift.
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            document.deleteItems(ids)
            tools.selection = []
        case 53: // Escape
            tools.selection = []
        case 123: document.transformItems(ids, by: CGAffineTransform(translationX: -step, y: 0), coalescing: "nudge")
        case 124: document.transformItems(ids, by: CGAffineTransform(translationX: step, y: 0), coalescing: "nudge")
        case 125: document.transformItems(ids, by: CGAffineTransform(translationX: 0, y: step), coalescing: "nudge")
        case 126: document.transformItems(ids, by: CGAffineTransform(translationX: 0, y: -step), coalescing: "nudge")
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Composition

    private var planInk: RGBA { RGBA(hex: 0x64748B) }
    private var planLineWidth: CGFloat { max(3, CGFloat(document.width) / 400) }

    private func note(at point: CGPoint) -> Note? {
        document.notes.last { NoteRenderer.box(of: $0).insetBy(dx: -4 * screenPixel, dy: -4 * screenPixel).contains(point) }
    }

    private func compositionMouseDown(at point: CGPoint, event: NSEvent) {
        switch tools.planMode {
        case .pose:
            guard let figure = document.figure, figure.isVisible,
                  let part = figure.part(at: point, reach: 16 * screenPixel)
            else {
                tools.notice = PlanMode.pose.hint
                return
            }
            dragCounter += 1
            let grab = CGVector(dx: point.x - figure.x, dy: point.y - figure.y)
            holding = (part, grab, "figure-\(dragCounter)")
            needsDisplay = true
        case .pen, .eraser:
            let isEraser = tools.planMode == .eraser
            let layer = document.makeCompositionLayer()
            lastPressure = pressure(of: event)
            smoothed = point
            erasedNotes = []
            let started = document.beginStroke(
                at: StrokePoint(x: point.x, y: point.y, pressure: isEraser ? 1 : lastPressure),
                color: planInk, width: isEraser ? tools.eraserSize : planLineWidth, isEraser: isEraser, on: layer
            )
            if !started {
                tools.notice = L(
                    "「構図」レイヤーが非表示なので描けません。右の一覧で目のマークを押すと表示されます。",
                    "The Composition layer is hidden. Click its eye icon in the list on the right to show it."
                )
            }
            if isEraser { eraseNotes(near: point) }
        case .note:
            if let held = note(at: point) {
                dragCounter += 1
                heldNote = (held.id, CGVector(dx: point.x - held.x, dy: point.y - held.y), false, "note-\(dragCounter)")
            } else {
                arrow = (point, point)
            }
        }
    }

    private func eraseNotes(near point: CGPoint) {
        let reach = tools.eraserSize / 2
        for note in document.notes where NoteRenderer.box(of: note).insetBy(dx: -reach, dy: -reach).contains(point) {
            erasedNotes.insert(note.id)
        }
    }

    /// Handles a drag for the composition tool. Returns false when the drag is a stroke.
    private func compositionMouseDragged(to point: CGPoint) -> Bool {
        if let holding, var figure = document.figure {
            figure.move(holding.part, to: point, grab: holding.grab)
            document.setFigure(figure, coalescing: holding.key)
            return true
        }
        if let held = heldNote {
            var notes = document.notes
            if let index = notes.firstIndex(where: { $0.id == held.id }) {
                notes[index].origin = CGPoint(x: point.x - held.offset.dx, y: point.y - held.offset.dy)
                document.setNotes(notes, coalescing: held.key)
                heldNote?.moved = true
            }
            return true
        }
        if let start = arrow?.start {
            arrow = (start, point)
            needsDisplay = true
            return true
        }
        if tools.tool == .figure, tools.planMode == .eraser {
            eraseNotes(near: point)
        }
        return false
    }

    /// Finishes a composition action. Returns false when it was a stroke.
    private func compositionMouseUp(at point: CGPoint) -> Bool {
        if holding != nil {
            holding = nil
            needsDisplay = true
            return true
        }
        if let held = heldNote {
            heldNote = nil
            if !held.moved, let note = document.notes.first(where: { $0.id == held.id }) {
                beginDraft(note, isNew: false)
            }
            return true
        }
        if let arrow {
            self.arrow = nil
            let dragged = hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y) > 24 * screenPixel
            let size = Note.fontSize(forCanvasWidth: document.width)
            // The text sits where the drag began, and the arrow points where it ended.
            let origin = CGPoint(x: arrow.start.x - size * 0.4, y: arrow.start.y - size * 0.8)
            beginDraft(Note(text: "", at: origin, pointingAt: dragged ? arrow.end : nil, fontSize: size), isNew: true)
            needsDisplay = true
            return true
        }
        return false
    }

    private func removeErasedNotes() {
        guard !erasedNotes.isEmpty else { return }
        document.setNotes(document.notes.filter { !erasedNotes.contains($0.id) })
        erasedNotes = []
    }

    // MARK: Writing a note

    private func beginDraft(_ note: Note, isNew: Bool) {
        finishDraft()
        let field = NoteField(frame: .zero)
        field.stringValue = note.text
        field.font = NSFont.systemFont(ofSize: note.fontSize)
        field.textColor = NSColor(cgColor: NoteRenderer.ink)
        field.backgroundColor = .white
        field.drawsBackground = true
        field.isBordered = true
        field.isBezeled = false
        field.focusRingType = .none
        field.placeholderString = L("メモを書いて Enter", "Type a note, then Enter")
        field.target = self
        field.action = #selector(noteFieldDone(_:))
        field.onCancel = { [weak self] in self?.cancelDraft() }
        field.onLoseFocus = { [weak self] in self?.finishDraft() }
        let box = NoteRenderer.box(of: note)
        field.frame = CGRect(x: note.x, y: note.y, width: max(box.width + note.fontSize * 4, note.fontSize * 12), height: box.height)
        addSubview(field)
        draft = (note, isNew, field)
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    @objc private func noteFieldDone(_ sender: NSTextField) {
        finishDraft()
    }

    /// Puts the note being written into the document, or removes it when left empty.
    private func finishDraft() {
        guard let draft else { return }
        self.draft = nil
        draft.field.removeFromSuperview()
        let text = draft.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = document.notes
        if text.isEmpty {
            notes.removeAll { $0.id == draft.note.id }
        } else {
            var note = draft.note
            note.text = text
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
            } else {
                notes.append(note)
            }
        }
        document.setNotes(notes)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelDraft() {
        guard let draft else { return }
        self.draft = nil
        draft.field.removeFromSuperview()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private var screenPixel: CGFloat { 1 / max(enclosingScrollView?.magnification ?? 1, 0.05) }

    /// Round knobs on the joints while the doll is being posed. The hips get a
    /// square one, since holding them moves the whole doll.
    private func drawFigureHandles(in context: CGContext) {
        guard tools.tool == .figure, tools.planMode == .pose, let figure = document.figure, figure.isVisible else { return }
        let radius = 7 * screenPixel
        context.setLineWidth(2 * screenPixel)
        for handle in figure.handles {
            let rect = CGRect(x: handle.point.x - radius, y: handle.point.y - radius, width: radius * 2, height: radius * 2)
            let isHeld = holding?.part == handle.part
            context.setFillColor(isHeld ? Figure.ink : .white)
            context.setStrokeColor(Figure.ink)
            if handle.part == .pelvis {
                let square = rect.insetBy(dx: -radius * 0.2, dy: -radius * 0.2)
                context.fill(square)
                context.stroke(square)
            } else {
                context.fillEllipse(in: rect)
                context.strokeEllipse(in: rect)
            }
        }
    }

    private var ringRect: CGRect? {
        guard let hover, let size = tools.activeSize else { return nil }
        return CGRect(x: hover.x - size / 2, y: hover.y - size / 2, width: size, height: size)
    }

    /// A circle the size of the brush, so the width of the next line is visible before drawing.
    private func drawSizeRing(in context: CGContext) {
        guard let ringRect else { return }
        let hairline = 1 / max(enclosingScrollView?.magnification ?? 1, 0.05)
        context.setLineWidth(hairline * 2.5)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.strokeEllipse(in: ringRect)
        context.setLineWidth(hairline)
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.75))
        context.strokeEllipse(in: ringRect)
    }

    private func moveHover(to point: CGPoint?) {
        let margin = 4 / max(enclosingScrollView?.magnification ?? 1, 0.05)
        if let ringRect { setNeedsDisplay(ringRect.insetBy(dx: -margin, dy: -margin)) }
        hover = point
        if let ringRect { setNeedsDisplay(ringRect.insetBy(dx: -margin, dy: -margin)) }
    }

    // MARK: Input

    private func pressure(of event: NSEvent) -> CGFloat {
        // A pen reports how hard it is pressed; a mouse or trackpad does not.
        guard event.subtype == .tabletPoint else { return 1 }
        return max(CGFloat(event.pressure), 0.02)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        tools.notice = nil
        let adding = event.modifierFlags.contains(.command)
        if adding {
            select(at: point, adding: true)
            return
        }
        if tools.tool == .select {
            let under = document.trace(point, slack: 4 * screenPixel)
            if let id = under?.path.last, tools.selection.contains(id) {
                // Pressing on something picked starts dragging all that is picked.
                dragCounter += 1
                moving = (point, .zero, "move-\(dragCounter)")
            } else {
                // Anywhere else a drag boxes things in; a click picks what is under it.
                lasso = (point, point, false, under?.path.last)
            }
            return
        }
        // Drawing something new moves the attention away from what was selected.
        tools.selectedItem = nil
        switch tools.tool {
        case .select:
            break
        case .brush, .airbrush, .eraser:
            let isEraser = tools.tool == .eraser
            let isAirbrush = tools.tool == .airbrush
            lastPressure = pressure(of: event)
            smoothed = point
            let started = document.beginStroke(
                at: StrokePoint(x: point.x, y: point.y, pressure: lastPressure),
                color: tools.color, width: isEraser ? tools.eraserSize : isAirbrush ? tools.airbrushSize : tools.brushSize,
                isEraser: isEraser,
                opacity: isEraser ? 1 : isAirbrush ? tools.airbrushOpacity : tools.brushOpacity,
                softness: isAirbrush ? 1 : 0
            )
            if started {
                if !isEraser { tools.noteColorUsed() }
            } else {
                explainWhyNothingHappened()
            }
        case .gradient:
            gradientDrag = (point, point)
        case .shape:
            shapeDrag = [point]
        case .fill:
            if document.fill(at: point, color: tools.color) {
                tools.noteColorUsed()
            } else if bounds.contains(point) {
                explainWhyNothingHappened()
            }
        case .eyedropper:
            if let picked = document.pickColor(at: point) {
                tools.color = picked
                tools.tool = .brush
            }
        case .figure:
            compositionMouseDown(at: point, event: event)
        case .panel:
            panelDrag = (point, point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        moveHover(to: point)
        if compositionMouseDragged(to: point) { return }
        if let drag = gradientDrag {
            gradientDrag = (drag.start, point)
            needsDisplay = true
            return
        }
        if let drag = panelDrag {
            panelDrag = (drag.start, point)
            needsDisplay = true
            return
        }
        if var outline = shapeDrag {
            if let last = outline.last, hypot(point.x - last.x, point.y - last.y) >= 2 * screenPixel {
                outline.append(point)
                shapeDrag = outline
                needsDisplay = true
            }
            return
        }
        if let held = moving {
            // Whole pixels only, so fills move without being redrawn.
            let want = CGVector(dx: point.x - held.last.x + held.carry.dx, dy: point.y - held.last.y + held.carry.dy)
            let step = CGVector(dx: want.dx.rounded(), dy: want.dy.rounded())
            if step.dx != 0 || step.dy != 0 {
                document.transformItems(tools.selection, by: CGAffineTransform(translationX: step.dx, y: step.dy), coalescing: held.key)
            }
            moving = (point, CGVector(dx: want.dx - step.dx, dy: want.dy - step.dy), held.key)
            return
        }
        if let area = lasso {
            lasso = (area.start, point, area.adding, area.clicked)
            needsDisplay = true
            return
        }
        guard document.isDrawing, let previous = smoothed else { return }
        // Follow the hand with a little lag; the lag is what smooths out shake.
        let follow = 1 - tools.stabilizer * 0.85
        let next = CGPoint(x: previous.x + (point.x - previous.x) * follow, y: previous.y + (point.y - previous.y) * follow)
        smoothed = next
        lastPressure = pressure(of: event)
        document.continueStroke(to: StrokePoint(x: next.x, y: next.y, pressure: lastPressure))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if compositionMouseUp(at: point) { return }
        if moving != nil {
            moving = nil
            return
        }
        if let area = lasso {
            lasso = nil
            needsDisplay = true
            let rect = CGRect(x: min(area.start.x, point.x), y: min(area.start.y, point.y),
                              width: abs(point.x - area.start.x), height: abs(point.y - area.start.y))
            // A click without a drag only picks (or clears) what is under it.
            guard rect.width > 4 * screenPixel || rect.height > 4 * screenPixel else {
                select(at: area.start)
                return
            }
            tools.selection = document.items(in: rect)
            return
        }
        if var outline = shapeDrag {
            shapeDrag = nil
            needsDisplay = true
            outline.append(point)
            if document.fillShape(outline, color: tools.color) {
                tools.noteColorUsed()
            } else if outline.count > 2 {
                explainWhyNothingHappened()
            }
            return
        }
        if let drag = panelDrag {
            panelDrag = nil
            needsDisplay = true
            if !document.cutPanel(from: drag.start, to: point) {
                tools.notice = L(
                    "コマを切るには、コマの端から端まで、横か縦に線を引いてください。細すぎるコマはできません。",
                    "To cut a panel, draw a line across it from one side to the other. A panel can't be made too thin."
                )
            }
            return
        }
        if let drag = gradientDrag {
            gradientDrag = nil
            needsDisplay = true
            guard hypot(point.x - drag.start.x, point.y - drag.start.y) > 4 else { return }
            var clear = tools.color
            clear.a = 0
            let gradient = GradientItem(shape: tools.gradientShape, start: drag.start, end: point, from: tools.color, to: clear)
            if document.addGradient(gradient) {
                tools.noteColorUsed()
            } else {
                explainWhyNothingHappened()
            }
            return
        }
        defer { removeErasedNotes() }
        guard document.isDrawing else { return }
        // Catch up to where the pen was lifted.
        document.continueStroke(to: StrokePoint(x: point.x, y: point.y, pressure: lastPressure))
        document.endStroke()
        smoothed = nil
    }

    override func mouseMoved(with event: NSEvent) {
        moveHover(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        moveHover(to: nil)
    }

    private func explainWhyNothingHappened() {
        if document.activeLayer?.isVisible == false {
            tools.notice = L(
                "選んでいるレイヤーが非表示なので描けません。右の一覧で目のマークを押すと表示されます。",
                "The selected layer is hidden, so you can't draw on it. Click its eye icon in the list on the right to show it."
            )
        }
    }
}

/// The text field for writing a note, which reports Escape and losing focus.
private final class NoteField: NSTextField {
    var onCancel: (() -> Void)?
    var onLoseFocus: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        // Enter sends the action instead; anything else that ends editing finishes the note.
        if let movement = notification.userInfo?["NSTextMovement"] as? Int, movement == NSTextMovement.return.rawValue { return }
        onLoseFocus?()
    }
}
