import SwiftUI
import AppKit

extension AppModel {

    // MARK: - アンドゥ / リドゥ

    /// 変更前に呼ぶ。coalesceKey が同じ操作が 1 秒以内に続く場合はまとめる（カーソルキー連打用）
    func pushUndo(_ label: String, coalesceKey key: String? = nil) {
        if let key, key == coalesceKey, Date().timeIntervalSince(coalesceTime) < 1.0 {
            coalesceTime = Date()
            return
        }
        coalesceKey = key
        coalesceTime = Date()
        undoStack.append(currentSnapshot(label: label))
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        redoStack.removeAll()
    }

    private func currentSnapshot(label: String) -> Snapshot {
        Snapshot(layers: layers, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                 selection: selection, activeLayerID: activeLayerID, label: label)
    }

    /// 操作が失敗（ロック等）した場合に直前の pushUndo を取り消す
    func discardLastUndo() {
        guard !undoStack.isEmpty else { return }
        undoStack.removeLast()
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot(label: snap.label))
        restore(snap)
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot(label: snap.label))
        restore(snap)
    }

    private func restore(_ snap: Snapshot) {
        layers = snap.layers
        canvasWidth = snap.canvasWidth
        canvasHeight = snap.canvasHeight
        selection = snap.selection
        activeLayerID = snap.activeLayerID
        pendingTransform = SelectionTransform()
        floatingLayer = nil
        pixelMovePreview = nil
        originalMoveBuffer = nil
        originalMoveBounds = nil
        coalesceKey = nil
        recomposite()
        if tool == .move { beginMoveTransform() }
    }
}
