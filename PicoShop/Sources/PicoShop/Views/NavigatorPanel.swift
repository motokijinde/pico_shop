import SwiftUI

// MARK: - ナビゲーターパネル（仕様 5-0）

struct NavigatorPanel: View {
    @EnvironmentObject var model: AppModel

    private let thumbHeight: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

        }
        .padding(8)
    }
}
