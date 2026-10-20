import AppKit
import OekakiKit
import SwiftUI

/// The assistant's side of the window: what was asked, what came back, and
/// whether the result has been accepted yet.
final class AssistantModel: ObservableObject {
    enum Setup {
        case checking
        case ready
        case notInstalled
        case notLoggedIn
    }

    enum Phase: Equatable {
        case idle
        case working(AITask, since: Date)
        case failed(String)
    }

    /// How long the assistant may think. More effort gives finer results and
    /// a longer wait; all three use the same model.
    enum Pace: String, CaseIterable, Identifiable {
        case fast
        case normal
        case careful

        var id: String { rawValue }

        var effort: String {
            switch self {
            case .fast: return "low"
            case .normal: return "medium"
            case .careful: return "high"
            }
        }

        var title: String {
            switch self {
            case .fast: return L("はやい", "Fast")
            case .normal: return L("ふつう", "Normal")
            case .careful: return L("ていねい", "Careful")
            }
        }
    }

    /// A result that is on the canvas but not yet accepted.
    struct Pending {
        var task: AITask
        var placement: AIPlacement
        var sessionID: String?
    }

    /// What the person is drawing and how they want it coloured.
    @Published var request = ""
    @Published var pace: Pace = .normal
    /// A change to ask for on the pending result.
    @Published var change = ""
    @Published private(set) var setup: Setup = .checking
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var advice: String?
    @Published private(set) var pending: Pending?

    private let currentDocument: () -> CanvasDocument
    private var executable: URL?
    private var run: ClaudeCLI.Run?
    private var workDirectory: URL?
    private var loginPoll: Timer?

    init(document: @escaping () -> CanvasDocument) {
        currentDocument = document
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }


    // MARK: Setup

    func checkSetup() {
        setup = .checking
        guard let found = ClaudeCLI.locate() else {
            setup = .notInstalled
            return
        }
        executable = found
        ClaudeCLI.checkLogin(executable: found) { [weak self] loggedIn in
            self?.setup = loggedIn ? .ready : .notLoggedIn
        }
    }

    /// Opens the sign-in page and waits for the user to come back signed in.
    func logIn() {
        guard let executable else { return }
        ClaudeCLI.startLogin(executable: executable)
        loginPoll?.invalidate()
        var checksLeft = 90
        loginPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            checksLeft -= 1
            guard let self, checksLeft > 0 else {
                timer.invalidate()
                return
            }
            ClaudeCLI.checkLogin(executable: executable) { loggedIn in
                guard loggedIn else { return }
                timer.invalidate()
                self.setup = .ready
            }
        }
    }

    /// Forgets everything tied to the previous picture.
    func reset() {
        run?.cancel()
        run = nil
        phase = .idle
        advice = nil
        pending = nil
        change = ""
        workDirectory = nil
    }

    // MARK: Requests

    func start(_ task: AITask) {
        guard setup == .ready, !isWorking, let executable else { return }
        // Asking for the next step means the last result is being kept.
        pending = nil
        let document = currentDocument()
        guard let directory = prepareWorkDirectory(), let picture = AIPicture.png(of: document, includingComposition: task == .guide || task == .consult) else {
            phase = .failed(L("キャンバスの画像を用意できませんでした。", "Could not prepare the canvas picture."))
            return
        }
        do {
            try picture.write(to: directory.appendingPathComponent("canvas.png"), options: .atomic)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        let prompt = AIPrompts.prompt(for: task, width: document.width, height: document.height, request: request)
        send(prompt, task: task, resume: nil, executable: executable, directory: directory, replacing: nil)
    }

    /// Asks for a change to the pending result, in the same conversation.
    func revise() {
        let wanted = change.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isWorking, !wanted.isEmpty, let pending, let sessionID = pending.sessionID,
              let executable, let directory = workDirectory
        else { return }
        let prompt = AIPrompts.followUp(for: pending.task, change: wanted)
        send(prompt, task: pending.task, resume: sessionID, executable: executable, directory: directory, replacing: pending)
    }

    /// Throws the pending result away and asks again from scratch.
    func retry() {
        guard let pending, !isWorking else { return }
        discard()
        start(pending.task)
    }

    /// Keeps the pending result.
    func adopt() {
        pending = nil
        change = ""
    }

    /// Takes the pending result off the canvas.
    func discard() {
        guard let pending else { return }
        currentDocument().discard(pending.placement)
        self.pending = nil
        change = ""
    }

    func cancel() {
        run?.cancel()
    }

    private func send(
        _ prompt: String, task: AITask, resume: String?, executable: URL, directory: URL, replacing previous: Pending?
    ) {
        phase = .working(task, since: Date())
        let document = currentDocument()
        run = ClaudeCLI.run(
            executable: executable, prompt: prompt, directory: directory,
            model: ClaudeCLI.model, effort: pace.effort, resume: resume
        ) { [weak self] result in
            guard let self, document === self.currentDocument() else { return }
            self.run = nil
            switch result {
            case .success(let reply):
                self.finish(task, reply: reply, on: document, replacing: previous)
            case .failure(.cancelled):
                self.phase = .idle
            case .failure(.notLoggedIn):
                self.setup = .notLoggedIn
                self.phase = .idle
            case .failure(let failure):
                self.phase = .failed(failure.localizedDescription)
            }
        }
    }

    private func finish(_ task: AITask, reply: ClaudeCLI.Reply, on document: CanvasDocument, replacing previous: Pending?) {
        let response = AIResponse(parsing: reply.text)
        let lines = response.svg.flatMap { SVGRaster.image(from: $0, width: document.width, height: document.height) }
        let nothingUsable = L(
            "AI の返事から絵を取り出せませんでした。もう一度お試しください。",
            "The assistant's answer had no drawing in it. Please try again."
        )
        switch task {
        case .consult:
            guard response.advice != nil else {
                phase = .failed(nothingUsable)
                return
            }
        case .cleanup, .guide:
            guard lines != nil else {
                phase = .failed(nothingUsable)
                return
            }
        case .underpaint:
            guard lines != nil || !response.fills.isEmpty else {
                phase = .failed(nothingUsable)
                return
            }
        }
        // A revised result takes the place of the one it revises.
        if let previous {
            document.discard(previous.placement)
        }
        var placement = AIPlacement()
        switch task {
        case .cleanup:
            if let lines { placement = document.applyLineArt(lines) }
        case .guide:
            if let lines { placement = document.applyGuide(lines) }
        case .underpaint:
            placement = document.applyUnderpaint(fills: response.fills, details: lines)
        case .consult:
            break
        }
        advice = response.advice
        change = ""
        pending = placement.isEmpty ? nil : Pending(task: task, placement: placement, sessionID: reply.sessionID)
        phase = .idle
        NSSound(named: "Glass")?.play()
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    /// One folder per picture, so follow-up requests find their conversation.
    private func prepareWorkDirectory() -> URL? {
        if let workDirectory { return workDirectory }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("OekakiStudio/assistant/\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        workDirectory = directory
        return directory
    }
}

extension AITask {
    var title: String {
        switch self {
        case .cleanup: return L("清書", "Clean Up")
        case .underpaint: return L("下塗り", "Base Colors")
        case .guide: return L("小物と背景", "Props & Background")
        case .consult: return L("相談する", "Ask Advice")
        }
    }

    var systemImage: String {
        switch self {
        case .cleanup: return "wand.and.stars"
        case .underpaint: return "paintpalette"
        case .guide: return "square.dashed"
        case .consult: return "bubble.left"
        }
    }

    var explanation: String {
        switch self {
        case .cleanup:
            return L("今のラフを、整った線に描き直してもらいます", "Have your rough sketch redrawn as tidy lines")
        case .underpaint:
            return L("線で囲まれたところに、色を塗ってもらいます", "Have the areas enclosed by lines filled with color")
        case .guide:
            return L(
                "書いた希望(例:マイクを持つ、教室の窓ぎわ)に合わせて、小物と背景を紫の簡単な線で構図に足してもらいます",
                "Have props and background you asked for (say, holding a microphone, by a classroom window) added to the composition as simple purple lines"
            )
        case .consult:
            return L("今の絵を見て、次にやることを教えてもらいます", "Get advice on what to do next")
        }
    }

    /// Shown once the result is on the canvas.
    var doneMessage: String {
        switch self {
        case .cleanup: return L("清書ができました", "The clean lines are ready")
        case .underpaint: return L("下塗りができました", "The base colors are ready")
        case .guide: return L("小物と背景ができました", "The props and background are ready")
        case .consult: return ""
        }
    }
}
