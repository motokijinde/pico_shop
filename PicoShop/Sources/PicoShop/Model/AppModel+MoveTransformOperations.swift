import SwiftUI
import AppKit

extension AppModel {

    // MARK: ピクセル移動変形（move ツール）

    /// move ツール選択時：バウンズだけ記録してハンドルを表示（ロック中は何もしない）
    func beginMoveTransform() {
        guard floatingLayer == nil else { return }
        guard let idx = activeLayerIndex else { return }
        guard !layers[idx].locked else { return }
        let layer = layers[idx]
        moveLayerID = layer.id
        moveStartedWithSelection = selection != nil

        if let sel = selection, let b = sel.bounds() {
            originalMoveBounds = b
        } else {
            originalMoveBounds = CGRect(x: CGFloat(layer.offsetX), y: CGFloat(layer.offsetY),
                                        width: CGFloat(layer.buffer.width),
                                        height: CGFloat(layer.buffer.height))
        }
        pendingTransform = SelectionTransform()
    }

    /// ドラッグ開始時（遅延実行）：ピクセル抽出をバックグラウンドで行い floatingLayer をセット
    func extractMovePixels() {
        guard !isMoveExtracting, floatingLayer == nil,
              let moveLayerID,
              let idx = layers.firstIndex(where: { $0.id == moveLayerID }),
              originalMoveBounds != nil else { return }

        isMoveExtracting = true

        // スナップショットをメインスレッドで取得（値コピーなので安全）
        let snapshot  = layers[idx].buffer
        let offsetX   = layers[idx].offsetX
        let offsetY   = layers[idx].offsetY
        let sel       = self.selection

        let ver = beginRasterTaskVersion()

        Task.detached(priority: .userInitiated) { [snapshot, offsetX, offsetY, sel, weak self] in
            let floatBuf:   PixelBuffer
            let clearedBuf: PixelBuffer
            let floatOX:    Int
            let floatOY:    Int

            if let sel = sel, let b = sel.bounds() {
                // 選択あり：選択ピクセルを抽出、元バッファから選択部分のアルファをクリア
                let sw = max(1, Int(b.width)), sh = max(1, Int(b.height))
                var extracted = PixelBuffer(width: sw, height: sh)
                var cleared   = snapshot  // 値コピー（スレッドセーフ）
                for y in 0..<sh {
                    for x in 0..<sw {
                        let cx = Int(b.minX) + x, cy = Int(b.minY) + y
                        guard sel.isSelected(x: cx, y: cy) else { continue }
                        let lx = cx - offsetX, ly = cy - offsetY
                        guard lx >= 0, lx < snapshot.width,
                              ly >= 0, ly < snapshot.height else { continue }
                        let src = (ly * snapshot.width + lx) * 4
                        let dst = (y * sw + x) * 4
                        extracted.pixels[dst]     = snapshot.pixels[src]
                        extracted.pixels[dst + 1] = snapshot.pixels[src + 1]
                        extracted.pixels[dst + 2] = snapshot.pixels[src + 2]
                        extracted.pixels[dst + 3] = snapshot.pixels[src + 3]
                        cleared.pixels[src]       = 0
                        cleared.pixels[src + 1]   = 0
                        cleared.pixels[src + 2]   = 0
                        cleared.pixels[src + 3]   = 0
                    }
                }
                floatBuf   = extracted
                clearedBuf = cleared
                floatOX    = Int(b.minX.rounded())
                floatOY    = Int(b.minY.rounded())
            } else {
                // 選択なし：スナップショットをそのまま使い、空バッファで元レイヤーをクリア
                floatBuf   = snapshot
                clearedBuf = PixelBuffer(width: snapshot.width, height: snapshot.height)
                floatOX    = offsetX
                floatOY    = offsetY
            }

            await MainActor.run { [weak self, floatBuf, clearedBuf, floatOX, floatOY] in
                guard let self, self.isCurrentRasterTask(ver) else {
                    self?.isMoveExtracting = false
                    return
                }
                self.isMoveExtracting = false
                self.pushUndo("移動")
                self.layers[idx].buffer = clearedBuf
                self.layers[idx].markContentChanged()
                self.originalMoveBuffer = floatBuf
                self.floatingLayer = Layer(name: "_floating", buffer: floatBuf,
                                          offsetX: floatOX, offsetY: floatOY)
                // 抽出中にドラッグ・矢印キー操作が走っていた場合は即再ラスタライズ
                if !self.pendingTransform.isIdentity {
                    self.rasterizePreview()
                } else {
                    self.recomposite()
                }
            }
        }
    }

    /// ドラッグ終了・数値入力確定時：表示用の GPU 変形プレビューだけ更新する。
    /// PixelBuffer への焼き込みは commitMoveTransform() で一度だけ行う。
    func rasterizePreview() {
        guard originalMoveBuffer != nil, originalMoveBounds != nil else { return }
        recomposite()
    }

    /// 確定：floatingLayer をキャンバスクリップして移動開始時のレイヤーに書き込む
    func commitMoveTransform(completion: (() -> Void)? = nil) {
        guard originalMoveBounds != nil else { return }
        guard let fl = floatingLayer, let bounds = originalMoveBounds else {
            cleanupMoveTransform()
            if tool == .move { beginMoveTransform() }
            completion?()
            return
        }
        guard let moveLayerID,
              let idx = layers.firstIndex(where: { $0.id == moveLayerID }) else {
            cleanupMoveTransform()
            if tool == .move { beginMoveTransform() }
            completion?()
            return
        }
        guard !layers[idx].locked else {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return
        }

        // バックグラウンドに渡す値をキャプチャしてから、すぐに状態をクリア（二重コミット防止）
        let layerBuf    = layers[idx].buffer
        let layerOX     = layers[idx].offsetX
        let layerOY     = layers[idx].offsetY
        let moveBuf     = originalMoveBuffer ?? fl.buffer
        let targetLayerID = moveLayerID
        let cw = canvasWidth, ch = canvasHeight
        let sel = selection
        let preservesSelection = moveStartedWithSelection
        let t   = pendingTransform
        let q   = resizeOpts.quality
        cleanupMoveTransform()
        // bounds は確定前にキャプチャ・検証済みのため、beginMoveTransform のガードをバイパスして直接復元
        originalMoveBounds = bounds

        Task.detached(priority: .userInitiated) { [layerBuf, moveBuf, weak self] in
            let transformed = PixelTransformEngine.transformed(buffer: moveBuf, transform: t, quality: q)
            let midX = bounds.midX + t.dx
            let midY = bounds.midY + t.dy
            let sourceOffsetX = Int((midX - Double(transformed.width) / 2).rounded())
            let sourceOffsetY = Int((midY - Double(transformed.height) / 2).rounded())
            let result: PixelBuffer
            let resultOffsetX: Int
            let resultOffsetY: Int
            if preservesSelection {
                let pasted = PixelTransformEngine.pastedExpanding(source: transformed,
                                                                  sourceOffsetX: sourceOffsetX,
                                                                  sourceOffsetY: sourceOffsetY,
                                                                  onto: layerBuf,
                                                                  destinationOffsetX: layerOX,
                                                                  destinationOffsetY: layerOY)
                result = pasted.buffer
                resultOffsetX = pasted.offsetX
                resultOffsetY = pasted.offsetY
            } else {
                result = transformed
                resultOffsetX = sourceOffsetX
                resultOffsetY = sourceOffsetY
            }
            let newSel = preservesSelection
                ? PixelTransformEngine.transformedSelection(sel, bounds: bounds,
                                                            transform: t,
                                                            canvasWidth: cw,
                                                            canvasHeight: ch)
                : nil

            await MainActor.run { [weak self, targetLayerID, result, resultOffsetX, resultOffsetY, newSel] in
                guard let self,
                      let targetIndex = self.layers.firstIndex(where: { $0.id == targetLayerID }) else { return }
                self.layers[targetIndex].buffer = result
                self.layers[targetIndex].offsetX = resultOffsetX
                self.layers[targetIndex].offsetY = resultOffsetY
                self.layers[targetIndex].markContentChanged()
                self.selection = newSel
                self.recomposite()
                if self.tool == .move {
                    self.beginMoveTransform()  // 確定後も move ツールが継続できるよう即再初期化
                }
                completion?()
            }
        }
    }

    /// リセット：originalMoveBuffer から floatingLayer を復元、pendingTransform をクリア
    func resetMoveTransform() {
        guard let orig = originalMoveBuffer, let bounds = originalMoveBounds else { return }
        floatingLayer = Layer(name: "_floating", buffer: orig,
                              offsetX: Int(bounds.minX.rounded()),
                              offsetY: Int(bounds.minY.rounded()))
        pendingTransform = SelectionTransform()
        recomposite()
    }

    func refreshMoveTransformTargetForSelectionChange() {
        guard tool == .move else { return }
        guard floatingLayer == nil else {
            commitMoveTransform { [weak self] in
                self?.refreshMoveTransformTargetForSelectionChange()
            }
            return
        }
        cleanupMoveTransform()
        beginMoveTransform()
        recomposite()
    }

    func refreshMoveTransformTargetForLayerChange() {
        guard tool == .move else { return }
        guard floatingLayer == nil else {
            commitMoveTransform()
            return
        }
        cleanupMoveTransform()
        beginMoveTransform()
        recomposite()
    }

    func commitMoveTransformIfNeeded(then action: @escaping () -> Void) {
        guard tool == .move, floatingLayer != nil else {
            action()
            return
        }
        commitMoveTransform(completion: action)
    }

    private func cleanupMoveTransform() {
        cancelRasterTasks()   // 飛行中の抽出・プレビュー・確定タスクを一括キャンセル
        isMoveExtracting = false
        floatingLayer = nil
        moveLayerID = nil
        moveStartedWithSelection = false
        originalMoveBuffer = nil
        originalMoveBounds = nil
        pendingTransform = SelectionTransform()
    }

}
