import CoreGraphics
import SwiftUI

/// キャンバス座標系の選択マスク（0–255、128 以上を「選択」とみなす）
struct SelectionMask {
    var width: Int
    var height: Int
    var data: [UInt8]

    init(width: Int, height: Int, data: [UInt8]? = nil) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.data = data ?? [UInt8](repeating: 0, count: self.width * self.height)
    }

    func isSelected(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        return data[y * width + x] >= 128
    }

    /// 選択値（0–255）。カット等でソフトエッジを反映するため
    func value(x: Int, y: Int) -> UInt8 {
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return data[y * width + x]
    }

    var selectedPixelCount: Int {
        data.lazy.filter { $0 >= 128 }.count
    }

    var isEmpty: Bool { !data.contains { $0 >= 128 } }

    /// 選択領域のバウンディングボックス（キャンバス座標）
    func bounds() -> CGRect? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where data[row + x] >= 128 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - 基本操作

    static func all(width: Int, height: Int) -> SelectionMask {
        SelectionMask(width: width, height: height,
                      data: [UInt8](repeating: 255, count: max(1, width) * max(1, height)))
    }

    static func rect(width: Int, height: Int, rect: CGRect) -> SelectionMask {
        var m = SelectionMask(width: width, height: height)
        let x0 = max(0, Int(rect.minX.rounded())), x1 = min(width, Int(rect.maxX.rounded()))
        let y0 = max(0, Int(rect.minY.rounded())), y1 = min(height, Int(rect.maxY.rounded()))
        guard x1 > x0, y1 > y0 else { return m }
        for y in y0..<y1 {
            for x in x0..<x1 { m.data[y * width + x] = 255 }
        }
        return m
    }

    /// フリーハンド（ラッソ）：キャンバス座標の頂点列をポリゴンとして塗りつぶす
    static func polygon(width: Int, height: Int, points: [CGPoint]) -> SelectionMask {
        var m = SelectionMask(width: width, height: height)
        guard points.count >= 3 else { return m }
        m.drawIntoMask { ctx in
            ctx.setShouldAntialias(false)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.move(to: points[0])
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.closePath()
            ctx.fillPath()
        }
        return m
    }

    func inverted() -> SelectionMask {
        var m = self
        for i in 0..<m.data.count { m.data[i] = 255 &- m.data[i] }
        return m
    }

    func translated(dx: Int, dy: Int) -> SelectionMask {
        var m = SelectionMask(width: width, height: height)
        for y in 0..<height {
            let sy = y - dy
            guard sy >= 0, sy < height else { continue }
            for x in 0..<width {
                let sx = x - dx
                guard sx >= 0, sx < width else { continue }
                m.data[y * width + x] = data[sy * width + sx]
            }
        }
        return m
    }

    /// 拡大（dilate）/ 縮小（erode）。4近傍を px 回反復
    func grown(by px: Int) -> SelectionMask {
        var m = binarized()
        for _ in 0..<max(0, px) {
            var next = m.data
            for y in 0..<height {
                for x in 0..<width where m.data[y * width + x] < 128 {
                    if m.isSelected(x: x - 1, y: y) || m.isSelected(x: x + 1, y: y)
                        || m.isSelected(x: x, y: y - 1) || m.isSelected(x: x, y: y + 1) {
                        next[y * width + x] = 255
                    }
                }
            }
            m.data = next
        }
        return m
    }

    func shrunk(by px: Int) -> SelectionMask {
        var m = binarized()
        for _ in 0..<max(0, px) {
            var next = m.data
            for y in 0..<height {
                for x in 0..<width where m.data[y * width + x] >= 128 {
                    // 画像端は外側を非選択として扱う
                    let edge = x == 0 || x == width - 1 || y == 0 || y == height - 1
                    if edge || !m.isSelected(x: x - 1, y: y) || !m.isSelected(x: x + 1, y: y)
                        || !m.isSelected(x: x, y: y - 1) || !m.isSelected(x: x, y: y + 1) {
                        next[y * width + x] = 0
                    }
                }
            }
            m.data = next
        }
        return m
    }

    func binarized() -> SelectionMask {
        var m = self
        for i in 0..<m.data.count { m.data[i] = m.data[i] >= 128 ? 255 : 0 }
        return m
    }

    /// 既存選択と新規選択の和（論理OR）
    func union(_ other: SelectionMask) -> SelectionMask {
        var m = SelectionMask(width: width, height: height)
        let count = min(data.count, other.data.count)
        for i in 0..<count {
            m.data[i] = max(data[i], other.data[i])
        }
        return m
    }

    /// 既存選択から新規選択を除外（論理AND NOT）
    func subtracting(_ other: SelectionMask) -> SelectionMask {
        var m = self
        let count = min(data.count, other.data.count)
        for i in 0..<count {
            m.data[i] = data[i] > other.data[i] ? data[i] - other.data[i] : 0
        }
        return m
    }

    // MARK: - ブラシ（手動マスク編集）

    /// ブラシでスタンプ。add=false なら削除。座標はキャンバス座標。
    mutating func stampBrush(at p: CGPoint, size: Double, hardness: Double, opacity: Double, add: Bool) {
        let radius = max(0.5, size / 2)
        let x0 = max(0, Int((p.x - radius).rounded(.down)))
        let x1 = min(width - 1, Int((p.x + radius).rounded(.up)))
        let y0 = max(0, Int((p.y - radius).rounded(.down)))
        let y1 = min(height - 1, Int((p.y + radius).rounded(.up)))
        guard x1 >= x0, y1 >= y0 else { return }
        let hard = max(0.0, min(1.0, hardness))
        let op = max(0.0, min(1.0, opacity))
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Double(x) + 0.5 - p.x
                let dy = Double(y) + 0.5 - p.y
                let d = (dx * dx + dy * dy).squareRoot() / radius
                guard d <= 1.0 else { continue }
                // 硬さ：hard=1 で全域フラット、hard=0 で中心から線形フォールオフ
                let falloffStart = hard
                let strength: Double
                if d <= falloffStart || falloffStart >= 1.0 {
                    strength = 1.0
                } else {
                    strength = max(0, 1.0 - (d - falloffStart) / max(0.001, 1.0 - falloffStart))
                }
                let delta = strength * op * 255
                let i = y * width + x
                if add {
                    data[i] = UInt8(min(255, Double(data[i]) + delta))
                } else {
                    data[i] = UInt8(max(0, Double(data[i]) - delta))
                }
            }
        }
    }

    // MARK: - アフィン変形（選択範囲変形の適用）

    /// マスク全体を top-left 座標系のアフィン変形（移動・スケール・回転）で再ラスタライズ
    func transformed(dx: Double, dy: Double, scaleX: Double, scaleY: Double,
                     rotationDegrees: Double, center: CGPoint) -> SelectionMask {
        var m = SelectionMask(width: width, height: height)
        guard let srcImage = makeGrayImage() else { return self }
        var buf = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &buf, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return self }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        // 反転なしの CG（y-up）コンテキストで描くため、top-left 座標系の変形を
        // F·T·F（F は上下反転）で y-up 座標系に共役変換して適用する
        let cgCenter = CGPoint(x: center.x, y: CGFloat(height) - center.y)
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: dx, y: -dy)
        t = t.translatedBy(x: cgCenter.x, y: cgCenter.y)
        t = t.rotated(by: -rotationDegrees * .pi / 180)
        t = t.scaledBy(x: scaleX, y: scaleY)
        t = t.translatedBy(x: -cgCenter.x, y: -cgCenter.y)
        ctx.concatenate(t)
        ctx.draw(srcImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        m.data = buf
        return m
    }

    // MARK: - グレースケール画像との相互変換

    private func makeGrayImage() -> CGImage? {
        let data = Data(self.data) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// 8bit グレースケールコンテキストに描画してマスクへ反映する
    private mutating func drawIntoMask(_ draw: (CGContext) -> Void) {
        var buf = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &buf, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }
        // top-left 座標系で描けるように反転
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx)
        data = buf
    }

    // MARK: - マーチングアンツ用境界パス（キャンバス座標）

    /// 選択境界のエッジを水平・垂直ランにまとめた Path を返す
    func boundaryPath() -> Path {
        var path = Path()
        // 水平エッジ：行 y-1 と行 y の間
        for y in 0...height {
            var runStart: Int? = nil
            for x in 0...width {
                let above = y > 0 && x < width && data[(y - 1) * width + x] >= 128
                let below = y < height && x < width && data[y * width + x] >= 128
                let isEdge = x < width && (above != below)
                if isEdge {
                    if runStart == nil { runStart = x }
                } else if let s = runStart {
                    path.move(to: CGPoint(x: s, y: y))
                    path.addLine(to: CGPoint(x: x, y: y))
                    runStart = nil
                }
            }
        }
        // 垂直エッジ：列 x-1 と列 x の間
        for x in 0...width {
            var runStart: Int? = nil
            for y in 0...height {
                let left = x > 0 && y < height && data[y * width + (x - 1)] >= 128
                let right = x < width && y < height && data[y * width + x] >= 128
                let isEdge = y < height && (left != right)
                if isEdge {
                    if runStart == nil { runStart = y }
                } else if let s = runStart {
                    path.move(to: CGPoint(x: x, y: s))
                    path.addLine(to: CGPoint(x: x, y: y))
                    runStart = nil
                }
            }
        }
        return path
    }
}
