import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppModel {

    // MARK: ピクセル変形（transform ツール）

    /// pendingTransform を選択内ピクセルまたはレイヤー全体に適用
    func applyPixelTransform() {
        guard !pendingTransform.isIdentity else { return }
        guard let idx = activeLayerIndex else { return }
        guard !layers[idx].locked else {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return
        }

        if let sel = selection, let b = sel.bounds() {
            let layer = layers[idx]
            let srcBuf = PixelTransformEngine.extractSelection(from: layer, selection: sel, bounds: b)

            pushUndo("変形")
            let ok = withActiveLayer { l in
                let cleared = PixelTransformEngine.clearingSelection(in: l.buffer,
                                                                     layerOffsetX: l.offsetX,
                                                                     layerOffsetY: l.offsetY,
                                                                     selection: sel,
                                                                     bounds: b)
                let transformedBuf = PixelTransformEngine.transformed(buffer: srcBuf,
                                                                      transform: pendingTransform,
                                                                      quality: resizeOpts.quality)
                let destCX = b.midX + CGFloat(pendingTransform.dx)
                let destCY = b.midY + CGFloat(pendingTransform.dy)
                let destOX = Int(destCX - CGFloat(transformedBuf.width) / 2)
                let destOY = Int(destCY - CGFloat(transformedBuf.height) / 2)
                l.buffer = PixelTransformEngine.pasted(source: transformedBuf,
                                                       sourceOffsetX: destOX,
                                                       sourceOffsetY: destOY,
                                                       onto: cleared,
                                                       destinationOffsetX: l.offsetX,
                                                       destinationOffsetY: l.offsetY)
                l.markContentChanged()
            }
            if ok {
                selection = nil
                pendingTransform = SelectionTransform()
                recomposite()
            } else {
                discardLastUndo()
            }

        } else {
            // レイヤー全体を変形
            pushUndo("変形")
            let q = resizeOpts.quality

            if pendingTransform.rotation != 0 {
                let (rotated, rdx, rdy) = layers[idx].buffer.cpuRotated(byDegrees: pendingTransform.rotation, quality: q)
                layers[idx].buffer = rotated
                layers[idx].offsetX += rdx
                layers[idx].offsetY += rdy
                layers[idx].markContentChanged()
            }

            if abs(pendingTransform.scaleX - 1) > 0.001 || abs(pendingTransform.scaleY - 1) > 0.001 {
                let buf = layers[idx].buffer
                let nw = max(1, Int((Double(buf.width) * abs(pendingTransform.scaleX)).rounded()))
                let nh = max(1, Int((Double(buf.height) * abs(pendingTransform.scaleY)).rounded()))
                layers[idx].buffer = buf.cpuResized(width: nw, height: nh, quality: q)
                layers[idx].markContentChanged()
            }

            if pendingTransform.dx != 0 || pendingTransform.dy != 0 {
                layers[idx].offsetX += Int(pendingTransform.dx.rounded())
                layers[idx].offsetY += Int(pendingTransform.dy.rounded())
            }

            pendingTransform = SelectionTransform()
            recomposite()
        }
    }

}
