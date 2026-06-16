import SwiftUI

private let detailLabelGap: CGFloat  = 2   // ラベルと数値の間隔（X/Y で統一）
private let detailGroupGap: CGFloat  = 8   // X/Y 各組どうしの間隔（ラベル間隔より広め）
private let detailXYValueW: CGFloat  = 40  // X/Y 値の幅

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
            detailRow(label: "画像サイズ", value: "\(layer.buffer.width) × \(layer.buffer.height) px")
            HStack(spacing: 6) {
                detailLabel("位置")
                HStack(spacing: detailGroupGap) {
                    fixedValue("X", String(layer.offsetX), valueWidth: detailXYValueW)
                    fixedValue("Y", String(layer.offsetY), valueWidth: detailXYValueW)
                }
            }
            .lineLimit(1)

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
                        model.commitMoveTransformIfNeeded {
                            model.pushUndo("レイヤーの移動")
                            model.updateLayer(layer.id) { $0.offsetX = v }
                        }
                    }
                }
                NumberField(label: "Y", text: $offsetYText, width: 48) {
                    if let v = Int(offsetYText) {
                        model.commitMoveTransformIfNeeded {
                            model.pushUndo("レイヤーの移動")
                            model.updateLayer(layer.id) { $0.offsetY = v }
                        }
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

    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            detailLabel(label)
            Text(value)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func detailLabel(_ label: String) -> some View {
        Text(label)
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .leading)
            .font(.caption2.monospacedDigit())
    }

    private func fixedValue(_ label: String, _ value: String, valueWidth: CGFloat) -> some View {
        HStack(spacing: detailLabelGap) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 9, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .frame(width: valueWidth, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
    }
}
