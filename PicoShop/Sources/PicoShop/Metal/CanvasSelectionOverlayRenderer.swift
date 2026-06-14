import SwiftUI
import MetalKit

extension CanvasRenderer {
    func buildMarchingAnts(_ s: inout OverlayScene, model: AppModel) {
        // selectionTransform + selection == nil → レイヤー全体の破線矩形
        if model.tool == .selectionTransform, model.selection == nil,
           let layer = model.activeLayer, let eng = engine {
            let rect = CGRect(x: CGFloat(layer.offsetX), y: CGFloat(layer.offsetY),
                              width: CGFloat(layer.buffer.width), height: CGFloat(layer.buffer.height))
            let key = "\(layer.offsetX),\(layer.offsetY),\(layer.buffer.width),\(layer.buffer.height)"
            if key != layerBoundsMeshKey {
                layerBoundsMesh = StrokeMesh(device: eng.device,
                                             polylines: [Self.rectPolyline(rect)], closed: false)
                layerBoundsMeshKey = key
            }
            if let mesh = layerBoundsMesh {
                appendAlternatingDashedOutline(&s, mesh: mesh,
                                               transform: activeOutlineTransform(model: model, rect: rect))
            }
            return
        }

        // move + selection == nil → originalMoveBounds の破線矩形
        if model.tool == .move, model.selection == nil,
           let bounds = model.originalMoveBounds, let eng = engine {
            let key = "\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))"
            if key != layerBoundsMeshKey {
                layerBoundsMesh = StrokeMesh(device: eng.device,
                                             polylines: [Self.rectPolyline(bounds)], closed: false)
                layerBoundsMeshKey = key
            }
            if let mesh = layerBoundsMesh {
                appendAlternatingDashedOutline(&s, mesh: mesh,
                                               transform: activeOutlineTransform(model: model, rect: bounds))
            }
            return
        }

        guard model.selection != nil, let path = model.selectionPath else { return }

        if antsMeshVersion != model.selectionVersion {
            antsMesh = engine.flatMap { StrokeMesh(device: $0.device,
                                                   polylines: Self.polylines(from: path),
                                                   closed: false) }
            antsMeshVersion = model.selectionVersion
        }
        guard let mesh = antsMesh else { return }

        // pendingTransform のプレビューは変形ツール・選択変形ツール・移動ツールで適用（ドラッグ中は dragPreviewTransform を優先）
        var affine = model.canvasToViewAffine
        if (model.tool == .transform || model.tool == .selectionTransform || model.tool == .move),
           let b = model.selectionBaseBounds {
            let activeTransform = model.dragPreviewTransform ?? model.pendingTransform
            if !activeTransform.isIdentity {
                affine = activeTransform
                    .affine(center: CGPoint(x: b.midX, y: b.midY))
                    .concatenating(affine)
            }
        }
        appendAlternatingDashedOutline(&s, mesh: mesh,
                                       transform: OverlayScene.Transform2D(affine: affine))
    }

    /// SwiftUI Path（move/line/close 前提）→ ポリライン列。close は先頭点を末尾に複製して表現。
    static func polylines(from path: Path) -> [[CGPoint]] {
        var lines: [[CGPoint]] = []
        var current: [CGPoint] = []
        func flush() {
            if current.count >= 2 { lines.append(current) }
            current = []
        }
        path.forEach { element in
            switch element {
            case .move(let to):
                flush()
                current = [to]
            case .line(let to):
                current.append(to)
            case .quadCurve(let to, _), .curve(let to, _, _):
                current.append(to)  // 境界パスには現れない想定の保険
            case .closeSubpath:
                if let first = current.first { current.append(first) }
                flush()
            }
        }
        flush()
        return lines
    }
}

