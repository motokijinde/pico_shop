import SwiftUI
import AppKit

extension CanvasView {
    // MARK: - ブラシ

    func strokeBrush(to p: CGPoint) {
        guard model.brushStrokeSelection != nil else { return }
        appendBrushStrokePreviewPoint(p)
        let opts = model.brushOpts
        let addsToSelection = model.selectionOperationMode != .subtract
        if let last = lastBrushPoint {
            let d = distance(last, p)
            let stepLen = max(1.0, opts.size / 4)
            let steps = max(1, Int(d / stepLen))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let q = CGPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t)
                model.brushStrokeSelection?.stampBrush(at: q, size: opts.size, hardness: opts.hardness / 100,
                                                       opacity: opts.opacity / 100, add: addsToSelection)
            }
        } else {
            model.brushStrokeSelection?.stampBrush(at: p, size: opts.size, hardness: opts.hardness / 100,
                                                   opacity: opts.opacity / 100, add: addsToSelection)
        }
        lastBrushPoint = p
    }

    func appendBrushStrokePreviewPoint(_ p: CGPoint) {
        guard let last = model.brushStrokePreviewPoints.last else {
            model.brushStrokePreviewPoints = [p]
            return
        }
        let minSpacing = max(1, 3 / max(model.zoom, 0.01))
        if distance(last, p) >= minSpacing {
            model.brushStrokePreviewPoints.append(p)
        }
    }

    // MARK: - ヒットテスト・ユーティリティ

    func isInsideTransformedSelection(_ canvasP: CGPoint) -> Bool {
        guard let b = model.transformHandles()?.bounds else { return false }
        let t = model.pendingTransform
        let inverse = t.affine(center: CGPoint(x: b.midX, y: b.midY)).inverted()
        let q = canvasP.applying(inverse)
        if let sel = model.selection {
            return sel.isSelected(x: Int(q.x.rounded(.down)), y: Int(q.y.rounded(.down)))
        } else {
            // selection == nil かつ transform ツール → レイヤー bounds で判定
            return b.contains(q)
        }
    }

    func updateCursor() {
        if model.spaceKeyDown {
            NSCursor.openHand.set()
            return
        }
        switch model.tool {
        case .rectSelect, .freehandSelect:
            switch model.selectionOperationMode {
            case .replace:  Self.selectionBaseCursor.set()
            case .add:      Self.selectionAddCursor.set()
            case .subtract: Self.selectionSubtractCursor.set()
            }
        case .colorRangeSelect:
            switch model.selectionOperationMode {
            case .replace:  Self.colorRangeBaseCursor.set()
            case .add:      Self.colorRangeAddCursor.set()
            case .subtract: Self.colorRangeSubtractCursor.set()
            }
        case .maskBrush:
            Self.brushCursor(for: model.selectionOperationMode).set()
        case .selectionTransform, .transform, .move:
            updateTransformCursor()
        case .layerMove:
            if case .moveLayer = dragAction {
                NSCursor.closedHand.set()
            } else {
                NSCursor.openHand.set()
            }
        case .eyedropper, .fill:
            NSCursor.crosshair.set()
        default:
            NSCursor.arrow.set()
        }
    }

    func updateTransformCursor() {
        if case .transformMove = dragAction {
            NSCursor.closedHand.set()
            return
        }
        guard let vp = model.mouseCanvasPos.map({ model.canvasToView($0) }) else {
            NSCursor.arrow.set()
            return
        }
        if let h = model.transformHandles() {
            if distance(vp, h.center) < 8 {
                Self.rotateCursor.set()
                return
            }
            for p in h.corners where distance(vp, p) < 8 {
                resizeCursor(from: h.center, to: p).set()
                return
            }
            for p in h.edges where distance(vp, p) < 8 {
                resizeCursor(from: h.center, to: p).set()
                return
            }
            if let cp = model.mouseCanvasPos, isInsideTransformedSelection(cp) {
                NSCursor.openHand.set()
                return
            }
        }
        NSCursor.arrow.set()
    }

    func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x).rounded(.down), y: min(a.y, b.y).rounded(.down),
               width: abs(b.x - a.x).rounded(), height: abs(b.y - a.y).rounded())
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// center → handle の方向角から、回転後も正しいリサイズカーソルを返す
    func resizeCursor(from center: CGPoint, to handle: CGPoint) -> NSCursor {
        let angleDeg = atan2(Double(handle.y - center.y), Double(handle.x - center.x)) * 180 / .pi
        let normalized = (angleDeg + 360).truncatingRemainder(dividingBy: 360)
        let sector = Int((normalized / 45).rounded()) % 8
        switch sector % 4 {
        case 1: return Self.resizeNWSECursor
        case 2: return NSCursor.resizeUpDown
        case 3: return Self.resizeNESWCursor
        default: return NSCursor.resizeLeftRight
        }
    }

    func rotate(_ p: CGPoint, around c: CGPoint, by rad: Double) -> CGPoint {
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cos(rad) - dy * sin(rad),
                       y: c.y + dx * sin(rad) + dy * cos(rad))
    }

    // MARK: - スクロールホイール

    func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard self.hovering else { return event }
            if event.hasPreciseScrollingDeltas {
                model.panOffset.width  += event.scrollingDeltaX
                model.panOffset.height += event.scrollingDeltaY
            } else {
                if event.scrollingDeltaY > 0 {
                    model.setZoom(model.zoom * 1.5, around: self.lastHoverViewPoint)
                } else if event.scrollingDeltaY < 0 {
                    model.setZoom(model.zoom / 1.5, around: self.lastHoverViewPoint)
                }
            }
            return nil
        }
    }

    func removeScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        scrollMonitor = nil
    }
}
