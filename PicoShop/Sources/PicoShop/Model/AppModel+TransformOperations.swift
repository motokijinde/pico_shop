import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppModel {

    // MARK: ピクセル変形（transform ツール）

    func commitSynchronousTransformIfNeeded() {
        switch tool {
        case .selectionTransform:
            applySelectionTransform()
        case .transform:
            applyPixelTransform(preservesSelection: true)
        default:
            break
        }
    }

    @discardableResult
    func commitPendingPixelTransformIfNeeded(preservesSelection: Bool) -> Bool {
        guard tool != .selectionTransform,
              tool != .move,
              !pendingTransform.isIdentity else { return true }
        guard let idx = activeLayerIndex else { return false }
        guard !layers[idx].locked else {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return false
        }
        applyPixelTransform(preservesSelection: preservesSelection)
        return pendingTransform.isIdentity
    }

    /// pendingTransform を選択内ピクセルまたはレイヤー全体に適用
    func applyPixelTransform(preservesSelection: Bool = false) {
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
            let newSelection = PixelTransformEngine.transformedSelection(sel, bounds: b,
                                                                          transform: pendingTransform,
                                                                          canvasWidth: canvasWidth,
                                                                          canvasHeight: canvasHeight)

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
                let pasted = PixelTransformEngine.pastedExpanding(source: transformedBuf,
                                                                  sourceOffsetX: destOX,
                                                                  sourceOffsetY: destOY,
                                                                  onto: cleared,
                                                                  destinationOffsetX: l.offsetX,
                                                                  destinationOffsetY: l.offsetY)
                l.buffer = pasted.buffer
                l.offsetX = pasted.offsetX
                l.offsetY = pasted.offsetY
                l.markContentChanged()
            }
            if ok {
                selection = preservesSelection && !newSelection.isEmpty ? newSelection : nil
                pendingTransform = SelectionTransform()
                recomposite()
            } else {
                discardLastUndo()
            }

        } else {
            // レイヤー全体を変形
            pushUndo("変形")
            let q = resizeOpts.quality

            let originalFrame = layers[idx].frame
            let transformed = PixelTransformEngine.transformed(buffer: layers[idx].buffer,
                                                               transform: pendingTransform,
                                                               quality: q)
            let centerX = originalFrame.midX + CGFloat(pendingTransform.dx)
            let centerY = originalFrame.midY + CGFloat(pendingTransform.dy)
            layers[idx].buffer = transformed
            layers[idx].offsetX = Int((centerX - CGFloat(transformed.width) / 2).rounded())
            layers[idx].offsetY = Int((centerY - CGFloat(transformed.height) / 2).rounded())
            layers[idx].markContentChanged()

            pendingTransform = SelectionTransform()
            recomposite()
        }
    }

}
