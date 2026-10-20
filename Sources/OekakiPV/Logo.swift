import CoreGraphics
import Foundation
import OekakiKit

/// The Oekaki Studio mark, drawn in Oekaki Studio: a drop of paint held in
/// a pair of brush-drawn braces. Code around a picture.
enum Logo {
    static let size = 1024

    enum Colors {
        static let paper = RGBA(hex: 0xFFFBF5)
        static let paperLow = RGBA(hex: 0xFFE7D2)
        /// Dark enough against white for the fill to stop at it.
        static let edge = RGBA(hex: 0xEBC9AE)
        static let ink = RGBA(hex: 0x2B2A4C)
        static let dropTop = RGBA(hex: 0xFFB45A)
        static let dropBottom = RGBA(hex: 0xFF4F6E)
        static let dropShade = RGBA(hex: 0xC2569A)
        static let dropLight = RGBA(hex: 0xFFF2C8)
        static let white = RGBA(hex: 0xFFFFFF)
        static let glow = RGBA(hex: 0xFFC27A)
        static let accent = RGBA(hex: 0x2FB9B3)
    }

    /// The tile behind the mark, with the corners of a macOS app icon.
    static let tile = "M 290 100 L 734 100 Q 924 100, 924 290 L 924 734 Q 924 924, 734 924 L 290 924 Q 100 924, 100 734 L 100 290 Q 100 100, 290 100"
    /// The drop: pointed at the top, round at the bottom.
    static let drop = "M 512 336 C 542 400, 628 464, 628 568 C 628 636, 576 686, 512 686 C 448 686, 396 636, 396 568 C 396 464, 482 400, 512 336"

    enum Mark: String, CaseIterable {
        /// A drop of paint held in braces.
        case braces
        /// A brush stroke that ends in a text cursor.
        case cursor
        /// The kana お written with a brush, its dot a drop of paint.
        case kana
        /// The code sign </>, its slash a brush stroke.
        case tag
    }

    static func draw(_ mark: Mark = .braces) -> (document: CanvasDocument, problems: [String]) {
        let document = CanvasDocument(width: size, height: size)
        let a = Artist(document: document)
        document.renameLayer(document.activeLayerID, to: "下地")
        tile(a)
        switch mark {
        case .braces: braces(a)
        case .cursor: cursor(a)
        case .kana: kana(a)
        case .tag: tag(a)
        }
        document.flushJournal()
        return (document, a.problems)
    }

    static func tile(_ a: Artist) {
        // The tile: an outline in its own colour, filled, then a warm light over it.
        a.line(tile, Pen(width: 4, color: Colors.edge, start: 0, end: 0, floor: 1))
        a.fill("下地", 512, 512, Colors.paper, gap: 1)
        a.layer("下地の光", style: LayerStyle(isClipped: true))
        a.gradient(.linear, from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924), clear(Colors.paperLow), Colors.paperLow)
        a.gradient(.radial, from: CGPoint(x: 300, y: 260), to: CGPoint(x: 820, y: 260), Colors.white, clear(Colors.white))
    }

    static let brush = Pen(width: 54, color: Colors.ink, start: 0.25, end: 0.45, floor: 0.12)

    static func braces(_ a: Artist) {
        // The braces, each drawn as two strokes that meet in the point.
        a.layer("括弧")
        for side: CGFloat in [-1, 1] {
            func x(_ value: CGFloat) -> CGFloat { side < 0 ? value : 1024 - value }
            a.line("M \(x(352)) 266 C \(x(290)) 268, \(x(300)) 318, \(x(300)) 380 L \(x(300)) 444 C \(x(300)) 486, \(x(282)) 506, \(x(232)) 512", brush)
            a.line("M \(x(352)) 758 C \(x(290)) 756, \(x(300)) 706, \(x(300)) 644 L \(x(300)) 580 C \(x(300)) 538, \(x(282)) 518, \(x(232)) 512", brush)
        }

        paintDrop(a, at: CGPoint(x: 512, y: 512), scale: 1)
        a.layer("きらめき")
        a.line("M 636 340 L 636 420", Pen(width: 12, color: Colors.accent, start: 0.5, end: 0.5, floor: 0.05))
        a.line("M 596 380 L 676 380", Pen(width: 12, color: Colors.accent, start: 0.5, end: 0.5, floor: 0.05))
    }

    /// A drop of paint centred on `center`: its shape, then colour, shade
    /// and light clipped to it, then its shine.
    static func paintDrop(_ a: Artist, at center: CGPoint, scale: CGFloat) {
        let saved = a.transform
        a.transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale).translatedBy(x: -512, y: -512)
        a.layer("しずく")
        a.line(drop, Pen(width: 3 / scale, color: Colors.dropBottom, start: 0, end: 0, floor: 1))
        a.fill("しずく", 512, 560, Colors.dropTop, gap: 1)
        a.layer("しずくの色", style: LayerStyle(isClipped: true))
        a.gradient(.linear, from: CGPoint(x: 470, y: 380), to: CGPoint(x: 560, y: 680), Colors.dropTop, Colors.dropBottom)
        a.layer("しずくの影", style: LayerStyle(blend: .multiply, isClipped: true))
        a.line("M 604 520 C 616 590, 590 650, 510 676", .airbrush(90 * scale, Colors.dropShade, opacity: 0.45))
        a.layer("しずくの光", style: LayerStyle(blend: .screen, isClipped: true))
        a.line("M 450 520 C 440 580, 460 620, 500 640", .airbrush(90 * scale, Colors.dropLight, opacity: 0.5))
        a.layer("ハイライト")
        a.line("M 452 548 C 452 506, 470 470, 492 446", Pen(width: 22 * scale, color: Colors.white, start: 0.4, end: 0.5, floor: 0.1, opacity: 0.9))
        a.dot(470, 600, diameter: 16 * scale, color: Colors.white)
        a.transform = saved
    }

    /// The drop alone on a clear canvas, cropped to it.
    static func dropOnly() -> CGImage? {
        let document = CanvasDocument(width: size, height: size)
        paintDrop(Artist(document: document), at: CGPoint(x: 512, y: 512), scale: 1)
        return document.compositeImage(background: nil)?.cropping(to: CGRect(x: 390, y: 330, width: 244, height: 362))
    }

    /// A warm brush stroke sweeping into a text cursor: drawing is typing.
    static func cursor(_ a: Artist) {
        a.layer("筆")
        a.line("M 226 676 C 300 690, 400 640, 480 560 C 550 490, 610 440, 676 420",
               Pen(width: 100, color: Colors.dropBottom, start: 0.3, end: 0.6, floor: 0.06))
        a.layer("筆の色", style: LayerStyle(isClipped: true))
        a.gradient(.linear, from: CGPoint(x: 226, y: 676), to: CGPoint(x: 676, y: 420), Colors.dropTop, Colors.dropBottom)
        a.layer("筆の光", style: LayerStyle(blend: .screen, isClipped: true))
        a.line("M 300 664 C 370 664, 430 620, 500 552", Pen(width: 14, color: Colors.dropLight, start: 0.4, end: 0.5, floor: 0.05, opacity: 0.8))
        a.layer("カーソル")
        a.line("M 732 330 L 732 694", Pen(width: 34, color: Colors.ink, start: 0, end: 0, floor: 1))
        a.line("M 690 330 L 774 330", Pen(width: 20, color: Colors.ink, start: 0, end: 0, floor: 1))
        a.line("M 690 694 L 774 694", Pen(width: 20, color: Colors.ink, start: 0, end: 0, floor: 1))
    }

    /// お written in three strokes; the third, its dot, is a drop of paint.
    static func kana(_ a: Artist) {
        a.layer("お")
        let pen = brush.with(width: 50)
        a.line("M 262 404 C 330 396, 410 390, 486 384", pen.with(start: 0.2, end: 0.5))
        a.line("M 388 268 C 394 400, 398 540, 392 676 C 388 720, 352 726, 330 700 C 300 664, 342 600, 432 576 C 540 548, 650 590, 640 666 C 632 726, 560 752, 500 744",
               pen.with(start: 0.1, end: 0.35))
        paintDrop(a, at: CGPoint(x: 690, y: 400), scale: 0.36)
    }

    /// </> with a brush stroke for its slash.
    static func tag(_ a: Artist) {
        a.layer("記号")
        let pen = brush.with(width: 58, start: 0.15, end: 0.15, floor: 0.4)
        a.line("M 360 356 L 214 512 L 360 668", pen)
        a.line("M 664 356 L 810 512 L 664 668", pen)
        a.layer("筆")
        a.line("M 590 300 C 560 420, 500 580, 438 724", Pen(width: 88, color: Colors.dropBottom, start: 0.1, end: 0.6, floor: 0.06))
        a.layer("筆の色", style: LayerStyle(isClipped: true))
        a.gradient(.linear, from: CGPoint(x: 590, y: 300), to: CGPoint(x: 438, y: 724), Colors.dropTop, Colors.dropBottom)
        a.layer("筆の光", style: LayerStyle(blend: .screen, isClipped: true))
        a.line("M 566 340 C 548 420, 520 500, 494 560", Pen(width: 12, color: Colors.dropLight, start: 0.4, end: 0.5, floor: 0.05, opacity: 0.8))
    }

    private static func clear(_ color: RGBA) -> RGBA {
        var faded = color
        faded.a = 0
        return faded
    }
}
