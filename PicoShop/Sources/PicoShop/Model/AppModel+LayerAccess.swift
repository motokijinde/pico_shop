import SwiftUI
import AppKit

extension AppModel {

    // MARK: - レイヤーアクセス

    var activeLayer: Layer? {
        guard let id = activeLayerID else { return nil }
        return layers.first { $0.id == id }
    }

    var activeLayerIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return layers.firstIndex { $0.id == id }
    }

    /// アクティブレイヤーを変更（ロック検査つき）。ロック中なら警告して false。
    func withActiveLayer(checkLock: Bool = true, _ body: (inout Layer) -> Void) -> Bool {
        guard let idx = activeLayerIndex else {
            warn("レイヤーが選択されていません")
            return false
        }
        if checkLock && layers[idx].locked {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return false
        }
        body(&layers[idx])
        return true
    }

    /// 手動マスク編集の開始（選択がなければ空のマスクを作る）
    func beginBrushStroke() {
        pushUndo("手動マスク編集", coalesceKey: "brush")
        if selection == nil {
            selection = SelectionMask(width: canvasWidth, height: canvasHeight)
        }
    }

    func warn(_ message: String) {
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }
}
