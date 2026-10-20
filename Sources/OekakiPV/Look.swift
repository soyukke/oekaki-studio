import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Colours, fonts and drawing helpers for the film. Every frame is drawn
/// with the origin at the top left and y growing downward.
enum Look {
    static let width = 1920
    static let height = 1080
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // The window, laid out like an editor: the canvas on the left, the
    // source on the right, a status bar along the bottom.
    static let titleBar = CGRect(x: 0, y: 0, width: 1920, height: 44)
    static let canvasArea = CGRect(x: 0, y: 44, width: 1280, height: 1006)
    static let panel = CGRect(x: 1280, y: 44, width: 640, height: 1006)
    static let statusBar = CGRect(x: 0, y: 1050, width: 1920, height: 30)

    static let window = color(0x121418)
    static let editor = color(0x1A1C21)
    static let panelBackground = color(0x1F2229)
    static let border = color(0x2C303A)
    static let accent = color(0x5AB4FF)
    static let teal = color(0x3E9BA8)
    static let text = color(0xD7DCE4)
    static let dim = color(0x7D8594)

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
        )
    }

    static func codeFont(_ size: CGFloat) -> CTFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
    }

    static func uiFont(_ size: CGFloat, bold: Bool = false) -> CTFont {
        CTFontCreateWithName((bold ? "HiraginoSans-W6" : "HiraginoSans-W3") as CFString, size, nil)
    }

    static func line(_ text: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Draws text with its baseline starting at `point`.
    static func draw(_ line: CTLine, at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = point
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Draws text centred on `center`.
    static func draw(_ text: String, font: CTFont, color: CGColor, centeredAt center: CGPoint, in context: CGContext) {
        let line = line(text, font: font, color: color)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        draw(line, at: CGPoint(x: center.x - width(of: line) / 2, y: center.y + (ascent - descent) / 2), in: context)
    }

    /// Draws an image the right way up into a rect of the top-left context.
    static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The mouse pointer, its tip at `tip`.
    static func drawPointer(at tip: CGPoint, pressed: Bool, in context: CGContext) {
        let shape: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 23), CGPoint(x: 5.6, y: 17.6), CGPoint(x: 9.6, y: 26.4),
            CGPoint(x: 13.2, y: 24.8), CGPoint(x: 9.3, y: 16.2), CGPoint(x: 16.5, y: 16.2),
        ]
        let scale: CGFloat = pressed ? 1.45 : 1.6
        let path = CGMutablePath()
        path.addLines(between: shape.map { CGPoint(x: tip.x + $0.x * scale, y: tip.y + $0.y * scale) })
        path.closeSubpath()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: color(0x000000, alpha: 0.45))
        context.addPath(path)
        context.setFillColor(color(0x111111))
        context.fillPath()
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(color(0xFFFFFF))
        context.setLineWidth(2)
        context.setLineJoin(.round)
        context.strokePath()
    }

    /// A ring spreading from a click, `progress` 0...1.
    static func drawRipple(at point: CGPoint, progress: CGFloat, in context: CGContext) {
        guard progress > 0, progress < 1 else { return }
        let radius = 8 + 34 * Ease.out(progress)
        context.setStrokeColor(accent.copy(alpha: 0.9 * (1 - progress))!)
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
    }
}

enum Ease {
    static func clamp(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
    static func inOut(_ x: CGFloat) -> CGFloat {
        let t = clamp(x)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    static func out(_ x: CGFloat) -> CGFloat {
        let t = clamp(x)
        return 1 - pow(1 - t, 3)
    }
    /// 0 before `start`, rising to 1 over `length` seconds.
    static func ramp(_ time: Double, _ start: Double, _ length: Double) -> CGFloat {
        clamp(CGFloat((time - start) / length))
    }
    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t)) }
    static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: mix(a.minX, b.minX, t), y: mix(a.minY, b.minY, t), width: mix(a.width, b.width, t), height: mix(a.height, b.height, t))
    }
}
