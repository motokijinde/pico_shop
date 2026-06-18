import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppModel {

    // MARK: キャンバス操作

    /// anchor: 0–8（3×3 グリッド、0=左上, 4=中央, 8=右下）
    func resizeCanvas(width: Int, height: Int, anchor: Int) {
        guard commitPendingPixelTransformIfNeeded(preservesSelection: true) else { return }
        let w = max(1, width), h = max(1, height)
        pushUndo("キャンバスサイズ変更")
        let ax = Double(anchor % 3) / 2.0   // 0, 0.5, 1
        let ay = Double(anchor / 3) / 2.0
        let dx = Int((Double(w - canvasWidth) * ax).rounded())
        let dy = Int((Double(h - canvasHeight) * ay).rounded())
        for i in layers.indices {
            layers[i].offsetX += dx
            layers[i].offsetY += dy
        }
        if let sel = selection {
            var newSel = SelectionMask(width: w, height: h)
            for y in 0..<sel.height {
                let ny = y + dy
                guard ny >= 0, ny < h else { continue }
                for x in 0..<sel.width {
                    let nx = x + dx
                    guard nx >= 0, nx < w else { continue }
                    newSel.data[ny * w + nx] = sel.data[y * sel.width + x]
                }
            }
            selection = newSel.isEmpty ? nil : newSel
        }
        canvasWidth = w
        canvasHeight = h
        recomposite()
    }

    /// 全表示レイヤーの結合範囲でキャンバスを自動リサイズ
    func fitCanvasToLayers() {
        guard commitPendingPixelTransformIfNeeded(preservesSelection: false) else { return }
        let visible = layers.filter { $0.visible }
        guard !visible.isEmpty else { return }
        var bounds = visible[0].frame
        for l in visible.dropFirst() { bounds = bounds.union(l.frame) }
        pushUndo("キャンバスを画像に合わせる")
        let ox = Int(bounds.minX.rounded(.down)), oy = Int(bounds.minY.rounded(.down))
        for i in layers.indices {
            layers[i].offsetX -= ox
            layers[i].offsetY -= oy
        }
        canvasWidth = Int(bounds.width.rounded(.up))
        canvasHeight = Int(bounds.height.rounded(.up))
        selection = nil
        recomposite()
    }

    /// アクティブレイヤーを透明でクリア（選択がある場合は選択範囲のみ）
    func clearActiveLayerTransparent() {
        pushUndo("透明でクリア")
        if selection != nil {
            cutSelection()
            return
        }
        let ok = withActiveLayer { l in
            l.buffer = PixelBuffer(width: l.buffer.width, height: l.buffer.height)
            l.markContentChanged()
        }
        if ok { recomposite() }
    }

}
