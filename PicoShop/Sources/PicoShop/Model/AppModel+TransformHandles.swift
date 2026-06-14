import SwiftUI
import AppKit

// MARK: - ビュー幾何ヘルパー（CanvasView と Metal レンダラーで共用）

extension AppModel {

    /// キャンバス座標 → ビュー座標のアフィン変換
    var canvasToViewAffine: CGAffineTransform {
        let c = canvasCenter
        return CGAffineTransform(translationX: viewSize.width / 2 + panOffset.width - c.x * zoom,
                                 y: viewSize.height / 2 + panOffset.height - c.y * zoom)
            .scaledBy(x: zoom, y: zoom)
    }

    struct TransformHandles {
        var corners: [CGPoint]
        var edges: [CGPoint]
        var center: CGPoint
        var cornersBase: [CGPoint]
        var edgesBase: [CGPoint]
        var bounds: CGRect
    }

    /// 変形ツールのハンドル位置（ビュー座標）。
    /// transform ツールは selection == nil のときアクティブレイヤーの frame を使う。
    func transformHandles() -> TransformHandles? {
        let b: CGRect
        if let selBounds = selectionBaseBounds {
            b = selBounds
        } else if tool == .move, let mb = originalMoveBounds {
            b = mb
        } else if (tool == .transform || tool == .selectionTransform), let layer = activeLayer {
            b = CGRect(x: CGFloat(layer.offsetX), y: CGFloat(layer.offsetY),
                       width: CGFloat(layer.buffer.width), height: CGFloat(layer.buffer.height))
        } else {
            return nil
        }
        let t = pendingTransform
        let center = CGPoint(x: b.midX, y: b.midY)
        let affine = t.affine(center: center).concatenating(canvasToViewAffine)

        let cornersBase = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                           CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
        let edgesBase = [CGPoint(x: b.midX, y: b.minY), CGPoint(x: b.maxX, y: b.midY),
                         CGPoint(x: b.midX, y: b.maxY), CGPoint(x: b.minX, y: b.midY)]
        return TransformHandles(
            corners: cornersBase.map { $0.applying(affine) },
            edges: edgesBase.map { $0.applying(affine) },
            center: center.applying(t.affine(center: center)).applying(canvasToViewAffine),
            cornersBase: cornersBase,
            edgesBase: edgesBase,
            bounds: b
        )
    }
}
