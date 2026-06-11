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

// MARK: - ルーペキャンバス（クロップ描画）

private struct LoupeCanvasView: View {
    @EnvironmentObject var model: AppModel
    let size: CGFloat

    /// カーソル位置（キャンバス外なら境界にクランプ）
    private var cursorPos: CGPoint {
        let p = model.mouseCanvasPos ?? model.canvasCenter
        return CGPoint(
            x: min(max(p.x, 0), CGFloat(model.canvasWidth) - 0.001),
            y: min(max(p.y, 0), CGFloat(model.canvasHeight) - 0.001)
        )
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let factor = CGFloat(model.loupeZoom) / 100
            let p = cursorPos

            // 背景チェッカー
            drawCheckerboard(&ctx, in: CGRect(origin: .zero, size: canvasSize), tile: 8)

            guard let img = model.composite else { return }
            let b = model.compositeBounds

            // カーソル周辺のキャンバス領域（canvas座標）
            let cropW = canvasSize.width / factor
            let cropH = canvasSize.height / factor
            let cropCanvas = CGRect(
                x: p.x - cropW / 2,
                y: p.y - cropH / 2,
                width: cropW,
                height: cropH
            )

            // composite画像上のピクセル矩形（切り出し範囲）
            let scaleX = CGFloat(img.width)  / b.width
            let scaleY = CGFloat(img.height) / b.height
            let imgCropRect = CGRect(
                x: (cropCanvas.minX - b.minX) * scaleX,
                y: (cropCanvas.minY - b.minY) * scaleY,
                width: cropW * scaleX,
                height: cropH * scaleY
            ).integral

            // クランプ（画像外を除外）
            let clampedCrop = imgCropRect.intersection(
                CGRect(x: 0, y: 0, width: img.width, height: img.height)
            )

            if !clampedCrop.isNull, clampedCrop.width > 0, clampedCrop.height > 0,
               let cropped = img.cropping(to: clampedCrop) {
                // クロップ画像を補間なし（ドット感維持）で描画
                ctx.withCGContext { cg in
                    cg.interpolationQuality = .none
                    cg.saveGState()
                    // CGContextはy-up座標系なので反転
                    cg.translateBy(x: 0, y: canvasSize.height)
                    cg.scaleBy(x: 1, y: -1)
                    // クロップ範囲がカーソルより左上にある場合のオフセット
                    let drawX = (clampedCrop.minX - imgCropRect.minX) / scaleX * factor
                    let drawY = (clampedCrop.minY - imgCropRect.minY) / scaleY * factor
                    let drawW = clampedCrop.width  / scaleX * factor
                    let drawH = clampedCrop.height / scaleY * factor
                    cg.draw(cropped, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
                    cg.restoreGState()
                }
            }

            // ピクセルグリッド（200% 以上で表示）
            if factor >= 2 {
                let pixW = canvasSize.width / factor
                let pixH = canvasSize.height / factor
                var grid = Path()
                var gx: CGFloat = fmod(canvasSize.width / 2, factor)
                while gx < canvasSize.width {
                    grid.move(to: CGPoint(x: gx, y: 0))
                    grid.addLine(to: CGPoint(x: gx, y: canvasSize.height))
                    gx += factor
                }
                var gy: CGFloat = fmod(canvasSize.height / 2, factor)
                while gy < canvasSize.height {
                    grid.move(to: CGPoint(x: 0, y: gy))
                    grid.addLine(to: CGPoint(x: canvasSize.width, y: gy))
                    gy += factor
                }
                ctx.stroke(grid, with: .color(Color.gray.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 0.5))
                let _ = (pixW, pixH)
            }

            // 中央の十字マーカー
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            var marker = Path()
            marker.move(to: CGPoint(x: cx - 10, y: cy))
            marker.addLine(to: CGPoint(x: cx + 10, y: cy))
            marker.move(to: CGPoint(x: cx, y: cy - 10))
            marker.addLine(to: CGPoint(x: cx, y: cy + 10))
            marker.addEllipse(in: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10))
            ctx.stroke(marker, with: .color(.red), lineWidth: 1.5)

            // 座標・RGB 情報をキャンバス下部に重ねて描画
            let px = Int(p.x.rounded(.down)), py = Int(p.y.rounded(.down))
            let color = model.compositeColor(atCanvas: p)
            let info: String
            if let c = color {
                info = "X:\(px) Y:\(py)  RGB:\(c.r),\(c.g),\(c.b)  \(c.hexString)"
            } else {
                info = "X:\(px) Y:\(py)"
            }
            ctx.draw(
                Text(info)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(.white),
                at: CGPoint(x: 4, y: canvasSize.height - 4),
                anchor: .bottomLeading
            )
        }
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
