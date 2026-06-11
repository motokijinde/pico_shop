import SwiftUI

// MARK: - 新規ファイルダイアログ（仕様 4-1-1）

struct NewFileDialog: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var widthText = "1024"
    @State private var heightText = "768"
    @State private var transparent = true
    @State private var bgColor = PixelColor.white

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新規ファイル")
                .font(.headline)

            HStack(spacing: 8) {
                NumberField(label: "幅", text: $widthText, width: 64)
                NumberField(label: "高さ", text: $heightText, width: 64)
                Text("px").font(.caption).foregroundStyle(.secondary)
            }

            Picker("背景", selection: $transparent) {
                Text("透明").tag(true)
                Text("単色").tag(false)
            }
            .pickerStyle(.radioGroup)

            if !transparent {
                ColorPicker("背景色", selection: $bgColor.swiftUIColor, supportsOpacity: false)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("作成") {
                    let w = Int(widthText) ?? 1024
                    let h = Int(heightText) ?? 768
                    model.newDocument(width: w, height: h,
                                      background: transparent ? .clear : bgColor)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - キャンバスサイズダイアログ（仕様 6-1）

struct CanvasSizeDialog: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var widthText = ""
    @State private var heightText = ""
    @State private var anchor = 4  // 中央

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("キャンバスサイズ変更")
                .font(.headline)

            HStack(spacing: 8) {
                NumberField(label: "幅", text: $widthText, width: 64)
                NumberField(label: "高さ", text: $heightText, width: 64)
                Text("px").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("アンカーポイント（基準点）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AnchorGrid(anchor: $anchor)
            }

            HStack {
                Button("リセット") {
                    widthText = String(model.canvasWidth)
                    heightText = String(model.canvasHeight)
                    anchor = 4
                }
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("適用") {
                    if let w = Int(widthText), let h = Int(heightText), w > 0, h > 0 {
                        // アンカー＝既存コンテンツが新キャンバスのどこに残るか。
                        // resizeCanvas はアンカー位置からの拡縮なので反転は不要
                        model.resizeCanvas(width: w, height: h, anchor: anchor)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            widthText = String(model.canvasWidth)
            heightText = String(model.canvasHeight)
        }
    }
}

// MARK: - 選択範囲の変更ダイアログ（仕様 7-6）

struct ModifySelectionDialog: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var grow = true
    @State private var pixelsText = "8"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("選択範囲の変更")
                .font(.headline)

            Picker("", selection: $grow) {
                Text("拡大").tag(true)
                Text("縮小").tag(false)
            }
            .pickerStyle(.radioGroup)

            HStack {
                NumberField(label: "ピクセル数", text: $pixelsText, width: 56)
                Text("px").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("適用") {
                    if let px = Int(pixelsText), px > 0 {
                        if grow {
                            model.growSelection(by: px)
                        } else {
                            model.shrinkSelection(by: px)
                        }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear { pixelsText = String(model.lastGrowShrinkAmount) }
    }
}

// MARK: - エクスポートダイアログ（仕様 4-1-4）

struct ExportDialog: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var fileName = "project"
    @State private var format = ExportFormat.png
    @State private var sizeMode = ExportSizeMode.canvas
    @State private var jpegQuality: Double = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("エクスポート")
                .font(.headline)

            HStack {
                Text("ファイル名")
                    .font(.caption)
                TextField("", text: $fileName)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("形式", selection: $format) {
                ForEach(ExportFormat.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.radioGroup)

            Picker("出力サイズ", selection: $sizeMode) {
                ForEach(ExportSizeMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.radioGroup)

            if format == .jpeg {
                HStack {
                    Text("品質")
                        .font(.caption)
                    Slider(value: $jpegQuality, in: 1...100)
                    Text("\(Int(jpegQuality))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }
            }

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("エクスポート") {
                    dismiss()
                    model.exportImage(format: format, sizeMode: sizeMode,
                                      jpegQuality: jpegQuality, fileName: fileName)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            if let url = model.projectURL {
                fileName = url.deletingPathExtension().lastPathComponent
            }
        }
    }
}
