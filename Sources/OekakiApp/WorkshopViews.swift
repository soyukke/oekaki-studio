import AppKit
import OekakiKit
import SwiftUI

/// What the right-hand panel shows.
enum SidePanel: String, CaseIterable, Identifiable {
    case layers, colors, parts, versions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layers: return L("レイヤー", "Layers")
        case .colors: return L("色", "Colours")
        case .parts: return L("部品", "Parts")
        case .versions: return L("案", "Versions")
        }
    }
}

/// Two versions side by side, one wiped over the other.
struct Comparison: Identifiable {
    let id = UUID()
    var left: UUID
    var right: UUID
}

// MARK: - The selection

/// Everything picked out, changed together: like editing with many cursors.
struct SelectionInspector: View {
    @ObservedObject var session: Session
    @ObservedObject var document: CanvasDocument
    @ObservedObject var tools: ToolState
    @State private var partName = ""
    @State private var lookName = ""
    private let chipColumns = Array(repeating: GridItem(.fixed(18), spacing: 4), count: 7)

    private var ids: [Int] { tools.selection.filter { document.item($0) != nil } }
    private var items: [LayerItem] { ids.compactMap { document.item($0)?.item } }
    private var strokes: [Stroke] {
        items.compactMap { if case .stroke(let stroke) = $0, !stroke.isEraser { return stroke } else { return nil } }
    }
    /// The one balloon picked out, if that is the selection.
    private var balloon: BalloonItem? {
        guard items.count == 1, case .balloon(let balloon) = items[0] else { return nil }
        return balloon
    }

    /// The one use of a part picked out, if that is the selection.
    private var use: InstanceItem? {
        guard items.count == 1, case .instance(let use) = items[0] else { return nil }
        return use
    }

    /// One change to all of them, taken back in one step. A drag on a slider is one change.
    private func update(_ key: String? = nil, _ change: @escaping (inout LayerItem) -> Void) {
        document.updateItems(ids, coalescing: key, change)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let use, let part = document.library.component(use.component) {
                placement(use, part)
            } else if let balloon {
                words(balloon)
            } else {
                common
            }
            if let joining = document.partAndOthers(ids), !joining.others.isEmpty, let part = document.library.component(joining.part) {
                Button {
                    document.addToComponent(joining.others, joining: joining.use)
                    tools.selection = [joining.use]
                } label: {
                    Label(L("部品「\(part.name)」に入れる", "Add to \"\(part.name)\""), systemImage: "square.on.square.dashed")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .help(L("選んだ線を部品に足します。置いた所すべてに出ます", "Adds these to the part, so every copy has them"))
            }
            HStack(spacing: 6) {
                Button(role: .destructive) {
                    document.deleteItems(ids)
                    tools.selection = []
                } label: {
                    Label(deleteTitle, systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }

    /// Deleting a line inside a part takes it from every copy, so the button says so.
    private var deleteTitle: String {
        if document.reachesIntoPart(ids) { return L("部品から消す（置いた所すべてから）", "Delete from the Part (Every Copy)") }
        return ids.count > 1 ? L("まとめて消す", "Delete All") : L("消す", "Delete")
    }

    /// A use of a part goes by the part's name.
    private var headerTitle: String {
        if items.count != 1 { return L("\(items.count) 個を選んでいます", "\(items.count) selected") }
        if let use, let part = document.library.component(use.component) { return L("部品「\(part.name)」", "Part \"\(part.name)\"") }
        if let inside = document.partAndOthers(ids), inside.others.isEmpty, let part = document.library.component(inside.part) {
            return L("部品「\(part.name)」の", "In \"\(part.name)\": ") + items[0].title
        }
        return items[0].title
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: items.count == 1 ? items[0].symbol : "square.stack.3d.down.right").foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                tools.selection = []
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("選ぶのをやめる (esc)", "Deselect (esc)"))
        }
    }

    /// Colour, width, opacity, size and wobble, for everything picked.
    @ViewBuilder private var common: some View {
        if items.count == 1 {
            Text(items[0].source).font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            Text(L("⌘ クリックで足したり外したり、ドラッグで囲んで選べます", "⌘-click to add or remove; drag to select an area"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        if let color = items.compactMap(\.color).first {
            HStack(spacing: 8) {
                SectionTitle(text: L("色", "Colour"))
                ColorPicker("", selection: Binding(
                    get: { color.color },
                    set: { new in update("selection-color") { $0.color = RGBA(new) } }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 4) {
                ForEach(ToolState.palette, id: \.self) { chip in
                    ColorChip(color: chip, isSelected: color == chip) { update { $0.color = chip } }
                }
            }
            HStack(spacing: 6) {
                Menu {
                    ForEach(document.library.swatches) { swatch in
                        Button(swatch.name) { document.bind(ids, to: swatch.id) }
                    }
                    if !document.library.swatches.isEmpty { Divider() }
                    Button(L("今の色に新しい名前を付ける", "Name This Colour")) {
                        let name = L("色 \(document.library.swatches.count + 1)", "Colour \(document.library.swatches.count + 1)")
                        let swatch = document.addSwatch(named: name, color: color)
                        document.bind(ids, to: swatch)
                        session.panel = .colors
                    }
                } label: {
                    Label(L("名前付きの色にする", "Use a Named Colour"), systemImage: "tag")
                }
                .controlSize(.small)
                .help(L("色に名前を付けて結びつけます。名前の色を変えると、結びついた所が全部変わります", "Link to a named colour; change the name's colour and all of these change"))
                Button {
                    tools.selection = document.items(coloured: color)
                } label: {
                    Image(systemName: "eyedropper.full")
                }
                .controlSize(.small)
                .help(L("同じ色の所を全部選ぶ", "Select everything in this colour"))
            }
        }
        if let first = strokes.first {
            GuideSlider(
                title: L("太さ", "Width"), text: "\(Int(first.width.rounded()))",
                value: Binding(get: { Double(first.width) }, set: { width in
                    update("selection-width") { item in
                        if case .stroke(var stroke) = item, !stroke.isEraser {
                            stroke.width = CGFloat(width)
                            item = .stroke(stroke)
                        }
                    }
                }),
                range: 1...80
            )
        }
        if let alpha = items.compactMap(\.alpha).first {
            GuideSlider(
                title: L("濃さ", "Opacity"), text: "\(Int((alpha * 100).rounded()))%",
                value: Binding(get: { Double(alpha) }, set: { value in update("selection-alpha") { $0.alpha = CGFloat(value) } }),
                range: 0...1
            )
        }
        HStack(spacing: 4) {
            SectionTitle(text: L("大きさ", "Size"))
            if let area = document.selectionBounds(ids) {
                Text("\(Int(area.width.rounded())) × \(Int(area.height.rounded()))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button { document.scaleItems(ids, by: 1 / 1.1) } label: { Image(systemName: "minus") }
            Button { document.scaleItems(ids, by: 1.1) } label: { Image(systemName: "plus") }
        }
        .controlSize(.small)
        if !strokes.isEmpty {
            HStack(spacing: 4) {
                SectionTitle(text: L("うねり", "Wobble"))
                Button(L("おだやかに", "Calmer")) { document.changeWaviness(ids, by: 0.7) }
                Button(L("強く", "Stronger")) { document.changeWaviness(ids, by: 1.4) }
            }
            .controlSize(.small)
            .help(L("線の揺れを強めたり、なだらかにしたりします", "Make the lines wobble more, or less"))
        }
        if !document.reachesIntoPart(ids) {
            makePart
        }
    }

    /// Makes the selection a part of its own.
    private var makePart: some View {
        HStack(spacing: 4) {
            TextField(L("部品の名前", "Part name"), text: $partName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            Button(L("部品にする", "Make a Part")) {
                let name = partName.isEmpty ? L("部品 \(document.library.components.count + 1)", "Part \(document.library.components.count + 1)") : partName
                if let use = document.makeComponent(from: ids, named: name) {
                    tools.selection = [use]
                    partName = ""
                    session.panel = .parts
                }
            }
            .controlSize(.small)
            .help(L("選んだものを部品にまとめます。部品は何度でも置けて、元を直すと全部そろって変わります", "Make these a part you can place many times; changing it changes every copy"))
        }
    }

    /// Where one use of a part is, which drawing it shows, and its own colours.
    @ViewBuilder private func placement(_ use: InstanceItem, _ part: Component) -> some View {
        Text(part.looks.count > 1
            ? L("線を直すと、同じ絵を出している所が全部同じに変わる。色だけは 1 つずつ変えられる", "Change a line and every copy showing the same drawing changes; colours can differ copy by copy")
            : L("どれか 1 つの線を直すと、全部が同じに変わる。色だけは 1 つずつ変えられる", "Change a line in any copy and every copy changes; colours can differ copy by copy"))
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        GuideSlider(
            title: L("大きさ", "Size"), text: "\(Int((use.placement.scale * 100).rounded()))%",
            value: Binding(get: { Double(use.placement.scale) }, set: { value in
                var placement = use.placement
                placement.scale = CGFloat(value)
                document.setPlacement(use.id, placement, coalescing: "part-scale-\(use.id)")
            }),
            range: 0.2...3
        )
        GuideSlider(
            title: L("向き", "Turn"), text: "\(Int(use.placement.rotation.rounded()))°",
            value: Binding(get: { Double(use.placement.rotation) }, set: { value in
                var placement = use.placement
                placement.rotation = CGFloat(value)
                document.setPlacement(use.id, placement, coalescing: "part-turn-\(use.id)")
            }),
            range: -180...180
        )
        Toggle(L("左右を反転", "Mirror"), isOn: Binding(get: { use.placement.flipped }, set: { value in
            var placement = use.placement
            placement.flipped = value
            document.setPlacement(use.id, placement)
        }))
        .toggleStyle(.checkbox)
        .font(.system(size: 11))
        looks(use, part)
        let named = document.library.swatches.filter { swatch in part.allItems.contains { $0.colorRefs.contains(swatch.id) } }
        if !named.isEmpty {
            SectionTitle(text: L("ここに置いた 1 つだけの色", "Colours for This Copy Only"))
            ForEach(named) { swatch in
                HStack(spacing: 6) {
                    Text(swatch.name).font(.system(size: 11))
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { (use.overrides[swatch.id] ?? swatch.color).color },
                        set: { document.setOverride(use.id, swatch: swatch.id, RGBA($0), coalescing: "part-color-\(use.id)") }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    if use.overrides[swatch.id] != nil {
                        Button { document.setOverride(use.id, swatch: swatch.id, nil) } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.plain)
                        .help(L("みんなと同じ色に戻す", "Back to the shared colour"))
                    }
                }
            }
        }
        Button(L("この 1 つだけ切り離す", "Cut This One Loose")) { document.detach(use.id) }
            .controlSize(.small)
            .help(L("部品とのつながりを切って、ふつうのまとまりにします", "Turn it into a plain group that no longer follows the part"))
    }
}

extension SelectionInspector {
    /// Changes the one balloon picked out.
    fileprivate func change(_ key: String? = nil, _ body: @escaping (inout BalloonItem) -> Void) {
        document.updateItems(tools.selection, coalescing: key) { item in
            guard case .balloon(var balloon) = item else { return }
            body(&balloon)
            item = .balloon(balloon)
        }
    }

    /// A balloon's words, its shape and its size.
    @ViewBuilder fileprivate func words(_ balloon: BalloonItem) -> some View {
        SectionTitle(text: L("言葉", "Words"))
        TextEditor(text: Binding(get: { balloon.text }, set: { text in change("balloon-text-\(balloon.id)") { $0.text = text } }))
            .font(.system(size: 13))
            .frame(height: 64)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.4)))
        Text(balloon.vertical
            ? L("改行すると、左の列に移ります", "A new line starts the next column, to the left")
            : L("改行すると、次の行に移ります", "A new line starts the next line"))
            .font(.system(size: 10)).foregroundStyle(.secondary)
        Picker(L("形", "Shape"), selection: Binding(get: { balloon.shape }, set: { shape in change { $0.shape = shape } })) {
            ForEach(BalloonItem.Shape.allCases) { shape in
                Text(shape.title).tag(shape)
            }
        }
        .font(.system(size: 11))
        GuideSlider(
            title: L("文字の大きさ", "Letter Size"), text: "\(Int(balloon.fontSize.rounded()))px",
            value: Binding(get: { Double(balloon.fontSize) }, set: { size in change("balloon-size-\(balloon.id)") { $0.fontSize = CGFloat(size.rounded()) } }),
            range: 8...200
        )
        HStack(spacing: 8) {
            Toggle(L("縦書き", "Vertical"), isOn: Binding(get: { balloon.vertical }, set: { vertical in change { $0.vertical = vertical } }))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Spacer()
            if balloon.tail != nil {
                Button(L("しっぽを消す", "Remove Tail")) { change { $0.tail = nil } }
                    .controlSize(.small)
            }
        }
        Text(L("しっぽは、ふきだしの道具で吹き出しからドラッグすると向きを変えられます", "To point the tail, drag from the balloon with the Balloon tool"))
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The part's drawings: which one this copy shows, and making another
    /// from a copy of it, like the sheets of a character drawn many ways.
    @ViewBuilder fileprivate func looks(_ use: InstanceItem, _ part: Component) -> some View {
        let shown = part.lookIndex(use.look)
        SectionTitle(text: L("描き分け（差分）", "Variations"))
        Text(L("向きや表情を変えた絵を、1 つの部品にまとめておける。選んだ絵は、ここに置いた 1 つだけに出る", "Keep other angles or faces of it in the one part. The drawing you pick shows on this copy only"))
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(Array(part.looks.enumerated()), id: \.element.id) { index, look in
            HStack(spacing: 6) {
                Button { document.setLook(use.id, look.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: index == shown ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index == shown ? Color.accentColor : .secondary)
                        Text(look.title).font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .help(L("ここに置いた 1 つを、この絵にします", "Show this drawing on this copy"))
                Spacer()
                Text(L("\(document.uses(of: part.id, showing: look.id).count) か所", "\(document.uses(of: part.id, showing: look.id).count) copies"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                if part.looks.count > 1 {
                    Button { document.removeLook(part.id, look.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(L("この絵を消します。この絵を出していた所は「\(part.looks[0].title)」に戻ります", "Delete this drawing; copies showing it go back to \"\(part.looks[0].title)\""))
                }
            }
        }
        HStack(spacing: 4) {
            TextField(L("絵の名前（例：笑顔）", "Name (e.g. Smile)"), text: $lookName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            Button(L("写して足す", "Copy as New")) {
                let name = lookName.isEmpty ? L("差分 \(part.looks.count + 1)", "Variation \(part.looks.count + 1)") : lookName
                document.addLook(copying: use.id, named: name)
                lookName = ""
            }
            .controlSize(.small)
            .help(L("今の絵を写して新しい絵にし、ここに出します。写した絵の線を直しても、ほかの絵は変わりません", "Copies the drawing shown here as a new one and shows it here; changing its lines leaves the other drawings alone"))
            Button(L("名前を付ける", "Rename")) {
                document.renameLook(part.id, part.looks[shown].id, to: lookName)
                lookName = ""
            }
            .controlSize(.small)
            .disabled(lookName.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(L("ここに出している絵の名前を変えます", "Renames the drawing shown here"))
        }
    }
}

// MARK: - Named colours

struct PalettePanel: View {
    @ObservedObject var session: Session
    @ObservedObject var document: CanvasDocument
    @ObservedObject var tools: ToolState
    @State private var themeName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: L("名前付きの色", "Named Colours"))
                Text(L("色を変えると、使っている所が全部変わる", "Change it, and everything using it changes"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(document.library.swatches) { swatch in
                    SwatchRow(document: document, tools: tools, swatch: swatch)
                }
                Button {
                    let name = L("色 \(document.library.swatches.count + 1)", "Colour \(document.library.swatches.count + 1)")
                    document.addSwatch(named: name, color: tools.color)
                } label: {
                    Label(L("いま描いている色に名前を付ける", "Name the Colour You Draw With"), systemImage: "plus")
                }
                .controlSize(.small)

                Divider()
                SectionTitle(text: L("色の組", "Colour Sets"))
                Text(L("押すと全部の色が切り替わる", "Press to switch every colour"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(document.library.themes) { theme in
                    HStack(spacing: 6) {
                        Image(systemName: document.library.currentTheme == theme.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(document.library.currentTheme == theme.id ? Color.accentColor : .secondary)
                        Text(theme.name).font(.system(size: 12))
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(document.library.swatches.prefix(6)) { swatch in
                                Circle().fill((theme.colors[swatch.id] ?? swatch.color).color).frame(width: 10, height: 10)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { document.applyTheme(theme.id) }
                }
                HStack(spacing: 4) {
                    TextField(L("色の組の名前", "Set name"), text: $themeName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    Button(L("今の色を組にして残す", "Keep as a Set")) {
                        document.saveTheme(named: themeName.isEmpty ? L("組 \(document.library.themes.count + 1)", "Set \(document.library.themes.count + 1)") : themeName)
                        themeName = ""
                    }
                    .controlSize(.small)
                    .disabled(document.library.swatches.isEmpty)
                }

                Divider()
                Button {
                    session.exportStyle()
                } label: {
                    Label(L("絵柄メモに色を書き出す", "Write Colours to the Style Notes"), systemImage: "doc.text")
                }
                .controlSize(.small)
                .disabled(document.library.swatches.isEmpty)
                .help(L("色の名前と値を、絵と同じフォルダの絵柄メモ（STYLE.md）に書き出します", "Write the colour names and values into the style notes (STYLE.md) next to the picture"))
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct SwatchRow: View {
    @ObservedObject var document: CanvasDocument
    @ObservedObject var tools: ToolState
    let swatch: Swatch
    @State private var name = ""

    var body: some View {
        HStack(spacing: 6) {
            ColorPicker("", selection: Binding(
                get: { swatch.color.color },
                set: { document.setSwatchColor(swatch.id, RGBA($0), coalescing: "swatch-\(swatch.id)") }
            ), supportsOpacity: false)
            .labelsHidden()
            TextField("", text: $name, onCommit: { document.renameSwatch(swatch.id, to: name) })
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onAppear { name = swatch.name }
                .onChange(of: swatch.name) { _, new in name = new }
            Spacer()
            let users = document.layers.flatMap { $0.items.flatMap(\.flattened) }.filter { $0.colorRefs.contains(swatch.id) && $0.children.isEmpty }
            Button {
                tools.selection = users.map(\.id)
            } label: {
                Text(L("\(users.count) か所", "\(users.count) uses")).font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("この色を使っている所を全部選ぶ", "Select everything using this colour"))
        }
    }
}

// MARK: - Parts

struct PartsPanel: View {
    @ObservedObject var document: CanvasDocument
    @ObservedObject var tools: ToolState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: L("部品", "Parts"))
                Text(L("どれか 1 つの線を直すと、全部が同じに変わる。色だけは 1 つずつ変えられる", "Change a line in any copy and every copy changes; colours can differ copy by copy"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if document.library.components.isEmpty {
                    Text(L("まだありません。線を選んで「部品にする」", "None yet. Pick lines and choose Make a Part")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(document.library.components) { part in
                    HStack(spacing: 8) {
                        Image(systemName: "square.on.square.dashed").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(part.name).font(.system(size: 12, weight: .medium))
                            Text(part.looks.count > 1
                                ? L("絵 \(part.looks.count) 枚・\(document.uses(of: part.id).count) か所に置いています", "\(part.looks.count) drawings, used \(document.uses(of: part.id).count) times")
                                : L("\(document.uses(of: part.id).count) か所に置いています", "Used \(document.uses(of: part.id).count) times"))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L("選ぶ", "Select")) { tools.selection = document.uses(of: part.id) }
                            .controlSize(.small)
                        Button(L("もう 1 つ置く", "Place Another")) {
                            // A little to the side of the last use, so the new one shows.
                            let last = document.uses(of: part.id).last.flatMap { document.selectionBounds([$0]) }
                            let point = last.map { CGPoint(x: $0.maxX + $0.width * 0.6, y: $0.midY) }
                                ?? CGPoint(x: CGFloat(document.width) / 2, y: CGFloat(document.height) / 2)
                            if let use = document.placeComponent(part.id, at: point) { tools.selection = [use] }
                        }
                        .controlSize(.small)
                        .help(L("最後に置いた所の右どなりに置きます。置いたあとはドラッグで動かせます", "Places it to the right of the last one; drag it where you want"))
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Versions

struct VersionsPanel: View {
    @ObservedObject var session: Session
    @ObservedObject var document: CanvasDocument
    @ObservedObject var assistant: AssistantModel
    @State private var request = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: L("案", "Versions"))
                Text(L("別の案を作って見比べる", "Try another version and compare"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(document.branches) { branch in
                    VersionRow(session: session, document: document, branch: branch)
                }
                HStack(spacing: 6) {
                    Button(L("今の絵から新しい案", "New Version")) {
                        document.makeBranch(named: L("案 \(document.branches.count)", "Version \(document.branches.count)"))
                    }
                    Button(L("色の組から案を作る", "From Colour Sets")) {
                        session.propose("", source: ThemeProposalSource())
                    }
                    .disabled(document.library.themes.isEmpty)
                    .help(L("残してある色の組を、それぞれ別の案にします。AI は使いません", "Make a version from each kept colour set, without the assistant"))
                    Button(L("見比べる", "Compare")) {
                        let other = document.branches.first { $0.id != document.currentBranch }?.id ?? document.currentBranch
                        session.comparison = Comparison(left: document.currentBranch, right: other)
                    }
                    .disabled(document.branches.count < 2)
                }
                .controlSize(.small)

                Divider()
                SectionTitle(text: L("AI に案を出してもらう", "Ask the Assistant"))
                Text(L("案が増えるだけ。今の絵は変わりません", "Adds versions; the picture stays as it is"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(L("例: 夜の配色", "e.g. night colours"), text: $request)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                HStack {
                    Button(session.isProposing ? L("考えています…", "Thinking…") : L("案を出してもらう", "Ask for Versions")) {
                        session.propose(request)
                    }
                    .disabled(session.isProposing || document.library.swatches.isEmpty)
                    .controlSize(.small)
                    if document.library.swatches.isEmpty {
                        Text(L("先に色に名前を付けてください", "Name some colours first"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct VersionRow: View {
    @ObservedObject var session: Session
    @ObservedObject var document: CanvasDocument
    let branch: BranchInfo

    var body: some View {
        let isCurrent = branch.id == document.currentBranch
        HStack(alignment: .top, spacing: 8) {
            if let picture = document.picture(ofBranch: branch.id) {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(branch.name).font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                if isCurrent {
                    Text(L("いま描いている案", "In hand")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let note = branch.note, !note.isEmpty {
                    // What the version changes, so it can be judged before opening it.
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Each colour it changes, as it is now and as the version has it.
                ForEach(branch.colorChanges.prefix(4), id: \.name) { change in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(change.before.color).frame(width: 14, height: 12)
                        Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 3).fill(change.after.color).frame(width: 14, height: 12)
                        Text(change.name).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                if branch.colorChanges.count > 4 {
                    Text(L("ほか \(branch.colorChanges.count - 4) 色", "and \(branch.colorChanges.count - 4) more"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                // The actions on a line of their own, so long names do not push the panel wider.
                HStack(spacing: 6) {
                    if !isCurrent {
                        Button(L("開く", "Open")) { document.switchBranch(branch.id) }
                    }
                    if branch.id != document.mainBranch {
                        Button(L("本番にする", "Use")) { document.adoptBranch(branch.id) }
                            .help(L("この案を本番の絵にします。取り消しで戻せます", "Make this the main picture; undo takes it back"))
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Color.accentColor.opacity(0.15) : .clear))
    }
}

/// Two versions, one over the other, with a handle that wipes between them.
struct CompareView: View {
    @ObservedObject var session: Session
    @ObservedObject var document: CanvasDocument
    @State var comparison: Comparison
    @State private var share = 0.5

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker(L("左", "Left"), selection: $comparison.left) {
                    ForEach(document.branches) { Text($0.name).tag($0.id) }
                }
                Picker(L("右", "Right"), selection: $comparison.right) {
                    ForEach(document.branches) { Text($0.name).tag($0.id) }
                }
                Spacer()
                Button(L("閉じる", "Close")) { session.comparison = nil }
                    .keyboardShortcut(.cancelAction)
            }
            if let left = document.picture(ofBranch: comparison.left), let right = document.picture(ofBranch: comparison.right) {
                GeometryReader { geometry in
                    let size = fit(CGSize(width: left.width, height: left.height), in: geometry.size)
                    ZStack(alignment: .leading) {
                        Image(decorative: left, scale: 1).resizable().frame(width: size.width, height: size.height)
                        Image(decorative: right, scale: 1).resizable().frame(width: size.width, height: size.height)
                            .mask(alignment: .trailing) {
                                Rectangle().frame(width: size.width * (1 - share))
                            }
                        Rectangle().fill(Color.accentColor).frame(width: 3, height: size.height)
                            .offset(x: size.width * share - 1.5)
                    }
                    .frame(width: size.width, height: size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
            Slider(value: $share, in: 0...1)
            HStack {
                Text(sideName(comparison.left)).font(.system(size: 12, weight: .semibold))
                Spacer()
                if comparison.right != document.mainBranch {
                    Button(L("右の案を本番にする", "Use the Right One")) {
                        document.adoptBranch(comparison.right)
                        session.comparison = nil
                    }
                }
                Spacer()
                Text(sideName(comparison.right)).font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(16)
        .frame(minWidth: 820, minHeight: 760)
    }

    /// A version's name, marked when it is the assistant's idea.
    private func sideName(_ id: UUID) -> String {
        guard let branch = document.branches.first(where: { $0.id == id }) else { return "" }
        let fromAssistant = branch.note?.hasPrefix(L("AI の案", "Assistant's idea")) == true
        return fromAssistant ? L("AI の案「\(branch.name)」", "Assistant's idea \"\(branch.name)\"") : branch.name
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGSize {
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

// MARK: - Session

extension Session {
    /// Writes the colour names into STYLE.md next to the picture, keeping
    /// whatever else the file says.
    func exportStyle() {
        let url: URL
        if let fileURL {
            url = fileURL.deletingLastPathComponent().appendingPathComponent("STYLE.md")
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "STYLE.md"
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        do {
            try StyleColors.merged(document.library, into: existing).write(to: url, atomically: true, encoding: .utf8)
            tools.notice = L("色の名前を \(url.lastPathComponent) に書き出しました", "Wrote the colour names to \(url.lastPathComponent)")
            tools.noticeIsGood = true
        } catch {
            tools.notice = error.localizedDescription
        }
    }

    /// Asks for versions: from the assistant when it is installed, otherwise
    /// from the colour sets. Each idea becomes a version; the picture in hand stays.
    func propose(_ request: String, source: ProposalSource? = nil) {
        let chosen: ProposalSource = source ?? ClaudeCLI.locate().map { AssistantProposalSource(executable: $0) } ?? ThemeProposalSource()
        isProposing = true
        let document = self.document
        chosen.propose(request, for: document) { [weak self] result in
            guard let self else { return }
            self.isProposing = false
            switch result {
            case .success(let ideas):
                ideas.forEach { document.branch(trying: $0) }
                self.tools.notice = L("\(ideas.count) つの案を作りました。「案」から開いて見比べられます", "Made \(ideas.count) versions; open them under Versions")
                self.tools.noticeIsGood = true
            case .failure(let error):
                self.tools.notice = error.localizedDescription
            }
        }
    }
}
