import SwiftUI

// MARK: - レイヤー詳細（仕様 5-1）

struct LayerDetailView: View {
    @EnvironmentObject var model: AppModel
    let layer: Layer

    @State private var offsetXText = ""
    @State private var offsetYText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("名前: \(layer.name)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("画像サイズ: \(String(layer.buffer.width)) × \(String(layer.buffer.height)) px")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("表示サイズ: \(String(layer.buffer.width)) × \(String(layer.buffer.height)) px")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("合成", selection: Binding(
                get: { layer.blend },
                set: { newValue in model.updateLayer(layer.id) { $0.blend = newValue } }
            )) {
                ForEach(LayerBlendMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .font(.caption)
            .controlSize(.small)

            HStack {
                Text("不透明度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { layer.opacity },
                    set: { newValue in model.updateLayer(layer.id) { $0.opacity = newValue } }
                ), in: 0...100)
                Text("\(Int(layer.opacity))%")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            .controlSize(.mini)

            HStack(spacing: 6) {
                NumberField(label: "X", text: $offsetXText, width: 48) {
                    if let v = Int(offsetXText) {
                        model.pushUndo("レイヤーの移動")
                        model.updateLayer(layer.id) { $0.offsetX = v }
                    }
                }
                NumberField(label: "Y", text: $offsetYText, width: 48) {
                    if let v = Int(offsetYText) {
                        model.pushUndo("レイヤーの移動")
                        model.updateLayer(layer.id) { $0.offsetY = v }
                    }
                }
            }
        }
        .onAppear { syncOffsets() }
        .onChange(of: layer.offsetX) { syncOffsets() }
        .onChange(of: layer.offsetY) { syncOffsets() }
        .onChange(of: layer.id) { syncOffsets() }
    }

    private func syncOffsets() {
        offsetXText = String(layer.offsetX)
        offsetYText = String(layer.offsetY)
    }
}
