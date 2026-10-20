import AppKit
import OekakiKit
import SwiftUI

@main
struct OekakiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = Session()

    var body: some Scene {
        Window("Oekaki Studio", id: "main") {
            ContentView(session: session, document: session.document, tools: session.tools, assistant: session.assistant)
                // A new or opened picture gets a fresh canvas view.
                .id(ObjectIdentifier(session.document))
                .frame(minWidth: 980, minHeight: 720)
                .onAppear {
                    appDelegate.session = session
                    DevSnapshot.runIfRequested(session: session)
                }
        }
        .defaultSize(width: 1320, height: 860)
        .commands { AppCommands(session: session) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var session: Session? {
        didSet { openWaitingFile() }
    }
    /// A file the Finder asked to open before the window was ready.
    private var waitingFile: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary is run directly rather than from an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Files double-clicked in the Finder or dropped on the app's icon.
    /// The window holds one picture, so the last of them is opened.
    func application(_ application: NSApplication, open urls: [URL]) {
        waitingFile = urls.last
        openWaitingFile()
    }

    private func openWaitingFile() {
        guard let session, let url = waitingFile else { return }
        waitingFile = nil
        // Not while the window is being laid out: opening replaces the canvas view.
        DispatchQueue.main.async { session.open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session, !DevSnapshot.isRequested else { return .terminateNow }
        return session.confirmLosingChanges() ? .terminateNow : .terminateCancel
    }
}

struct AppCommands: Commands {
    let session: Session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("新しい絵", "New Picture")) { session.newDocument() }
                .keyboardShortcut("n")
            Button(L("開く…", "Open…")) { session.open() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button(L("保存", "Save")) { session.save() }
                .keyboardShortcut("s")
            Button(L("別名で保存…", "Save As…")) { session.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button(L("画像で書き出す…", "Export Image…")) { session.exportPNG() }
                .keyboardShortcut("e")
        }
        CommandGroup(replacing: .undoRedo) {
            Button(L("取り消す", "Undo")) { session.document.undo() }
                .keyboardShortcut("z")
            Button(L("やり直す", "Redo")) { session.document.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Button(L("大きく表示", "Zoom In")) { session.canvas.zoom(by: 1.25) }
                .keyboardShortcut("+")
            Button(L("小さく表示", "Zoom Out")) { session.canvas.zoom(by: 1 / 1.25) }
                .keyboardShortcut("-")
            Button(L("全体を見る", "See All")) { session.canvas.fit() }
                .keyboardShortcut("0")
        }
    }
}
