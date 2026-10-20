import CoreGraphics
import Foundation
import OekakiKit

/// One step of the journal written as a line of code.
struct CodeLine {
    enum Token {
        case text(String, CodeColor)
        /// A colour literal: a small square of the colour, then its hex.
        case swatch(RGBA)
    }

    var tokens: [Token]
    /// The layer the step worked on, for the status bar.
    var layer: String?
    /// The item the step made, if one.
    var itemID: Int?

    var plain: String {
        tokens.map { token in
            switch token {
            case .text(let text, _): return text
            case .swatch(let color): return "■ " + Self.hex(color)
            }
        }.joined()
    }

    static func hex(_ color: RGBA) -> String {
        String(format: "%02X%02X%02X", Int((color.r * 255).rounded()), Int((color.g * 255).rounded()), Int((color.b * 255).rounded()))
    }
}

/// Syntax colours, after a common dark editor theme.
enum CodeColor {
    case function, keyword, number, string, identifier, plain, comment

    var cgColor: CGColor {
        switch self {
        case .function: return Look.color(0x61AFEF)
        case .keyword: return Look.color(0xC678DD)
        case .number: return Look.color(0xD19A66)
        case .string: return Look.color(0x98C379)
        case .identifier: return Look.color(0xE5C07B)
        case .plain: return Look.color(0xABB2BF)
        case .comment: return Look.color(0x6B7280)
        }
    }
}

enum Code {
    /// The journal as source: one line per step.
    static func lines(for replay: Replay, width: Int, height: Int) -> [CodeLine] {
        replay.changes.enumerated().map { index, change in
            line(for: change, title: replay.titles[index], width: width, height: height)
        }
    }

    private static func call(_ name: String, _ arguments: [CodeLine.Token], kind: CodeColor = .function) -> [CodeLine.Token] {
        var tokens: [CodeLine.Token] = [.text(name, kind), .text("(", .plain)]
        tokens += arguments
        tokens.append(.text(")", .plain))
        return tokens
    }

    private static func string(_ text: String) -> CodeLine.Token { .text("\"\(text)\"", .string) }
    private static func number(_ value: CGFloat) -> CodeLine.Token {
        .text(value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value), .number)
    }
    private static func id(_ id: Int) -> CodeLine.Token { .text("#\(id)", .identifier) }
    private static let comma = CodeLine.Token.text(", ", .plain)

    private static func styleArguments(_ style: LayerStyle) -> [CodeLine.Token] {
        var tokens: [CodeLine.Token] = []
        if style.blend != .normal { tokens += [comma, .text("blend: ", .plain), .text(".\(style.blend.rawValue)", .keyword)] }
        if style.isClipped { tokens += [comma, .text("clip: ", .plain), .text("true", .keyword)] }
        if style.glow > 0 { tokens += [comma, .text("glow: ", .plain), number(style.glow)] }
        if style.blur > 0 { tokens += [comma, .text("blur: ", .plain), number(style.blur)] }
        return tokens
    }

    static func line(for change: StepChange, title: String, width: Int, height: Int) -> CodeLine {
        switch change.kind {
        case .start:
            return CodeLine(tokens: call("paper", [number(CGFloat(width)), comma, number(CGFloat(height))]))
        case .opened:
            return CodeLine(tokens: call("open", []))
        case .undo:
            return CodeLine(tokens: call("undo", [], kind: .keyword))
        case .redo:
            return CodeLine(tokens: call("redo", [], kind: .keyword))
        case .edit:
            break
        }
        if let renamed = change.renamedLayers.first {
            return CodeLine(tokens: call("rename", [string(renamed.from), comma, string(renamed.to)]), layer: renamed.to)
        }
        // Tidying makes a layer of steadied copies and hides the original.
        if let made = change.addedLayers.first, let hidden = change.hiddenLayers.first, !change.added.isEmpty {
            return CodeLine(
                tokens: call("tidy", [string(hidden)]) + [.text("  // \(change.added.count) 本 → 「\(made)」", .comment)],
                layer: made
            )
        }
        if let made = change.addedLayers.first {
            var arguments = [string(made)]
            if let style = change.addedLayerStyles.first {
                arguments += styleArguments(style)
            }
            return CodeLine(tokens: call("layer", arguments), layer: made)
        }
        if let (name, style) = change.restyledLayers.first {
            if style.blur > 0, !title.contains("重ね方") {
                return CodeLine(
                    tokens: [.text("layer", .function), .text("(", .plain), string(name), .text(").blur = ", .plain), number(style.blur)],
                    layer: name
                )
            }
            return CodeLine(
                tokens: [.text("layer", .function), .text("(", .plain), string(name), .text(").blend = ", .plain), .text(".\(style.blend.rawValue)", .keyword)],
                layer: name
            )
        }
        if let hidden = change.hiddenLayers.first {
            return CodeLine(tokens: call("hide", [string(hidden)]), layer: hidden)
        }
        if change.added.count == 1, let (layer, item) = change.added.first {
            switch item {
            case .stroke(let stroke) where stroke.softness > 0:
                return CodeLine(
                    tokens: call("airbrush", [
                        id(stroke.id), comma, .text("r: ", .plain), number((stroke.width / 2).rounded()), comma,
                        .text("\(Int((stroke.opacity * 100).rounded()))%", .number), comma, .swatch(stroke.color),
                    ]),
                    layer: layer, itemID: stroke.id
                )
            case .stroke(let stroke):
                var arguments = [id(stroke.id), comma, .text("w: ", .plain), number(stroke.width), comma]
                if stroke.opacity < 1 {
                    arguments += [.text("\(Int((stroke.opacity * 100).rounded()))%", .number), comma]
                }
                return CodeLine(tokens: call("line", arguments + [.swatch(stroke.color)]), layer: layer, itemID: stroke.id)
            case .gradient(let gradient):
                return CodeLine(
                    tokens: call("gradient", [
                        id(gradient.id), comma, .text(".\(gradient.shape.rawValue)", .keyword), comma, .swatch(gradient.from),
                        .text(" → ", .plain), .swatch(gradient.to),
                    ]),
                    layer: layer, itemID: gradient.id
                )
            case .fill(let fill) where fill.seed == nil:
                // Drawn round with the lasso fill: no point was clicked.
                return CodeLine(tokens: call("shape", [id(fill.id), comma, .swatch(fill.color)]), layer: layer, itemID: fill.id)
            case .fill(let fill):
                let seed = fill.seed ?? CGPoint(x: fill.rect.midX, y: fill.rect.midY)
                return CodeLine(
                    tokens: call("fill", [
                        id(fill.id), comma, .text("at: (", .plain), number(seed.x.rounded()), comma, number(seed.y.rounded()),
                        .text(")", .plain), comma, .swatch(fill.color),
                    ]),
                    layer: layer, itemID: fill.id
                )
            default:
                break
            }
        }
        if let (layer, first) = change.changed.first, let color = first.color {
            var tokens: [CodeLine.Token] = [id(first.id), .text(".color = ", .plain), .swatch(color)]
            if change.changed.count > 1 {
                tokens.append(.text("  // 影も +\(change.changed.count - 1)", .comment))
            }
            return CodeLine(tokens: tokens, layer: layer, itemID: first.id)
        }
        return CodeLine(tokens: [.text("// " + title, .comment)])
    }
}
