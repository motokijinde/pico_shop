import SwiftUI

// MARK: - サイドパネル（オプションのみ。ナビゲーター・レイヤーはフローティング NSPanel）

struct SidePanelView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.showOptionsPanel {
                ScrollView {
                    OptionsPanel()
                        .padding(8)
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
