import CoreGraphics

enum PixelTransformEngine {
    static func transformed(buffer: PixelBuffer, transform t: SelectionTransform,
                            quality: ResampleQuality) -> PixelBuffer {
        var result = buffer
        if t.rotation != 0 {
            let (rotated, _, _) = result.cpuRotated(byDegrees: t.rotation, quality: quality)
            result = rotated
        }
        if abs(t.scaleX - 1) > 0.001 || abs(t.scaleY - 1) > 0.001 {
            let width = max(1, Int((Double(result.width) * abs(t.scaleX)).rounded()))
            let height = max(1, Int((Double(result.height) * abs(t.scaleY)).rounded()))
            result = result.cpuResized(width: width, height: height, quality: quality)
        }
        return result
    }

    static func extractSelection(from layer: Layer, selection: SelectionMask, bounds b: CGRect) -> PixelBuffer {
        let width = max(1, Int(b.width))
        let height = max(1, Int(b.height))
        var extracted = PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let cx = Int(b.minX) + x
                let cy = Int(b.minY) + y
                guard selection.isSelected(x: cx, y: cy) else { continue }
                let lx = cx - layer.offsetX
                let ly = cy - layer.offsetY
                guard lx >= 0, lx < layer.buffer.width,
                      ly >= 0, ly < layer.buffer.height else { continue }
                copyPixel(from: layer.buffer, x: lx, y: ly, to: &extracted, x: x, y: y)
            }
        }
        return extracted
    }

    static func clearingSelection(in buffer: PixelBuffer, layerOffsetX: Int, layerOffsetY: Int,
                                  selection: SelectionMask, bounds b: CGRect) -> PixelBuffer {
        let width = max(1, Int(b.width))
        let height = max(1, Int(b.height))
        var cleared = buffer
        for y in 0..<height {
            for x in 0..<width {
                let cx = Int(b.minX) + x
                let cy = Int(b.minY) + y
                guard selection.isSelected(x: cx, y: cy) else { continue }
                let lx = cx - layerOffsetX
                let ly = cy - layerOffsetY
                guard lx >= 0, lx < cleared.width,
                      ly >= 0, ly < cleared.height else { continue }
                let i = (ly * cleared.width + lx) * 4
                cleared.pixels[i] = 0
                cleared.pixels[i + 1] = 0
                cleared.pixels[i + 2] = 0
                cleared.pixels[i + 3] = 0
            }
        }
        return cleared
    }

    static func pasted(source: PixelBuffer, sourceOffsetX: Int, sourceOffsetY: Int,
                       onto destination: PixelBuffer, destinationOffsetX: Int, destinationOffsetY: Int,
                       clipCanvasWidth: Int? = nil, clipCanvasHeight: Int? = nil) -> PixelBuffer {
        var result = destination
        for y in 0..<source.height {
            for x in 0..<source.width {
                guard source.pixels[(y * source.width + x) * 4 + 3] > 0 else { continue }
                let cx = x + sourceOffsetX
                let cy = y + sourceOffsetY
                if let clipCanvasWidth, let clipCanvasHeight {
                    guard cx >= 0, cx < clipCanvasWidth, cy >= 0, cy < clipCanvasHeight else { continue }
                }
                let lx = cx - destinationOffsetX
                let ly = cy - destinationOffsetY
                guard lx >= 0, lx < destination.width,
                      ly >= 0, ly < destination.height else { continue }
                copyPixel(from: source, x: x, y: y, to: &result, x: lx, y: ly)
            }
        }
        return result
    }

    static func transformedSelection(_ selection: SelectionMask?, bounds: CGRect,
                                     transform t: SelectionTransform,
                                     canvasWidth: Int, canvasHeight: Int) -> SelectionMask {
        let base = selection ?? SelectionMask.rect(width: canvasWidth, height: canvasHeight, rect: bounds)
        return base.transformed(dx: t.dx, dy: t.dy,
                                scaleX: t.scaleX, scaleY: t.scaleY,
                                rotationDegrees: t.rotation,
                                center: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private static func copyPixel(from source: PixelBuffer, x sx: Int, y sy: Int,
                                  to destination: inout PixelBuffer, x dx: Int, y dy: Int) {
        let src = (sy * source.width + sx) * 4
        let dst = (dy * destination.width + dx) * 4
        destination.pixels[dst] = source.pixels[src]
        destination.pixels[dst + 1] = source.pixels[src + 1]
        destination.pixels[dst + 2] = source.pixels[src + 2]
        destination.pixels[dst + 3] = source.pixels[src + 3]
    }
}
