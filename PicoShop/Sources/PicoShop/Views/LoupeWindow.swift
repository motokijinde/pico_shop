import SwiftUI
import AppKit

private let loupeInfoBarH: CGFloat = 44
private let loupeMinCanvasW: CGFloat  = 160   // ズームピッカーが収まる最小幅
private let loupeMinCanvasH: CGFloat  = 160   // 最小時にキャンバスが正方形になる高さ

private let loupeLabelGap: CGFloat  = 2   // ラベルと数値の間隔（全組で統一）
private let loupeGroupGap: CGFloat  = 8   // R/G/B/A/X/Y 各組どうしの間隔（ラベル間隔より広め）
private let loupeRGBValueW: CGFloat = 18  // RGBA 値の幅（最大3桁）
private let loupeXYValueW: CGFloat  = 28  // XY 値の幅

// MARK: - パネルコンテンツ

struct LoupePanelContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            LoupeCanvasView()
                .frame(minWidth: loupeMinCanvasW, maxWidth: .infinity, minHeight: loupeMinCanvasH, maxHeight: .infinity)
            Divider()
            LoupeInfoBar(hover: model.hover)
                .frame(minWidth: loupeMinCanvasW, maxWidth: .infinity,
                       minHeight: loupeInfoBarH, maxHeight: loupeInfoBarH)
        }
    }
}

// MARK: - ルーペキャンバス（グリッドボタン＋ズームピッカーオーバーレイ）

private struct LoupeCanvasView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        LoupeMetalView()
            .overlay(alignment: .top) {
                HStack(spacing: 4) {
                    LoupeToggleButton(systemImage: "rectangle.dashed", help: "選択境界", isOn: $model.loupeShowSelection)
                    LoupeToggleButton(systemImage: "square.grid.3x3", help: "グリッド", isOn: $model.loupeShowGrid)
                    Spacer()
                    Picker("", selection: $model.loupeZoom) {
                        Text("1×").tag(100)
                        Text("2×").tag(200)
                        Text("4×").tag(400)
                        Text("8×").tag(800)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 110)
                }
                .padding(4)
            }
            .background(Color.black)
    }
}

// MARK: - ルーペトグルボタン（アイコン・固定サイズ・ホバーエフェクト）

private struct LoupeToggleButton: View {
    let systemImage: String
    let help: String
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(buttonBg, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(isOn ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }

    private var buttonBg: Color {
        if isOn        { return Color.white.opacity(0.9) }
        if isHovering  { return Color.white.opacity(0.3) }
        return Color.black.opacity(0.45)
    }
}

// MARK: - カラー情報バー（色 / 座標）

private struct LoupeInfoBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var hover: HoverState
    @State private var sampledX: Int?
    @State private var sampledY: Int?
    @State private var sampledColor: PixelColor?

    var body: some View {
        let pos = hover.mouseCanvasPos ?? model.canvasCenter
        let px  = Int(pos.x.rounded(.down))
        let py  = Int(pos.y.rounded(.down))
        let c   = sampledColor

        VStack(alignment: .leading, spacing: 4) {
            // 1行目: 色見本 + HEX
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(c.map { Color(nsColor: $0.nsColor) } ?? Color.secondary.opacity(0.15))
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
                    )

                Text(c?.hexString ?? "—")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
            }

            // 2行目: R G B A X Y
            HStack(spacing: loupeGroupGap) {
                fixedValue("R", c.map { String($0.r) } ?? "—", labelColor: .red, valueWidth: loupeRGBValueW)
                fixedValue("G", c.map { String($0.g) } ?? "—", labelColor: Color(nsColor: .systemGreen), valueWidth: loupeRGBValueW)
                fixedValue("B", c.map { String($0.b) } ?? "—", labelColor: .blue, valueWidth: loupeRGBValueW)
                fixedValue("A", c.map { String($0.a) } ?? "—", labelColor: Color(nsColor: .tertiaryLabelColor), valueWidth: loupeRGBValueW)
                fixedValue("X", String(px), labelColor: .secondary, valueWidth: loupeXYValueW)
                fixedValue("Y", String(py), labelColor: .secondary, valueWidth: loupeXYValueW)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { sampleColor(force: true) }
        .onChange(of: hover.mouseCanvasPos) { _, _ in sampleColor(force: false) }
        .onChange(of: model.compositeBounds) { _, _ in sampleColor(force: true) }
        .onReceive(model.objectWillChange) { _ in
            Task { @MainActor in sampleColor(force: true) }
        }
    }

    private func sampleColor(force: Bool) {
        let pos = hover.mouseCanvasPos ?? model.canvasCenter
        let px = Int(pos.x.rounded(.down))
        let py = Int(pos.y.rounded(.down))
        guard force || sampledX != px || sampledY != py else { return }
        sampledX = px
        sampledY = py
        sampledColor = model.compositeColor(atCanvas: pos)
    }

    private func fixedValue(_ label: String, _ value: String, labelColor: Color, valueWidth: CGFloat) -> some View {
        HStack(spacing: loupeLabelGap) {
            Text(label)
                .foregroundStyle(labelColor)
                .frame(width: 9, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .frame(width: valueWidth, alignment: .leading)
        }
        .font(.system(size: 9).monospacedDigit())
    }
}
