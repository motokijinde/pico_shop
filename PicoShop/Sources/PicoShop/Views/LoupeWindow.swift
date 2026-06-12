import SwiftUI
import AppKit

// MARK: - ルーペオーバーレイ（メインウィンドウ内フローティングパネル）

private let loupeSmallSize: CGFloat = 160
private let loupeLargeSize: CGFloat = 240

struct LoupeOverlayView: View {
    @EnvironmentObject var model: AppModel
    @State private var dragOffset: CGSize = .zero

    private var canvasSize: CGFloat {
        model.loupeIsLarge ? loupeLargeSize : loupeSmallSize
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            LoupeCanvasView(size: canvasSize)
                .frame(width: canvasSize, height: canvasSize)
        }
        .fixedSize()
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
    }

    private var titleBar: some View {
        HStack(spacing: 6) {
            Text("ルーペ")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            // サイズ切り替えボタン
            Button {
                model.loupeIsLarge.toggle()
            } label: {
                Image(systemName: model.loupeIsLarge ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(model.loupeIsLarge ? "小さくする" : "大きくする")

            Button {
                model.showLoupe = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("ルーペを閉じる")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
        // タイトルバーをドラッグして移動
        .gesture(
            DragGesture()
                .onChanged { v in
                    model.loupePosition = CGPoint(
                        x: model.loupePosition.x + v.translation.width  - dragOffset.width,
                        y: model.loupePosition.y + v.translation.height - dragOffset.height
                    )
                    dragOffset = v.translation
                }
                .onEnded { _ in dragOffset = .zero }
        )
    }
}

// MARK: - ルーペキャンバス（Metal 描画 + ズームピッカー）

private struct LoupeCanvasView: View {
    @EnvironmentObject var model: AppModel
    let size: CGFloat

    var body: some View {
        LoupeMetalView()
            // ズーム切り替えのピッカー
            .overlay(alignment: .topTrailing) {
                Picker("", selection: $model.loupeZoom) {
                    Text("1×").tag(100)
                    Text("2×").tag(200)
                    Text("4×").tag(400)
                    Text("8×").tag(800)
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 110)
                .padding(4)
            }
            .background(Color.black)
    }
}
