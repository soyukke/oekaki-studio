import AppKit
import OekakiKit

/// A development aid: `OEKAKI_SNAPSHOT=/path/to.png` saves a picture of the
/// window shortly after launch and quits. `OEKAKI_DEMO=1` draws a small
/// sample first, so the picture shows the app in use; `OEKAKI_DEMO=input`
/// instead sends mouse events to the canvas and prints what they did, and
/// `OEKAKI_DEMO=ai` asks the real assistant to clean up and colour a rough
/// sketch, saving a picture after each step (this uses your Claude plan).
/// `OEKAKI_DEMO=tidy` paints a drawing roughly and tidies the paint, and
/// `OEKAKI_DEMO=lines` draws with a shaky hand and steadies the lines.
/// `OEKAKI_DEMO=select` draws the sample and ⌘-clicks it at `OEKAKI_AT=x,y`
/// (default 800,500), so the item that drew that spot is selected.
/// `OEKAKI_DEMO=replay` draws the sample and opens the replay part way
/// through a line, at about `OEKAKI_STEP` (a share of the steps, default 0.4).
/// `OEKAKI_DEMO=paint` draws the sample, then shades it with an airbrush on
/// a clipped multiply layer and lights it with a gradient on an add layer.
/// `OEKAKI_DEMO=multi`, `colors`, `parts`, `versions` and `compare` show
/// picking many items, named colours and colour sets, parts, and versions;
/// `parts-looks` gives a part a second drawing, and `panels` cuts the page
/// into comic panels and draws across them.
/// `OEKAKI_DEMO=file` opens the document at `OEKAKI_FILE`, with the layer
/// named `OEKAKI_LAYER` chosen if given. `OEKAKI_DEMO=shape` draws round an
/// area with the lasso fill; `shape-done` lets go, so the area is filled.
/// `OEKAKI_APPEARANCE=light` or `dark` picks the appearance.
enum DevSnapshot {
    static var isRequested: Bool { path != nil }
    private static var path: String? { ProcessInfo.processInfo.environment["OEKAKI_SNAPSHOT"] }
    private static var didStart = false

    static func runIfRequested(session: Session) {
        guard let path, !didStart else { return }
        didStart = true
        switch ProcessInfo.processInfo.environment["OEKAKI_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            switch ProcessInfo.processInfo.environment["OEKAKI_DEMO"] {
            case "ai":
                driveAssistant(session: session, path: path)
                return
            case "tidy":
                driveTidy(session: session, path: path)
                return
            case "lines":
                driveLines(session: session, path: path)
                return
            case "figure": driveFigure(session: session)
            case "plan": drivePlan(session: session, path: path)
            case "input": driveInput(session: session)
            case "select":
                drawSample(on: session.document)
                driveSelect(session: session)
            case "paint":
                drawSample(on: session.document)
                drivePaint(session: session)
            case "multi":
                drawSample(on: session.document)
                driveMulti(session: session)
            case "lasso", "lasso-done":
                drawSample(on: session.document)
                driveLasso(session: session, finish: ProcessInfo.processInfo.environment["OEKAKI_DEMO"] == "lasso-done")
            case "transform-before", "transform-after":
                drawSample(on: session.document)
                driveTransform(session: session, apply: ProcessInfo.processInfo.environment["OEKAKI_DEMO"] == "transform-after")
            case "colors":
                drawSample(on: session.document)
                driveColors(session: session)
            case "parts":
                drawSample(on: session.document)
                driveParts(session: session)
            case "parts-grow", "parts-grow-done":
                drawSample(on: session.document)
                drivePartsGrow(session: session, apply: ProcessInfo.processInfo.environment["OEKAKI_DEMO"] == "parts-grow-done")
            case "panels":
                drivePanels(session: session)
            case "parts-looks":
                drawSample(on: session.document)
                drivePartsLooks(session: session)
            case "parts-trim", "parts-trim-done":
                drawSample(on: session.document)
                drivePartsTrim(session: session, apply: ProcessInfo.processInfo.environment["OEKAKI_DEMO"] == "parts-trim-done")
            case "versions-ai":
                drawSample(on: session.document)
                driveColors(session: session)
                driveAssistantVersions(session: session, path: path)
                return
            case "journal":
                // The new kinds of step, as the replay puts them into words.
                // The background on a layer of its own below the cat, so the cat
                // can grow without the background painting over it.
                drawSample(on: session.document, background: false)
                let paper = session.document.insertLayer(named: L("背景", "Background"), items: [], at: 0)
                session.document.activeLayerID = paper
                session.document.addGradient(GradientItem(
                    shape: .linear, start: .zero, end: CGPoint(x: 0, y: CGFloat(session.document.height)),
                    from: RGBA(hex: 0xC8E6C9), to: RGBA(hex: 0xC8E6C9)
                ))
                // Whiskers, six lines with no fill, picked together and made wavier.
                var whiskers: [Int] = []
                session.document.activeLayerID = session.document.layers.last!.id
                for (side, sign) in [(640.0, -1.0), (1010.0, 1.0)] {
                    for (index, dy) in [-24.0, 0.0, 24.0].enumerated() {
                        let start = CGPoint(x: side, y: 700 + dy)
                        let end = CGPoint(x: side + sign * 200, y: 690 + dy * 2 - Double(index) * 4)
                        guard session.document.beginStroke(at: StrokePoint(x: start.x, y: start.y), color: RGBA(hex: 0x333333), width: 4, isEraser: false) else { continue }
                        for step in 1...24 {
                            let t = CGFloat(step) / 24
                            let x = start.x + (end.x - start.x) * t
                            let y = start.y + (end.y - start.y) * t + sin(t * .pi * 3) * 5
                            session.document.continueStroke(to: StrokePoint(x: x, y: y))
                        }
                        session.document.endStroke()
                        if let id = session.document.activeLayer?.items.last?.id { whiskers.append(id) }
                    }
                }
                session.document.changeWaviness(whiskers, by: 3)
                // The cat's lines and its fills move together.
                let document = session.document
                let cat = document.layers.flatMap(\.items).filter { $0.bounds(canvas: document.bounds).width < document.bounds.width * 0.9 }.map(\.id)
                document.transformItems(cat, by: CGAffineTransform(translationX: 12, y: 0))
                // And made bigger together, lines and fills alike.
                document.scaleItems(cat, by: 1.25)
                driveColors(session: session)
                driveParts(session: session)
                if let gold = session.document.library.swatches.first(where: { $0.name == L("きらめき", "Sparkle") })?.id {
                    session.document.setSwatchColor(gold, RGBA(hex: 0xFF7AB6))
                }
                session.document.undo()
                session.document.redo()
                // A version from a colour set, taken as the main picture.
                session.propose("", source: ThemeProposalSource())
                if let idea = session.document.branches.dropFirst().first?.id { session.document.adoptBranch(idea) }
                session.showReplay()
                if let player = session.replay {
                    // OEKAKI_TITLE picks the step whose words contain it.
                    let wanted = ProcessInfo.processInfo.environment["OEKAKI_TITLE"]
                    let step = wanted.flatMap { title in player.replay.titles.lastIndex { $0.contains(title) } } ?? player.count - 1
                    player.show(step)
                    print("journal: step \(step + 1)/\(player.count): \(player.replay.titles[step])")
                }
            case "file":
                openFile(session: session)
            case "shape", "shape-done":
                drawSample(on: session.document)
                driveShape(session: session, finish: ProcessInfo.processInfo.environment["OEKAKI_DEMO"] == "shape-done")
            case "versions", "compare":
                drawSample(on: session.document)
                driveColors(session: session)
                driveVersions(session: session, compare: ProcessInfo.processInfo.environment["OEKAKI_DEMO"] == "compare")
            case "replay":
                drawSample(on: session.document)
                session.showReplay()
                if let player = session.replay {
                    let share = Double(ProcessInfo.processInfo.environment["OEKAKI_STEP"] ?? "") ?? 0.4
                    let wanted = Int(Double(player.count) * share)
                    let line = (wanted..<player.count).first { player.replay.strokeDrawn(at: $0) != nil } ?? wanted
                    player.show(line, share: 0.55)
                    print("replay: \(player.count) steps, showing \(line): \(player.replay.titles[line])")
                }
            case .some: drawSample(on: session.document)
            case nil: break
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                capture(to: path)
                exit(0)
            }
        }
    }

    /// A saved picture, opened as the app opens it, with one of its layers chosen.
    private static func openFile(session: Session) {
        guard let path = ProcessInfo.processInfo.environment["OEKAKI_FILE"],
              let data = FileManager.default.contents(atPath: path),
              let opened = try? DocumentFile.decode(data)
        else {
            print("file: could not open \(ProcessInfo.processInfo.environment["OEKAKI_FILE"] ?? "nothing")")
            return
        }
        session.load(opened, from: URL(fileURLWithPath: path))
        if let name = ProcessInfo.processInfo.environment["OEKAKI_LAYER"], let layer = opened.layers.first(where: { $0.name == name }) {
            opened.activeLayerID = layer.id
        }
        session.panel = .layers
        // The lasso fill in hand, so the new tool and its hint show.
        session.tools.tool = .shape
        print("file: \(opened.layers.count) layers, \(opened.journal.count) steps, chose \(opened.activeLayer?.name ?? "?")")
    }

    /// The lasso fill: the mouse goes round an area beside the cat, and lets go to fill it.
    private static func driveShape(session: Session, finish: Bool) {
        func find(_ view: NSView?) -> CanvasNSView? {
            guard let view else { return nil }
            if let canvas = view as? CanvasNSView { return canvas }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let canvas = find(window.contentView) else { return }
        session.tools.tool = .shape
        session.tools.color = RGBA(hex: 0x7FD8C8)
        // A leaf-like shape beside the cat.
        let center = CGPoint(x: 360, y: 420)
        let points = (0...48).map { step -> CGPoint in
            let angle = CGFloat(step) / 48 * 2 * .pi
            let r = 150 + 40 * sin(angle * 2)
            return CGPoint(x: center.x + r * cos(angle), y: center.y + r * 0.7 * sin(angle))
        }
        for (index, point) in points.enumerated() {
            let type: NSEvent.EventType = index == 0 ? .leftMouseDown : .leftMouseDragged
            guard let event = NSEvent.mouseEvent(
                with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { continue }
            if type == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseDragged(with: event) }
        }
        if finish, let last = points.last, let event = NSEvent.mouseEvent(
            with: .leftMouseUp, location: canvas.convert(last, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ) {
            canvas.mouseUp(with: event)
        }
        let fills = session.document.layers.flatMap(\.items).filter { if case .fill(let fill) = $0 { return fill.seed == nil } else { return false } }
        print("shape: \(fills.count) lasso fill(s)")
    }

    /// The cat's lines, picked many at once, and made wavier.
    private static func driveMulti(session: Session) {
        let document = session.document
        let lines = document.layers.flatMap { $0.items }.filter { if case .stroke = $0 { return true } else { return false } }.map(\.id)
        let picked = Array(lines.prefix(6))
        document.changeWaviness(picked, by: 1.25)
        session.tools.tool = .select
        session.tools.selection = picked
        session.panel = .layers
        print("multi: picked \(picked.count) of \(lines.count) lines")
    }

    /// A box dragged out with the mouse around the cat's face, with the
    /// select tool; with `finish`, the mouse is let go and what it boxed is picked.
    private static func driveLasso(session: Session, finish: Bool) {
        func find(_ view: NSView?) -> CanvasNSView? {
            guard let view else { return nil }
            if let canvas = view as? CanvasNSView { return canvas }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let canvas = find(window.contentView) else { return }
        session.tools.tool = .select
        // Around the eyes and mouth: the cat's small lines.
        let document = session.document
        let small = document.layers.flatMap(\.items).filter { item in
            guard case .stroke = item else { return false }
            let box = item.bounds(canvas: document.bounds)
            return box.width < 200 && box.height < 200
        }.map(\.id)
        let area = (document.selectionBounds(small) ?? CGRect(x: 560, y: 560, width: 520, height: 300)).insetBy(dx: -40, dy: -40)
        let path = [CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.midX, y: area.midY), CGPoint(x: area.maxX, y: area.maxY)]
        for (index, point) in path.enumerated() {
            let type: NSEvent.EventType = index == 0 ? .leftMouseDown : .leftMouseDragged
            guard let event = NSEvent.mouseEvent(
                with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { continue }
            if type == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseDragged(with: event) }
        }
        if finish, let event = NSEvent.mouseEvent(
            with: .leftMouseUp, location: canvas.convert(path[2], to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ) {
            canvas.mouseUp(with: event)
        }
        print("lasso: picked \(session.tools.selection.map { session.document.item($0)?.item.title ?? "?" })")
    }

    /// The cat's eyes and mouth picked, then made bigger and wavier with the
    /// inspector's own actions.
    private static func driveTransform(session: Session, apply: Bool) {
        let document = session.document
        let lines = document.layers.flatMap(\.items).filter { if case .stroke = $0 { return true } else { return false } }
        // The small ones: eyes and mouth.
        let picked = lines.filter { item in
            let box = item.bounds(canvas: document.bounds)
            return box.width < 200 && box.height < 200
        }.map(\.id)
        let before = document.selectionBounds(picked)
        if apply {
            document.scaleItems(picked, by: 1.1)
            document.scaleItems(picked, by: 1.1)
            document.scaleItems(picked, by: 1.1)
            document.changeWaviness(picked, by: 1.4)
        }
        session.tools.tool = .select
        session.tools.selection = picked
        print("transform: \(picked.count) picked, bounds \(before.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-") -> \(document.selectionBounds(picked).map { "\(Int($0.width))x\(Int($0.height))" } ?? "-")")
    }

    /// The fills given names, kept as a day set, then switched to evening.
    private static func driveColors(session: Session) {
        let document = session.document
        let names = [L("顔", "Face"), L("耳", "Ears"), L("背景", "Background")]
        var swatches: [UUID] = []
        for (index, name) in names.enumerated() {
            let color = [RGBA(hex: 0xFBD9BE), RGBA(hex: 0xF2994A), RGBA(hex: 0xC8E6C9)][index]
            let swatch = document.addSwatch(named: name, color: color)
            // Everything painted in that colour: fills, and a background gradient if there is one.
            document.bind(document.items(coloured: color), to: swatch)
            swatches.append(swatch)
        }
        document.saveTheme(named: L("昼", "Day"))
        let evening = [RGBA(hex: 0xF6C3A8), RGBA(hex: 0xE0603A), RGBA(hex: 0x6B5BA8)]
        for (swatch, color) in zip(swatches, evening) { document.setSwatchColor(swatch, color) }
        document.saveTheme(named: L("夕方", "Evening"))
        session.panel = .colors
        print("colors: \(document.library.swatches.count) names, \(document.library.themes.count) sets")
    }

    /// A sparkle made a part and placed four times, one turned and recoloured.
    @discardableResult
    private static func driveParts(session: Session) -> [Int] {
        let document = session.document
        func line(_ a: CGPoint, _ b: CGPoint) -> Int? {
            guard document.beginStroke(at: StrokePoint(x: a.x, y: a.y), color: RGBA(hex: 0xF2B705), width: 12, isEraser: false) else { return nil }
            document.continueStroke(to: StrokePoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
            document.continueStroke(to: StrokePoint(x: b.x, y: b.y))
            document.endStroke()
            return document.activeLayer?.items.last?.id
        }
        let lines = [line(CGPoint(x: 260, y: 160), CGPoint(x: 260, y: 300)), line(CGPoint(x: 190, y: 230), CGPoint(x: 330, y: 230))].compactMap { $0 }
        let gold = document.addSwatch(named: L("きらめき", "Sparkle"), color: RGBA(hex: 0xF2B705))
        document.bind(lines, to: gold)
        guard let first = document.makeComponent(from: lines, named: L("きらめき", "Sparkle")),
              let part = document.library.components.first?.id else { return [] }
        var uses = [first]
        for (x, y, scale) in [(1320.0, 200.0, 0.7), (1400.0, 900.0, 1.2), (240.0, 960.0, 0.8)] {
            if let use = document.placeComponent(part, at: CGPoint(x: x, y: y), scale: scale) { uses.append(use) }
        }
        document.setPlacement(uses[2], Placement(center: CGPoint(x: 1400, y: 900), scale: 1.2, rotation: 30))
        document.setOverride(uses[3], swatch: gold, RGBA(hex: 0x5AB4FF))
        session.tools.tool = .select
        session.tools.selection = [uses[3]]
        session.panel = .parts
        print("parts: \(document.uses(of: part).count) uses")
        return uses
    }

    /// The page cut into four panels, with lines begun inside a panel kept to
    /// it, one begun between panels running across them, and a balloon on a
    /// layer over the frames.
    private static func drivePanels(session: Session) {
        let document = session.document
        let w = CGFloat(document.width), h = CGFloat(document.height)
        document.cutPanel(from: CGPoint(x: w * 0.05, y: h * 0.42), to: CGPoint(x: w * 0.95, y: h * 0.42))
        document.cutPanel(from: CGPoint(x: w * 0.58, y: h * 0.08), to: CGPoint(x: w * 0.58, y: h * 0.38))
        document.cutPanel(from: CGPoint(x: w * 0.36, y: h * 0.48), to: CGPoint(x: w * 0.36, y: h * 0.92))
        func line(_ points: [CGPoint], width: CGFloat = 10, color: RGBA = .black) {
            guard document.beginStroke(at: StrokePoint(x: points[0].x, y: points[0].y), color: color, width: width, isEraser: false) else { return }
            points.dropFirst().forEach { document.continueStroke(to: StrokePoint(x: $0.x, y: $0.y)) }
            document.endStroke()
        }
        document.addLayer()
        // Speed lines begun in the first panel, dragged far past it.
        for index in 0..<7 {
            let y = h * (0.12 + 0.035 * CGFloat(index))
            line([CGPoint(x: w * 0.93, y: y), CGPoint(x: w * 0.2, y: y + h * 0.3)], width: 6)
        }
        // A shape filled in the big panel, bigger than the panel.
        document.fillShape([CGPoint(x: w * 0.5, y: h * 0.55), CGPoint(x: w * 1.1, y: h * 0.6), CGPoint(x: w * 0.9, y: h * 1.1), CGPoint(x: w * 0.3, y: h * 1.0)], color: RGBA(hex: 0x9CA3AF))
        // Begun in the gap, a line crosses into both panels below.
        line([CGPoint(x: w * 0.2, y: h * 0.42), CGPoint(x: w * 0.5, y: h * 0.75)], width: 14, color: RGBA(hex: 0x2563EB))
        document.addLayer()
        document.renameLayer(document.activeLayerID, to: L("吹き出し", "Balloons"))
        document.setLayerOverPanels(document.activeLayerID, true)
        let center = CGPoint(x: w * 0.58, y: h * 0.42)
        let balloon = (0...48).map { step -> CGPoint in
            let angle = CGFloat(step) / 48 * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * w * 0.12, y: center.y + sin(angle) * h * 0.09)
        }
        document.fillShape(balloon, color: .white)
        line(balloon, width: 5)
        session.tools.tool = .panel
        print("panels: \(document.panels.count) panels")
    }

    /// The sparkle given a second drawing, turned into an X, shown on the
    /// last use only.
    private static func drivePartsLooks(session: Session) {
        let document = session.document
        let uses = driveParts(session: session)
        guard let last = uses.last, document.addLook(copying: last, named: L("ななめ", "Slanted")) != nil,
              case .instance(let use)? = document.item(last)?.item
        else { return }
        document.updateItems(use.content.map(\.id)) { $0 = $0.transformed(by: CGAffineTransform(rotationAngle: .pi / 4)) }
        session.tools.selection = [last]
        session.panel = .parts
        let part = document.library.components[0]
        print("parts-looks: \(part.looks.map(\.title)), showing \(part.looks.map { document.uses(of: part.id, showing: $0.id).count })")
    }

    /// Two more lines drawn over the first use of the part, picked with it,
    /// and with `apply` put into the part, so every use gains them.
    private static func drivePartsGrow(session: Session, apply: Bool) {
        let document = session.document
        let uses = driveParts(session: session)
        guard let first = uses.first, let gold = document.library.swatches.first?.id else { return }
        var extra: [Int] = []
        for (a, b) in [(CGPoint(x: 215, y: 185), CGPoint(x: 305, y: 275)), (CGPoint(x: 305, y: 185), CGPoint(x: 215, y: 275))] {
            guard document.beginStroke(at: StrokePoint(x: a.x, y: a.y), color: RGBA(hex: 0xF2B705), width: 7, isEraser: false) else { continue }
            document.continueStroke(to: StrokePoint(x: b.x, y: b.y))
            document.endStroke()
            if let id = document.activeLayer?.items.last?.id { extra.append(id) }
        }
        document.bind(extra, to: gold)
        session.tools.selection = [first] + extra
        session.panel = .parts
        if apply {
            document.addToComponent(extra, joining: first)
            session.tools.selection = [first]
        }
        print("parts-grow: part has \(document.library.components.first?.items(for: nil).count ?? 0) items, \(document.uses(of: document.library.components[0].id).count) uses")
    }

    /// One line inside a use of the part picked, and with `apply` taken out
    /// of the part, so it goes from every use.
    private static func drivePartsTrim(session: Session, apply: Bool) {
        let document = session.document
        let uses = driveParts(session: session)
        guard uses.count > 1, case .instance(let use)? = document.item(uses[1])?.item, let across = use.content.last?.id else { return }
        session.tools.selection = [across]
        session.panel = .parts
        if apply {
            document.deleteItems([across])
            session.tools.selection = [uses[1]]
        }
        print("parts-trim: part has \(document.library.components.first?.items(for: nil).count ?? 0) items")
    }

    /// Versions asked of the real assistant; the picture is taken when they arrive.
    private static func driveAssistantVersions(session: Session, path: String) {
        session.panel = .versions
        session.propose(ProcessInfo.processInfo.environment["OEKAKI_REQUEST"] ?? L("夜の配色", "night colours"))
        let started = Date()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            guard !session.isProposing || Date().timeIntervalSince(started) > 300 else { return }
            timer.invalidate()
            print("versions-ai: \(session.document.branches.map { "\($0.name) [\($0.note ?? "")]" }) after \(Int(Date().timeIntervalSince(started)))s")
            // With OEKAKI_OPEN, the first idea is opened on the canvas.
            if ProcessInfo.processInfo.environment["OEKAKI_OPEN"] != nil, let idea = session.document.branches.dropFirst().first?.id {
                session.document.switchBranch(idea)
            }
            // With OEKAKI_ADOPT, the first idea is taken and the replay opened at that step.
            if ProcessInfo.processInfo.environment["OEKAKI_ADOPT"] != nil, let idea = session.document.branches.dropFirst().first?.id {
                let note = session.document.branches.first { $0.id == idea }?.note ?? ""
                session.document.adoptBranch(idea)
                let hidden = session.document.layers.filter { !$0.isVisible }.map(\.name)
                print("versions-ai: took [\(note)], hidden layers now \(hidden)")
                session.showReplay()
                if let player = session.replay {
                    player.show(player.count - 1)
                    print("versions-ai: replay step \(player.count): \(player.replay.titles.last ?? "")")
                }
            }
            // With OEKAKI_COMPARE, the first idea is laid against the picture in hand.
            if ProcessInfo.processInfo.environment["OEKAKI_COMPARE"] != nil, let idea = session.document.branches.dropFirst().first?.id {
                session.comparison = Comparison(left: session.document.currentBranch, right: idea)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                capture(to: path)
                exit(0)
            }
        }
    }

    /// Versions from the colour sets, as the assistant's ideas arrive.
    private static func driveVersions(session: Session, compare: Bool) {
        let document = session.document
        session.propose("", source: ThemeProposalSource())
        session.panel = .versions
        if ProcessInfo.processInfo.environment["OEKAKI_OPEN"] != nil, let idea = document.branches.dropFirst().first?.id {
            document.switchBranch(idea)
        }
        if compare, let other = document.branches.dropFirst().first?.id {
            session.comparison = Comparison(left: document.currentBranch, right: other)
        }
        print("versions: \(document.branches.map(\.name))")
    }

    private static func drivePaint(session: Session) {
        let document = session.document
        document.addLayer()
        let shade = document.activeLayerID
        document.renameLayer(shade, to: L("影", "Shadow"))
        document.setLayerBlend(shade, .multiply)
        document.setLayerClipped(shade, true)
        if document.beginStroke(
            at: StrokePoint(x: 500, y: 300), color: RGBA(hex: 0x8A78B8), width: 260, isEraser: false, opacity: 0.7, softness: 1
        ) {
            for step in 1...40 {
                document.continueStroke(to: StrokePoint(x: 500 + CGFloat(step) * 18, y: 300 + CGFloat(step) * 10))
            }
            document.endStroke()
        }
        document.addLayer()
        let light = document.activeLayerID
        document.renameLayer(light, to: L("光", "Light"))
        document.setLayerBlend(light, .add)
        document.setLayerGlow(light, 40)
        document.addGradient(GradientItem(
            shape: .radial, start: CGPoint(x: 200, y: 150), end: CGPoint(x: 900, y: 150),
            from: RGBA(hex: 0xFF9A55), to: RGBA(r: 1, g: 0.6, b: 0.33, a: 0)
        ))
        session.tools.tool = .airbrush
    }

    private static func capture(to path: String) {
        // An open sheet, such as the replay, is what is being looked at.
        let window = NSApp.windows.first { $0.isVisible && $0.isSheet } ?? NSApp.windows.first { $0.isVisible }
        guard let view = window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        // The window paints its own background, which a cached display lacks.
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                NSColor.windowBackgroundColor.setFill()
                NSRect(origin: .zero, size: view.bounds.size).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Places the pose doll and poses it with mouse events, as a person would.
    private static func driveFigure(session: Session) {
        let document = session.document
        session.tools.tool = .figure
        var figure = Figure.standing(in: document.size)
        let env = ProcessInfo.processInfo.environment
        figure.heads = Double(env["OEKAKI_HEADS"] ?? "") ?? 5.5
        figure.face = FaceShape(rawValue: env["OEKAKI_FACE"] ?? "") ?? .egg
        figure.yaw = Double(env["OEKAKI_YAW"] ?? "") ?? 30
        figure.pitch = Double(env["OEKAKI_PITCH"] ?? "") ?? 10
        figure.apply(.peace)
        document.setFigure(figure)
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let canvas = findCanvas(in: window.contentView)
        else { return }
        // Raise the left hand by dragging it, through the canvas like a mouse.
        let wrist = figure.joints.wrist[0]
        let target = CGPoint(x: wrist.x - 120, y: wrist.y - 330)
        for (index, point) in [wrist, CGPoint(x: wrist.x - 60, y: wrist.y - 160), target].enumerated() {
            guard let event = NSEvent.mouseEvent(
                with: index == 0 ? .leftMouseDown : .leftMouseDragged, location: canvas.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { continue }
            index == 0 ? canvas.mouseDown(with: event) : canvas.mouseDragged(with: event)
        }
        let reached = document.figure.map { hypot($0.joints.wrist[0].x - target.x, $0.joints.wrist[0].y - target.y) } ?? -1
        print("figure: hand is \(String(format: "%.1f", reached)) px from where it was dragged")
        if let event = NSEvent.mouseEvent(
            with: .leftMouseUp, location: canvas.convert(target, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ) { canvas.mouseUp(with: event) }
    }

    /// Plans a picture through the composition tool with mouse events: the
    /// doll, a few composition lines, and two notes typed into the canvas.
    /// Also writes the image for a commission to `<path>-brief.png`.
    private static func drivePlan(session: Session, path: String) {
        let document = session.document
        let tools = session.tools
        session.startComposition()
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let canvas = findCanvas(in: window.contentView) else { return }
        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            guard let event = NSEvent.mouseEvent(
                with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return }
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        func drag(_ points: [CGPoint]) {
            send(.leftMouseDown, points[0])
            for (a, b) in zip(points, points.dropFirst()) {
                for step in 1...12 {
                    let t = CGFloat(step) / 12
                    send(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            send(.leftMouseUp, points[points.count - 1])
        }
        func type(_ text: String) {
            guard let field = canvas.subviews.compactMap({ $0 as? NSTextField }).first else {
                print("plan: no note field")
                return
            }
            field.stringValue = text
            field.sendAction(field.action, to: field.target)
        }
        // The doll waves; the hand that waves holds a microphone.
        var figure = document.figure!
        figure.apply(.waving)
        figure.heads = 5.5
        document.setFigure(figure)
        let hand = document.figure!.joints.wrist[1]
        tools.planMode = .pen
        drag([CGPoint(x: hand.x - 10, y: hand.y + 40), CGPoint(x: hand.x + 20, y: hand.y - 60)])
        drag([CGPoint(x: hand.x + 5, y: hand.y - 95), CGPoint(x: hand.x + 45, y: hand.y - 75), CGPoint(x: hand.x + 30, y: hand.y - 40), CGPoint(x: hand.x - 5, y: hand.y - 60), CGPoint(x: hand.x + 5, y: hand.y - 95)])
        drag([CGPoint(x: 120, y: 1010), CGPoint(x: 1480, y: 1010)])
        tools.planMode = .note
        drag([CGPoint(x: 1150, y: 260), CGPoint(x: hand.x + 50, y: hand.y - 80)])
        type(L("マイクを持って手をふる", "Waving, holding a microphone"))
        send(.leftMouseDown, CGPoint(x: 140, y: 900))
        send(.leftMouseUp, CGPoint(x: 140, y: 900))
        type(L("背景はステージ、明るい色", "A stage behind, bright colors"))
        print("plan: \(document.notes.count) notes, composition strokes \(document.layers.first { $0.isComposition }?.items.count ?? 0)")
        print("plan: picture blank \(document.compositeImage().map { _ in document.pickColor(at: CGPoint(x: 800, y: 1010)) == .white } ?? false)")
        if let data = document.pngData(includingComposition: true) {
            try? data.write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-brief.png")))
        }
    }

    private static func findCanvas(in view: NSView?) -> CanvasNSView? {
        guard let view else { return nil }
        if let canvas = view as? CanvasNSView { return canvas }
        return view.subviews.lazy.compactMap(findCanvas).first
    }

    /// Sends the canvas the events a mouse would, and checks the picture afterwards.
    private static func driveSelect(session: Session) {
        func find(_ view: NSView?) -> CanvasNSView? {
            guard let view else { return nil }
            if let canvas = view as? CanvasNSView { return canvas }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let canvas = find(window.contentView) else {
            print("select: canvas not found")
            return
        }
        let at = (ProcessInfo.processInfo.environment["OEKAKI_AT"] ?? "800,500").split(separator: ",").compactMap { Double($0) }
        let point = at.count == 2 ? CGPoint(x: at[0], y: at[1]) : CGPoint(x: 800, y: 500)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: canvas.convert(point, to: nil), modifierFlags: [.command],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { continue }
            if type == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseUp(with: event) }
        }
        let picked = session.tools.selectedItem.flatMap { session.document.item($0)?.item }
        print("select: \(picked.map(\.title) ?? "nothing")")
    }

    private static func driveInput(session: Session) {
        func find(_ view: NSView?) -> CanvasNSView? {
            guard let view else { return nil }
            if let canvas = view as? CanvasNSView { return canvas }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible }), let canvas = find(window.contentView) else {
            print("input: canvas not found")
            return
        }
        let document = session.document
        let tools = session.tools
        func send(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) {
            guard let event = NSEvent.mouseEvent(
                with: type, location: canvas.convert(CGPoint(x: x, y: y), to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return }
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        func drag(from start: CGPoint, to end: CGPoint) {
            send(.leftMouseDown, start.x, start.y)
            for step in 1...30 {
                let t = CGFloat(step) / 30
                send(.leftMouseDragged, start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t)
            }
            send(.leftMouseUp, end.x, end.y)
        }
        func check(_ name: String, _ x: CGFloat, _ y: CGFloat, is expected: RGBA) {
            let actual = document.pickColor(at: CGPoint(x: x, y: y))
            print("input: \(name): \(actual == expected ? "ok" : "WRONG, got \(String(describing: actual))")")
        }
        let ink = tools.color
        let red = RGBA(hex: 0xE5484D)
        // A box drawn with the brush, at the default steadying.
        drag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 1200, y: 300))
        drag(from: CGPoint(x: 1200, y: 300), to: CGPoint(x: 1200, y: 900))
        drag(from: CGPoint(x: 1200, y: 900), to: CGPoint(x: 400, y: 900))
        drag(from: CGPoint(x: 400, y: 900), to: CGPoint(x: 400, y: 300))
        check("brush draws under the pointer", 800, 300, is: ink)
        check("line reaches where the pen lifted", 1196, 300, is: ink)
        check("nothing drawn elsewhere", 800, 600, is: .white)
        tools.tool = .fill
        tools.color = red
        send(.leftMouseDown, 800, 600)
        send(.leftMouseUp, 800, 600)
        check("fill colours the inside", 800, 600, is: red)
        check("fill stays inside the box", 200, 200, is: .white)
        tools.tool = .eraser
        drag(from: CGPoint(x: 700, y: 300), to: CGPoint(x: 900, y: 300))
        check("eraser removes the line", 800, 300, is: .white)
        tools.tool = .eyedropper
        tools.color = .black
        send(.leftMouseDown, 800, 600)
        send(.leftMouseUp, 800, 600)
        print("input: pick colour takes the colour and returns to the brush: \(tools.color == red && tools.tool == .brush ? "ok" : "WRONG")")
        document.undo()
        check("undo brings the erased line back", 800, 300, is: ink)
        print("input: zoom while testing was \(Int((session.canvas.magnification * 100).rounded()))%")
    }

    /// Runs clean-up and then base colours through the real assistant.
    private static func driveAssistant(session: Session, path: String) {
        let assistant = session.assistant
        let base = (path as NSString).deletingPathExtension
        let sketch = ProcessInfo.processInfo.environment["OEKAKI_SKETCH"]
        let lopsided = sketch == "lopsided"
        var steps: [AITask] = lopsided ? [.cleanup] : [.cleanup, .underpaint]
        if sketch == "plan" {
            // A planned composition, with props and background asked of the assistant.
            drivePlan(session: session, path: path)
            assistant.request = L(
                "マイクを持って手をふる。背景はライブのステージ。スポットライトと床。",
                "Waving with a microphone in hand. A concert stage behind: spotlights and the floor."
            )
            steps = [.guide]
        } else {
            drawCat(on: session.document, shake: lopsided ? 4 : 9, lopsided: lopsided, dense: lopsided)
            assistant.request = Localization.isJapanese ? "三毛猫の顔。パステル調で、背景は淡いミント。" : "A calico cat's face, in pastel colors, on a pale mint background."
        }
        var started = Date()
        var current: AITask?
        var waitedForSetup = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if assistant.setup != .ready {
                waitedForSetup += 0.5
                if assistant.setup != .checking || waitedForSetup > 20 {
                    print("ai: not ready (\(assistant.setup))")
                    timer.invalidate()
                    exit(1)
                }
                return
            }
            if assistant.isWorking { return }
            if let finished = current {
                current = nil
                if case .failed(let message) = assistant.phase {
                    print("ai: \(finished.rawValue) failed: \(message)")
                    timer.invalidate()
                    exit(1)
                }
                let seconds = Int(Date().timeIntervalSince(started).rounded())
                print("ai: \(finished.rawValue) done in \(seconds)s, layers: \(session.document.layers.map(\.name))")
                print("ai: advice: \(assistant.advice ?? "(none)")")
                let document = session.document
                if finished == .cleanup, let sketch = document.layers.first, let lines = document.activeLayer,
                   let fidelity = document.lineFidelity(sketch: sketch.id, lines: lines.id) {
                    print(String(format: "ai: lines on the sketch %.1f%%, sketch kept %.1f%%", fidelity.followed * 100, fidelity.kept * 100))
                }
                capture(to: "\(base)-\(finished.rawValue)-pending.png")
                assistant.adopt()
                if finished == .guide, let data = document.pngData(includingComposition: true) {
                    try? data.write(to: URL(fileURLWithPath: "\(base)-guide-brief.png"))
                }
                return
            }
            guard !steps.isEmpty else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    capture(to: path)
                    exit(0)
                }
                return
            }
            current = steps.removeFirst()
            started = Date()
            assistant.start(current!)
        }
    }

    /// `OEKAKI_STRENGTH=light`, `normal` or `strong` picks how hard the tidy demos work.
    private static var requestedStrength: TidyStrength {
        ProcessInfo.processInfo.environment["OEKAKI_STRENGTH"].flatMap(TidyStrength.init) ?? .normal
    }

    /// Draws a shaky cat, then steadies its lines.
    private static func driveLines(session: Session, path: String) {
        let document = session.document
        let base = (path as NSString).deletingPathExtension
        drawCat(on: document, shake: 4, lopsided: true, dense: true)
        guard let sketch = document.activeLayer?.id else { return }
        try? document.pngData()?.write(to: URL(fileURLWithPath: "\(base)-before-canvas.png"))
        let started = Date()
        session.tools.tidyStrength = requestedStrength
        session.tidyLines()
        let milliseconds = Int((Date().timeIntervalSince(started) * 1000).rounded())
        print("lines: \(session.tools.notice ?? "") (\(milliseconds) ms), layers: \(document.layers.map { "\($0.name)\($0.isVisible ? "" : " (hidden)")" })")
        if let fidelity = document.lineFidelity(sketch: sketch, lines: document.activeLayerID, reach: 4) {
            print(String(format: "lines: within 4 px of the sketch %.1f%%, sketch kept %.1f%%", fidelity.followed * 100, fidelity.kept * 100))
        }
        try? document.pngData()?.write(to: URL(fileURLWithPath: "\(base)-after-canvas.png"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            capture(to: path)
            exit(0)
        }
    }

    /// Paints a cat loosely on a layer under its lines, then tidies the paint.
    private static func driveTidy(session: Session, path: String) {
        let document = session.document
        let base = (path as NSString).deletingPathExtension
        drawCat(on: document)
        document.addLayer()
        document.moveLayer(document.activeLayerID, by: -1)
        var counter: CGFloat = 0
        func noise(_ amount: CGFloat) -> CGFloat {
            counter += 1
            return sin(counter * 78.233) * amount
        }
        /// Hatches an oval with a wide brush, missing its edge by up to `slop` either way.
        func hatch(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, color: UInt32, brush: CGFloat, slop: CGFloat) {
            var y = cy - ry + brush * 0.4
            var leftToRight = true
            var started = false
            while y < cy + ry - brush * 0.3 {
                let t = (y - cy) / ry
                let half = rx * (max(0, 1 - t * t)).squareRoot()
                let left = StrokePoint(x: cx - half + brush / 2 + noise(slop), y: y + noise(4))
                let right = StrokePoint(x: cx + half - brush / 2 + noise(slop), y: y + noise(4))
                for point in leftToRight ? [left, right] : [right, left] {
                    if started {
                        document.continueStroke(to: point)
                    } else {
                        document.beginStroke(at: point, color: RGBA(hex: color), width: brush, isEraser: false)
                        started = true
                    }
                }
                leftToRight.toggle()
                y += brush * 0.8
            }
            document.endStroke()
        }
        hatch(800, 640, 300, 265, color: 0xFBD9BE, brush: 56, slop: 34)
        hatch(615, 372, 52, 72, color: 0xF28FB1, brush: 30, slop: 16)
        hatch(1000, 360, 52, 72, color: 0xF28FB1, brush: 30, slop: 16)
        hatch(850, 465, 95, 62, color: 0xF2994A, brush: 26, slop: 14)
        hatch(800, 850, 205, 52, color: 0xE8B796, brush: 26, slop: 14)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            capture(to: "\(base)-before.png")
            try? document.pngData()?.write(to: URL(fileURLWithPath: "\(base)-before-canvas.png"))
            let started = Date()
            session.tools.tidyStrength = requestedStrength
            session.tidyPaint()
            let milliseconds = Int((Date().timeIntervalSince(started) * 1000).rounded())
            print("tidy: \(session.tools.notice ?? "") (\(milliseconds) ms), layers: \(document.layers.map { "\($0.name)\($0.isVisible ? "" : " (hidden)")" })")
            try? document.pngData()?.write(to: URL(fileURLWithPath: "\(base)-after-canvas.png"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                capture(to: path)
                exit(0)
            }
        }
    }

    /// A cat's face. `shake` wobbles the lines like an unsteady hand;
    /// `lopsided` gives it mismatched ears and eyes and an off-centre nose;
    /// `dense` samples the lines finely, as a pen does.
    private static func drawCat(on document: CanvasDocument, shake: CGFloat = 0, lopsided: Bool = false, dense: Bool = false) {
        var counter: CGFloat = 0
        func wobble() -> CGFloat {
            counter += 1
            return sin(counter * 12.9898) * shake
        }
        func stroke(_ sparse: [(CGFloat, CGFloat)], width: CGFloat = 7) {
            var points = sparse
            if dense {
                // A point every few pixels, as a pen gives, so the shake is a fine tremble.
                points = []
                for (a, b) in zip(sparse, sparse.dropFirst()) {
                    let steps = max(1, Int(hypot(b.0 - a.0, b.1 - a.1) / 5))
                    for step in 0..<steps {
                        let t = CGFloat(step) / CGFloat(steps)
                        points.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
                    }
                }
                points.append(sparse[sparse.count - 1])
            }
            guard let first = points.first else { return }
            document.beginStroke(at: StrokePoint(x: first.0, y: first.1), color: RGBA(hex: 0x111111), width: width, isEraser: false)
            points.dropFirst().forEach { document.continueStroke(to: StrokePoint(x: $0.0 + wobble(), y: $0.1 + wobble())) }
            document.endStroke()
        }
        func ring(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> [(CGFloat, CGFloat)] {
            (0...48).map { step in
                let angle = CGFloat(step) / 48 * 2 * .pi
                return (cx + rx * cos(angle), cy + ry * sin(angle))
            }
        }
        if lopsided {
            // Uneven on purpose: an assistant asked to trace should leave it uneven.
            stroke(ring(800, 640, 300, 265))
            stroke([(560, 480), (560, 425), (585, 388), (640, 398), (700, 391)])
            stroke([(895, 389), (990, 250), (1100, 180), (1085, 330), (1030, 469)])
            stroke(ring(690, 590, 26, 30))
            stroke(ring(925, 640, 52, 60))
            stroke([(700, 740), (760, 740), (730, 770), (700, 740)], width: 5)
            return
        }
        stroke(ring(800, 640, 300, 265))
        stroke([(560, 480), (545, 360), (548, 260), (630, 300), (700, 391)])
        stroke([(895, 389), (975, 292), (1068, 244), (1062, 345), (1030, 469)])
        stroke(ring(690, 600, 38, 44))
        stroke(ring(915, 600, 38, 44))
        stroke([(780, 700), (840, 700), (810, 730), (780, 700)], width: 5)
    }

    private static func drawSample(on document: CanvasDocument, background: Bool = true) {
        drawCat(on: document)
        document.addLayer()
        document.moveLayer(document.activeLayerID, by: -1)
        document.fill(at: CGPoint(x: 800, y: 500), color: RGBA(hex: 0xFBD9BE))
        document.fill(at: CGPoint(x: 600, y: 350), color: RGBA(hex: 0xF2994A))
        document.fill(at: CGPoint(x: 1010, y: 340), color: RGBA(hex: 0xF2994A))
        if background {
            document.fill(at: CGPoint(x: 100, y: 100), color: RGBA(hex: 0xC8E6C9))
        } else {
            // With the background on a layer of its own, the eyes and mouth
            // need white of their own, or the background shows through.
            for (x, y) in [(701, 600), (926, 600), (824, 704)] {
                document.fill(at: CGPoint(x: x, y: y), color: .white)
            }
        }
    }
}
