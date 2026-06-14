import SwiftUI

// MARK: - オプションパネル（ツールごとの詳細設定）

struct OptionsPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("オプション: \(model.tool.displayName)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            switch model.tool {
            case .rectSelect:         RectSelectOptionsView()
            case .freehandSelect:     FreehandSelectOptionsView()
            case .colorRangeSelect:   ColorRangeSelectOptionsView()
            case .maskBrush:          MaskBrushOptionsView()
            case .selectionTransform: SelectionTransformOptionsView()
            case .move:               MoveTransformPanel()
            case .layerMove:          LayerMoveToolOptions()
            case .transform:          TransformToolOptionsView()
            case .fill:               FillToolOptions()
            case .resize:             ResizeToolOptions()
            case .text:               TextToolOptions()
            case .rotate:             RotateToolOptions()
            case .flip:               FlipToolOptions()
            case .eyedropper:         EyedropperOptions()
            }
        }
    }
}

// MARK: - 選択操作モードボタン（新規・追加・除外）

struct SelectionModeButtons: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SelectionOperationMode.allCases) { mode in
                Button {
                    model.selectionOperationMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 24)
                        .background(
                            model.selectionOperationMode == mode
                                ? Color.accentColor.opacity(0.3)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.displayName)
            }
            Spacer()
            if model.selection != nil {
                Button("選択反転") { model.invertSelection() }
                    .controlSize(.mini)
                    .buttonStyle(.borderless)
            }
        }
    }
}
