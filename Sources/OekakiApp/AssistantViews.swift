import OekakiKit
import SwiftUI

/// The "draw with AI" part of the side panel.
struct AssistantPanel: View {
    @ObservedObject var assistant: AssistantModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: L("AI と描く", "Draw with AI"))
            switch assistant.setup {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("AI を使えるか確認しています…", "Checking that the assistant is available…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            case .notInstalled:
                setupNote(
                    L(
                        "AI を使うには、Claude Code というアプリが必要です。claude.com/claude-code から入れたあと、下のボタンを押してください。",
                        "The assistant needs an app called Claude Code. Install it from claude.com/claude-code, then press the button below."
                    ),
                    button: L("もう一度確認する", "Check Again")
                ) { assistant.checkSetup() }
            case .notLoggedIn:
                setupNote(
                    L(
                        "AI を使うには、Claude へのログインが必要です。ボタンを押すとブラウザが開きます。",
                        "The assistant needs you to sign in to Claude. The button opens your browser."
                    ),
                    button: L("ログインする", "Sign In")
                ) { assistant.logIn() }
            case .ready:
                ready
            }
        }
        .padding(12)
        .onAppear {
            if assistant.setup == .checking { assistant.checkSetup() }
        }
    }

    @ViewBuilder
    private var ready: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $assistant.request)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(4)
            if assistant.request.isEmpty {
                Text(L("何を描くか、色の希望などを書きます\n例:三毛猫。パステル調で", "Write what you are drawing and any color wishes\ne.g. a calico cat, in pastel colors"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)))

        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(AITask.allCases) { task in
                LabeledButton(title: task.title, systemImage: task.systemImage) { assistant.start(task) }
                    .help(task.explanation)
            }
        }
        .disabled(assistant.isWorking)

        Picker("", selection: $assistant.pace) {
            ForEach(AssistantModel.Pace.allCases) { pace in
                Text(pace.title).tag(pace)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(assistant.isWorking)
        .help(L(
            "AI が考える時間です。「はやい」は 20 秒ほど、「ていねい」は 1 分ほどで、仕上がりが細かくなります",
            "How long the assistant thinks. Fast takes about 20 seconds; Careful takes about a minute and gives finer results"
        ))

        switch assistant.phase {
        case .working(let task, let since):
            WorkingNote(task: task, since: since) { assistant.cancel() }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            if let advice = assistant.advice {
                ScrollView {
                    Text(advice)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 96)
            }
        }
    }

    private func setupNote(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(button, action: action)
        }
    }
}

/// Progress while a request is out, with a way to stop it.
private struct WorkingNote: View {
    let task: AITask
    let since: Date
    let cancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { timeline in
            let seconds = max(0, Int(timeline.date.timeIntervalSince(since)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("\(task.title)をお願いしています… \(seconds) 秒", "Working on \(task.title)… \(seconds)s"))
                        .font(.system(size: 11).monospacedDigit())
                    Spacer()
                    Button(L("中止", "Stop"), action: cancel)
                        .controlSize(.small)
                }
                Text(seconds < 45
                    ? L("待っているあいだも描き続けられます。", "You can keep drawing while you wait.")
                    : L("もう少しかかりそうです。コーヒーでも飲んで、ゆっくりどうぞ。終わったら音でお知らせします。", "This one takes a while. Go get a coffee; a sound will tell you when it is done."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Shown over the canvas while a result waits to be accepted.
struct ResultBar: View {
    @ObservedObject var assistant: AssistantModel
    let pending: AssistantModel.Pending

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text(pending.task.doneMessage)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 16)
                Button(L("これでいい", "Keep It")) { assistant.adopt() }
                    .buttonStyle(.borderedProminent)
                    .help(L("この結果をそのまま使います", "Use this result as it is"))
                Button(L("やり直す", "Try Again")) { assistant.retry() }
                    .help(L("この結果を捨てて、もう一度お願いします", "Throw this away and ask again"))
                Button(L("やめる", "Discard")) { assistant.discard() }
                    .help(L("この結果を捨てて、元に戻します", "Throw this away and go back to how it was"))
            }
            if pending.sessionID != nil {
                HStack(spacing: 8) {
                    TextField(L("直してほしいところを書く(例:耳をもっと大きく)", "Describe a change (e.g. make the ears bigger)"), text: $assistant.change)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { assistant.revise() }
                    Button(L("直してもらう", "Revise")) { assistant.revise() }
                        .disabled(assistant.change.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .controlSize(.large)
        .padding(12)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}
