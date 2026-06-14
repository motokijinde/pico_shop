import SwiftUI

// MARK: - サイドパネル（ナビゲーター + レイヤー + オプション）

struct SidePanelView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NavigatorPanel()
            Divider()
            if model.showLayersPanel {
                LayerPalette()
                Divider()
            }
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
