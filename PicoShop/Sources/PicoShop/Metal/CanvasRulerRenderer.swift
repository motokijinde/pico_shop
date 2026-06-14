import SwiftUI
import MetalKit

extension CanvasRenderer {
    static let rulerSize: CGFloat = 20

    func buildRulers(_ s: inout OverlayScene, model: AppModel, viewSize: CGSize) {
        let rulerSize = Self.rulerSize
        let bg = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        s.fill(CGRect(x: 0, y: 0, width: viewSize.width, height: rulerSize), color: bg)
        s.fill(CGRect(x: 0, y: 0, width: rulerSize + 4, height: viewSize.height), color: bg)

        let candidates: [CGFloat] = [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
        let step = candidates.first { $0 * model.zoom >= 42 } ?? 5000
        let visible = model.visibleCanvasRect
        let tickColor = NSColor.secondaryLabelColor
        let labelColor = NSColor.secondaryLabelColor

        var x = (visible.minX / step).rounded(.down) * step
        while x <= visible.maxX {
            let vx = model.canvasToView(CGPoint(x: x, y: 0)).x
            if vx >= rulerSize {
                s.stroke([CGPoint(x: vx, y: rulerSize - 6), CGPoint(x: vx, y: rulerSize)],
                         color: tickColor)
                s.text(String(Int(x)), at: CGPoint(x: vx + 2, y: 6), anchor: .leading,
                       fontSize: 9, color: labelColor)
            }
            x += step
        }

        var y = (visible.minY / step).rounded(.down) * step
        while y <= visible.maxY {
            let vy = model.canvasToView(CGPoint(x: 0, y: y)).y
            if vy >= rulerSize {
                s.stroke([CGPoint(x: rulerSize - 2, y: vy), CGPoint(x: rulerSize + 4, y: vy)],
                         color: tickColor)
                s.text(String(Int(y)), at: CGPoint(x: 2, y: vy + 2), anchor: .topLeading,
                       fontSize: 9, color: labelColor)
            }
            y += step
        }

        let borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.4)
        s.stroke([CGPoint(x: 0, y: rulerSize), CGPoint(x: viewSize.width, y: rulerSize)],
                 color: borderColor)
        s.stroke([CGPoint(x: rulerSize + 4, y: 0), CGPoint(x: rulerSize + 4, y: viewSize.height)],
                 color: borderColor)
    }
}
