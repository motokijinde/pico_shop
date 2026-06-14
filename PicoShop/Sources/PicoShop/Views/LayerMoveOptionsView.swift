import SwiftUI

// MARK: - レイヤー移動ツール

struct LayerMoveToolOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "レイヤー移動") {
            Text("選択範囲に関わらず\nアクティブレイヤー全体を移動します（非破壊）")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("カーソルキー: 1px 移動")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

