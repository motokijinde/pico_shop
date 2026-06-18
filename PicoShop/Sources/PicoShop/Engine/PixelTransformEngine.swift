import CoreGraphics

enum PixelTransformEngine {
    static func transformed(buffer: PixelBuffer, transform t: SelectionTransform,
                            quality: ResampleQuality) -> PixelBuffer {
        guard !t.isIdentity else { return buffer }
        guard let src = buffer.makeCGImage() else { return buffer }

        let sourceRect = CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height)
        let center = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        var shapeTransform = t
        shapeTransform.dx = 0
        shapeTransform.dy = 0
        let affine = shapeTransform.affine(center: center)
        let corners = [
            CGPoint(x: sourceRect.minX, y: sourceRect.minY).applying(affine),
            CGPoint(x: sourceRect.maxX, y: sourceRect.minY).applying(affine),
            CGPoint(x: sourceRect.minX, y: sourceRect.maxY).applying(affine),
            CGPoint(x: sourceRect.maxX, y: sourceRect.maxY).applying(affine)
        ]
        let minX = corners.map(\.x).min() ?? 0
        let maxX = corners.map(\.x).max() ?? sourceRect.width
        let minY = corners.map(\.y).min() ?? 0
        let maxY = corners.map(\.y).max() ?? sourceRect.height
        let newW = max(1, Int((maxX - minX).rounded(.up)))
        let newH = max(1, Int((maxY - minY).rounded(.up)))

        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: PixelBuffer.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return buffer }
        ctx.interpolationQuality = quality.cgQuality
        ctx.concatenate(affine.concatenating(CGAffineTransform(translationX: -minX, y: -minY)))
        ctx.draw(src, in: sourceRect)

        guard let out = ctx.makeImage(), let result = PixelBuffer(cgImage: out) else { return buffer }
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

    static func pastedExpanding(source: PixelBuffer, sourceOffsetX: Int, sourceOffsetY: Int,
                                onto destination: PixelBuffer,
                                destinationOffsetX: Int, destinationOffsetY: Int)
        -> (buffer: PixelBuffer, offsetX: Int, offsetY: Int) {
        let destinationFrame = CGRect(x: destinationOffsetX, y: destinationOffsetY,
                                      width: destination.width, height: destination.height)
        let sourceFrame = CGRect(x: sourceOffsetX, y: sourceOffsetY,
                                 width: source.width, height: source.height)
        let frame = destinationFrame.union(sourceFrame).integral
        let newOffsetX = Int(frame.minX)
        let newOffsetY = Int(frame.minY)
        var expanded = PixelBuffer(width: max(1, Int(frame.width)),
                                   height: max(1, Int(frame.height)))

        for y in 0..<destination.height {
            for x in 0..<destination.width {
                copyPixel(from: destination, x: x, y: y,
                          to: &expanded,
                          x: x + destinationOffsetX - newOffsetX,
                          y: y + destinationOffsetY - newOffsetY)
            }
        }

        let pasted = pasted(source: source,
                            sourceOffsetX: sourceOffsetX,
                            sourceOffsetY: sourceOffsetY,
                            onto: expanded,
                            destinationOffsetX: newOffsetX,
                            destinationOffsetY: newOffsetY)
        return (pasted, newOffsetX, newOffsetY)
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
