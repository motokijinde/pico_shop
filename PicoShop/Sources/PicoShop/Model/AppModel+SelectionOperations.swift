import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppModel {

    // MARK: 選択操作

    func setSelection(_ mask: SelectionMask?, label: String) {
        pushUndo(label)
        selection = (mask?.isEmpty ?? true) ? nil : mask
        pendingTransform = SelectionTransform()
        refreshMoveTransformTargetForSelectionChange()
    }

    /// selectionOperationMode に従って選択を適用（新規/追加/除外）
    func applySelection(_ mask: SelectionMask, label: String) {
        let result: SelectionMask
        switch selectionOperationMode {
        case .replace:
            result = mask
        case .add:
            result = (selection ?? SelectionMask(width: mask.width, height: mask.height)).union(mask)
        case .subtract:
            guard let existing = selection else { return }
            result = existing.subtracting(mask)
        }
        setSelection(result, label: label)
    }

    func selectAll() {
        guard let layer = activeLayer else {
            warn("レイヤーが選択されていません")
            return
        }
        setSelection(
            .rect(width: canvasWidth, height: canvasHeight, rect: layer.frame),
            label: "すべてを選択"
        )
    }

    func invertSelection() {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        setSelection(sel.inverted(), label: "選択を反転")
    }

    func clearSelection() {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.clearSelection()
            }
            return
        }
        guard selection != nil else {
            refreshMoveTransformTargetForSelectionChange()
            return
        }
        pushUndo("選択をクリア")
        selection = nil
        pendingTransform = SelectionTransform()
        refreshMoveTransformTargetForSelectionChange()
    }

    func growSelection(by px: Int) {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        lastGrowShrinkAmount = px
        setSelection(sel.grown(by: px), label: "選択範囲を拡大")
    }

    func shrinkSelection(by px: Int) {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        lastGrowShrinkAmount = px
        setSelection(sel.shrunk(by: px), label: "選択範囲を縮小")
    }

    // MARK: 選択範囲の変形

    /// 保留中の変形を適用してマスクを再ラスタライズ。
    /// selectionTransform ツールで selection == nil のときはレイヤー全体を選択してから変形する。
    func applySelectionTransform() {
        if selection == nil, tool == .selectionTransform, let layer = activeLayer {
            selection = .rect(width: canvasWidth, height: canvasHeight,
                              rect: CGRect(x: layer.offsetX, y: layer.offsetY,
                                           width: layer.buffer.width, height: layer.buffer.height))
        }
        guard let sel = selection, let b = sel.bounds(), !pendingTransform.isIdentity else { return }
        pushUndo("選択範囲の変形")
        selection = sel.transformed(
            dx: pendingTransform.dx, dy: pendingTransform.dy,
            scaleX: pendingTransform.scaleX, scaleY: pendingTransform.scaleY,
            rotationDegrees: pendingTransform.rotation,
            center: CGPoint(x: b.midX, y: b.midY)
        )
        pendingTransform = SelectionTransform()
        if selection?.isEmpty ?? true {
            selection = nil
            warn("変形の結果、選択範囲が空になりました")
        }
    }

    func resetSelectionTransform() {
        pendingTransform = SelectionTransform()
    }

    // MARK: 色域選択

    /// キャンバス座標 p のアクティブレイヤーピクセルを基準色としてflood fill選択を実行
    func applyColorRangeSelection(atCanvas p: CGPoint) {
        guard let layer = activeLayer else {
            warn("レイヤーが選択されていません")
            return
        }
        let lx = Int(p.x.rounded(.down)) - layer.offsetX
        let ly = Int(p.y.rounded(.down)) - layer.offsetY
        guard lx >= 0, lx < layer.buffer.width,
              ly >= 0, ly < layer.buffer.height else { return }

        let w = layer.buffer.width, h = layer.buffer.height
        let ox = layer.offsetX, oy = layer.offsetY
        let cw = canvasWidth, ch = canvasHeight
        let opts = colorRangeOpts

        var mask = ColorRangeEngine.floodFill(
            pixels: layer.buffer.pixels, width: w, height: h,
            startX: lx, startY: ly,
            tolerance: Int(opts.level),
            contiguous: opts.contiguous
        )

        let adj = Int(opts.boundaryAdjust.rounded())
        if adj != 0 {
            ColorRangeEngine.adjustBoundary(mask: &mask, width: w, height: h, amount: -adj)
        }

        var canvasData = [UInt8](repeating: 0, count: cw * ch)
        for y in 0..<h {
            let cy = y + oy
            guard cy >= 0, cy < ch else { continue }
            for x in 0..<w {
                let cx = x + ox
                guard cx >= 0, cx < cw else { continue }
                canvasData[cy * cw + cx] = mask[y * w + x]
            }
        }

        let result = SelectionMask(width: cw, height: ch, data: canvasData)
        colorRangeLastPoint = p
        applySelection(result, label: "色域選択")
    }

    func retryColorRangeSelection() {
        guard let p = colorRangeLastPoint else { return }
        applyColorRangeSelection(atCanvas: p)
    }

}
