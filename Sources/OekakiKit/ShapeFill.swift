import CoreGraphics
import Foundation

/// The lasso fill: paint inside a closed outline that is not on the canvas,
/// with soft edges, for shapes of shadow and light that have no lines.
public enum ShapeFill {
    /// The fill for the area `outline` goes round, kept inside the canvas.
    /// Returns nil when the outline encloses nothing on it.
    static func make(_ outline: [CGPoint], color: RGBA, canvas: CGRect) -> FillItem? {
        guard outline.count >= 3 else { return nil }
        let path = CGMutablePath()
        path.addLines(between: outline)
        path.closeSubpath()
        // A pixel of room round the shape for its soft edge.
        let area = path.boundingBoxOfPath.insetBy(dx: -1, dy: -1).integral.intersection(canvas)
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        let width = Int(area.width), height = Int(area.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // Canvas coordinates, with y down, shifted to the area: the first row is the top.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -area.minX, y: -area.minY)
        context.setShouldAntialias(true)
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path)
        context.fillPath()
        guard let data = context.data else { return nil }
        let bytes = Data(bytes: data, count: width * height)
        guard bytes.contains(where: { $0 > 0 }), let mask = Raster.maskImage(bytes: bytes, width: width, height: height) else { return nil }
        return FillItem(rect: area, full: mask, interior: mask, color: color)
    }
}

extension CanvasDocument {
    /// Paints the area a closed outline goes round on the active layer, with
    /// soft edges and no lines: the lasso fill. Unlike the paint bucket it
    /// needs no lines, so it suits shapes of shadow and light. Returns false
    /// when the outline encloses nothing on the canvas.
    @discardableResult
    public func fillShape(_ outline: [CGPoint], color: RGBA) -> Bool {
        guard !isDrawing, let index = layers.firstIndex(where: { $0.id == activeLayerID }), layers[index].isVisible,
              let item = ShapeFill.make(outline, color: color, canvas: bounds)
        else { return false }
        pushUndo()
        appendItem(.fill(item), toLayerAt: index, alreadyDrawn: false)
        invalidate(item.rect)
        return true
    }
}
