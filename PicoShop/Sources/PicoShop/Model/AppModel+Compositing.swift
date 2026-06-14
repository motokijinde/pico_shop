import SwiftUI
import AppKit

extension AppModel {

    // MARK: - 合成

    /// レイヤー変更後に呼ぶ。move 中の floatingLayer は GPU 上の変形プレビューとして合成する。
    func recomposite(includeMovePreview: Bool = true) {
        let preview = includeMovePreview ? currentMoveFloatingPreview() : nil
        let hasMoveFloatingLayer = floatingLayer != nil && originalMoveBounds != nil
        var baseLayers = layers
        if preview == nil, !hasMoveFloatingLayer, let fl = floatingLayer {
            baseLayers.insert(fl, at: 0)
        }
        var bounds = CPUCompositor.unionBounds(layers: baseLayers, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        if let preview {
            bounds = bounds.union(transformedMovePreviewBounds(originalBounds: preview.originalBounds,
                                                              transform: preview.transform))
        }
        compositeBounds = CGRect(x: bounds.minX.rounded(.down), y: bounds.minY.rounded(.down),
                                 width: bounds.width.rounded(.up), height: bounds.height.rounded(.up))
        gpuCompositor?.composite(layers: baseLayers, bounds: compositeBounds, floatingPreview: preview)
    }

    /// キャンバス座標の合成済みピクセル色（ルーペ・スポイト用、GPU から1ピクセル読み出し）
    func compositeColor(atCanvas p: CGPoint) -> PixelColor? {
        let x = Int(p.x.rounded(.down)) - Int(compositeBounds.minX)
        let y = Int(p.y.rounded(.down)) - Int(compositeBounds.minY)
        return gpuCompositor?.readPixel(x: x, y: y)
    }

    func currentMoveFloatingPreview() -> GPUCompositor.FloatingPreview? {
        guard let floatingLayer, let originalMoveBounds else { return nil }
        return GPUCompositor.FloatingPreview(layer: floatingLayer,
                                             originalBounds: originalMoveBounds,
                                             transform: dragPreviewTransform ?? pendingTransform)
    }

    private func transformedMovePreviewBounds(originalBounds b: CGRect,
                                              transform: SelectionTransform) -> CGRect {
        let affine = transform.affine(center: CGPoint(x: b.midX, y: b.midY))
        let points = [
            CGPoint(x: b.minX, y: b.minY).applying(affine),
            CGPoint(x: b.maxX, y: b.minY).applying(affine),
            CGPoint(x: b.minX, y: b.maxY).applying(affine),
            CGPoint(x: b.maxX, y: b.maxY).applying(affine)
        ]
        let minX = points.map(\.x).min() ?? b.minX
        let maxX = points.map(\.x).max() ?? b.maxX
        let minY = points.map(\.y).min() ?? b.minY
        let maxY = points.map(\.y).max() ?? b.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
