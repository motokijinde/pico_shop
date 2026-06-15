import SwiftUI

// MARK: - ナビゲーターパネル（仕様 5-0）

private struct NavButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 22)
                .background(
                    isHovered ? Color.secondary.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

struct NavigatorPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ナビゲーター")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let b = model.compositeBounds
                let scale = min(geo.size.width / max(1, b.width), geo.size.height / max(1, b.height))
                let thumbSize = CGSize(width: b.width * scale, height: b.height * scale)
                let origin = CGPoint(x: (geo.size.width - thumbSize.width) / 2,
                                     y: (geo.size.height - thumbSize.height) / 2)

                // サムネイルと赤枠（可視範囲）は Metal で描画
                NavigatorMetalView()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            // ドラッグ位置のキャンバス座標をビュー中心へスクロール
                            let cx = (v.location.x - origin.x) / scale + b.minX
                            let cy = (v.location.y - origin.y) / scale + b.minY
                            model.scrollTo(canvasPoint: CGPoint(x: cx, y: cy))
                        }
                )
            }
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Divider()

            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    NavButton(systemName: "minus.magnifyingglass", help: "ズームアウト") { model.zoomOut() }

                    Text(String(format: "%d%%", Int((model.zoom * 100).rounded())))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(minWidth: 46, alignment: .center)

                    NavButton(systemName: "plus.magnifyingglass", help: "ズームイン") { model.zoomIn() }
                }

                Spacer()

                HStack(spacing: 4) {
                    NavButton(systemName: "arrow.down.right.and.arrow.up.left", help: "全体表示") { model.fitToView() }
                    NavButton(systemName: "1.square", help: "等倍表示") { model.zoomActualSize() }
                }
            }
        }
        .padding(8)
    }
}
