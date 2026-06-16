import SwiftUI

// MARK: - 移動ツール

struct MoveTransformPanel: View {
    @EnvironmentObject var model: AppModel
    @State private var wText    = ""
    @State private var hText    = ""
    @State private var wPctText = ""
    @State private var hPctText = ""
    @State private var xText    = ""
    @State private var yText    = ""
    @State private var rotText  = ""

    private var baseBounds: CGRect? { model.originalMoveBounds }

    var body: some View {
        OptionSection(title: "移動") {
            if let b = baseBounds {
                Text("元サイズ: \(Int(b.width)) × \(Int(b.height)) px")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    NumberField(label: "幅", text: $wText, width: 48, labelWidth: 24) { commitSize(.width) }
                    NumberField(label: "高さ", text: $hText, width: 48, labelWidth: 24) { commitSize(.height) }
                }
                HStack(spacing: 6) {
                    NumberField(label: "W%", text: $wPctText, width: 48, labelWidth: 24) { commitPercent(.width) }
                    NumberField(label: "H%", text: $hPctText, width: 48, labelWidth: 24) { commitPercent(.height) }
                }
                HStack(spacing: 6) {
                    NumberField(label: "X", text: $xText, width: 48, labelWidth: 24) { commitPosition() }
                    NumberField(label: "Y", text: $yText, width: 48, labelWidth: 24) { commitPosition() }
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
        .onChange(of: model.originalMoveBounds) { sync() }
    }

    private func sync() {
        guard let b = baseBounds else { return }
        let fields = TransformFieldMath.snapshot(base: b, transform: model.pendingTransform)
        wText = fields.widthText
        hText = fields.heightText
        wPctText = fields.widthPercentText
        hPctText = fields.heightPercentText
        xText = fields.xText
        yText = fields.yText
        rotText = fields.rotationText
    }

    private func commitSize(_ edited: TransformDimension) {
        guard let b = baseBounds,
              let next = TransformFieldMath.resizing(base: b, current: model.pendingTransform,
                                                     edited: edited, widthText: wText, heightText: hText,
                                                     keepAspect: model.transformKeepAspect) else { return }
        applyPreviewTransform(next)
    }

    private func commitPercent(_ edited: TransformDimension) {
        guard let b = baseBounds,
              let next = TransformFieldMath.resizingByPercent(base: b, current: model.pendingTransform,
                                                              edited: edited,
                                                              widthPercentText: wPctText,
                                                              heightPercentText: hPctText,
                                                              keepAspect: model.transformKeepAspect) else { return }
        applyPreviewTransform(next)
    }

    private func commitPosition() {
        guard let b = baseBounds,
              let next = TransformFieldMath.repositioning(base: b, current: model.pendingTransform,
                                                          xText: xText, yText: yText) else { return }
        applyPreviewTransform(next)
    }

    private func commitRotation() {
        guard let next = TransformFieldMath.rotating(current: model.pendingTransform,
                                                     rotationText: rotText) else { return }
        applyPreviewTransform(next)
    }

    private func applyPreviewTransform(_ transform: SelectionTransform) {
        model.pendingTransform = transform
        sync()
        model.extractMovePixels()
        model.rasterizePreview()
    }
}
