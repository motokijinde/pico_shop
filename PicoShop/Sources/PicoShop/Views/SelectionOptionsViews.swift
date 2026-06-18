import SwiftUI

// MARK: - マスクブラシ（仕様 7-4）

struct MaskBrushOptionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var redrawToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionSection(title: "マスクブラシ") {
                sliderRow("サイズ",    $model.brushOpts.size,     1...100, "px")
                sliderRow("硬さ",      $model.brushOpts.hardness,  0...100, "%")
                sliderRow("不透明度",  $model.brushOpts.opacity,   0...100, "%")
            }
        }
        .buttonStyle(.plain)
        .id(redrawToken)
        .onAppear { redrawToken.toggle() }
    }

    private func sliderRow(_ label: String, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>, _ unit: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.small)
            Text("\(Int(value.wrappedValue))\(unit)")
                .font(.caption2.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}
