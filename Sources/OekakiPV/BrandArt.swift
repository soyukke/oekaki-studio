import AppKit
import CoreGraphics
import CoreText
import Foundation
import OekakiKit

/// Pictures made from the drawn mark: smaller copies for the app icon, and
/// the mark set beside the name in type.
enum BrandArt {
    /// One way of looking at it, offered rather than insisted on.
    static let tagline = "もしも、お絵描きソフトが IDE だったら。"

    static func scaled(_ image: CGImage, to side: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: Look.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    /// The mark on the left, "Oekaki Studio" and what it is on the right.
    static func wordmark(_ mark: CGImage) -> CGImage? {
        let width = 1800, height = 520
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: Look.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        Look.draw(mark, in: CGRect(x: 20, y: 20, width: 480, height: 480), context: context)
        let rounded = NSFont.systemFont(ofSize: 150, weight: .bold).fontDescriptor.withDesign(.rounded)
        let nameFont = rounded.flatMap { NSFont(descriptor: $0, size: 150) } ?? NSFont.systemFont(ofSize: 150, weight: .bold)
        let ink = Look.color(0x2B2A4C)
        Look.draw(Look.line("Oekaki Studio", font: nameFont as CTFont, color: ink), at: CGPoint(x: 540, y: 270), in: context)
        Look.draw(Look.line(tagline, font: Look.uiFont(54, bold: true), color: Look.color(0x6A6888)), at: CGPoint(x: 552, y: 380), in: context)
        return context.makeImage()
    }

    private static let ink = Look.color(0x2B2A4C)
    private static let soft = Look.color(0x6A6888)

    private static func canvas(_ width: Int, _ height: Int, _ background: CGColor? = nil) -> CGContext? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: Look.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    private static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return (base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base) as CTFont
    }

    /// "Oekaki" whose i has a drop of paint for its dot, then "Studio", and
    /// the tagline under them if wanted. The picture is as wide as the words.
    /// `onDark` lightens the dark letters, for a dark page behind them.
    static func dropWordmark(_ drop: CGImage, withTagline: Bool = true, onDark: Bool = false) -> CGImage? {
        let bold = rounded(190, .heavy)
        // A dotless i, so the drop can take the dot's place.
        let name = Look.line("Oekakı", font: bold, color: onDark ? Look.color(0xECEBF5) : ink)
        let studio = Look.line("Studio", font: rounded(190, .regular), color: Look.color(0xE0566A))
        let width = Int(80 + Look.width(of: name) + 50 + Look.width(of: studio) + 80)
        guard let context = canvas(width, withTagline ? 520 : 420) else { return nil }
        let origin = CGPoint(x: 80, y: 340)
        Look.draw(name, at: origin, in: context)
        let iStart = CTLineGetOffsetForStringIndex(name, 5, nil)
        let iEnd = CTLineGetOffsetForStringIndex(name, 6, nil)
        let dropWidth: CGFloat = 70
        let dropHeight = dropWidth * CGFloat(drop.height) / CGFloat(drop.width)
        let center = origin.x + (iStart + iEnd) / 2
        Look.draw(drop, in: CGRect(x: center - dropWidth / 2 + 4, y: origin.y - 112 - dropHeight, width: dropWidth, height: dropHeight), context: context)
        Look.draw(studio, at: CGPoint(x: origin.x + Look.width(of: name) + 50, y: origin.y), in: context)
        if withTagline {
            Look.draw(Look.line(tagline, font: Look.uiFont(50, bold: true), color: onDark ? Look.color(0xA8A6C2) : soft), at: CGPoint(x: 90, y: 450), in: context)
        }
        return context.makeImage()
    }

    /// The name as code: a small mark, monospaced type and a cursor.
    static func codeWordmark(_ mark: CGImage) -> CGImage? {
        guard let context = canvas(1800, 520) else { return nil }
        Look.draw(mark, in: CGRect(x: 40, y: 80, width: 360, height: 360), context: context)
        let mono = NSFont.monospacedSystemFont(ofSize: 132, weight: .bold) as CTFont
        let name = Look.line("oekaki.studio", font: mono, color: ink)
        let origin = CGPoint(x: 440, y: 300)
        Look.draw(name, at: origin, in: context)
        context.setFillColor(Look.color(0x2FB9B3))
        context.fill(CGRect(x: origin.x + Look.width(of: name) + 14, y: origin.y - 104, width: 26, height: 124))
        Look.draw(Look.line("// " + tagline, font: NSFont.monospacedSystemFont(ofSize: 40, weight: .medium) as CTFont, color: soft),
                  at: CGPoint(x: 446, y: 400), in: context)
        return context.makeImage()
    }

    /// Every idea on one sheet, to choose from.
    static func sheet(marks: [(String, String, CGImage)], wordmarks: [(String, String, CGImage)]) -> CGImage? {
        let width = 2000, height = 2560
        guard let context = canvas(width, height, Look.color(0xF6F3EF)) else { return nil }
        Look.draw(Look.line("Oekaki Studio ロゴ案", font: Look.uiFont(64, bold: true), color: ink), at: CGPoint(x: 80, y: 120), in: context)
        Look.draw(Look.line("マークはすべて Oekaki Studio で描いたもの（.\(DocumentFile.fileExtension) で開いて直せる）。文字は書体で組んでいる。",
                            font: Look.uiFont(28), color: soft), at: CGPoint(x: 80, y: 180), in: context)
        for (index, (label, note, image)) in marks.enumerated() {
            let x = 80 + CGFloat(index) * 470
            let box = CGRect(x: x, y: 240, width: 420, height: 420)
            Look.draw(image, in: box, context: context)
            Look.draw(Look.line(label, font: Look.uiFont(40, bold: true), color: ink), at: CGPoint(x: x + 10, y: 720), in: context)
            Look.draw(Look.line(note, font: Look.uiFont(24), color: soft), at: CGPoint(x: x + 10, y: 762), in: context)
            // Small, as in the Dock and in Finder lists.
            if let small = scaled(image, to: 64), let tiny = scaled(image, to: 32) {
                Look.draw(small, in: CGRect(x: x + 10, y: 790, width: 64, height: 64), context: context)
                Look.draw(tiny, in: CGRect(x: x + 94, y: 806, width: 32, height: 32), context: context)
            }
        }
        for (index, (label, note, image)) in wordmarks.enumerated() {
            let y = 920 + CGFloat(index) * 540
            context.setFillColor(Look.color(0xFFFFFF))
            context.addPath(Look.roundedRect(CGRect(x: 60, y: y, width: 1880, height: 500), radius: 24))
            context.fillPath()
            Look.draw(image, in: CGRect(x: 100, y: y + 30, width: 1480, height: 411), context: context)
            Look.draw(Look.line(label, font: Look.uiFont(40, bold: true), color: ink), at: CGPoint(x: 1600, y: y + 90), in: context)
            Look.draw(Look.line(note, font: Look.uiFont(24), color: soft), at: CGPoint(x: 1600, y: y + 132), in: context)
        }
        return context.makeImage()
    }
}
