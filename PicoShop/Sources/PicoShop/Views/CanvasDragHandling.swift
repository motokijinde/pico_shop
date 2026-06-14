import SwiftUI
import AppKit

extension CanvasView {
    // MARK: - ドラッグジェスチャー

    var canvasDrag: some Gesture {
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

    func decideAction(viewPoint: CGPoint, canvasPoint: CGPoint) -> DragAction {
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

        case .selectionTransform, .transform:
            return transformDragAction(viewPoint: viewPoint, canvasPoint: canvasPoint, extractsMovePixels: false)

        case .move:
            return transformDragAction(viewPoint: viewPoint, canvasPoint: canvasPoint, extractsMovePixels: true)

        case .layerMove:
            guard let layer = model.activeLayer else { return .ignore }
            if layer.locked {
                model.warn("レイヤーがロックされています")
                NSSound.beep()
                return .ignore
            }
            model.pushUndo("レイヤーの移動", coalesceKey: nil)
            return .moveLayer(baseX: layer.offsetX, baseY: layer.offsetY, start: canvasPoint)

        case .fill, .eyedropper, .text, .resize, .rotate, .flip:
            return .ignore
        }
    }

    func updateDrag(_ v: DragGesture.Value, canvasP: CGPoint) {
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


        case .transformMove, .transformScale, .transformRotate:
            updateTransformDrag(action, canvasP: canvasP)

        case .ignore:
            break
        }
    }

    func endDrag(_ v: DragGesture.Value) {
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
        case .transformMove, .transformScale, .transformRotate:
            finishTransformDrag()
        case .ignore, nil:
            guard isClick else { break }
            handleClick(at: canvasP)
        default:
            break
        }
    }

    func handleClick(at canvasP: CGPoint) {
        switch model.tool {
        case .colorRangeSelect:
            model.applyColorRangeSelection(atCanvas: canvasP)
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
}

extension Double {
    func clampedMagnitude(min minMag: Double) -> Double {
        if abs(self) < minMag { return self < 0 ? -minMag : minMag }
        return self
    }
}
