import CoreGraphics
import Foundation

/// Where ideas for other versions come from: the assistant, or the colour
/// sets already kept. Either way they arrive as proposals, each tried on a
/// version of its own; the picture in hand is never changed.
public protocol ProposalSource {
    func propose(_ request: String, for document: CanvasDocument, completion: @escaping (Result<[Proposal], Error>) -> Void)
}

/// Ideas from the colour sets kept with the picture, with no assistant.
public struct ThemeProposalSource: ProposalSource {
    public init() {}

    public func propose(_ request: String, for document: CanvasDocument, completion: @escaping (Result<[Proposal], Error>) -> Void) {
        // A set the picture already has would make a version with nothing to compare.
        let current = document.library.colors
        let different = document.themeProposals.filter { proposal in
            proposal.colors.contains { name, color in
                guard let swatch = document.library.swatches.first(where: { $0.name == name }) else { return false }
                return current[swatch.id]?.hexKey != color.hexKey
            }
        }
        let ideas = different.filter { request.isEmpty || request.contains($0.name) || $0.name.contains(request) }
        completion(.success(ideas.isEmpty ? different : ideas))
    }
}

/// Ideas from the assistant, asked through the Claude command line.
public struct AssistantProposalSource: ProposalSource {
    /// Sends a prompt to the assistant, which may read the files in the
    /// folder given, and hands back its answer.
    public typealias Send = (_ prompt: String, _ folder: URL, _ completion: @escaping (Result<String, Error>) -> Void) -> Void

    let send: Send

    public init(executable: URL, model: String = ClaudeCLI.model, effort: String = ClaudeCLI.effort) {
        send = { prompt, folder, completion in
            ClaudeCLI.run(executable: executable, prompt: prompt, directory: folder, model: model, effort: effort, timeout: 300) {
                completion($0.map(\.text).mapError { $0 as Error })
            }
        }
    }

    /// Asks through `send` instead of the Claude command line, as tests do.
    public init(send: @escaping Send) {
        self.send = send
    }

    public enum Failure: LocalizedError {
        case noIdeas

        public var errorDescription: String? {
            L("アシスタントから案を受け取れませんでした。", "The assistant gave no ideas.")
        }
    }

    public func propose(_ request: String, for document: CanvasDocument, completion: @escaping (Result<[Proposal], Error>) -> Void) {
        let prompt = ProposalPrompt.prompt(
            for: request, library: document.library, layers: document.layers.map(\.name), width: document.width, height: document.height
        )
        // The picture, with a grid of coordinates, for the assistant to look at.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OekakiStudio/proposals/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let png = AIPicture.png(of: document) { try? png.write(to: folder.appendingPathComponent("picture.png")) }
        send(prompt, folder) { result in
            switch result {
            case .success(let reply):
                var ideas = ProposalPrompt.parse(reply)
                for index in ideas.indices { ideas[index].origin = L("AI の案", "Assistant's idea") }
                completion(ideas.isEmpty ? .failure(Failure.noIdeas) : .success(ideas))
            case .failure(let failure):
                completion(.failure(failure))
            }
        }
    }
}

/// What the assistant is asked, and how its answer is read.
public enum ProposalPrompt {
    public static func prompt(for request: String, library: Library, layers: [String], width: Int = 1000, height: Int = 1000) -> String {
        let colors = library.swatches.map { "- \($0.name): \(StyleColors.hex($0.color))" }.joined(separator: "\n")
        let sheets = layers.map { "- \($0)" }.joined(separator: "\n")
        return """
        You help with an illustration. Its colours have names, and changing a named colour changes everything painted with it.
        Propose 2 or 3 versions for this request: \(request)

        Named colours (name: current value):
        \(colors)

        Layers:
        \(sheets)

        The picture is in picture.png in this folder, with a grid of canvas coordinates; read it first. The canvas is \(width) × \(height) pixels, x to the right and y down.

        A version may give named colours new values, may hide or show layers by name, may erase lines, and may draw lines on a new layer on top.
        To change an expression, erase the old mouth or eyes by giving boxes around them in "erase" as [left, top, right, bottom]:
        every line and fill wholly inside a box is taken out. Keep each box tight so nothing else is inside it. Then draw the new ones.
        Lines are lists of points in canvas pixels, with a width and a colour. Use only the colour and layer names above.
        Name each version in a few words, in the language of the request.
        Answer with JSON only, in this form:
        {"proposals": [{"name": "...", "colors": {"<colour name>": "#RRGGBB"}, "hide": ["<layer name>"], "show": [],
                        "erase": [[left, top, right, bottom]],
                        "lines": [{"points": [[x, y], [x, y]], "width": 6, "color": "#RRGGBB"}]}]}
        """
    }

    /// The proposals in the assistant's answer; none when it cannot be read.
    public static func parse(_ text: String) -> [Proposal] {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let list = object["proposals"] as? [[String: Any]]
        else { return [] }
        return list.compactMap { entry in
            guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
            var colors: [String: RGBA] = [:]
            for (key, value) in entry["colors"] as? [String: String] ?? [:] {
                if let color = RGBA(hexString: value) { colors[key] = color }
            }
            let lines = (entry["lines"] as? [[String: Any]] ?? []).compactMap { line -> ProposedLine? in
                let points = (line["points"] as? [[Double]] ?? []).compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
                guard !points.isEmpty else { return nil }
                let width = (line["width"] as? Double).map { CGFloat(min(max($0, 1), 200)) } ?? 6
                let color = (line["color"] as? String).flatMap(RGBA.init(hexString:)) ?? .black
                return ProposedLine(points: points, width: width, color: color)
            }
            let erased = (entry["erase"] as? [[Double]] ?? []).compactMap { box -> CGRect? in
                guard box.count == 4 else { return nil }
                let area = CGRect(x: min(box[0], box[2]), y: min(box[1], box[3]), width: abs(box[2] - box[0]), height: abs(box[3] - box[1]))
                return area.width > 0 && area.height > 0 ? area : nil
            }
            return Proposal(
                name: name, colors: colors,
                hiddenLayers: entry["hide"] as? [String] ?? [], shownLayers: entry["show"] as? [String] ?? [], lines: lines,
                erasedAreas: erased
            )
        }
    }
}
