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

// MARK: - 選択変形ツール
// 選択マスクの移動・リサイズ・回転。W/H/X/Y は即時反映。
// バウンディングボックスドラッグはドロップ時に自動適用。

struct SelectionTransformOptionsView: View {
    @EnvironmentObject var model: AppModel
    @State private var wText = ""
    @State private var hText = ""
    @State private var xText = ""
    @State private var yText = ""
    @State private var rotText = ""

    private var baseBounds: CGRect? {
        if let b = model.selectionBaseBounds { return b }
        guard let layer = model.activeLayer else { return nil }
        return CGRect(x: CGFloat(layer.offsetX), y: CGFloat(layer.offsetY),
                      width: CGFloat(layer.buffer.width), height: CGFloat(layer.buffer.height))
    }

    var body: some View {
        OptionSection(title: "選択変形") {
            if baseBounds != nil {
                HStack(spacing: 6) {
                    NumberField(label: "X",  text: $xText, width: 48, labelWidth: 20) { commitPosition() }
                    NumberField(label: "Y",  text: $yText, width: 48, labelWidth: 20) { commitPosition() }
                }
                HStack(spacing: 6) {
                    NumberField(label: "幅", text: $wText, width: 48, labelWidth: 20) { commitSize() }
                    NumberField(label: "高さ", text: $hText, width: 48, labelWidth: 20) { commitSize() }
                }
                NumberField(label: "回転(°)", text: $rotText, width: 48) {
                    if let v = Double(rotText) {
                        var deg = v.truncatingRemainder(dividingBy: 360)
                        if deg < 0 { deg += 360 }
                        model.pendingTransform.rotation = deg
                    }
                }
                HStack(spacing: 4) {
                    Button("確定") { model.applySelectionTransform() }
                        .disabled(model.pendingTransform.isIdentity)
                    Button("リセット") { model.resetSelectionTransform() }
                        .disabled(model.pendingTransform.isIdentity)
                }
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

    private var transformedRect: CGRect? {
        guard let b = baseBounds else { return nil }
        let t = model.pendingTransform
        let w = b.width * CGFloat(abs(t.scaleX))
        let h = b.height * CGFloat(abs(t.scaleY))
        return CGRect(x: b.midX + CGFloat(t.dx) - w / 2,
                      y: b.midY + CGFloat(t.dy) - h / 2,
                      width: w, height: h)
    }

    private func sync() {
        if let r = transformedRect {
            wText = String(Int(r.width.rounded()))
            hText = String(Int(r.height.rounded()))
            xText = String(Int(r.minX.rounded()))
            yText = String(Int(r.minY.rounded()))
        }
        rotText = String(Int(model.pendingTransform.rotation.rounded()))
    }

    private func commitSize() {
        guard let b = baseBounds, b.width > 0, b.height > 0,
              let w = Double(wText), let h = Double(hText), w >= 1, h >= 1 else { return }
        model.pendingTransform.scaleX = max(0.01, w / Double(b.width))
        model.pendingTransform.scaleY = max(0.01, h / Double(b.height))
    }

    private func commitPosition() {
        guard let b = baseBounds,
              let x = Double(xText), let y = Double(yText) else { return }
        let t = model.pendingTransform
        let w = Double(b.width) * abs(t.scaleX)
        let h = Double(b.height) * abs(t.scaleY)
        model.pendingTransform.dx = x + w / 2 - Double(b.midX)
        model.pendingTransform.dy = y + h / 2 - Double(b.midY)
    }
}

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
                    NumberField(label: "幅", text: $wText, width: 48) { commitSize() }
                    NumberField(label: "高さ", text: $hText, width: 48) { commitSize() }
                }
                HStack(spacing: 6) {
                    NumberField(label: "W%", text: $wPctText, width: 48) { commitPct(fromW: true) }
                    NumberField(label: "H%", text: $hPctText, width: 48) { commitPct(fromW: false) }
                }
                HStack(spacing: 6) {
                    NumberField(label: "X", text: $xText, width: 48) { commitPosition() }
                    NumberField(label: "Y", text: $yText, width: 48) { commitPosition() }
                }
                NumberField(label: "回転(°)", text: $rotText, width: 48) {
                    if var v = Double(rotText) {
                        v = v.truncatingRemainder(dividingBy: 360)
                        if v < 0 { v += 360 }
                        model.pendingTransform.rotation = v
                        model.extractMovePixels()
                        model.rasterizePreview()
                    }
                }
                Toggle("アスペクト比維持", isOn: $model.transformKeepAspect)
                    .font(.caption)
                    .controlSize(.small)

                HStack(spacing: 4) {
                    Button("確定") { model.commitMoveTransform() }
                        .disabled(model.originalMoveBounds == nil)
                    Button("リセット") { model.resetMoveTransform() }
                        .disabled(model.pendingTransform.isIdentity)
                }
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
        let t = model.pendingTransform
        let w = Double(b.width)  * abs(t.scaleX)
        let h = Double(b.height) * abs(t.scaleY)
        let cx = b.midX + t.dx
        let cy = b.midY + t.dy
        wText    = String(Int(w.rounded()))
        hText    = String(Int(h.rounded()))
        wPctText = String(format: "%.1f", abs(t.scaleX) * 100)
        hPctText = String(format: "%.1f", abs(t.scaleY) * 100)
        xText    = String(Int((cx - w / 2).rounded()))
        yText    = String(Int((cy - h / 2).rounded()))
        rotText  = String(Int(t.rotation.rounded()))
    }

    private func commitSize() {
        guard let b = baseBounds, b.width > 0, b.height > 0,
              let w = Double(wText), let h = Double(hText), w >= 1, h >= 1 else { return }
        let sx = w / Double(b.width)
        var sy = h / Double(b.height)
        if model.transformKeepAspect {
            sy = sx
            hText    = String(Int((Double(b.height) * sy).rounded()))
            hPctText = String(format: "%.1f", sy * 100)
        }
        model.pendingTransform.scaleX = max(0.01, sx)
        model.pendingTransform.scaleY = max(0.01, sy)
        model.extractMovePixels()
        model.rasterizePreview()
    }

    private func commitPct(fromW: Bool) {
        guard let b = baseBounds, b.width > 0, b.height > 0 else { return }
        if fromW {
            guard let pct = Double(wPctText), pct >= 0.1 else { return }
            let sx = pct / 100
            model.pendingTransform.scaleX = max(0.01, sx)
            wText = String(Int((Double(b.width) * sx).rounded()))
            if model.transformKeepAspect {
                model.pendingTransform.scaleY = max(0.01, sx)
                hPctText = wPctText
                hText = String(Int((Double(b.height) * sx).rounded()))
            }
        } else {
            guard let pct = Double(hPctText), pct >= 0.1 else { return }
            let sy = pct / 100
            model.pendingTransform.scaleY = max(0.01, sy)
            hText = String(Int((Double(b.height) * sy).rounded()))
            if model.transformKeepAspect {
                model.pendingTransform.scaleX = max(0.01, sy)
                wPctText = hPctText
                wText = String(Int((Double(b.width) * sy).rounded()))
            }
        }
        model.extractMovePixels()
        model.rasterizePreview()
    }

    private func commitPosition() {
        guard let b = baseBounds,
              let x = Double(xText), let y = Double(yText) else { return }
        let t = model.pendingTransform
        let w = Double(b.width)  * abs(t.scaleX)
        let h = Double(b.height) * abs(t.scaleY)
        model.pendingTransform.dx = x + w / 2 - Double(b.midX)
        model.pendingTransform.dy = y + h / 2 - Double(b.midY)
        model.extractMovePixels()
        model.rasterizePreview()
    }
}

// MARK: - レイヤー移動ツール

struct LayerMoveToolOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "レイヤー移動") {
            Text("選択範囲に関わらず\nアクティブレイヤー全体を移動します（非破壊）")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("カーソルキー: 1px 移動")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

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
                    NumberField(label: "幅", text: $wText, width: 48) { commitSize() }
                    NumberField(label: "高さ", text: $hText, width: 48) { commitSize() }
                }
                HStack(spacing: 6) {
                    NumberField(label: "X", text: $xText, width: 48) { commitPosition() }
                    NumberField(label: "Y", text: $yText, width: 48) { commitPosition() }
                }
                NumberField(label: "回転(°)", text: $rotText, width: 48) {
                    if let v = Double(rotText) {
                        model.pendingTransform.rotation = v.truncatingRemainder(dividingBy: 360)
                    }
                }
                Toggle("アスペクト比維持", isOn: $model.transformKeepAspect)
                    .font(.caption)
                    .controlSize(.small)

                HStack(spacing: 4) {
                    Button("適用") { model.applyPixelTransform() }
                        .disabled(model.pendingTransform.isIdentity)
                    Button("リセット") { model.resetSelectionTransform() }
                        .disabled(model.pendingTransform.isIdentity)
                }
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

    private var transformedRect: CGRect? {
        guard let b = baseBounds else { return nil }
        let t = model.pendingTransform
        let w = b.width * CGFloat(abs(t.scaleX))
        let h = b.height * CGFloat(abs(t.scaleY))
        return CGRect(x: b.midX + CGFloat(t.dx) - w / 2,
                      y: b.midY + CGFloat(t.dy) - h / 2,
                      width: w, height: h)
    }

    private func sync() {
        guard let r = transformedRect else { return }
        wText   = String(Int(r.width.rounded()))
        hText   = String(Int(r.height.rounded()))
        xText   = String(Int(r.minX.rounded()))
        yText   = String(Int(r.minY.rounded()))
        rotText = String(Int(model.pendingTransform.rotation.rounded()))
    }

    private func commitSize() {
        guard let b = baseBounds, b.width > 0, b.height > 0,
              let w = Double(wText), let h = Double(hText), w >= 1, h >= 1 else { return }
        let sx = w / Double(b.width)
        var sy = h / Double(b.height)
        if model.transformKeepAspect {
            sy = sx
            hText = String(Int((Double(b.height) * sy).rounded()))
        }
        model.pendingTransform.scaleX = max(0.01, sx)
        model.pendingTransform.scaleY = max(0.01, sy)
    }

    private func commitPosition() {
        guard let b = baseBounds,
              let x = Double(xText), let y = Double(yText) else { return }
        let t = model.pendingTransform
        let w = Double(b.width) * abs(t.scaleX)
        let h = Double(b.height) * abs(t.scaleY)
        model.pendingTransform.dx = x + w / 2 - Double(b.midX)
        model.pendingTransform.dy = y + h / 2 - Double(b.midY)
    }
}

// MARK: - 塗りつぶしツール（仕様 8-2）

struct FillToolOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "塗りつぶし") {
            ColorPicker("塗色", selection: $model.fillOpts.color.swiftUIColor)
                .font(.caption)

            Picker("範囲", selection: $model.fillOpts.scope) {
                ForEach(FillOptions.Scope.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.radioGroup)
            .font(.caption)
            .controlSize(.small)

            Toggle("アンチエイリアス", isOn: $model.fillOpts.antialias)
                .font(.caption)
                .controlSize(.small)

            HStack(spacing: 4) {
                Text("許容度")
                    .font(.caption2)
                    .frame(width: 44, alignment: .leading)
                Slider(value: $model.fillOpts.tolerance, in: 0...100)
                    .controlSize(.mini)
                Text("\(Int(model.fillOpts.tolerance))")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
            }

            if model.fillOpts.scope == .selection {
                Button("選択範囲を塗りつぶし") { model.fillSelection() }
                    .controlSize(.small)
            } else {
                Text("キャンバスをクリックすると\n隣接する類似色を塗りつぶします")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - リサイズツール（仕様 8-3）

struct ResizeToolOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "リサイズ") {
            if model.selection == nil, let layer = model.activeLayer {
                Text("元: \(layer.buffer.width) × \(layer.buffer.height) px")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let b = model.selectionBaseBounds {
                Text("選択範囲: \(Int(b.width)) × \(Int(b.height)) px")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            NumberField(label: "拡大率(%)", text: $model.resizeOpts.scalePercent, width: 52) {
                applyScalePercent()
            }
            HStack(spacing: 6) {
                NumberField(label: "幅", text: $model.resizeOpts.widthText, width: 48) {
                    syncFromWidth()
                }
                NumberField(label: "高さ", text: $model.resizeOpts.heightText, width: 48) {
                    syncFromHeight()
                }
            }
            Toggle("比率を維持", isOn: $model.resizeOpts.keepAspect)
                .font(.caption)
                .controlSize(.small)

            Picker("補間", selection: $model.resizeOpts.quality) {
                ForEach(ResampleQuality.allCases) { q in
                    Text(q.rawValue).tag(q)
                }
            }
            .font(.caption)
            .controlSize(.small)

            HStack(spacing: 4) {
                Button("確定") { commit() }
                Button("キャンセル") { syncCurrent() }
            }
            .controlSize(.small)
        }
        .onAppear { syncCurrent() }
        .onChange(of: model.activeLayerID) { syncCurrent() }
    }

    private var baseSize: (w: Int, h: Int)? {
        if let b = model.selectionBaseBounds {
            return (Int(b.width), Int(b.height))
        }
        guard let layer = model.activeLayer else { return nil }
        return (layer.buffer.width, layer.buffer.height)
    }

    private func syncCurrent() {
        guard let s = baseSize else { return }
        model.resizeOpts.widthText = String(s.w)
        model.resizeOpts.heightText = String(s.h)
        model.resizeOpts.scalePercent = "100"
    }

    private func applyScalePercent() {
        guard let s = baseSize, let pct = Double(model.resizeOpts.scalePercent), pct > 0 else { return }
        model.resizeOpts.widthText  = String(max(1, Int((Double(s.w) * pct / 100).rounded())))
        model.resizeOpts.heightText = String(max(1, Int((Double(s.h) * pct / 100).rounded())))
    }

    private func syncFromWidth() {
        guard let s = baseSize, let w = Double(model.resizeOpts.widthText), w > 0 else { return }
        let pct = w / Double(s.w) * 100
        model.resizeOpts.scalePercent = String(Int(pct.rounded()))
        if model.resizeOpts.keepAspect {
            model.resizeOpts.heightText = String(max(1, Int((Double(s.h) * pct / 100).rounded())))
        }
    }

    private func syncFromHeight() {
        guard let s = baseSize, let h = Double(model.resizeOpts.heightText), h > 0 else { return }
        let pct = h / Double(s.h) * 100
        model.resizeOpts.scalePercent = String(Int(pct.rounded()))
        if model.resizeOpts.keepAspect {
            model.resizeOpts.widthText = String(max(1, Int((Double(s.w) * pct / 100).rounded())))
        }
    }

    private func commit() {
        guard let w = Int(model.resizeOpts.widthText),
              let h = Int(model.resizeOpts.heightText), w > 0, h > 0 else {
            model.warn("サイズが不正です")
            return
        }
        model.resizeActiveLayer(width: w, height: h)
        syncCurrent()
    }
}

// MARK: - テキストツール（仕様 9）

struct TextToolOptions: View {
    @EnvironmentObject var model: AppModel

    private static let fontFamilies = TextRenderer.availableFamilies

    var body: some View {
        OptionSection(title: "テキスト") {
            Picker("フォント", selection: $model.textOpts.fontFamily) {
                ForEach(Self.fontFamilies, id: \.self) { f in
                    Text(f).tag(f)
                }
            }
            .font(.caption)
            .controlSize(.small)

            HStack(spacing: 6) {
                NumberField(label: "サイズ", text: $model.textOpts.sizeText, width: 44)
                Picker("", selection: $model.textOpts.weight) {
                    ForEach(TextWeight.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .controlSize(.small)
                .frame(width: 90)
            }

            ColorPicker("色", selection: $model.textOpts.color.swiftUIColor)
                .font(.caption)

            Toggle("アンチエイリアス", isOn: $model.textOpts.antialias)
                .font(.caption)
                .controlSize(.small)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("配置基準")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    AnchorGrid(anchor: $model.textOpts.anchor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    NumberField(label: "X", text: $model.textOpts.xText, width: 48)
                    NumberField(label: "Y", text: $model.textOpts.yText, width: 48)
                }
            }

            Text("テキスト（キャンバスのクリックで位置指定）")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextEditor(text: $model.textOpts.text)
                .font(.body)
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))

            Button("確定（レイヤーに追加）") { model.commitText() }
                .controlSize(.small)
        }
    }
}

// MARK: - クロップツール（仕様 10-2）

// MARK: - 回転ツール（仕様 10-3）

struct RotateToolOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "回転") {
            NumberField(label: "角度(°)", text: $model.rotateOpts.angleText, width: 52) {
                applyAngle()
            }
            HStack(spacing: 4) {
                Button("90°")  { model.rotate(byDegrees: 90) }
                Button("-90°") { model.rotate(byDegrees: -90) }
                Button("180°") { model.rotate(byDegrees: 180) }
            }
            .controlSize(.small)
            Button("適用") { applyAngle() }
                .controlSize(.small)
        }
    }

    private func applyAngle() {
        guard let deg = Double(model.rotateOpts.angleText), deg != 0 else { return }
        model.rotate(byDegrees: deg)
    }
}

// MARK: - 反転ツール（仕様 10-4）

struct FlipToolOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "反転") {
            HStack(spacing: 4) {
                Button("水平反転") { model.flip(horizontal: true) }
                Button("垂直反転") { model.flip(horizontal: false) }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - スポイト（仕様 10-5）

struct EyedropperOptions: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        OptionSection(title: "スポイト") {
            Text("キャンバスをクリックして色を取得")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: model.foregroundColor.nsColor))
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5)))
                VStack(alignment: .leading) {
                    Text(model.foregroundColor.hexString)
                        .font(.caption.monospaced())
                    Text("R:\(model.foregroundColor.r) G:\(model.foregroundColor.g) B:\(model.foregroundColor.b)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
