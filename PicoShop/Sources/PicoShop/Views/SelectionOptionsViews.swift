import SwiftUI

// MARK: - マスクブラシ（仕様 7-4）

struct MaskBrushOptionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
