import SwiftUI
import AppKit

extension AppModel {

    // MARK: - 座標変換（キャンバス座標 ↔ ビュー座標）

    var canvasCenter: CGPoint {
        CGPoint(x: CGFloat(canvasWidth) / 2, y: CGFloat(canvasHeight) / 2)
    }

    func canvasToView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - canvasCenter.x) * zoom + viewSize.width / 2 + panOffset.width,
                y: (p.y - canvasCenter.y) * zoom + viewSize.height / 2 + panOffset.height)
    }

    func viewToCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - viewSize.width / 2 - panOffset.width) / zoom + canvasCenter.x,
                y: (p.y - viewSize.height / 2 - panOffset.height) / zoom + canvasCenter.y)
    }

    /// 現在ビューに見えているキャンバス座標の矩形
    var visibleCanvasRect: CGRect {
        let tl = viewToCanvas(.zero)
        let br = viewToCanvas(CGPoint(x: viewSize.width, y: viewSize.height))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    // MARK: - ズーム / パン

    func setZoom(_ z: CGFloat, around viewPoint: CGPoint? = nil) {
        let newZoom = max(0.02, min(64, z))
        if let vp = viewPoint {
            // ポイント下のキャンバス座標を固定してズーム
            let c = viewToCanvas(vp)
            zoom = newZoom
            let after = canvasToView(c)
            panOffset.width += vp.x - after.x
            panOffset.height += vp.y - after.y
        } else {
            zoom = newZoom
        }
    }

    func zoomIn() { setZoom(zoom * 1.5) }
    func zoomOut() { setZoom(zoom / 1.5) }

    func fitToView() {
        guard viewSize.width > 0 else { return }
        let b = compositeBounds
        let s = min(viewSize.width / b.width, viewSize.height / b.height) * 0.92
        zoom = max(0.02, min(64, s))
        // composite の中心がビュー中心に来るように
        let bCenter = CGPoint(x: b.midX, y: b.midY)
        panOffset = CGSize(width: -(bCenter.x - canvasCenter.x) * zoom,
                           height: -(bCenter.y - canvasCenter.y) * zoom)
    }

    func zoomActualSize() {
        zoom = 1
        panOffset = .zero
    }

    /// ナビゲーターから：キャンバス座標 c がビュー中心に来るようにパン
    func scrollTo(canvasPoint c: CGPoint) {
        panOffset = CGSize(width: -(c.x - canvasCenter.x) * zoom,
                           height: -(c.y - canvasCenter.y) * zoom)
    }
}
