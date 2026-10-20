import Foundation
import OekakiKit
import ImageIO
import UniformTypeIdentifiers

/// Makes the promotional film.
///
///     OekakiPV film out/pv.mp4          the film
///     OekakiPV still out/picture.png    the finished picture alone
///     OekakiPV frames out/frames t...   frames at the given seconds
let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, arguments.count >= 2 else {
    print("usage: OekakiPV film|still|frames <path> [seconds...]")
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

switch command {
case "still":
    let picture = Portrait.draw()
    picture.problems.forEach { print("problem:", $0) }
    if let image = picture.document.compositeImage() {
        writePNG(image, to: output)
        print("wrote \(output.path), \(picture.document.journal.count) steps")
    }
    // How much of the canvas only the background covers.
    let document = picture.document
    if document.layers.first != nil {
        // Only the figure itself: its lines and its base colours.
        for layer in document.layers where !["下塗り", "線画", "瞳"].contains(layer.name) {
            document.setLayerVisible(layer.id, false)
        }
        if let figure = document.compositeImage(background: nil) {
            let width = figure.width, height = figure.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(figure, in: CGRect(x: 0, y: 0, width: width, height: height))
            let open = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] < 128 }.count
            print(String(format: "background shows on %.1f%% of the canvas", Double(open) * 100 / Double(width * height)))
        }
    }

case "film":
    let film = Film(picture: Portrait.draw())
    film.picture.problems.forEach { print("problem:", $0) }
    let encoder = try Encoder(url: output, width: Look.width, height: Look.height, fps: Film.fps)
    let frames = film.frameCount
    for frame in 0..<frames {
        let time = Double(frame) / Double(Film.fps)
        try autoreleasepool {
            try encoder.append { film.draw(at: time, in: $0) }
        }
        if frame % 150 == 0 { print("frame \(frame) / \(frames)") }
    }
    try encoder.finish()
    print(String(format: "wrote %@: %d frames, %.1f s, %d steps, 1x length %.1f s", output.path, frames, film.times.end, film.replay.count, film.naturalLength))
case "frames":
    let film = Film(picture: Portrait.draw())
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    print(film.times)
    for argument in arguments.dropFirst(2) {
        guard let time = Double(argument), let image = frameImage({ film.draw(at: time, in: $0) }) else { continue }
        writePNG(image, to: output.appendingPathComponent(String(format: "t%05.2f.png", time)))
    }
case "logo":
    // The mark, its source file, the app icon and the mark with the name.
    let (document, problems) = Logo.draw()
    problems.forEach { print("problem:", $0) }
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let source = try DocumentFile.encode(document)
    try source.write(to: output.appendingPathComponent("logo.\(DocumentFile.fileExtension)"))
    guard let mark = document.compositeImage(background: nil) else { exit(1) }
    // The saved file must open as the same picture.
    let reopened = try DocumentFile.decode(source)
    if let again = reopened.compositeImage(background: nil), let a = again.dataProvider?.data, let b = mark.dataProvider?.data {
        let x = Array(a as Data), y = Array(b as Data)
        let off = zip(x, y).filter { abs(Int($0) - Int($1)) > 2 }.count
        print("logo.\(DocumentFile.fileExtension) reopened: \(reopened.layers.count) layers, \(off) of \(x.count) bytes differ by more than 2")
    }
    writePNG(mark, to: output.appendingPathComponent("logo.png"))
    let iconset = output.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            if let image = BrandArt.scaled(mark, to: points * scale) { writePNG(image, to: iconset.appendingPathComponent(name)) }
        }
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
    try iconutil.run()
    iconutil.waitUntilExit()
    if let drop = Logo.dropOnly() {
        if let wordmark = BrandArt.dropWordmark(drop) { writePNG(wordmark, to: output.appendingPathComponent("logo-wordmark.png")) }
        // For pages shown in dark mode, such as the README on GitHub.
        if let wordmark = BrandArt.dropWordmark(drop, onDark: true) { writePNG(wordmark, to: output.appendingPathComponent("logo-wordmark-dark.png")) }
    }
    print("wrote the mark, AppIcon.icns and the wordmark to \(output.path), \(document.journal.count) steps")
case "treat":
    // "Want a bite?": the rough, then the picture in each look, into the folder given.
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (index, look) in [Treat.strawberry, Treat.mint, Treat.vanillaNight].enumerated() {
        let result = Treat.draw(look)
        result.problems.forEach { print("problem (\(look.name)):", $0) }
        if index == 0, let rough = result.rough { writePNG(rough, to: output.appendingPathComponent("0-ラフ.png")) }
        if let image = result.document.compositeImage() {
            writePNG(image, to: output.appendingPathComponent("\(index + 1)-\(look.name).png"))
        }
    }
    print("wrote \(output.path)")

case "bite":
    // 「一口食べる？」: each phase of the making, then the finished picture.
    //     OekakiPV bite out/bite [unit]
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let unit = arguments.count > 2 ? CGFloat(Double(arguments[2]) ?? 2) : 2
    let started = Date()
    if arguments.count > 3, arguments[3] == "looks" {
        // Only the finished picture, in each set of colours.
        for colors in [Bite.mintDay, Bite.strawberryEvening, Bite.vanillaNight] {
            let result = Bite.draw(colors, unit: unit)
            result.problems.forEach { print("problem (\(colors.name)):", $0) }
            if let image = result.document.compositeImage() { writePNG(image, to: output.appendingPathComponent("\(colors.name).png")) }
        }
        print(String(format: "wrote the looks to %@, %.1f s", output.path, Date().timeIntervalSince(started)))
        break
    }
    let result = Bite.draw(unit: unit)
    result.problems.forEach { print("problem:", $0) }
    let document = result.document
    document.flushJournal()
    let replay = Replay(steps: document.journal, width: document.width, height: document.height)
    for phase in Bite.Phase.allCases {
        guard let end = result.phaseEnds[phase] else { continue }
        replay.seek(to: end)
        if let image = replay.frame(maxSide: max(document.width, document.height)) {
            writePNG(image, to: output.appendingPathComponent("\(phase.rawValue).png"))
        }
    }
    if let image = document.compositeImage() { writePNG(image, to: output.appendingPathComponent("完成.png")) }
    // The picture as a file the app opens, with every step of its making.
    try DocumentFile.encode(document).write(to: output.appendingPathComponent("一口食べる？.\(DocumentFile.fileExtension)"))
    print(String(format: "wrote %@: %d steps, %d layers, %.1f s", output.path, document.journal.count, document.layers.count, Date().timeIntervalSince(started)))

case "pv":
    // The film of 「一口食べる？」 being made in Oekaki Studio.
    //     OekakiPV pv out/bite/pv.mp4 [unit]       the film
    //     OekakiPV pv out/bite/frames 1 t1 t2 ...  frames at the given seconds
    let unit = arguments.count > 2 ? CGFloat(Double(arguments[2]) ?? 1) : 1
    let started = Date()
    // The app's own window with the picture open, if a picture of it was taken (see DevSnapshot's OEKAKI_DEMO=file).
    let window = output.deletingLastPathComponent().appendingPathComponent("app/file-blur.png")
    let film = BitePV(unit: unit, finishUnit: 2, appWindow: FileManager.default.fileExists(atPath: window.path) ? window : nil)
    film.picture.problems.forEach { print("problem:", $0) }
    print(String(format: "made ready in %.1f s: %d steps", Date().timeIntervalSince(started), film.replay.count))
    if output.pathExtension == "mp4" {
        let encoder = try Encoder(url: output, width: Look.width, height: Look.height, fps: BitePV.fps)
        for frame in 0..<film.frameCount {
            let time = Double(frame) / Double(BitePV.fps)
            try autoreleasepool { try encoder.append { film.draw(at: time, in: $0) } }
            if frame % 150 == 0 { print(String(format: "frame %d / %d, %.0f s", frame, film.frameCount, Date().timeIntervalSince(started))) }
        }
        try encoder.finish()
        print(String(format: "wrote %@: %d frames, %.1f s of film, in %.0f s", output.path, film.frameCount, film.times.end, Date().timeIntervalSince(started)))
    } else {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for argument in arguments.dropFirst(3) {
            guard let time = Double(argument), let image = frameImage({ film.draw(at: time, in: $0) }) else { continue }
            writePNG(image, to: output.appendingPathComponent(String(format: "t%05.2f.png", time)))
        }
        print("wrote frames to \(output.path)")
    }

case "music":
    // The film's music, as long as the film, its tune coming in with the finished picture.
    let times = BitePV.Times()
    try MusicBox.write(to: output, length: times.end, climax: times.showcase, ending: times.ending)
    print("wrote \(output.path)")

case "features":
    // Four features on the evening picture, as a short film and stills.
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let request = "夜の配色"
    // Ask the real assistant once, when it is installed; otherwise use the colour sets.
    let asked = Portrait.draw().document
    let sets = Portrait.nameColors(asked)
    var proposals: [Proposal] = []
    var source = "色の組から"
    var log = "request: \(request)\n"
    if let executable = ClaudeCLI.locate() {
        var finished = false
        AssistantProposalSource(executable: executable).propose(request, for: asked) { result in
            switch result {
            case .success(let ideas):
                proposals = ideas
                source = "AI の案"
                log += "assistant: \(ideas.count) ideas\n" + ideas.map { idea in
                    "- \(idea.name): " + idea.colors.sorted { $0.key < $1.key }.map { "\($0.key)=\(CodeLine.hex($0.value))" }.joined(separator: ", ")
                        + (idea.hiddenLayers.isEmpty ? "" : " hide=\(idea.hiddenLayers)")
                }.joined(separator: "\n") + "\n"
            case .failure(let error):
                log += "assistant failed: \(error.localizedDescription)\n"
            }
            finished = true
        }
        let deadline = Date().addingTimeInterval(320)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    } else {
        log += "assistant: not installed\n"
    }
    if proposals.isEmpty {
        proposals = asked.themeProposals.filter { $0.name != "夕方" }
        _ = sets
    }
    try log.write(to: output.appendingPathComponent("ai-proposals.txt"), atomically: true, encoding: .utf8)
    print(log)
    let film = FeatureFilm(proposals: proposals, source: source, request: request)
    let encoder = try Encoder(url: output.appendingPathComponent("demo.mp4"), width: Look.width, height: Look.height, fps: FeatureFilm.fps)
    for frame in 0..<film.frameCount {
        let time = Double(frame) / Double(FeatureFilm.fps)
        try autoreleasepool { try encoder.append { film.draw(at: time, in: $0) } }
    }
    try encoder.finish()
    for (name, time) in [("1-まとめて選ぶ-前", 3.5), ("1-まとめて選ぶ", 8.2), ("2-色の組", 13.5), ("3-部品-並べ始め", 17.7), ("3-部品-全部置いた", 20.3), ("3-部品-元の色を変えた", 22.3), ("3-部品", 22.0), ("4-AIの案", 25.5), ("4-AIの案-見比べ", 28.0), ("4-AIの案-採用", 30.0), ("5-おわり", 33.3)] {
        if let image = frameImage({ film.draw(at: time, in: $0) }) { writePNG(image, to: output.appendingPathComponent("\(name).png")) }
    }
    print("wrote \(output.path)/demo.mp4: \(film.frameCount) frames")
case "night":
    // The picture in its evening colours and in its night colours.
    let picture = Portrait.draw()
    let sets = Portrait.nameColors(picture.document)
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    if let image = picture.document.compositeImage() { writePNG(image, to: output.appendingPathComponent("evening.png")) }
    picture.document.applyTheme(sets.night)
    if let image = picture.document.compositeImage() { writePNG(image, to: output.appendingPathComponent("night.png")) }
    print("named \(picture.document.library.swatches.count) colours")
case "logos":
    // Every idea for the mark and the name, side by side.
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let notes: [Logo.Mark: (String, String)] = [
        .braces: ("A", "括弧の中に絵の具"), .cursor: ("B", "筆の線がカーソルに"),
        .kana: ("C", "「お」の点が絵の具"), .tag: ("D", "</> の斜線が筆"),
    ]
    var marks: [(String, String, CGImage)] = []
    var images: [Logo.Mark: CGImage] = [:]
    for mark in Logo.Mark.allCases {
        let (document, problems) = Logo.draw(mark)
        problems.forEach { print("problem in \(mark):", $0) }
        try DocumentFile.encode(document).write(to: output.appendingPathComponent("mark-\(mark.rawValue).\(DocumentFile.fileExtension)"))
        guard let image = document.compositeImage(background: nil) else { continue }
        writePNG(image, to: output.appendingPathComponent("mark-\(mark.rawValue).png"))
        images[mark] = image
        marks.append((notes[mark]!.0, notes[mark]!.1, image))
    }
    var wordmarks: [(String, String, CGImage)] = []
    if let mark = images[.braces], let image = BrandArt.wordmark(mark) { wordmarks.append(("W1", "マーク＋丸ゴシック", image)) }
    if let drop = Logo.dropOnly(), let image = BrandArt.dropWordmark(drop) { wordmarks.append(("W2", "i の点が絵の具", image)) }
    if let mark = images[.tag], let image = BrandArt.codeWordmark(mark) { wordmarks.append(("W3", "コードの見た目", image)) }
    for (index, item) in wordmarks.enumerated() {
        writePNG(item.2, to: output.appendingPathComponent("wordmark-\(index + 1).png"))
    }
    if let sheet = BrandArt.sheet(marks: marks, wordmarks: wordmarks) {
        writePNG(sheet, to: output.appendingPathComponent("logo-ideas.png"))
    }
    print("wrote \(marks.count) marks and \(wordmarks.count) wordmarks to \(output.path)")
default:
    print("unknown command \(command)")
    exit(2)
}
