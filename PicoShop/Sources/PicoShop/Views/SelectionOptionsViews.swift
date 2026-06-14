import SwiftUI

// MARK: - 矩形選択（仕様 7-3）
// W/H/X/Y フィールドは選択変形ツールに移動

struct RectSelectOptionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelectionModeButtons()

            OptionSection(title: "矩形選択") {
                Text("キャンバス上をドラッグして矩形を選択します")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("アスペクト比維持", isOn: $model.rectSelKeepAspect)
                    .font(.caption)
                    .controlSize(.small)
                Toggle("中央から選択", isOn: $model.rectSelFromCenter)
                    .font(.caption)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - フリーハンド選択（仕様 7-3）

struct FreehandSelectOptionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelectionModeButtons()

            OptionSection(title: "フリーハンド選択") {
                Text("キャンバス上をドラッグして\n自由な形で選択します")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 色域選択

struct ColorRangeSelectOptionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelectionModeButtons()

            OptionSection(title: "色域選択") {
                sliderRow(label: "Level",
                          value: $model.colorRangeOpts.level,
                          range: 1...100)
                sliderRow(label: "境界調整",
                          value: $model.colorRangeOpts.boundaryAdjust,
                          range: -10...10,
                          hint: "← 縮小   拡大 →")

                Toggle("隣接のみ", isOn: $model.colorRangeOpts.contiguous)
                    .font(.caption)
                    .controlSize(.small)

                HStack(spacing: 6) {
                    Button("Reset") {
                        model.colorRangeOpts.level = 30
                        model.colorRangeOpts.boundaryAdjust = 0
                    }
                    .controlSize(.small)

                    Button("再実行") { model.retryColorRangeSelection() }
                        .controlSize(.small)
                        .disabled(model.colorRangeLastPoint == nil)

                    Spacer()

                    if model.colorRangePreviewOn {
                        Button("プレビュー中") { model.colorRangePreviewOn.toggle() }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("B&Wプレビュー") { model.colorRangePreviewOn.toggle() }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                    }
                }

                Text("ヒント: キャンバスをクリックすると\nその色で選択を実行します")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sliderRow(label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .frame(width: 44, alignment: .leading)
                Slider(value: value, in: range)
                    .controlSize(.mini)
                Text("\(Int(value.wrappedValue))")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            }
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 48)
            }
        }
    }
}

// MARK: - マスクブラシ（仕様 7-4）

struct MaskBrushOptionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "マスクブラシ") {
            Picker("", selection: $model.brushOpts.add) {
                Text("追加").tag(true)
                Text("削除").tag(false)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            sliderRow("サイズ",    $model.brushOpts.size,     1...100, "px")
            sliderRow("硬さ",      $model.brushOpts.hardness,  0...100, "%")
            sliderRow("不透明度",  $model.brushOpts.opacity,   0...100, "%")
        }
    }

    private func sliderRow(_ label: String, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>, _ unit: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.mini)
            Text("\(Int(value.wrappedValue))\(unit)")
                .font(.caption2.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}
