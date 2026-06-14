import SwiftUI
import AppKit

extension CanvasView {
    func transformDragAction(viewPoint: CGPoint, canvasPoint: CGPoint, extractsMovePixels: Bool) -> DragAction {
        guard let h = model.transformHandles() else { return .ignore }

        let t0 = model.pendingTransform
        let center = CGPoint(x: h.bounds.midX, y: h.bounds.midY)
        let action: DragAction?

        if distance(viewPoint, h.center) < 8 {
            action = .transformRotate(t0: t0, p0: canvasPoint,
                                      center: CGPoint(x: center.x + t0.dx, y: center.y + t0.dy))
        } else {
            action = transformScaleAction(viewPoint: viewPoint, canvasPoint: canvasPoint, handles: h, center: center, transform: t0)
                ?? (isInsideTransformedSelection(canvasPoint) ? .transformMove(t0: t0, p0: canvasPoint) : nil)
        }

        if action != nil {
            if extractsMovePixels { model.extractMovePixels() }
            model.isDraggingTransform = true
        }
        return action ?? .ignore
    }

    private func transformScaleAction(viewPoint: CGPoint, canvasPoint: CGPoint, handles h: AppModel.TransformHandles,
                                      center: CGPoint, transform t0: SelectionTransform) -> DragAction? {
        for (i, p) in h.corners.enumerated() where distance(viewPoint, p) < 8 {
            let anchor = h.cornersBase[(i + 2) % 4]
            return .transformScale(t0: t0, p0: canvasPoint, anchorBase: anchor,
                                   center: center, axisX: true, axisY: true)
        }

        for (i, p) in h.edges.enumerated() where distance(viewPoint, p) < 8 {
            let anchor = h.edgesBase[(i + 2) % 4]
            let isVertical = (i == 0 || i == 2)
            return .transformScale(t0: t0, p0: canvasPoint, anchorBase: anchor,
                                   center: center, axisX: !isVertical, axisY: isVertical)
        }

        return nil
    }

    func updateTransformDrag(_ action: DragAction, canvasP: CGPoint) {
        switch action {
        case .transformMove(let t0, let p0):
            var t = t0
            t.dx = t0.dx + Double(canvasP.x - p0.x)
            t.dy = t0.dy + Double(canvasP.y - p0.y)
            model.dragPreviewTransform = t

        case .transformScale(let t0, let p0, let anchorBase, let center, let axisX, let axisY):
            let rot = -t0.rotation * .pi / 180
            let movedCenter = CGPoint(x: center.x + t0.dx, y: center.y + t0.dy)
            let q = rotate(canvasP, around: movedCenter, by: rot)
            let q0 = rotate(p0, around: movedCenter, by: rot)
            let aX = movedCenter.x + (anchorBase.x - center.x) * t0.scaleX
            let aY = movedCenter.y + (anchorBase.y - center.y) * t0.scaleY

            var sx = t0.scaleX
            var sy = t0.scaleY
            if axisX, abs(q0.x - aX) > 0.001 {
                sx = t0.scaleX * Double((q.x - aX) / (q0.x - aX))
            }
            if axisY, abs(q0.y - aY) > 0.001 {
                sy = t0.scaleY * Double((q.y - aY) / (q0.y - aY))
            }
            if model.transformKeepAspect, axisX, axisY, t0.scaleX != 0 {
                sy = sx / t0.scaleX * t0.scaleY
            }
            sx = sx.clampedMagnitude(min: 0.01)
            sy = sy.clampedMagnitude(min: 0.01)

            let rad = t0.rotation * .pi / 180
            let localDx = Double(anchorBase.x - center.x) * (t0.scaleX - sx)
            let localDy = Double(anchorBase.y - center.y) * (t0.scaleY - sy)
            var t = t0
            t.scaleX = sx
            t.scaleY = sy
            t.dx = t0.dx + localDx * cos(rad) - localDy * sin(rad)
            t.dy = t0.dy + localDx * sin(rad) + localDy * cos(rad)
            model.dragPreviewTransform = t

        case .transformRotate(let t0, let p0, let center):
            let a0 = atan2(p0.y - center.y, p0.x - center.x)
            let a1 = atan2(canvasP.y - center.y, canvasP.x - center.x)
            var deg = t0.rotation + Double(a1 - a0) * 180 / .pi
            deg = deg.truncatingRemainder(dividingBy: 360)
            if deg < 0 { deg += 360 }
            var t = t0
            t.rotation = deg
            model.dragPreviewTransform = t

        default:
            break
        }

    }

    func finishTransformDrag() {
        if let preview = model.dragPreviewTransform {
            model.pendingTransform = preview
        }
        model.dragPreviewTransform = nil
        model.isDraggingTransform = false
        if model.tool == .move {
            model.rasterizePreview()
        }
    }
}
