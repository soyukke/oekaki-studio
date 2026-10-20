import CoreGraphics
import Foundation
import OekakiKit

/// The neck, the blouse with its round collar and bow, and the summer knit
/// over it, written in the body's frame: the same middle as the head's, leaning less.
enum Body {
    static let neckFar = "M -70 196 C -68 236, -68 266, -72 292"
    static let neckNear = "M 58 200 C 56 238, 56 266, 60 290"
    static let neck = "M -72 170 C -68 236, -68 266, -74 296 C -30 306, 30 304, 62 294 C 58 266, 56 236, 58 176 Z"
    static let shoulderFar = "M -74 292 C -120 300, -180 306, -230 322 C -280 340, -316 380, -332 440 C -342 500, -346 600, -348 720"
    static let shoulderNear = "M 62 290 C 110 298, 170 304, 220 318 C 268 334, 300 368, 318 420 C 330 470, 338 560, 342 720"
    static let knit = "M -74 292 C -120 300, -180 306, -230 322 C -280 340, -316 380, -332 440 C -342 500, -346 600, -348 760 L 346 760 C 338 560, 330 470, 318 420 C 300 368, 268 334, 220 318 C 170 304, 110 298, 62 290 Z"
    static let blouse = "M -130 312 C -116 380, -104 470, -98 760 L 80 760 C 86 470, 96 380, 108 308 C 50 290, -70 294, -130 312 Z"
    static let knitFar = "M -130 312 C -116 380, -104 470, -98 700"
    static let knitNear = "M 108 308 C 96 380, 86 470, 80 700"
    static let collarFar = "M -8 294 C -44 288, -92 288, -124 306 C -134 330, -120 354, -88 360 C -56 364, -24 350, -8 328 Z"
    static let collarNear = "M -8 294 C 26 288, 74 286, 104 302 C 114 326, 102 350, 72 356 C 40 360, 6 348, -8 328 Z"
    static let placket = "M -8 364 C -6 430, -6 520, -4 700"

    // The bow under the collar.
    static let bowLeft = "M -8 332 C -32 310, -70 312, -72 333 C -74 354, -36 356, -8 340 Z"
    static let bowRight = "M -8 332 C 16 310, 54 312, 56 333 C 58 354, 20 356, -8 340 Z"
    static let knot = "M -19 325 C -19 319, 3 319, 3 325 L 3 343 C 3 349, -19 349, -19 343 Z"
    static let tailLeft = "M -16 343 C -26 368, -34 392, -48 414 L -32 420 C -22 398, -12 372, -6 345 Z"
    static let tailRight = "M -1 345 C 5 370, 13 394, 26 414 L 41 406 C 27 386, 13 364, 5 343 Z"

    static var roughLines: [String] { [neckFar, neckNear, collarFar, collarNear, shoulderFar, shoulderNear, knitFar, knitNear] }

    static func lines(_ a: Artist, _ c: Bite.Colors) {
        let outline = Pen(width: 3, color: c.clothLine, start: 0.1, end: 0.1, floor: 0.3)
        let skin = Pen(width: 2.8, color: c.skinLine, start: 0.3, end: 0.1, floor: 0.3)
        a.line(neckFar, skin)
        a.line(neckNear, skin)
        a.line(shoulderFar, outline.with(width: 3.4, end: 0.3))
        a.line(shoulderNear, outline.with(width: 3.4, end: 0.3))
        a.line(knitFar, outline.with(width: 2.6, end: 0.4))
        a.line(knitNear, outline.with(width: 2.6, end: 0.4))
        a.line(placket, outline.with(width: 1.6, start: 0.2, end: 0.5))
        a.line(collarFar, outline)
        a.line(collarNear, outline)
        for path in [bowLeft, bowRight, tailLeft, tailRight, knot] {
            a.line(path, outline.with(width: 2.2))
        }
        // Folds in the bow's loops.
        a.line("M -24 334 C -38 328, -52 328, -60 334", outline.with(width: 1.4, start: 0.3, end: 0.5))
        a.line("M 8 334 C 22 328, 34 328, 44 334", outline.with(width: 1.4, start: 0.3, end: 0.5))
        // The knit's ribbing beside its edges.
        for offset in [14, 28] as [CGFloat] {
            a.line("M \(-130 - offset) \(316 + offset * 0.2) C \(-116 - offset) 384, \(-104 - offset) 474, \(-98 - offset) 700", outline.with(width: 1.2, start: 0.3, end: 0.3, opacity: 0.6))
            a.line("M \(108 + offset) \(312 + offset * 0.2) C \(96 + offset) 384, \(86 + offset) 474, \(80 + offset) 700", outline.with(width: 1.2, start: 0.3, end: 0.3, opacity: 0.6))
        }
    }

    static func flats(_ a: Artist, _ c: Bite.Colors) {
        a.shape(neck, c.skin)
        a.shape(knit, c.knit)
        a.shape(blouse, c.blouse)
        a.shape(collarFar, c.blouse)
        a.shape(collarNear, c.blouse)
        for path in [tailLeft, tailRight, bowLeft, bowRight, knot] { a.shape(path, c.ribbon) }
    }
}
