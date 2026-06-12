import SwiftUI

// MARK: - ホバー状態（AppModel から分離）
//
// マウス座標はイベントレートが高い（最大120Hz）ため、AppModel の @Published に置くと
// アプリ全体のビューが毎回再評価されてルーペ遅延の原因になる。
// 専用の ObservableObject に分離し、観測するのはステータスバーの座標表示だけにする。
// Metal ビュー（キャンバス・ルーペ）は draw() 時にここを直接読む（latest-wins）。

@MainActor
final class HoverState: ObservableObject {
    /// マウスのキャンバスピクセル座標（キャンバス外・非ホバー時は nil）
    @Published var mouseCanvasPos: CGPoint?
}
