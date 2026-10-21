import AppKit
import Combine
import OekakiKit
import SwiftUI
import UniformTypeIdentifiers

/// How much the "tidy" buttons change what was drawn.
enum TidyStrength: String, CaseIterable, Identifiable {
    case light, normal, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return L("かるく", "Light")
        case .normal: return L("ふつう", "Normal")
        case .strong: return L("しっかり", "Strong")
        }
    }

    /// Smoothing along a line, in canvas pixels.
    var lineSmoothing: Double {
        switch self {
        case .light: return 6
        case .normal: return 12
        case .strong: return 18
        }
    }

    /// Smoothing of the border between two colours, in canvas pixels.
    var paintSmoothing: Double {
        switch self {
        case .light: return 3.5
        case .normal: return 8
        case .strong: return 14
        }
    }
}

/// What the composition tool does on the canvas.
enum PlanMode: String, CaseIterable, Identifiable {
    case pose, pen, eraser, note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pose: return L("人形", "Doll")
        case .pen: return L("線", "Lines")
        case .eraser: return L("消す", "Erase")
        case .note: return L("メモ", "Notes")
        }
    }

    var systemImage: String {
        switch self {
        case .pose: return "figure.arms.open"
        case .pen: return "pencil.line"
        case .eraser: return "eraser"
        case .note: return "text.bubble"
        }
    }

    var hint: String {
        switch self {
        case .pose:
            return L(
                "人形の点をドラッグしてポーズを決めます。腰の四角で全体を動かせます。",
                "Drag the dots on the doll to pose it. Drag the square at the hips to move it."
            )
        case .pen:
            return L(
                "小物や背景を、簡単な線で描きます。この線は構図用で、仕上げの画像には入りません。",
                "Sketch props and background with simple lines. These are for the plan and stay out of the finished picture."
            )
        case .eraser:
            return L("構図の線とメモを消します。", "Erases composition lines and notes.")
        case .note:
            return L(
                "クリックで文字のメモ、ドラッグで矢印つきのメモ。メモはドラッグで動かせ、クリックで書き直せます。",
                "Click for a note, drag for a note with an arrow. Drag a note to move it, click it to rewrite."
            )
        }
    }
}

/// The tool the user is holding and how it is set up.
final class ToolState: ObservableObject {
    static let palette: [RGBA] = [
        RGBA(hex: 0x111111), RGBA(hex: 0x7A7A7A), RGBA(hex: 0xFFFFFF), RGBA(hex: 0xE5484D),
        RGBA(hex: 0xF2994A), RGBA(hex: 0xF5D547), RGBA(hex: 0x4CAF50), RGBA(hex: 0x7CC4E6),
        RGBA(hex: 0x3B82F6), RGBA(hex: 0x8B5CF6), RGBA(hex: 0xF28FB1), RGBA(hex: 0x8D5A3B),
        RGBA(hex: 0xFBD9BE), RGBA(hex: 0xC8E6C9),
    ]
    static let recentLimit = 7

    @Published var tool: Tool = .brush
    @Published var color = ToolState.palette[0]
    @Published var brushSize: Double = 6
    @Published var eraserSize: Double = 30
    @Published var airbrushSize: Double = 120
    /// How much a stroke covers, 0...1.
    @Published var brushOpacity: Double = 1
    @Published var airbrushOpacity: Double = 0.5
    @Published var gradientShape: GradientItem.Shape = .linear
    /// 0 follows the hand exactly; 1 smooths the most.
    @Published var stabilizer: Double = 0.5
    @Published var tidyStrength: TidyStrength = .normal
    @Published var planMode: PlanMode = .pose
    @Published private(set) var recentColors: [RGBA] = []
    /// A short message for the hint bar, shown until the next action.
    @Published var notice: String? {
        didSet { noticeIsGood = false }
    }
    /// The notice tells of something that went well, not a problem.
    @Published var noticeIsGood = false
    /// The item picked out on the canvas or in the layer list, like the
    /// line under the cursor in a code editor.
    @Published var selection: [Int] = []

    /// The one item the inspector is about: the last one picked.
    var selectedItem: Int? {
        get { selection.last }
        set { selection = newValue.map { [$0] } ?? [] }
    }

    /// Adds the item to the selection, or takes it out if it is in.
    func toggle(_ id: Int) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else {
            selection.append(id)
        }
    }

    /// The size of the tool in hand, in canvas pixels. Nil for tools without one.
    var activeSize: Double? {
        switch tool {
        case .brush: return brushSize
        case .airbrush: return airbrushSize
        case .eraser: return eraserSize
        case .figure: return planMode == .eraser ? eraserSize : nil
        case .fill, .shape, .eyedropper, .select, .gradient, .panel: return nil
        }
    }

    /// Remembers a colour that was actually put on the canvas.
    func noteColorUsed() {
        guard !Self.palette.contains(color) else { return }
        recentColors.removeAll { $0 == color }
        recentColors.insert(color, at: 0)
        if recentColors.count > Self.recentLimit {
            recentColors.removeLast(recentColors.count - Self.recentLimit)
        }
    }
}

/// Zooming and scrolling the canvas from buttons and menus.
final class CanvasController: ObservableObject {
    @Published private(set) var magnification: CGFloat = 1
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []
    private var didInitialFit = false

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func attach(_ scrollView: NSScrollView) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        self.scrollView = scrollView
        didInitialFit = false
        scrollView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main) { [weak self] _ in
            self?.fitOnceLaidOut()
        })
        observers.append(center.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main) { [weak self] _ in
            self?.readMagnification()
        })
        DispatchQueue.main.async { [weak self] in self?.fitOnceLaidOut() }
    }

    private func fitOnceLaidOut() {
        guard !didInitialFit, let scrollView, scrollView.frame.width > 50, scrollView.frame.height > 50 else { return }
        didInitialFit = true
        fit()
    }

    private func readMagnification() {
        if let scrollView { magnification = scrollView.magnification }
    }

    /// Shows the whole canvas with a little room around it.
    func fit() {
        guard let scrollView, let canvas = scrollView.documentView else { return }
        scrollView.magnify(toFit: canvas.frame.insetBy(dx: -32, dy: -32))
        readMagnification()
    }

    func zoom(by factor: CGFloat) {
        guard let scrollView else { return }
        let target = min(max(scrollView.magnification * factor, scrollView.minMagnification), scrollView.maxMagnification)
        let visible = scrollView.contentView.bounds
        scrollView.setMagnification(target, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
        readMagnification()
    }
}

/// The open picture and where it is saved.
final class Session: ObservableObject {
    @Published private(set) var document = CanvasDocument()
    @Published private(set) var fileURL: URL?
    let tools = ToolState()
    let canvas = CanvasController()
    /// The playback of how the picture was made, while it is open.
    @Published var replay: ReplayPlayer?
    /// What the right-hand panel shows.
    @Published var panel: SidePanel = .layers
    /// Two versions being compared, when the comparison is open.
    @Published var comparison: Comparison?
    /// A request to the assistant for versions is under way.
    @Published var isProposing = false
    private(set) lazy var assistant = AssistantModel { [unowned self] in self.document }

    /// The last tidy and the layer it was made from, so that pressing the
    /// button again at another strength redoes it rather than tidying the result.
    private var lastTidy: (source: UUID, result: UUID, isLines: Bool)?

    private var documentType: UTType {
        UTType(filenameExtension: DocumentFile.fileExtension) ?? .data
    }

    var title: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? L("名前のない絵", "Untitled")
    }

    func newDocument() {
        guard confirmLosingChanges() else { return }
        assistant.reset()
        lastTidy = nil
        document = CanvasDocument()
        fileURL = nil
    }

    func open() {
        guard confirmLosingChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [documentType]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        read(url)
    }

    /// Opens a picture the Finder hands over, as when its file is double-clicked.
    func open(_ url: URL) {
        guard confirmLosingChanges() else { return }
        read(url)
    }

    private func read(_ url: URL) {
        do {
            load(try DocumentFile.decode(Data(contentsOf: url)), from: url)
        } catch {
            show(error, title: L("開けませんでした", "Could not open the file"))
        }
    }

    /// Makes `opened` the picture being worked on.
    func load(_ opened: CanvasDocument, from url: URL?) {
        assistant.reset()
        lastTidy = nil
        document = opened
        fileURL = url
    }

    // MARK: Tidying

    /// Steadies the lines on the layer in use. No assistant is involved.
    func tidyLines() {
        let done = tidy(isLines: true) { self.document.tidyLines(smoothing: self.tools.tidyStrength.lineSmoothing) }
        tools.notice = done
            ? L(
                "線のふるえを取りました。元の線は隠してあります。強さを変えてもう一度押すと、やり直せます。",
                "Steadied the lines. Your original is hidden, not gone. Change the strength and press again to redo."
            )
            : L(
                "このレイヤーにはブラシの線がありません。線を描いたレイヤーを選んでください。",
                "This layer has no brush lines. Choose the layer you drew the lines on."
            )
    }

    /// Cleans up loosely painted colour on the layer in use. No assistant is involved.
    func tidyPaint() {
        var result: CanvasDocument.TidyResult?
        let done = tidy(isLines: false) {
            result = self.document.tidyPaint(smoothing: self.tools.tidyStrength.paintSmoothing)
            return result != nil
        }
        if !done {
            tools.notice = L(
                "このレイヤーには色がありません。色を塗ったレイヤーを選んでください。",
                "This layer has no color. Choose the layer you painted on."
            )
        } else if result?.foundLines == true {
            tools.notice = L(
                "はみ出しと塗り残しを直しました。元の塗りは隠してあります。強さを変えてもう一度押すと、やり直せます。",
                "Fixed the spills and gaps. Your original is hidden, not gone. Change the strength and press again to redo."
            )
        } else {
            tools.notice = L(
                "線が見つからなかったので、色のふちだけ整えました。線と色を別のレイヤーに分けると、はみ出しも直せます。",
                "No lines were found, so only the edges of the color were smoothed. Keep lines and color on separate layers to fix spills too."
            )
        }
    }

    private func tidy(isLines: Bool, _ run: () -> Bool) -> Bool {
        let document = self.document
        var done = false
        if let last = lastTidy, last.isLines == isLines, document.activeLayerID == last.result,
           document.index(ofLayer: last.source) != nil {
            // Tidy the original again in place of the earlier result, as one undo step.
            document.transaction {
                document.removeLayers([last.result])
                document.setLayerVisible(last.source, true)
                document.activeLayerID = last.source
                done = run()
            }
        } else {
            let source = document.activeLayerID
            done = run()
            if done {
                lastTidy = (source, document.activeLayerID, isLines)
            }
            return done
        }
        if done, let last = lastTidy {
            lastTidy = (last.source, document.activeLayerID, isLines)
        }
        return done
    }

    /// Saves to the current file, asking for a place the first time.
    @discardableResult
    func save() -> Bool {
        guard let fileURL else { return saveAs() }
        return write(to: fileURL)
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [documentType]
        panel.nameFieldStringValue = title
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard write(to: url) else { return false }
        fileURL = url
        return true
    }

    private func write(to url: URL) -> Bool {
        do {
            try DocumentFile.encode(document).write(to: url, options: .atomic)
            document.markSaved()
            return true
        } catch {
            show(error, title: L("保存できませんでした", "Could not save"))
            return false
        }
    }

    /// Saves the picture with its plan, the doll, composition lines and notes,
    /// as an image to hand to an illustrator.
    func exportBrief() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = title + L("-依頼用", "-brief")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = document.pngData(includingComposition: true) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
            tools.notice = L("構図とメモを入れた画像を書き出しました。", "Exported the image with the composition and notes.")
        } catch {
            show(error, title: L("書き出せませんでした", "Could not export"))
        }
    }

    /// Switches to the composition tool, placing the doll and the composition
    /// sheet the first time.
    func startComposition() {
        tools.tool = .figure
        tools.notice = nil
        guard document.figure == nil || document.compositionLayerID == nil else { return }
        document.transaction {
            if document.figure == nil {
                document.setFigure(Figure.standing(in: document.size))
            }
            document.makeCompositionLayer()
        }
    }

    func showReplay() {
        tools.selectedItem = nil
        replay = ReplayPlayer(document: document)
    }

    func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = title
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = document.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
            tools.notice = L("画像を書き出しました。", "Exported the image.")
        } catch {
            show(error, title: L("書き出せませんでした", "Could not export"))
        }
    }

    /// Asks what to do with unsaved work. Returns false to keep the picture open.
    func confirmLosingChanges() -> Bool {
        guard document.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = L("この絵はまだ保存されていません。", "This picture has not been saved.")
        alert.informativeText = L("保存しないと、描いた内容は失われます。", "Without saving, your work will be lost.")
        alert.addButton(withTitle: L("保存する", "Save"))
        alert.addButton(withTitle: L("キャンセル", "Cancel"))
        alert.addButton(withTitle: L("保存しない", "Don't Save"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func show(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(converted.redComponent), g: Double(converted.greenComponent), b: Double(converted.blueComponent))
    }
}
