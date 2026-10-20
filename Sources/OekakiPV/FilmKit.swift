import CoreGraphics
import CoreText
import Foundation

/// The parts of the editor's window that the films draw: the frame, a line
/// of code, captions, badges and cards. Every frame has its origin at the top
/// left, y growing downward.
enum FilmKit {
    /// The window's title bar and the dark editor behind the canvas, with a faint dot grid.
    static func chrome(title: String, in context: CGContext) {
        context.setFillColor(Look.window)
        context.fill(CGRect(x: 0, y: 0, width: Look.width, height: Look.height))
        context.fill(Look.titleBar)
        for (index, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            context.setFillColor(Look.color(UInt32(hex)))
            context.fillEllipse(in: CGRect(x: 20 + CGFloat(index) * 22, y: 15, width: 14, height: 14))
        }
        Look.draw(title, font: Look.uiFont(17), color: Look.dim, centeredAt: CGPoint(x: 960, y: 22), in: context)
        context.setFillColor(Look.editor)
        context.fill(Look.canvasArea)
        context.setFillColor(Look.color(0x262A32))
        var y = Look.canvasArea.minY + 12
        while y < Look.canvasArea.maxY {
            var x = Look.canvasArea.minX + 12
            while x < Look.canvasArea.maxX {
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
                x += 24
            }
            y += 24
        }
    }

    /// The panel on the right, with a heading and a note beside it; returns the area below the heading.
    @discardableResult
    static func panel(_ heading: String, note: String, in context: CGContext) -> CGRect {
        let panel = Look.panel
        context.setFillColor(Look.panelBackground)
        context.fill(panel)
        context.setFillColor(Look.border)
        context.fill(CGRect(x: panel.minX, y: panel.minY, width: 1, height: panel.height))
        context.setFillColor(Look.color(0x191B21))
        context.fill(CGRect(x: panel.minX + 1, y: panel.minY, width: panel.width, height: 46))
        let title = Look.line(heading, font: Look.uiFont(18, bold: true), color: Look.text)
        Look.draw(title, at: CGPoint(x: panel.minX + 24, y: panel.minY + 30), in: context)
        Look.draw(Look.line(note, font: Look.uiFont(15), color: Look.dim), at: CGPoint(x: panel.minX + 40 + Look.width(of: title), y: panel.minY + 30), in: context)
        return CGRect(x: panel.minX, y: panel.minY + 46, width: panel.width, height: panel.height - 46)
    }

    /// The status bar along the bottom.
    static func status(left: String, right: String, in context: CGContext) {
        let bar = Look.statusBar
        context.setFillColor(Look.teal)
        context.fill(bar)
        Look.draw(Look.line(left, font: Look.uiFont(15, bold: true), color: Look.color(0xFFFFFF)), at: CGPoint(x: 20, y: bar.minY + 21), in: context)
        let line = Look.line(right, font: Look.codeFont(14), color: Look.color(0xE8F6F4))
        Look.draw(line, at: CGPoint(x: bar.maxX - 20 - Look.width(of: line), y: bar.minY + 20), in: context)
    }

    /// Draws one line of code, `typed` of it, and returns where it ends.
    @discardableResult
    static func code(_ line: CodeLine, typed: CGFloat, at origin: CGPoint, font: CTFont, in context: CGContext) -> CGFloat {
        var x = origin.x
        var budget = Int((CGFloat(line.plain.count) * typed).rounded())
        for token in line.tokens where budget > 0 {
            switch token {
            case .text(let text, let kind):
                let shown = String(text.prefix(budget))
                budget -= shown.count
                let part = Look.line(shown, font: font, color: kind.cgColor)
                Look.draw(part, at: CGPoint(x: x, y: origin.y), in: context)
                x += Look.width(of: part)
            case .swatch(let color):
                let box = CGRect(x: x + 1, y: origin.y - 14, width: 16, height: 16)
                context.addPath(Look.roundedRect(box, radius: 3))
                context.setFillColor(color.cgColor)
                context.fillPath()
                context.addPath(Look.roundedRect(box, radius: 3))
                context.setStrokeColor(Look.color(0xFFFFFF, alpha: 0.35))
                context.setLineWidth(1)
                context.strokePath()
                x += 22
                budget -= 2
                let hex = String(CodeLine.hex(color).prefix(max(0, budget)))
                budget -= hex.count
                let part = Look.line(hex, font: font, color: CodeColor.number.cgColor)
                Look.draw(part, at: CGPoint(x: x, y: origin.y), in: context)
                x += Look.width(of: part)
            }
        }
        return x
    }

    /// A caption in a dark rounded pill, rising a little as it fades in.
    static func caption(_ text: String, alpha: CGFloat, center: CGPoint, size: CGFloat = 40, in context: CGContext) {
        guard alpha > 0 else { return }
        let font = Look.uiFont(size, bold: true)
        let line = Look.line(text, font: font, color: Look.color(0xFFFFFF))
        let width = Look.width(of: line) + size * 1.6
        let height = size * 1.9
        let box = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let rise = (1 - Ease.out(alpha)) * 10
        context.saveGState()
        context.setAlpha(alpha)
        context.translateBy(x: 0, y: rise)
        context.setShadow(offset: CGSize(width: 0, height: 6), blur: 24, color: Look.color(0x000000, alpha: 0.4))
        context.addPath(Look.roundedRect(box, radius: height / 2))
        context.setFillColor(Look.color(0x101216, alpha: 0.86))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.setAlpha(alpha)
        context.translateBy(x: 0, y: rise)
        Look.draw(text, font: font, color: Look.color(0xFFFFFF), centeredAt: center, in: context)
        context.restoreGState()
    }

    /// A small rounded label.
    static func badge(_ text: String, at point: CGPoint, alignRight: Bool = false, accent: Bool = false, in context: CGContext) {
        let line = Look.line(text, font: Look.uiFont(17, bold: true), color: accent ? Look.color(0x0F1A26) : Look.text)
        let width = Look.width(of: line) + 32
        let box = CGRect(x: alignRight ? point.x - width : point.x, y: point.y, width: width, height: 40)
        context.addPath(Look.roundedRect(box, radius: 20))
        context.setFillColor(accent ? Look.accent : Look.color(0x000000, alpha: 0.6))
        context.fillPath()
        Look.draw(line, at: CGPoint(x: box.minX + 16, y: box.minY + 27), in: context)
    }

    /// A floating card with a soft shadow.
    static func card(_ rect: CGRect, alpha: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setAlpha(alpha)
        context.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: Look.color(0x000000, alpha: 0.5))
        context.addPath(Look.roundedRect(rect, radius: 16))
        context.setFillColor(Look.color(0x23262E))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.setAlpha(alpha)
        context.addPath(Look.roundedRect(rect, radius: 16))
        context.setStrokeColor(Look.border)
        context.setLineWidth(1.5)
        context.strokePath()
        context.restoreGState()
    }
}
