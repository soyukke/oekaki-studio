import COekakiCore
import CoreGraphics
import Foundation

/// Working memory for the paint bucket, kept between fills so a fill does not
/// allocate. Sized for one canvas.
final class FillScratch {
    let pixelCount: Int
    let wall: UnsafeMutablePointer<UInt8>
    let thick: UnsafeMutablePointer<UInt8>
    let tmp: UnsafeMutablePointer<UInt8>
    let interior: UnsafeMutablePointer<UInt8>
    let full: UnsafeMutablePointer<UInt8>
    let stack: UnsafeMutablePointer<Int32>

    init(width: Int, height: Int) {
        pixelCount = width * height
        wall = .allocate(capacity: pixelCount)
        thick = .allocate(capacity: pixelCount)
        tmp = .allocate(capacity: pixelCount)
        interior = .allocate(capacity: pixelCount)
        full = .allocate(capacity: pixelCount)
        stack = .allocate(capacity: pixelCount)
    }

    deinit {
        wall.deallocate()
        thick.deallocate()
        tmp.deallocate()
        interior.deallocate()
        full.deallocate()
        stack.deallocate()
    }
}

public enum BucketFill {
    /// How far a pixel's colour may differ from the clicked pixel and still
    /// count as the same area, per channel out of 255.
    static let defaultTolerance = 48
    /// Openings in an outline up to about twice this many pixels are closed.
    public static let defaultGap = 3

    /// Fills from `seed` on an opaque RGBA picture and returns the masks,
    /// cropped to the area touched. Returns nil when nothing was filled.
    static func run(
        picture: CGContext, seed: CGPoint, color: RGBA,
        tolerance: Int = defaultTolerance, gap: Int = defaultGap, scratch: FillScratch
    ) -> FillItem? {
        let width = picture.width
        let height = picture.height
        precondition(width * height == scratch.pixelCount, "Scratch buffers are for a different canvas size")
        precondition(picture.bytesPerRow == width * 4, "The picture must be tightly packed RGBA")
        guard let data = picture.data else { return nil }

        var bbox = [Int32](repeating: 0, count: 4)
        let count = core_bucket_fill(
            data.assumingMemoryBound(to: UInt8.self), Int32(width), Int32(height),
            Int32(seed.x.rounded(.down)), Int32(seed.y.rounded(.down)), Int32(tolerance), Int32(gap),
            scratch.wall, scratch.thick, scratch.tmp, scratch.interior, scratch.full,
            scratch.stack, &bbox
        )
        guard count > 0, bbox[2] >= bbox[0], bbox[3] >= bbox[1] else { return nil }

        let minX = Int(bbox[0])
        let minY = Int(bbox[1])
        let cropWidth = Int(bbox[2]) - minX + 1
        let cropHeight = Int(bbox[3]) - minY + 1
        func crop(_ mask: UnsafeMutablePointer<UInt8>) -> Data {
            var bytes = Data(count: cropWidth * cropHeight)
            bytes.withUnsafeMutableBytes { raw in
                let target = raw.bindMemory(to: UInt8.self).baseAddress!
                for row in 0..<cropHeight {
                    (target + row * cropWidth).update(from: mask + (minY + row) * width + minX, count: cropWidth)
                }
            }
            return bytes
        }
        guard
            let full = Raster.maskImage(bytes: crop(scratch.full), width: cropWidth, height: cropHeight),
            let interior = Raster.maskImage(bytes: crop(scratch.interior), width: cropWidth, height: cropHeight)
        else { return nil }
        let rect = CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)
        return FillItem(rect: rect, full: full, interior: interior, color: color)
    }
}
