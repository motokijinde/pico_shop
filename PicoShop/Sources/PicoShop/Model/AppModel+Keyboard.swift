import SwiftUI
import AppKit

extension AppModel {

    // MARK: - キーボード操作（カーソルキー 1px 調整）

    func installKeyMonitors() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // テキスト編集中は何もしない
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            return event
        }

        // スペースキー（パン用）
        if event.keyCode == 49 {
            spaceKeyDown = (event.type == .keyDown)
            return nil
        }

        guard event.type == .keyDown else { return event }

        switch event.keyCode {
        case 123: return handleArrow(dx: -1, dy: 0, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 124: return handleArrow(dx: 1, dy: 0, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 125: return handleArrow(dx: 0, dy: 1, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 126: return handleArrow(dx: 0, dy: -1, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 51, 117:  // Delete / Forward Delete → カット
            if selection != nil {
                cutSelection()
                return nil
            }
            return event
        default:
            return event
        }
    }

    /// カーソルキー：位置移動（1px）、Shift+カーソルキー：サイズ変更（1px）
    /// 戻り値：イベントを消費したか
    @discardableResult
    func handleArrow(dx: Int, dy: Int, shift: Bool) -> Bool {
        // 選択変形ツール・選択系ツール・マスクブラシ → 選択マスクを操作
        let targetSelectionMask =
            (tool == .selectionTransform && selection != nil) ||
            (tool.isSelectionTool && selection != nil) ||
            (tool == .maskBrush && selection != nil)

        if targetSelectionMask {
            guard let sel = selection, let b = sel.bounds() else { return false }
            if shift {
                let newW = max(1, b.width + CGFloat(dx))
                let newH = max(1, b.height + CGFloat(dy))
                pushUndo("選択範囲のサイズ変更", coalesceKey: "sel-resize")
                selection = sel.transformed(
                    dx: 0, dy: 0,
                    scaleX: Double(newW / b.width), scaleY: Double(newH / b.height),
                    rotationDegrees: 0,
                    center: CGPoint(x: b.minX, y: b.minY)
                )
            } else {
                pushUndo("選択範囲の移動", coalesceKey: "sel-move")
                selection = sel.translated(dx: dx, dy: dy)
            }
            return true
        }

        // move ツール：floatingLayer の位置を 1px 動かす
        if tool == .move, originalMoveBounds != nil, !shift {
            extractMovePixels()  // ドラッグ前に矢印キーが押された場合も抽出を開始する
            pendingTransform.dx += Double(dx)
            pendingTransform.dy += Double(dy)
            if let buf = floatingLayer?.buffer, let bounds = originalMoveBounds {
                let midX = bounds.midX + pendingTransform.dx
                let midY = bounds.midY + pendingTransform.dy
                floatingLayer?.offsetX = Int((midX - Double(buf.width)  / 2).rounded())
                floatingLayer?.offsetY = Int((midY - Double(buf.height) / 2).rounded())
            }
            recomposite()
            return true
        }

        // レイヤー操作
        guard activeLayer != nil else { return false }
        if shift {
            guard let layer = activeLayer else { return false }
            let newW = max(1, layer.buffer.width + dx)
            let newH = max(1, layer.buffer.height + dy)
            pushUndo("レイヤーのサイズ変更", coalesceKey: "layer-resize")
            let ok = withActiveLayer { l in
                l.buffer = l.buffer.cpuResized(width: newW, height: newH, quality: resizeOpts.quality)
                l.markContentChanged()
            }
            if ok { recomposite() }
            return ok
        } else {
            pushUndo("レイヤーの移動", coalesceKey: "layer-move")
            let ok = withActiveLayer { l in
                l.offsetX += dx
                l.offsetY += dy
            }
            if ok { recomposite() }
            return ok
        }
    }
}
