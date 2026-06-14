import SwiftUI

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
