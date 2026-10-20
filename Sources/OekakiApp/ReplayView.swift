import Combine
import OekakiKit
import SwiftUI

/// Plays back how the picture was made, step by step, with each line drawn
/// along its points the way it was drawn.
final class ReplayPlayer: ObservableObject, Identifiable {
    static let speeds: [Double] = [1, 2, 4, 8, 16]

    let replay: Replay
    @Published private(set) var frame: CGImage?
    /// The last step shown whole.
    @Published private(set) var index = 0
    /// The step whose line is being drawn, if one is part way.
    @Published private(set) var drawing: Int?
    @Published private(set) var isPlaying = false
    @Published var speed: Double = 2
    /// Time spent on the step after `index`, in seconds at 1x.
    private var elapsed: Double = 0
    private var timer: AnyCancellable?
    private var lastTick: Date?

    init(document: CanvasDocument) {
        document.flushJournal()
        replay = Replay(steps: document.journal, width: document.width, height: document.height)
        show(replay.count - 1)
    }

    var count: Int { replay.count }
    /// The step the caption is about: the line being drawn, or the last step shown.
    var current: Int { drawing ?? index }
    var title: String { replay.titles.indices.contains(current) ? replay.titles[current] : "" }
    var time: Date? { replay.steps.indices.contains(current) ? replay.steps[current].time : nil }

    /// How long step `index` takes at 1x: a line as long as its drawing
    /// deserves, within limits, and a short pause for anything else.
    private func duration(of index: Int) -> Double {
        if let drawn = replay.strokeDrawn(at: index) {
            return min(max(Double(drawn.stroke.points.count) / 120, 0.2), 1.2)
        }
        return 0.3
    }

    /// Shows the picture after step `target`, or part way through drawing
    /// the line that step adds.
    func show(_ target: Int, share: Double = 1) {
        let step = min(max(target, 0), count - 1)
        if share < 1, let drawn = replay.strokeDrawn(at: step) {
            replay.seek(to: step - 1)
            index = step - 1
            drawing = step
            frame = replay.frame(maxSide: 1400, partial: (drawn.layerID, drawn.stroke, share))
        } else {
            replay.seek(to: step)
            index = step
            drawing = nil
            frame = replay.frame(maxSide: 1400)
        }
    }

    func togglePlaying() {
        isPlaying ? pause() : play()
    }

    func play() {
        if index >= count - 1 { show(0) }
        elapsed = 0
        lastTick = nil
        isPlaying = true
        timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect().sink { [weak self] now in
            self?.tick(now)
        }
    }

    func pause() {
        isPlaying = false
        timer = nil
    }

    func step(by offset: Int) {
        pause()
        show(index + offset)
    }

    func scrub(to value: Double) {
        pause()
        show(Int(value.rounded()))
    }

    private func tick(_ now: Date) {
        let delta = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        elapsed += delta * speed
        var shown = index
        while shown + 1 < count, elapsed >= duration(of: shown + 1) {
            elapsed -= duration(of: shown + 1)
            shown += 1
        }
        guard shown + 1 < count else {
            show(count - 1)
            pause()
            return
        }
        if replay.strokeDrawn(at: shown + 1) != nil {
            // The next line is being drawn.
            show(shown + 1, share: elapsed / duration(of: shown + 1))
        } else if shown != index {
            show(shown)
        }
    }
}

struct ReplayView: View {
    @ObservedObject var player: ReplayPlayer
    let close: () -> Void

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(L("描いた順に再生", "Replay"), systemImage: "play.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(L("閉じる", "Close"), action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                if let frame = player.frame {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        .padding(20)
                }
            }

            Divider()
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text(player.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    if let time = player.time {
                        Text(Self.clock.string(from: time))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("\(player.current + 1) / \(player.count)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button { player.step(by: -1) } label: { Image(systemName: "backward.frame.fill") }
                        .disabled(player.index == 0)
                        .help(L("1 つ前の手順", "Previous step"))
                    Button { player.togglePlaying() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .help(player.isPlaying ? L("止める", "Pause") : L("再生する", "Play"))
                    Button { player.step(by: 1) } label: { Image(systemName: "forward.frame.fill") }
                        .disabled(player.index >= player.count - 1)
                        .help(L("1 つ次の手順", "Next step"))
                    Slider(
                        value: Binding(get: { Double(player.index) }, set: { player.scrub(to: $0) }),
                        in: 0...Double(max(player.count - 1, 1))
                    )
                    Picker("", selection: $player.speed) {
                        ForEach(ReplayPlayer.speeds, id: \.self) { speed in
                            Text("\(Int(speed))×").tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                    .help(L("再生の速さ", "Playback speed"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 860, minHeight: 680)
    }
}
