import SwiftUI
import MetalKit

extension CanvasRenderer {
    func buildScene(model: AppModel, viewSize: CGSize) -> OverlayScene {
        var s = OverlayScene()
        let canvasRect = canvasViewRect(model)
        let toView = model.canvasToViewAffine
        let accent = NSColor.controlAccentColor

        // キャンバス外の暗転 + 点線枠
        s.dimOutside(canvasRect, in: viewSize, color: NSColor.black.withAlphaComponent(0.35))
        s.strokeRect(canvasRect, width: 1, color: .white, dash: .init(on: 5, off: 4))

        // 中心の十字（破線）
        let center = model.canvasToView(model.canvasCenter)
        let crossColor = NSColor.gray.withAlphaComponent(0.55)
        let crossDash = OverlayScene.Dash(on: 3, off: 3)
        s.stroke([CGPoint(x: canvasRect.minX, y: center.y), CGPoint(x: canvasRect.maxX, y: center.y)],
                 color: crossColor, dash: crossDash)
        s.stroke([CGPoint(x: center.x, y: canvasRect.minY), CGPoint(x: center.x, y: canvasRect.maxY)],
                 color: crossColor, dash: crossDash)

        // ドラッグ中の矩形プレビュー（白+黒の交互破線で背景色に依存しない視認性を確保）
        if let r = previewRect {
            let vr = r.applying(toView)
            s.fill(vr, color: NSColor.white.withAlphaComponent(0.08))
            let phase = CGFloat(CACurrentMediaTime() * 20).truncatingRemainder(dividingBy: 10)
            s.strokeRect(vr, width: 1, color: .white, dash: .init(on: 5, off: 5, phase: phase))
            s.strokeRect(vr, width: 1, color: .black, dash: .init(on: 5, off: 5, phase: phase + 5))
        }

        // フリーハンド選択の軌跡
        if lassoPoints.count >= 2 {
            s.stroke(lassoPoints.map { $0.applying(toView) }, width: 1, color: accent)
        }

        // ブラシカーソル（マスクブラシツールのみ）
        if model.tool == .maskBrush, hovering, let mp = model.mouseCanvasPos {
            let r = CGFloat(model.brushOpts.size) / 2 * model.zoom
            let c = model.canvasToView(mp)
            s.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2),
                            width: 1, color: model.brushOpts.add ? .green : .red)
        }

        // 変形ハンドル（変形ツール・選択変形ツール・移動ツール）
        if (model.tool == .transform || model.tool == .selectionTransform || model.tool == .move),
           let h = model.transformHandles() {
            // バウンディングボックス破線（selection != nil のみ。== nil は buildMarchingAnts が担当）
            // .strokeCached で毎フレームのテッセレーションを回避する
            if model.selection != nil, let b = model.selectionBaseBounds, let eng = engine {
                if bboxMeshVersion != model.selectionVersion {
                    bboxMesh = StrokeMesh(device: eng.device,
                                          polylines: [Self.rectPolyline(b)], closed: false)
                    bboxMeshVersion = model.selectionVersion
                }
                if let mesh = bboxMesh {
                    appendAlternatingDashedOutline(&s, mesh: mesh,
                                                   transform: activeOutlineTransform(model: model, rect: b),
                                                   dashOn: 4, dashOff: 4, phaseModulo: 8)
                }
            }
            for p in h.corners + h.edges {
                let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                s.fill(r, color: .white)
                s.strokeRect(r, width: 1, color: .black)
            }
            let cr = CGRect(x: h.center.x - 5, y: h.center.y - 5, width: 10, height: 10)
            s.fillEllipse(in: cr, color: .white)
            s.strokeEllipse(in: cr, width: 1, color: .black)
        }

        buildMarchingAnts(&s, model: model)
        buildRulers(&s, model: model, viewSize: viewSize)
        return s
    }
}
