import SwiftUI
import AppKit

// MARK: - メインキャンバス

struct CanvasView: View {
    @EnvironmentObject var model: AppModel

    private enum DragAction {
        case pan(base: CGSize)
        case rectSelect(start: CGPoint, aspect: CGFloat?, fromCenter: Bool)
        case lasso
        case brush
        case moveLayer(baseX: Int, baseY: Int, start: CGPoint)
        case moveSelection(base: SelectionMask, start: CGPoint)
        case crop(start: CGPoint)
        case transformMove(t0: SelectionTransform, p0: CGPoint)
        case transformScale(t0: SelectionTransform, p0: CGPoint, anchorBase: CGPoint,
                            center: CGPoint, axisX: Bool, axisY: Bool)
        case transformRotate(t0: SelectionTransform, p0: CGPoint, center: CGPoint)
        case ignore
    }

    @State private var dragAction: DragAction?
    @State private var previewRect: CGRect?
    @State private var lassoPoints: [CGPoint] = []
    @State private var lastBrushPoint: CGPoint?
    @State private var hovering = false
    @State private var lastHoverViewPoint: CGPoint = .zero
    @State private var scrollMonitor: Any?
    @GestureState private var pinchDelta: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                // チェッカーボード・合成画像・オーバーレイ・定規はすべて Metal で描画
                CanvasMetalView(previewRect: previewRect,
                                lassoPoints: lassoPoints,
                                hovering: hovering)
            }
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    hovering = true
                    lastHoverViewPoint = p
                    model.mouseCanvasPos = model.viewToCanvas(p)
                    updateCursor()
                case .ended:
                    hovering = false
                    model.mouseCanvasPos = nil
                    NSCursor.arrow.set()
                @unknown default:
                    break
                }
            }
            .gesture(canvasDrag)
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinchDelta) { v, s, _ in s = v }
                    .onEnded { v in model.setZoom(model.zoom * v, around: lastHoverViewPoint) }
            )
            .onAppear {
                model.viewSize = geo.size
                installScrollMonitor()
                if model.gpuCompositor?.compositeTexture != nil { model.fitToView() }
            }
            .onDisappear { removeScrollMonitor() }
            .onChange(of: geo.size) { _, s in model.viewSize = s }
        }
    }

    // MARK: - ドラッグジェスチャー

    private var canvasDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let canvasP = model.viewToCanvas(v.location)
                if dragAction == nil {
                    dragAction = decideAction(viewPoint: v.startLocation,
                                              canvasPoint: model.viewToCanvas(v.startLocation))
                }
                updateDrag(v, canvasP: canvasP)
            }
            .onEnded { v in
                endDrag(v)
                dragAction = nil
                previewRect = nil
                lassoPoints = []
                lastBrushPoint = nil
            }
    }

    private func decideAction(viewPoint: CGPoint, canvasPoint: CGPoint) -> DragAction {
        if model.spaceKeyDown {
            return .pan(base: model.panOffset)
        }

        switch model.tool {
        case .rectSelect:
            var aspect: CGFloat? = nil
            if model.rectSelKeepAspect, let b = model.selectionBaseBounds, b.height > 0 {
                aspect = b.width / b.height
            } else if model.rectSelKeepAspect {
                aspect = 1
            }
            return .rectSelect(start: canvasPoint, aspect: aspect,
                               fromCenter: model.rectSelFromCenter)

        case .freehandSelect:
            lassoPoints = [canvasPoint]
            return .lasso

        case .colorRangeSelect:
            return .ignore  // クリックは onEnded で処理

        case .maskBrush:
            model.beginBrushStroke()
            lastBrushPoint = nil
            return .brush

        case .transform:
            if let h = model.transformHandles() {
                let t0 = model.pendingTransform
                let center = CGPoint(x: h.bounds.midX, y: h.bounds.midY)
                if distance(viewPoint, h.center) < 8 {
                    return .transformRotate(t0: t0, p0: canvasPoint,
                                            center: CGPoint(x: center.x + t0.dx, y: center.y + t0.dy))
                }
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
                if isInsideTransformedSelection(canvasPoint) {
                    return .transformMove(t0: t0, p0: canvasPoint)
                }
            }
            return .ignore

        case .move:
            if model.toolTargetMode == .selection {
                guard let sel = model.selection else {
                    model.warn("選択範囲がありません")
                    return .ignore
                }
                model.pushUndo("選択範囲の移動", coalesceKey: nil)
                return .moveSelection(base: sel, start: canvasPoint)
            }
            guard let layer = model.activeLayer else { return .ignore }
            if layer.locked {
                model.warn("レイヤーがロックされています")
                NSSound.beep()
                return .ignore
            }
            model.pushUndo("レイヤーの移動", coalesceKey: nil)
            return .moveLayer(baseX: layer.offsetX, baseY: layer.offsetY, start: canvasPoint)

        case .crop:
            return .crop(start: canvasPoint)

        case .fill, .eyedropper, .text, .resize, .rotate, .flip:
            return .ignore
        }
    }

    private func updateDrag(_ v: DragGesture.Value, canvasP: CGPoint) {
        guard let action = dragAction else { return }
        // ドラッグ中もルーペにカーソル位置を伝える
        model.mouseCanvasPos = canvasP
        switch action {
        case .pan(let base):
            model.panOffset = CGSize(width: base.width + v.translation.width,
                                     height: base.height + v.translation.height)

        case .rectSelect(let start, let aspect, let fromCenter):
            var r: CGRect
            if fromCenter {
                let halfW = abs(canvasP.x - start.x)
                var halfH = abs(canvasP.y - start.y)
                if let asp = aspect, asp > 0, halfW > 0 {
                    halfH = halfW / asp
                }
                r = CGRect(x: (start.x - halfW).rounded(.down),
                           y: (start.y - halfH).rounded(.down),
                           width: (halfW * 2).rounded(),
                           height: (halfH * 2).rounded())
            } else {
                r = normalizedRect(from: start, to: canvasP)
                if let aspect, aspect > 0 {
                    let h = r.width / aspect
                    r = CGRect(x: r.minX, y: canvasP.y < start.y ? start.y - h : r.minY,
                               width: r.width, height: h)
                }
            }
            previewRect = r

        case .lasso:
            if let last = lassoPoints.last, distance(last, canvasP) >= 1 {
                lassoPoints.append(canvasP)
            }

        case .brush:
            strokeBrush(to: canvasP)

        case .moveLayer(let baseX, let baseY, let start):
            let dx = Int((canvasP.x - start.x).rounded())
            let dy = Int((canvasP.y - start.y).rounded())
            _ = model.withActiveLayer { l in
                l.offsetX = baseX + dx
                l.offsetY = baseY + dy
            }
            model.recomposite()

        case .moveSelection(let base, let start):
            let dx = Int((canvasP.x - start.x).rounded())
            let dy = Int((canvasP.y - start.y).rounded())
            model.selection = base.translated(dx: dx, dy: dy)

        case .crop(let start):
            previewRect = normalizedRect(from: start, to: canvasP)
            model.cropRect = previewRect

        case .transformMove(let t0, let p0):
            model.pendingTransform.dx = t0.dx + Double(canvasP.x - p0.x)
            model.pendingTransform.dy = t0.dy + Double(canvasP.y - p0.y)

        case .transformScale(let t0, let p0, let anchorBase, let center, let axisX, let axisY):
            let rot = -t0.rotation * .pi / 180
            let movedCenter = CGPoint(x: center.x + t0.dx, y: center.y + t0.dy)
            let q  = rotate(canvasP, around: movedCenter, by: rot)
            let q0 = rotate(p0,      around: movedCenter, by: rot)
            let aX = movedCenter.x + (anchorBase.x - center.x) * t0.scaleX
            let aY = movedCenter.y + (anchorBase.y - center.y) * t0.scaleY

            var sx = t0.scaleX, sy = t0.scaleY
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
            model.pendingTransform.scaleX = sx
            model.pendingTransform.scaleY = sy
            model.pendingTransform.dx = t0.dx + Double(anchorBase.x - center.x) * (t0.scaleX - sx)
            model.pendingTransform.dy = t0.dy + Double(anchorBase.y - center.y) * (t0.scaleY - sy)

        case .transformRotate(let t0, let p0, let center):
            let a0 = atan2(p0.y - center.y, p0.x - center.x)
            let a1 = atan2(canvasP.y - center.y, canvasP.x - center.x)
            var deg = t0.rotation + Double(a1 - a0) * 180 / .pi
            deg = deg.truncatingRemainder(dividingBy: 360)
            if deg < 0 { deg += 360 }
            model.pendingTransform.rotation = deg

        case .ignore:
            break
        }
    }

    private func endDrag(_ v: DragGesture.Value) {
        let canvasP = model.viewToCanvas(v.location)
        let isClick = distance(v.startLocation, v.location) < 3

        switch dragAction {
        case .rectSelect(_, _, _):
            if let r = previewRect, r.width >= 1, r.height >= 1 {
                model.applySelection(
                    SelectionMask.rect(width: model.canvasWidth, height: model.canvasHeight, rect: r),
                    label: "矩形選択"
                )
            }
        case .lasso:
            if lassoPoints.count >= 3 {
                model.applySelection(
                    SelectionMask.polygon(width: model.canvasWidth, height: model.canvasHeight,
                                          points: lassoPoints),
                    label: "フリーハンド選択"
                )
            }
        case .pan(_):
            break
        case .ignore, nil:
            guard isClick else { break }
            handleClick(at: canvasP)
        default:
            break
        }
    }

    private func handleClick(at canvasP: CGPoint) {
        switch model.tool {
        case .colorRangeSelect:
            if let c = model.compositeColor(atCanvas: canvasP) {
                model.colorRangeOpts.bgColor = PixelColor(r: c.r, g: c.g, b: c.b)
                model.runColorRangeSelection()
            }
        case .fill:
            if model.fillOpts.scope == .selection {
                model.fillSelection()
            } else {
                model.floodFill(atCanvas: canvasP)
            }
        case .eyedropper:
            model.sampleColor(atCanvas: canvasP)
        case .text:
            model.textOpts.xText = String(Int(canvasP.x.rounded()))
            model.textOpts.yText = String(Int(canvasP.y.rounded()))
        default:
            break
        }
    }

    // MARK: - ブラシ

    private func strokeBrush(to p: CGPoint) {
        guard model.selection != nil else { return }
        let opts = model.brushOpts
        var sel = model.selection!
        if let last = lastBrushPoint {
            let d = distance(last, p)
            let stepLen = max(1.0, opts.size / 4)
            let steps = max(1, Int(d / stepLen))
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let q = CGPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t)
                sel.stampBrush(at: q, size: opts.size, hardness: opts.hardness / 100,
                               opacity: opts.opacity / 100, add: opts.add)
            }
        } else {
            sel.stampBrush(at: p, size: opts.size, hardness: opts.hardness / 100,
                           opacity: opts.opacity / 100, add: opts.add)
        }
        lastBrushPoint = p
        model.selection = sel
    }

    // MARK: - ヒットテスト・ユーティリティ

    private func isInsideTransformedSelection(_ canvasP: CGPoint) -> Bool {
        guard let sel = model.selection, let b = model.selectionBaseBounds else { return false }
        let t = model.pendingTransform
        let inverse = t.affine(center: CGPoint(x: b.midX, y: b.midY)).inverted()
        let q = canvasP.applying(inverse)
        return sel.isSelected(x: Int(q.x.rounded(.down)), y: Int(q.y.rounded(.down)))
    }

    private func updateCursor() {
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
            NSCursor.crosshair.set()
        case .maskBrush:
            NSCursor.crosshair.set()
        case .transform:
            updateTransformCursor()
        case .move:
            NSCursor.openHand.set()
        case .eyedropper, .fill:
            NSCursor.crosshair.set()
        default:
            NSCursor.arrow.set()
        }
    }

    private func updateTransformCursor() {
        guard let vp = model.mouseCanvasPos.map({ model.canvasToView($0) }) else {
            NSCursor.arrow.set()
            return
        }
        if let h = model.transformHandles() {
            if distance(vp, h.center) < 8 {
                NSCursor.crosshair.set()
                return
            }
            for p in h.corners where distance(vp, p) < 8 {
                NSCursor.crosshair.set()
                return
            }
            for p in h.edges where distance(vp, p) < 8 {
                NSCursor.resizeUpDown.set()
                return
            }
            if let cp = model.mouseCanvasPos, isInsideTransformedSelection(cp) {
                NSCursor.openHand.set()
                return
            }
        }
        NSCursor.arrow.set()
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x).rounded(.down), y: min(a.y, b.y).rounded(.down),
               width: abs(b.x - a.x).rounded(), height: abs(b.y - a.y).rounded())
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func rotate(_ p: CGPoint, around c: CGPoint, by rad: Double) -> CGPoint {
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cos(rad) - dy * sin(rad),
                       y: c.y + dx * sin(rad) + dy * cos(rad))
    }

    // MARK: - スクロールホイール

    private func installScrollMonitor() {
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

    private func removeScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        scrollMonitor = nil
    }
}

private extension Double {
    func clampedMagnitude(min minMag: Double) -> Double {
        if abs(self) < minMag { return self < 0 ? -minMag : minMag }
        return self
    }
}

// MARK: - カスタムカーソル（選択操作モードバッジ付き）

private extension CanvasView {
    static let selectionBaseCursor:     NSCursor = makeSelectionCursor()
    static let selectionAddCursor:      NSCursor = makeSelectionCursor(badge: "+")
    static let selectionSubtractCursor: NSCursor = makeSelectionCursor(badge: "−")

    static func makeSelectionCursor(badge: String? = nil) -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = size / 2, cy = size / 2
            let gap: CGFloat = 4  // 中心の空白

            ctx.setLineCap(.round)

            // 白ハロー
            ctx.setLineWidth(2.5)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.move(to: CGPoint(x: cx, y: 1));        ctx.addLine(to: CGPoint(x: cx, y: cy - gap))
            ctx.move(to: CGPoint(x: cx, y: cy + gap)); ctx.addLine(to: CGPoint(x: cx, y: size - 1))
            ctx.move(to: CGPoint(x: 1, y: cy));        ctx.addLine(to: CGPoint(x: cx - gap, y: cy))
            ctx.move(to: CGPoint(x: cx + gap, y: cy)); ctx.addLine(to: CGPoint(x: size - 1, y: cy))
            ctx.strokePath()

            // 黒クロスヘア
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.move(to: CGPoint(x: cx, y: 1));        ctx.addLine(to: CGPoint(x: cx, y: cy - gap))
            ctx.move(to: CGPoint(x: cx, y: cy + gap)); ctx.addLine(to: CGPoint(x: cx, y: size - 1))
            ctx.move(to: CGPoint(x: 1, y: cy));        ctx.addLine(to: CGPoint(x: cx - gap, y: cy))
            ctx.move(to: CGPoint(x: cx + gap, y: cy)); ctx.addLine(to: CGPoint(x: size - 1, y: cy))
            ctx.strokePath()

            // バッジ（+/− のみ、通常選択はなし）
            if let badge {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 8),
                    .foregroundColor: NSColor.black,
                    .strokeColor: NSColor.white,
                    .strokeWidth: -2.5
                ]
                NSAttributedString(string: badge, attributes: attrs)
                    .draw(at: NSPoint(x: cx + 3, y: 1))
            }
            return true
        }
        img.isTemplate = false
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}
