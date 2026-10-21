import AppKit
import OekakiKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var session: Session
    @ObservedObject var document: CanvasDocument
    @ObservedObject var tools: ToolState
    @ObservedObject var assistant: AssistantModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar(session: session, document: document, canvas: session.canvas)
            Divider()
            HStack(spacing: 0) {
                ToolRail(
                    tools: tools, document: document, startComposition: session.startComposition, exportBrief: session.exportBrief,
                    tidyLines: session.tidyLines, tidyPaint: session.tidyPaint)
                    // Kept to its width from the left edge, so nothing on the left is ever cut off.
                    .frame(width: 168, alignment: .topLeading)
                    .clipped()
                Divider()
                CanvasView(document: document, tools: tools, controller: session.canvas)
                    .overlay(alignment: .top) {
                        if document.isBlank && tools.tool != .figure {
                            FirstStepBanner()
                                .padding(.top, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let pending = assistant.pending, !assistant.isWorking {
                            ResultBar(assistant: assistant, pending: pending)
                                .padding(.bottom, 18)
                                .padding(.horizontal, 16)
                        }
                    }
                Divider()
                VStack(spacing: 0) {
                    Picker("", selection: $session.panel) {
                        ForEach(SidePanel.allCases) { panel in
                            Text(panel.title).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    switch session.panel {
                    case .layers: LayerPanel(document: document, tools: tools)
                    case .colors: PalettePanel(session: session, document: document, tools: tools)
                    case .parts: PartsPanel(document: document, tools: tools)
                    case .versions: VersionsPanel(session: session, document: document, assistant: assistant)
                    }
                    Divider()
                    // While something is picked, its settings take the assistant's place.
                    // The versions tab has its own way of asking the assistant.
                    if tools.selection.isEmpty, session.panel != .versions {
                        AssistantPanel(assistant: assistant)
                    } else if !tools.selection.isEmpty {
                        ScrollView {
                            SelectionInspector(session: session, document: document, tools: tools)
                                .padding(10)
                        }
                        .frame(maxHeight: 340)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 300)
            }
            Divider()
            HintBar(tools: tools)
        }
        .navigationTitle(session.title)
        .sheet(item: $session.replay) { player in
            ReplayView(player: player) { session.replay = nil }
        }
        .sheet(item: $session.comparison) { comparison in
            CompareView(session: session, document: document, comparison: comparison)
        }
    }
}

// MARK: - Buttons

/// A button that only shows its background while hovered or pressed.
private struct QuietButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration, isSelected: isSelected)
    }

    private struct QuietButtonBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(RoundedRectangle(cornerRadius: 8).fill(fill))
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { isHovered = $0 }
        }

        private var fill: AnyShapeStyle {
            if isSelected { return AnyShapeStyle(Color.accentColor) }
            if configuration.isPressed { return AnyShapeStyle(.primary.opacity(0.16)) }
            if isHovered && isEnabled { return AnyShapeStyle(.primary.opacity(0.08)) }
            return AnyShapeStyle(.clear)
        }
    }
}

/// An icon with its name underneath, large enough for a pen.
struct LabeledButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var minWidth: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(minWidth: minWidth, minHeight: 48)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle(isSelected: isSelected))
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var session: Session
    @ObservedObject var document: CanvasDocument
    @ObservedObject var canvas: CanvasController

    var body: some View {
        HStack(spacing: 4) {
            LabeledButton(title: L("取り消す", "Undo"), systemImage: "arrow.uturn.backward") { document.undo() }
                .disabled(!document.canUndo)
                .help(L("直前の操作をなかったことにします（⌘Z、トラックパッドを 2 本指でタップ）", "Take back the last thing you did (⌘Z, or tap the trackpad with two fingers)"))
            LabeledButton(title: L("やり直す", "Redo"), systemImage: "arrow.uturn.forward") { document.redo() }
                .disabled(!document.canRedo)
                .help(L("取り消した操作をもう一度行います（⇧⌘Z、トラックパッドを 3 本指でタップ）", "Do again what you took back (⇧⌘Z, or tap the trackpad with three fingers)"))

            Divider().frame(height: 32).padding(.horizontal, 6)

            LabeledButton(title: L("小さく", "Smaller"), systemImage: "minus.magnifyingglass") { canvas.zoom(by: 1 / 1.25) }
            Text("\(Int((canvas.magnification * 100).rounded()))%")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44)
            LabeledButton(title: L("大きく", "Bigger"), systemImage: "plus.magnifyingglass") { canvas.zoom(by: 1.25) }
            LabeledButton(title: L("全体を見る", "See All"), systemImage: "arrow.up.left.and.arrow.down.right") { canvas.fit() }
                .help(L("絵の全体が見える大きさに戻します", "Zoom so the whole picture is visible"))

            Spacer(minLength: 12)

            LabeledButton(title: L("再生", "Replay"), systemImage: "play.rectangle") { session.showReplay() }
                .help(L("この絵を描いた順に、はじめから再生します", "Play back how this picture was drawn, from the start"))

            Divider().frame(height: 32).padding(.horizontal, 6)

            LabeledButton(title: L("開く", "Open"), systemImage: "folder") { session.open() }
            LabeledButton(title: L("保存", "Save"), systemImage: "square.and.arrow.down") { session.save() }
                .help(L("あとで続きを描けるように保存します", "Save so you can continue later"))
            LabeledButton(title: L("画像にする", "Export"), systemImage: "photo") { session.exportPNG() }
                .help(L("人に見せたり投稿したりできる画像(PNG)を作ります", "Make a PNG image you can share"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - Tools

private extension Tool {
    var title: String {
        switch self {
        case .select: return L("えらぶ", "Select")
        case .brush: return L("ブラシ", "Brush")
        case .airbrush: return L("エアブラシ", "Airbrush")
        case .eraser: return L("消しゴム", "Eraser")
        case .fill: return L("塗る", "Fill")
        case .shape: return L("囲んで塗る", "Lasso Fill")
        case .gradient: return L("グラデ", "Gradient")
        case .eyedropper: return L("色をひろう", "Pick Color")
        case .figure: return L("構図", "Composition")
        case .panel: return L("コマ割り", "Panels")
        case .balloon: return L("ふきだし", "Balloon")
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .brush: return "paintbrush.pointed.fill"
        case .airbrush: return "cloud.fill"
        case .eraser: return "eraser.fill"
        case .fill: return "drop.fill"
        case .shape: return "lasso"
        case .gradient: return "circle.lefthalf.filled"
        case .eyedropper: return "eyedropper"
        case .figure: return "figure.arms.open"
        case .panel: return "rectangle.split.2x2"
        case .balloon: return "bubble.left"
        }
    }

    var hint: String {
        switch self {
        case .select:
            return L(
                "絵をクリックすると、そこを描いた線や塗りが選ばれます。ドラッグで囲むと中のものを全部選べ、⌘ クリックで足したり外したりできます。選んだものはドラッグや矢印キーで動かせます。",
                "Click the picture to pick the line or fill that drew it. ⌘-click adds or removes; drag from an empty spot to pick everything inside. Drag or use the arrow keys to move what is picked."
            )
        case .brush:
            return L(
                "ドラッグすると線が引けます。ペンなら、強く押すほど太くなります。",
                "Drag to draw a line. With a pen, pressing harder makes it thicker."
            )
        case .airbrush:
            return L(
                "ふちがぼけたやわらかい色を重ねます。影や光をふんわり足すのに使います。",
                "Lays soft color whose edge fades out. Good for gentle shadows and light."
            )
        case .gradient:
            return L(
                "ドラッグした始めの点が今の色、終わりの点で透明になります。空や光の広がりに使います。",
                "Drag from where the current color starts to where it fades to clear. Good for skies and spreading light."
            )
        case .eraser:
            return L(
                "ドラッグしたところが消えます。まちがえたら「取り消す」でも戻せます。",
                "Drag to erase. You can also take back a mistake with Undo."
            )
        case .fill:
            return L(
                "線で囲まれたところをクリックすると、その中が今の色で塗られます。",
                "Click inside an area enclosed by lines to fill it with the current color."
            )
        case .shape:
            return L(
                "ドラッグでぐるっと囲むと、その中が今の色で塗られます。線がいらないので、影や光の形に使えます。",
                "Drag round an area to fill it with the current color. It needs no lines, so it suits shapes of shadow and light."
            )
        case .eyedropper:
            return L(
                "絵の上をクリックすると、その場所の色が今の色になります。",
                "Click on the picture to use the color at that spot."
            )
        case .figure:
            return L(
                "人形・線・メモで絵の計画を立てます。ブラシでなぞって自分で描くことも、依頼用の画像にすることもできます。",
                "Plan the picture with the doll, lines and notes. Trace over it with the brush, or export it to commission an illustrator."
            )
        case .panel:
            return L(
                "ページの上に、コマの端から端まで線を引くと、そこでコマが切れます。コマの中で描き始めたものは、そのコマからはみ出しません。コマの間から描き始めると、コマをまたいで描けます。",
                "Draw a line from one side of a panel to the other to cut it there. Whatever you begin inside a panel stays inside it; begin between panels to draw across them."
            )
        case .balloon:
            return L(
                "押したところに吹き出しを置きます。そのままドラッグすると、離したところにしっぽが向きます。置いた吹き出しからドラッグすると、しっぽの向きを変えられます。言葉は右の欄で書きます。",
                "Click to put a balloon there; drag, and its tail points where you let go. Drag from a balloon to point its tail again. Write the words in the panel on the right."
            )
        }
    }
}

private struct ToolRail: View {
    @ObservedObject var tools: ToolState
    @ObservedObject var document: CanvasDocument
    let startComposition: () -> Void
    let exportBrief: () -> Void
    let tidyLines: () -> Void
    let tidyPaint: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
    private let chipColumns = Array(repeating: GridItem(.fixed(18), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 8) {
                    SectionTitle(text: L("道具", "Tools"))
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Tool.allCases) { tool in
                            LabeledButton(title: tool.title, systemImage: tool.systemImage, isSelected: tools.tool == tool, minWidth: 64) {
                                if tool == .figure {
                                    startComposition()
                                } else {
                                    tools.tool = tool
                                    tools.notice = nil
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 8) {
                    SectionTitle(text: L("色", "Color"))
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tools.color.color)
                            .frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.35)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("ほかの色", "More colors"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            ColorPicker("", selection: Binding(get: { tools.color.color }, set: { tools.color = RGBA($0) }), supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 4) {
                        ForEach(ToolState.palette, id: \.self) { color in
                            ColorChip(color: color, isSelected: tools.color == color) { choose(color) }
                        }
                    }
                    if !tools.recentColors.isEmpty {
                        SectionTitle(text: L("さっき使った色", "Recent"))
                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 4) {
                            ForEach(tools.recentColors, id: \.self) { color in
                                ColorChip(color: color, isSelected: tools.color == color) { choose(color) }
                            }
                        }
                    }
                }

                if tools.tool == .figure {
                    CompositionControls(tools: tools, document: document, exportBrief: exportBrief)
                } else if tools.tool == .panel {
                    PanelControls(document: document)
                } else if tools.tool == .airbrush {
                    SizeControl(title: L("大きさ", "Size"), value: $tools.airbrushSize, range: 10...400, color: tools.color.color)
                    PercentSlider(title: L("濃さ", "Opacity"), value: $tools.airbrushOpacity)
                } else if tools.tool == .gradient {
                    VStack(spacing: 4) {
                        SectionTitle(text: L("形", "Shape"))
                        Picker("", selection: $tools.gradientShape) {
                            Text(L("まっすぐ", "Linear")).tag(GradientItem.Shape.linear)
                            Text(L("まるく", "Radial")).tag(GradientItem.Shape.radial)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                } else if tools.tool == .brush {
                    SizeControl(title: L("線の太さ", "Line Width"), value: $tools.brushSize, range: 1...80, color: tools.color.color)
                    PercentSlider(title: L("濃さ", "Opacity"), value: $tools.brushOpacity)
                    VStack(spacing: 4) {
                        SectionTitle(text: L("手ぶれをおさえる", "Steady Hand"))
                        Slider(value: $tools.stabilizer, in: 0...1)
                        Text(L("強くすると線がなめらかになり、少し遅れてついてきます。", "Higher is smoother, and the line follows a little behind."))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if tools.tool == .eraser {
                    SizeControl(title: L("消しゴムの大きさ", "Eraser Size"), value: $tools.eraserSize, range: 4...200, color: .secondary)
                }

                VStack(spacing: 8) {
                    SectionTitle(text: L("ととのえる", "Tidy Up"))
                    Text(L(
                        "描いたものはそのままに、線のふるえや、色のはみ出し・塗り残しだけを直します。AI は使いません。",
                        "Keeps what you drew and fixes only shaky lines and color that spilled or missed. No AI involved."
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: columns, spacing: 6) {
                        LabeledButton(title: L("線", "Lines"), systemImage: "scribble.variable", minWidth: 64, action: tidyLines)
                            .help(L(
                                "今のレイヤーの線のふるえを取り、近い線の端どうしをつなぎます",
                                "Steadies the lines on this layer and joins ends that nearly meet"
                            ))
                        LabeledButton(title: L("塗り", "Color"), systemImage: "paintbrush.pointed", minWidth: 64, action: tidyPaint)
                            .help(L(
                                "今のレイヤーにざっくり塗った色を、線に合わせて整えます",
                                "Fits the color you roughly painted on this layer to the lines"
                            ))
                    }
                    Picker("", selection: $tools.tidyStrength) {
                        ForEach(TidyStrength.allCases) { strength in
                            Text(strength.title).tag(strength)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .help(L("どのくらい直すか。強いほどなめらかになり、細かい形は丸くなります", "How much to change. Stronger is smoother and rounds off fine detail"))
                }
            }
            // The rail's own width, less its margins, so nothing inside can widen it.
            .frame(width: 144, alignment: .leading)
            .padding(12)
        }
    }

    private func choose(_ color: RGBA) {
        tools.color = color
        if tools.tool == .eraser || tools.tool == .eyedropper {
            tools.tool = .brush
        }
    }
}

// MARK: - Composition

/// The panel tool's settings: how thick the frames are and how far apart.
private struct PanelControls: View {
    @ObservedObject var document: CanvasDocument

    var body: some View {
        VStack(spacing: 8) {
            SectionTitle(text: L("コマ割り", "Panels"))
            if let page = document.library.page {
                Text(L("いま \(page.root.count) コマ。数字は読む順です", "\(page.root.count) panels; the numbers are the reading order"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                slider(L("枠の太さ", "Frame"), \.line, 1...16, page)
                slider(L("上下のコマの間", "Gap Above and Below"), \.gapAcross, 0...120, page)
                slider(L("左右のコマの間", "Gap Side by Side"), \.gapDown, 0...120, page)
                slider(L("ページの余白", "Page Margin"), \.margin, 0...240, page)
                Button(role: .destructive) { document.setPage(nil) } label: {
                    Label(L("コマ割りをやめる", "Stop Dividing the Page"), systemImage: "rectangle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .help(L("枠を消して、ふつうの 1 枚の絵に戻します。描いたものは消えません", "Takes the frames away and makes it one picture again; nothing you drew is lost"))
            } else {
                Text(L("まだコマはありません。ページに横か縦に線を引くと、最初のコマ割りができます", "No panels yet. Draw a line across the page to make the first cut"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A slider for one size of the layout, one undo step per drag.
    private func slider(_ title: String, _ path: WritableKeyPath<PanelLayout, Double>, _ range: ClosedRange<Double>, _ page: PanelLayout) -> some View {
        GuideSlider(
            title: title, text: "\(Int(page[keyPath: path].rounded()))px",
            value: Binding(get: { page[keyPath: path] }, set: { value in
                var changed = page
                changed[keyPath: path] = value.rounded()
                document.setPage(changed, coalescing: "page-\(title)")
            }),
            range: range
        )
    }
}

/// The composition tool: what it does on the canvas, its settings, and the
/// way out to an image for a commission.
private struct CompositionControls: View {
    @ObservedObject var tools: ToolState
    @ObservedObject var document: CanvasDocument
    let exportBrief: () -> Void
    private let modeColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                SectionTitle(text: L("構図でできること", "Composition"))
                LazyVGrid(columns: modeColumns, spacing: 2) {
                    ForEach(PlanMode.allCases) { mode in
                        LabeledButton(title: mode.title, systemImage: mode.systemImage, isSelected: tools.planMode == mode, minWidth: 30) {
                            tools.planMode = mode
                            tools.notice = nil
                        }
                    }
                }
                Text(tools.planMode.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch tools.planMode {
            case .pose: FigureControls(document: document)
            case .eraser: SizeControl(title: L("消しゴムの大きさ", "Eraser Size"), value: $tools.eraserSize, range: 4...200, color: .secondary)
            case .pen, .note: EmptyView()
            }
            VStack(spacing: 4) {
                Button(action: exportBrief) {
                    Label(L("依頼用の画像にする", "Export for a Commission"), systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help(L("人形・構図の線・メモを入れた画像(PNG)を作ります", "Make a PNG with the doll, composition lines and notes"))
                Text(L("「画像にする」では、構図は入りません。", "Plain Export leaves the composition out."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Pose guide

/// Choosing the doll's pose, face and build.
private struct FigureControls: View {
    @ObservedObject var document: CanvasDocument
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 2)
    private let shapeColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    private static let poses: [(title: String, pose: FigurePose)] = [
        (L("立つ", "Stand"), .standing), (L("手をふる", "Wave"), .waving),
        (L("ピース", "Peace"), .peace), (L("腰に手", "Hands on Hips"), .handsOnHips),
        (L("ばんざい", "Cheer"), .cheering), (L("かしげる", "Tilt"), .tilting),
    ]

    var body: some View {
        if let figure = document.figure {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    SectionTitle(text: L("ポーズ", "Pose"))
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Self.poses, id: \.title) { item in
                            Button(item.title) { update { $0.pose = item.pose } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    note(L("人形の点をドラッグして、細かく直せます。", "Drag the dots on the doll to adjust."))
                }

                VStack(spacing: 6) {
                    HStack {
                        SectionTitle(text: L("顔の向き", "Face Direction"))
                        Button(L("正面", "Front")) { update { $0.yaw = 0; $0.pitch = 0 } }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                    FaceDirectionPad(figure: figure) { yaw, pitch in
                        update("figure-face") { $0.yaw = yaw; $0.pitch = pitch }
                    }
                    note(L("向かせたい方へドラッグします。", "Drag toward where the face should look."))
                }

                VStack(spacing: 6) {
                    SectionTitle(text: L("顔の形", "Face Shape"))
                    LazyVGrid(columns: shapeColumns, spacing: 2) {
                        ForEach(FaceShape.allCases) { shape in
                            FaceShapeButton(shape: shape, isSelected: figure.face == shape) { update { $0.face = shape } }
                        }
                    }
                }

                VStack(spacing: 8) {
                    SectionTitle(text: L("体型", "Build"))
                    GuideSlider(title: L("頭身", "Heads Tall"), text: String(format: "%.1f", figure.heads), value: binding(\.heads, "figure-heads"), range: Figure.headRange)
                    GuideSlider(title: L("肩幅", "Shoulders"), text: percent(figure.shoulders), value: binding(\.shoulders, "figure-shoulders"), range: Figure.shoulderRange)
                    GuideSlider(title: L("胸", "Chest"), text: percent(figure.bust), value: binding(\.bust, "figure-bust"), range: Figure.bustRange)
                    GuideSlider(title: L("腰まわり", "Hips"), text: percent(figure.hips), value: binding(\.hips, "figure-hips"), range: Figure.hipRange)
                    GuideSlider(title: L("脚の長さ", "Legs"), text: percent(figure.legs), value: binding(\.legs, "figure-legs"), range: Figure.legRange)
                    GuideSlider(
                        title: L("大きさ", "Size"), text: percent(figure.height / Double(document.height)),
                        value: Binding(
                            get: { figure.height / Double(document.height) },
                            set: { share in update("figure-size") { $0.height = share * Double(document.height) } }
                        ),
                        range: 0.2...1.2
                    )
                }

                HStack(spacing: 4) {
                    Button(figure.isVisible ? L("隠す", "Hide") : L("表示する", "Show")) { update { $0.isVisible.toggle() } }
                    Button(L("置きなおす", "Reset")) { document.setFigure(Figure.standing(in: document.size)) }
                        .help(L("人形をはじめの形に戻します", "Put the doll back as it started"))
                    Button(L("消す", "Remove")) { document.setFigure(nil) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            Button(L("人形を置く", "Place the Doll")) { document.setFigure(Figure.standing(in: document.size)) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }

    private func update(_ key: String? = nil, _ change: (inout Figure) -> Void) {
        guard var figure = document.figure else { return }
        change(&figure)
        document.setFigure(figure, coalescing: key)
    }

    private func binding(_ path: WritableKeyPath<Figure, Double>, _ key: String) -> Binding<Double> {
        Binding(get: { document.figure?[keyPath: path] ?? 0 }, set: { value in update(key) { $0[keyPath: path] = value } })
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GuideSlider: View {
    let title: String
    let text: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(text)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

/// The doll's head, large. Dragging on it turns the face toward the pointer.
private struct FaceDirectionPad: View {
    let figure: Figure
    let change: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, size in
                context.withCGContext { cg in
                    figure.drawHead(in: cg, center: CGPoint(x: size.width / 2, y: size.height * 0.42), radius: min(size.width, size.height) * 0.27)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                func share(_ value: CGFloat, _ length: CGFloat) -> Double { Double(min(max(value / length * 2 - 1, -1), 1)) }
                change(
                    share(drag.location.x, size.width) * Figure.yawRange.upperBound,
                    -share(drag.location.y, size.height) * Figure.pitchRange.upperBound
                )
            })
        }
        .frame(height: 110)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.2)))
    }
}

private struct FaceShapeButton: View {
    let shape: FaceShape
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Canvas { context, size in
                    var head = Figure(x: 0, y: 0, height: 1)
                    head.face = shape
                    context.withCGContext { cg in
                        head.drawHead(in: cg, center: CGPoint(x: size.width / 2, y: size.height * 0.4), radius: size.height * 0.33)
                    }
                }
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : .primary.opacity(0.2), lineWidth: isSelected ? 2 : 1))
                Text(shape.title)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ColorChip: View {
    let color: RGBA
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2.5 : 0).padding(-3))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SizeControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                SectionTitle(text: title)
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // The dot shows the real size at 100% zoom, up to what fits here,
            // on white like the paper.
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.white)
                RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.2))
                Circle().fill(color).frame(width: min(value, 40), height: min(value, 40))
            }
            .frame(height: 46)
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Layers

private struct LayerPanel: View {
    @ObservedObject var document: CanvasDocument
    @ObservedObject var tools: ToolState
    /// Layers and groups opened up to list what is in them.
    @State private var expanded: Set<UUID> = []
    @State private var expandedGroups: Set<Int> = []
    @State private var renamingID: UUID?
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                SectionTitle(text: L("レイヤー", "Layers"))
                Text(L(
                    "重ねて使う透明なシートです。線と色を別のシートに分けると、あとで直しやすくなります。",
                    "Transparent sheets stacked on top of each other. Keeping lines and colors on separate sheets makes fixing easier."
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // The list reads top to bottom the way the sheets are stacked: front first.
                        ForEach(document.layers.reversed()) { layer in
                            row(for: layer)
                            if expanded.contains(layer.id) {
                                itemRows(layer.items, depth: 1)
                            }
                        }
                    }
                }
                .onChange(of: tools.selectedItem) { _, id in
                    guard let id else { return }
                    reveal(id)
                    reader.scrollTo(id, anchor: .center)
                }
                // The sheet being drawn on stays in sight, however it was chosen.
                .onChange(of: document.activeLayerID) { _, id in
                    reader.scrollTo(id)
                }
                .onAppear {
                    let id = document.activeLayerID
                    DispatchQueue.main.async { reader.scrollTo(id) }
                }
            }
            .frame(maxHeight: .infinity)

            // While something is picked, its settings below take this room.
            if tools.selection.isEmpty, let active = document.activeLayer {
                VStack(spacing: 2) {
                    HStack {
                        SectionTitle(text: L("濃さ", "Opacity"))
                        Text("\(Int((active.opacity * 100).rounded()))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { active.opacity }, set: { document.setLayerOpacity(active.id, $0) }), in: 0...1)
                    LayerStyleControls(document: document, layer: active)
                }
            }

            let id = document.activeLayerID
            HStack(spacing: 2) {
                LabeledButton(title: L("追加", "Add"), systemImage: "plus.square.on.square", minWidth: 42) { document.addLayer() }
                    .help(L("新しいレイヤーを、選んでいるレイヤーの上に追加します", "Add a new layer above the selected one"))
                LabeledButton(title: L("前へ", "Forward"), systemImage: "arrow.up", minWidth: 42) { document.moveLayer(id, by: 1) }
                    .disabled(!document.canMoveLayer(id, by: 1))
                LabeledButton(title: L("後ろへ", "Back"), systemImage: "arrow.down", minWidth: 42) { document.moveLayer(id, by: -1) }
                    .disabled(!document.canMoveLayer(id, by: -1))
                LabeledButton(title: L("下と合体", "Merge"), systemImage: "arrow.down.to.line", minWidth: 42) { document.mergeLayerDown(id) }
                    .disabled(!document.canMergeDown(id))
                    .help(L("このレイヤーを、すぐ下のレイヤーと 1 枚にまとめます", "Combine this layer with the one below it"))
                LabeledButton(title: L("消す", "Delete"), systemImage: "trash", minWidth: 42) { document.deleteLayer(id) }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func row(for layer: Layer) -> some View {
        let isActive = layer.id == document.activeLayerID
        HStack(spacing: 8) {
            disclosure(isOpen: expanded.contains(layer.id), isEnabled: !layer.items.isEmpty) {
                if expanded.contains(layer.id) { expanded.remove(layer.id) } else { expanded.insert(layer.id) }
            }
            .help(L("このレイヤーに描いた線や塗りを一覧にします", "List the lines and fills on this layer"))

            Button {
                document.setLayerVisible(layer.id, !layer.isVisible)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(layer.isVisible ? .primary : .tertiary)
            .help(layer.isVisible ? L("このレイヤーを隠す", "Hide this layer") : L("このレイヤーを表示する", "Show this layer"))

            thumbnail(for: layer)

            if renamingID == layer.id {
                TextField("", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($nameFieldFocused)
                    .onSubmit { finishRenaming() }
                    .onChange(of: nameFieldFocused) { _, focused in
                        if !focused { finishRenaming() }
                    }
            } else {
                HStack(spacing: 4) {
                    Text(layer.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                    if layer.isComposition {
                        Image(systemName: "figure.arms.open")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .help(L("構図用のレイヤーです。仕上げの画像には入りません", "A composition layer. It stays out of the finished picture"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(isActive ? Color.accentColor.opacity(0.18) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            draftName = layer.name
            renamingID = layer.id
            nameFieldFocused = true
        }
        .onTapGesture {
            document.activeLayerID = layer.id
        }
        .opacity(layer.isVisible ? 1 : 0.55)
    }

    private func disclosure(isOpen: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isEnabled ? 1 : 0)
        .disabled(!isEnabled)
    }

    /// One row per item, front-most first, like the outline of a source file.
    private func itemRows(_ items: [LayerItem], depth: Int) -> AnyView {
        AnyView(ForEach(items.reversed(), id: \.id) { item in
            itemRow(item, depth: depth)
            if case .group = item, expandedGroups.contains(item.id) {
                itemRows(item.children, depth: depth + 1)
            }
        })
    }

    private func itemRow(_ item: LayerItem, depth: Int) -> some View {
        let isSelected = tools.selection.contains(item.id)
        return HStack(spacing: 6) {
            if case .group = item {
                disclosure(isOpen: expandedGroups.contains(item.id), isEnabled: true) {
                    if expandedGroups.contains(item.id) { expandedGroups.remove(item.id) } else { expandedGroups.insert(item.id) }
                }
            } else {
                Spacer().frame(width: 14)
            }
            // A round check, as in a photo library: tap to add or take away.
            Button {
                if let layerID = document.item(item.id)?.layerID { document.activeLayerID = layerID }
                tools.toggle(item.id)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(L("選ぶものに足す・外す", "Add to or remove from the selection"))
            Image(systemName: item.symbol)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let color = item.color {
                Circle()
                    .fill(color.color)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.25)))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.trailing, 6)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color.accentColor.opacity(0.22) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            if let layerID = document.item(item.id)?.layerID {
                document.activeLayerID = layerID
            }
            // ⌘ adds to the selection or takes away from it, as on the canvas.
            if NSEvent.modifierFlags.contains(.command) {
                tools.toggle(item.id)
            } else {
                tools.selectedItem = item.id
            }
        }
        .id(item.id)
    }

    /// Opens the layer and the groups that hold the item, so its row shows.
    private func reveal(_ id: Int) {
        guard let found = document.item(id), let layer = document.layers.first(where: { $0.id == found.layerID }) else { return }
        expanded.insert(layer.id)
        func groups(holding id: Int, in items: [LayerItem]) -> [Int]? {
            for item in items {
                if item.id == id { return [] }
                if let inner = groups(holding: id, in: item.children) { return [item.id] + inner }
            }
            return nil
        }
        expandedGroups.formUnion(groups(holding: id, in: layer.items) ?? [])
    }

    @ViewBuilder
    private func thumbnail(for layer: Layer) -> some View {
        let aspect = CGFloat(document.width) / CGFloat(document.height)
        ZStack {
            Rectangle().fill(.white)
            if let image = document.snapshotImage(for: layer.id) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(height: 38)
        .overlay(Rectangle().strokeBorder(.primary.opacity(0.2)))
    }

    private func finishRenaming() {
        if let renamingID {
            document.renameLayer(renamingID, to: draftName)
        }
        renamingID = nil
    }
}

// MARK: - Items

extension LayerItem {
    var symbol: String {
        switch self {
        case .stroke(let stroke): return stroke.isEraser ? "eraser" : "scribble"
        case .fill: return "drop.fill"
        case .bitmap: return "photo"
        case .group: return "square.stack.3d.up"
        case .gradient: return "circle.lefthalf.filled"
        case .instance: return "square.on.square.dashed"
        case .balloon: return "bubble.left"
        }
    }

    /// What the item is made from, in a few words.
    var source: String {
        switch self {
        case .stroke(let stroke):
            if stroke.softness > 0 {
                return L("\(stroke.points.count) 点を通るエアブラシ", "Airbrush through \(stroke.points.count) points")
            }
            return L("\(stroke.points.count) 点をつないだ線", "A line through \(stroke.points.count) points")
        case .fill(let fill):
            guard let seed = fill.seed else { return L("線で囲まれたところの塗り", "Fills an area enclosed by lines") }
            return L("(\(Int(seed.x)), \(Int(seed.y))) をクリックした塗り", "Filled by clicking (\(Int(seed.x)), \(Int(seed.y)))")
        case .bitmap:
            return L("手順の残っていない画像", "A picture with no steps behind it")
        case .group(let group):
            return L("合体したレイヤー、\(group.items.count) 個の中身", "A merged layer holding \(group.items.count) items")
        case .gradient(let gradient):
            return gradient.shape == .linear
                ? L("まっすぐなグラデーション", "A linear gradient")
                : L("まるいグラデーション", "A radial gradient")
        case .instance(let use):
            return L("部品を \(Int((use.placement.scale * 100).rounded()))% で置いたもの", "A part placed at \(Int((use.placement.scale * 100).rounded()))%")
        case .balloon(let balloon):
            return L("\(balloon.shape.title)の吹き出し、\(balloon.vertical ? "縦書き" : "横書き")", "A \(balloon.shape.title.lowercased()) balloon, written \(balloon.vertical ? "down" : "across")")
        }
    }
}


// MARK: - Hints

private struct FirstStepBanner: View {
    var body: some View {
        Text(L("白いところをドラッグして、線を引いてみましょう", "Drag on the white area to draw your first line"))
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
    }
}

private struct HintBar: View {
    @ObservedObject var tools: ToolState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tools.notice == nil ? "lightbulb" : tools.noticeIsGood ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(tools.notice == nil ? AnyShapeStyle(.secondary) : tools.noticeIsGood ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
            Text(tools.notice ?? "\(tools.tool.title): \(tools.tool == .figure ? tools.planMode.hint : tools.tool.hint)")
                .font(.system(size: 12))
                .foregroundStyle(tools.notice == nil ? .secondary : .primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 32)
    }
}

/// A 0...1 setting shown as a percentage.
private struct PercentSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                SectionTitle(text: title)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0.05...1)
        }
    }
}

/// How the active layer is put onto the ones below: blend mode, clipping, glow, blur, dots.
private struct LayerStyleControls: View {
    @ObservedObject var document: CanvasDocument
    let layer: Layer

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 3) {
                SectionTitle(text: L("重ね方", "Blend"))
                // Full width: the names say what each mode does, so they are long.
                Picker("", selection: Binding(get: { layer.style.blend }, set: { document.setLayerBlend(layer.id, $0) })) {
                    ForEach(BlendMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            Toggle(isOn: Binding(get: { layer.style.isClipped }, set: { document.setLayerClipped(layer.id, $0) })) {
                Text(L("下のレイヤーではみ出さない", "Clip to the layer below"))
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(L("下のレイヤーに塗ってあるところにだけ表示します", "Shows only where the layer below has paint"))
            if document.library.page != nil {
                Toggle(isOn: Binding(get: { layer.style.overPanels }, set: { document.setLayerOverPanels(layer.id, $0) })) {
                    Text(L("コマの上に重ねる", "Over the Panels"))
                        .font(.system(size: 11))
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(L("コマの枠より上に出し、コマをまたいで描けるようにします。吹き出しや効果音に使います", "Lays the layer over the frames and lets it run across panels, for speech balloons and sound effects"))
            }
            HStack {
                SectionTitle(text: L("光のにじみ", "Glow"))
                Text(layer.style.glow > 0 ? "\(Int(layer.style.glow))px" : L("なし", "Off"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(layer.style.glow) }, set: { document.setLayerGlow(layer.id, CGFloat($0)) }), in: 0...120)
            HStack {
                SectionTitle(text: L("ぼかし", "Blur"))
                Text(layer.style.blur > 0 ? "\(Int(layer.style.blur))px" : L("なし", "Off"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(layer.style.blur) }, set: { document.setLayerBlur(layer.id, CGFloat($0)) }), in: 0...60)
                .help(L("レイヤーをぼかします。遠くのものをピンぼけに見せるのに使えます", "Blurs the layer, for things far away and out of focus"))
            HStack {
                SectionTitle(text: L("点で塗る（トーン）", "Dots (Screen Tone)"))
                Text(layer.style.tone > 0 ? "\(Int(layer.style.tone))px" : L("なし", "Off"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(layer.style.tone) }, set: { document.setLayerTone(layer.id, CGFloat($0.rounded())) }), in: 0...24)
                .help(L("塗りを黒い点の模様にします。濃いところほど点が大きくなります。数字は点の間隔です", "Turns the paint into black dots, bigger where it is darker. The number is how far apart the dots are"))
        }
    }
}
