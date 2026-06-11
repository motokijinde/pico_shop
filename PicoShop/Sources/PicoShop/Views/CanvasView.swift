import SwiftUI
import AppKit

// MARK: - メインキャンバス

struct CanvasView: View {
    @EnvironmentObject var model: AppModel

    private enum DragAction {
        case pan(base: CGSize)
        case rectSelect(start: CGPoint, aspect: CGFloat?)
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

    private let rulerSize: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                Canvas { ctx, _ in
                    drawCheckerboard(&ctx, in: canvasViewRect())
                }

                if let img = model.composite {
                    let b = model.compositeBounds
                    let topLeft = model.canvasToView(CGPoint(x: b.minX, y: b.minY))
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(model.zoom >= 1 ? .none : .high)
                        .frame(width: b.width * model.zoom, height: b.height * model.zoom)
                        .position(x: topLeft.x + b.width * model.zoom / 2,
                                  y: topLeft.y + b.height * model.zoom / 2)
                }

                Canvas { ctx, size in
                    drawOverlays(&ctx, size: size)
                }
                .allowsHitTesting(false)

                if model.selection != nil {
                    TimelineView(.animation(minimumInterval: 0.1)) { timeline in
                        Canvas { ctx, _ in
                            drawMarchingAnts(&ctx, date: timeline.date)
                        }
                    }
                    .allowsHitTesting(false)
                }

                Canvas { ctx, size in
                    drawRulers(&ctx, size: size)
                }
                .allowsHitTesting(false)
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
                if model.composite != nil { model.fitToView() }
            }
            .onDisappear { removeScrollMonitor() }
            .onChange(of: geo.size) { _, s in model.viewSize = s }
        }
    }

    // MARK: - 座標ヘルパー

    private func canvasViewRect() -> CGRect {
        let tl = model.canvasToView(.zero)
        let br = model.canvasToView(CGPoint(x: CGFloat(model.canvasWidth), y: CGFloat(model.canvasHeight)))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    private func canvasToViewTransform() -> CGAffineTransform {
        let c = model.canvasCenter
        return CGAffineTransform(translationX: model.viewSize.width / 2 + model.panOffset.width - c.x * model.zoom,
                                 y: model.viewSize.height / 2 + model.panOffset.height - c.y * model.zoom)
            .scaledBy(x: model.zoom, y: model.zoom)
    }

    // MARK: - 描画

    private func drawOverlays(_ ctx: inout GraphicsContext, size: CGSize) {
        let canvasRect = canvasViewRect()

        var outside = Path(CGRect(origin: .zero, size: size))
        outside.addRect(canvasRect)
        ctx.fill(outside, with: .color(Color.black.opacity(0.35)), style: FillStyle(eoFill: true))

        ctx.stroke(Path(canvasRect), with: .color(.white),
                   style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

        let center = model.canvasToView(model.canvasCenter)
        var cross = Path()
        cross.move(to: CGPoint(x: canvasRect.minX, y: center.y))
        cross.addLine(to: CGPoint(x: canvasRect.maxX, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: canvasRect.minY))
        cross.addLine(to: CGPoint(x: center.x, y: canvasRect.maxY))
        ctx.stroke(cross, with: .color(Color.gray.opacity(0.55)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        let toView = canvasToViewTransform()

        if let r = previewRect {
            let vr = r.applying(toView)
            ctx.fill(Path(vr), with: .color(Color.accentColor.opacity(0.12)))
            ctx.stroke(Path(vr), with: .color(Color.accentColor), lineWidth: 1)
        }

        if model.tool == .crop, let r = model.cropRect {
            let vr = r.applying(toView)
            var dim = Path(CGRect(origin: .zero, size: size))
            dim.addRect(vr)
            ctx.fill(dim, with: .color(Color.black.opacity(0.3)), style: FillStyle(eoFill: true))
            ctx.stroke(Path(vr), with: .color(.yellow), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        }

        if lassoPoints.count >= 2 {
            var p = Path()
            p.move(to: lassoPoints[0])
            for pt in lassoPoints.dropFirst() { p.addLine(to: pt) }
            ctx.stroke(p.applying(toView), with: .color(Color.accentColor), lineWidth: 1)
        }

        // ブラシカーソル（マスクブラシツールのみ）
        if model.tool == .maskBrush, hovering, let mp = model.mouseCanvasPos {
            let r = CGFloat(model.brushOpts.size) / 2 * model.zoom
            let c = model.canvasToView(mp)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(model.brushOpts.add ? .green : .red), lineWidth: 1)
        }

        // 変形ハンドル（変形ツールのみ）
        if model.tool == .transform, let handles = transformHandles() {
            for p in handles.corners + handles.edges {
                let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                ctx.fill(Path(r), with: .color(.white))
                ctx.stroke(Path(r), with: .color(.black), lineWidth: 1)
            }
            let c = handles.center
            let cr = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: cr), with: .color(.white))
            ctx.stroke(Path(ellipseIn: cr), with: .color(.black), lineWidth: 1)
        }
    }

    private func drawMarchingAnts(_ ctx: inout GraphicsContext, date: Date) {
        guard var path = model.selectionPath else { return }
        // pendingTransform のプレビューは変形ツールのみ適用
        if model.tool == .transform, !model.pendingTransform.isIdentity,
           let b = model.selectionBaseBounds {
            path = path.applying(model.pendingTransform.affine(center: CGPoint(x: b.midX, y: b.midY)))
        }
        let viewPath = path.applying(canvasToViewTransform())
        let phase = CGFloat(date.timeIntervalSinceReferenceDate * 20).truncatingRemainder(dividingBy: 10)
        ctx.stroke(viewPath, with: .color(.white),
                   style: StrokeStyle(lineWidth: 1, dash: [5, 5], dashPhase: phase))
        ctx.stroke(viewPath, with: .color(.black),
                   style: StrokeStyle(lineWidth: 1, dash: [5, 5], dashPhase: phase + 5))
    }

    private func drawRulers(_ ctx: inout GraphicsContext, size: CGSize) {
        let bg = Color(nsColor: .windowBackgroundColor).opacity(0.92)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: rulerSize)), with: .color(bg))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: rulerSize + 4, height: size.height)), with: .color(bg))

        let candidates: [CGFloat] = [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
        let step = candidates.first { $0 * model.zoom >= 42 } ?? 5000
        let visible = model.visibleCanvasRect
        let tickColor = Color.secondary

        var x = (visible.minX / step).rounded(.down) * step
        while x <= visible.maxX {
            let vx = model.canvasToView(CGPoint(x: x, y: 0)).x
            if vx >= rulerSize {
                var tick = Path()
                tick.move(to: CGPoint(x: vx, y: rulerSize - 6))
                tick.addLine(to: CGPoint(x: vx, y: rulerSize))
                ctx.stroke(tick, with: .color(tickColor), lineWidth: 1)
                ctx.draw(Text(String(Int(x))).font(.system(size: 9)).foregroundColor(.secondary),
                         at: CGPoint(x: vx + 2, y: 6), anchor: .leading)
            }
            x += step
        }

        var y = (visible.minY / step).rounded(.down) * step
        while y <= visible.maxY {
            let vy = model.canvasToView(CGPoint(x: 0, y: y)).y
            if vy >= rulerSize {
                var tick = Path()
                tick.move(to: CGPoint(x: rulerSize - 2, y: vy))
                tick.addLine(to: CGPoint(x: rulerSize + 4, y: vy))
                ctx.stroke(tick, with: .color(tickColor), lineWidth: 1)
                ctx.draw(Text(String(Int(y))).font(.system(size: 9)).foregroundColor(.secondary),
                         at: CGPoint(x: 2, y: vy + 2), anchor: .topLeading)
            }
            y += step
        }

        var border = Path()
        border.move(to: CGPoint(x: 0, y: rulerSize))
        border.addLine(to: CGPoint(x: size.width, y: rulerSize))
        border.move(to: CGPoint(x: rulerSize + 4, y: 0))
        border.addLine(to: CGPoint(x: rulerSize + 4, y: size.height))
        ctx.stroke(border, with: .color(Color.secondary.opacity(0.4)), lineWidth: 1)
    }

    // MARK: - 変形ハンドル（変形ツール専用）

    private struct Handles {
        var corners: [CGPoint]
        var edges: [CGPoint]
        var center: CGPoint
        var cornersBase: [CGPoint]
        var edgesBase: [CGPoint]
        var bounds: CGRect
    }

    private func transformHandles() -> Handles? {
        guard let b = model.selectionBaseBounds else { return nil }
        let t = model.pendingTransform
        let center = CGPoint(x: b.midX, y: b.midY)
        let affine = t.affine(center: center).concatenating(canvasToViewTransform())

        let cornersBase = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                           CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
        let edgesBase = [CGPoint(x: b.midX, y: b.minY), CGPoint(x: b.maxX, y: b.midY),
                         CGPoint(x: b.midX, y: b.maxY), CGPoint(x: b.minX, y: b.midY)]
        return Handles(
            corners: cornersBase.map { $0.applying(affine) },
            edges: edgesBase.map { $0.applying(affine) },
            center: center.applying(t.affine(center: center)).applying(canvasToViewTransform()),
            cornersBase: cornersBase,
            edgesBase: edgesBase,
            bounds: b
        )
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
            return .rectSelect(start: canvasPoint, aspect: aspect)

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
            if let h = transformHandles() {
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
        switch action {
        case .pan(let base):
            model.panOffset = CGSize(width: base.width + v.translation.width,
                                     height: base.height + v.translation.height)

        case .rectSelect(let start, let aspect):
            var r = normalizedRect(from: start, to: canvasP)
            if let aspect, aspect > 0 {
                let h = r.width / aspect
                r = CGRect(x: r.minX, y: canvasP.y < start.y ? start.y - h : r.minY,
                           width: r.width, height: h)
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
        case .rectSelect:
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
        case .rectSelect, .freehandSelect, .colorRangeSelect:
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
        if let h = transformHandles() {
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
