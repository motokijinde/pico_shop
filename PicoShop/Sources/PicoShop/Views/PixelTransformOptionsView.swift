import SwiftUI

// MARK: - 変形ツール（選択内ピクセルまたはレイヤー全体を変形）

struct TransformToolOptionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        PixelTransformPanel()
    }
}

struct PixelTransformPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var wText = ""
    @State private var hText = ""
    @State private var xText = ""
    @State private var yText = ""
    @State private var rotText = ""

    private var baseBounds: CGRect? {
        if let sel = model.selectionBaseBounds { return sel }
        guard let layer = model.activeLayer else { return nil }
        return CGRect(x: CGFloat(layer.offsetX), y: CGFloat(layer.offsetY),
                      width: CGFloat(layer.buffer.width), height: CGFloat(layer.buffer.height))
    }

    var body: some View {
        OptionSection(title: "変形") {
            if let b = baseBounds {
                Text(model.selection == nil
                     ? "レイヤー: \(Int(b.width)) × \(Int(b.height)) px"
                     : "選択: \(Int(b.width)) × \(Int(b.height)) px")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    NumberField(label: "幅", text: $wText, width: 48) { commitSize(.width) }
                    NumberField(label: "高さ", text: $hText, width: 48) { commitSize(.height) }
                }
                HStack(spacing: 6) {
                    NumberField(label: "X", text: $xText, width: 48) { commitPosition() }
                    NumberField(label: "Y", text: $yText, width: 48) { commitPosition() }
                }
                NumberField(label: "回転(°)", text: $rotText, width: 48) { commitRotation() }
                Toggle("アスペクト比維持", isOn: $model.transformKeepAspect)
                    .font(.caption)
                    .controlSize(.small)
            } else {
                Text("レイヤーがありません")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { sync() }
        .onChange(of: model.pendingTransform) { sync() }
        .onChange(of: model.selection?.bounds()) { sync() }
        .onChange(of: model.activeLayerID) { sync() }
    }

    private func sync() {
        guard let b = baseBounds else { return }
        let fields = TransformFieldMath.snapshot(base: b, transform: model.pendingTransform)
        wText = fields.widthText
        hText = fields.heightText
        xText = fields.xText
        yText = fields.yText
        rotText = fields.rotationText
    }

    private func commitSize(_ edited: TransformDimension) {
        guard let b = baseBounds,
              let next = TransformFieldMath.resizing(base: b, current: model.pendingTransform,
                                                     edited: edited, widthText: wText, heightText: hText,
                                                     keepAspect: model.transformKeepAspect) else { return }
        model.pendingTransform = next
        sync()
    }

    private func commitPosition() {
        guard let b = baseBounds,
              let next = TransformFieldMath.repositioning(base: b, current: model.pendingTransform,
                                                          xText: xText, yText: yText) else { return }
        model.pendingTransform = next
    }

    private func commitRotation() {
        guard let next = TransformFieldMath.rotating(current: model.pendingTransform,
                                                     rotationText: rotText) else { return }
        model.pendingTransform = next
    }
}
