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
              let idx = activeLayerIndex, originalMoveBounds != nil else { return }

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
                self.layers[idx].buffer = clearedBuf
                self.layers[idx].markContentChanged()
                self.originalMoveBuffer = floatBuf
                self.floatingLayer = Layer(name: "_floating", buffer: floatBuf,
                                          offsetX: floatOX, offsetY: floatOY)
                // 抽出中にドラッグ・矢印キー操作が走っていた場合は即再ラスタライズ
                if !self.pendingTransform.isIdentity {
                    self.rasterizePreview()
                } else {
                    self.recomposite(includeMovePreview: !self.isDraggingTransform)
                }
            }
        }
    }

    /// ドラッグ終了・数値入力確定時：表示用の GPU 変形プレビューだけ更新する。
    /// PixelBuffer への焼き込みは commitMoveTransform() で一度だけ行う。
    func rasterizePreview() {
        guard originalMoveBuffer != nil, originalMoveBounds != nil else { return }
        recomposite(includeMovePreview: !isDraggingTransform)
    }

    /// 確定：floatingLayer をキャンバスクリップしてアクティブレイヤーに書き込む
    func commitMoveTransform() {
        guard originalMoveBounds != nil else { return }
        guard let fl = floatingLayer, let bounds = originalMoveBounds else {
            cleanupMoveTransform()
            beginMoveTransform()
            return
        }
        guard let idx = activeLayerIndex else {
            cleanupMoveTransform()
            beginMoveTransform()
            return
        }
        guard !layers[idx].locked else {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return
        }

        pushUndo("移動")

        // バックグラウンドに渡す値をキャプチャしてから、すぐに状態をクリア（二重コミット防止）
        let layerBuf    = layers[idx].buffer
        let layerOX     = layers[idx].offsetX
        let layerOY     = layers[idx].offsetY
        let moveBuf     = originalMoveBuffer ?? fl.buffer
        let cw = canvasWidth, ch = canvasHeight
        let sel = selection
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
            let result = PixelTransformEngine.pasted(source: transformed,
                                                     sourceOffsetX: sourceOffsetX,
                                                     sourceOffsetY: sourceOffsetY,
                                                     onto: layerBuf,
                                                     destinationOffsetX: layerOX,
                                                     destinationOffsetY: layerOY,
                                                     clipCanvasWidth: cw,
                                                     clipCanvasHeight: ch)
            let newSel = PixelTransformEngine.transformedSelection(sel, bounds: bounds,
                                                                   transform: t,
                                                                   canvasWidth: cw,
                                                                   canvasHeight: ch)

            await MainActor.run { [weak self, result, newSel] in
                guard let self else { return }
                self.layers[idx].buffer = result
                self.layers[idx].markContentChanged()
                self.selection = newSel
                self.recomposite()
                self.beginMoveTransform()  // 確定後も move ツールが継続できるよう即再初期化
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

    private func cleanupMoveTransform() {
        cancelRasterTasks()   // 飛行中の抽出・プレビュー・確定タスクを一括キャンセル
        floatingLayer = nil
        originalMoveBuffer = nil
        originalMoveBounds = nil
        pendingTransform = SelectionTransform()
    }

}
