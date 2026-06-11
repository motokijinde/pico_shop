import Foundation

/// 色域選択エンジン。
/// 参考実装（ImageTrimmer/ImageProcessor.swift）の背景検出アルゴリズムを
/// 「選択マスク生成」用に再構成したもの。
/// バックグラウンドスレッドでの実行を想定し、Sendable な値のみ扱う。
enum ColorRangeEngine {

    struct Params: Sendable {
        var bgColor: (r: UInt8, g: UInt8, b: UInt8)
        var level: Int        // 1–100: 背景色との許容誤差
        var erosion: Int      // 0–10: 選択エッジを削る量
        var inside: Bool      // 内側の閉じた背景領域も選択するか
    }

    struct Info: Sendable {
        let regionCount: Int   // 連結成分の総数
        let selectedPixels: Int
    }

    enum EngineError: Error, LocalizedError {
        case noRegionFound
        var errorDescription: String? { "色域が検出できません" }
    }

    /// レイヤーのピクセル（RGBA8 unpremultiplied）から選択マスク（レイヤー座標系）を生成
    static func select(pixels: [UInt8], width: Int, height: Int,
                       params: Params) throws -> (mask: [UInt8], info: Info) {
        let count = width * height

        // 1. 背景色マスク
        let margin = params.level
        let br = Int(params.bgColor.r), bg = Int(params.bgColor.g), bb = Int(params.bgColor.b)
        var bgMask = [Bool](repeating: false, count: count)
        for i in 0..<count {
            bgMask[i] = abs(Int(pixels[i * 4]) - br) <= margin
                && abs(Int(pixels[i * 4 + 1]) - bg) <= margin
                && abs(Int(pixels[i * 4 + 2]) - bb) <= margin
        }

        // 2. 連結成分ラベリング（BFS、4近傍）
        let (labeled, numLabels) = labelConnectedComponents(mask: bgMask, width: width, height: height)
        guard numLabels > 0 else { throw EngineError.noRegionFound }

        var sizes = [Int](repeating: 0, count: numLabels + 1)
        for lbl in labeled { sizes[lbl] += 1 }
        sizes[0] = 0
        let outerLabel = sizes.indices.dropFirst().max(by: { sizes[$0] < sizes[$1] }) ?? 1

        // 3. マスク確定：外側のみ or 全背景色領域
        var sel = [UInt8](repeating: 0, count: count)
        if params.inside {
            for i in 0..<count where bgMask[i] { sel[i] = 255 }
        } else {
            for i in 0..<count where labeled[i] == outerLabel { sel[i] = 255 }
        }

        // 4. Erosion：選択範囲のエッジを削る（4近傍）
        for _ in 0..<max(0, params.erosion) {
            var toRemove = [Bool](repeating: false, count: count)
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    guard sel[i] >= 128 else { continue }
                    if (y > 0 && sel[i - width] < 128) ||
                        (y < height - 1 && sel[i + width] < 128) ||
                        (x > 0 && sel[i - 1] < 128) ||
                        (x < width - 1 && sel[i + 1] < 128) {
                        toRemove[i] = true
                    }
                }
            }
            for i in 0..<count where toRemove[i] { sel[i] = 0 }
        }

        let selected = sel.lazy.filter { $0 >= 128 }.count
        guard selected > 0 else { throw EngineError.noRegionFound }
        return (sel, Info(regionCount: numLabels, selectedPixels: selected))
    }

    /// 画像の四隅をサンプリングして背景色を推定（参考実装と同じ手法）
    static func sampleBgColor(pixels: [UInt8], width: Int, height: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard width > 0, height > 0 else { return nil }
        let m = min(10, min(width, height) / 2)

        func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }

        let corners = [px(m, m), px(width - m - 1, m), px(m, height - m - 1), px(width - m - 1, height - m - 1)]
        let r = corners.map { $0.0 }.reduce(0, +) / 4
        let g = corners.map { $0.1 }.reduce(0, +) / 4
        let b = corners.map { $0.2 }.reduce(0, +) / 4
        return (r: UInt8(r), g: UInt8(g), b: UInt8(b))
    }

    // MARK: - 連結成分ラベリング

    private static func labelConnectedComponents(
        mask: [Bool], width: Int, height: Int
    ) -> ([Int], Int) {
        let count = width * height
        var labeled = [Int](repeating: 0, count: count)
        var currentLabel = 0

        for start in 0..<count {
            guard mask[start] && labeled[start] == 0 else { continue }
            currentLabel += 1
            var queue = [start]
            labeled[start] = currentLabel
            var head = 0

            while head < queue.count {
                let idx = queue[head]; head += 1
                let x = idx % width, y = idx / width

                if y > 0 { let n = idx - width; if mask[n] && labeled[n] == 0 { labeled[n] = currentLabel; queue.append(n) } }
                if y < height - 1 { let n = idx + width; if mask[n] && labeled[n] == 0 { labeled[n] = currentLabel; queue.append(n) } }
                if x > 0 { let n = idx - 1; if mask[n] && labeled[n] == 0 { labeled[n] = currentLabel; queue.append(n) } }
                if x < width - 1 { let n = idx + 1; if mask[n] && labeled[n] == 0 { labeled[n] = currentLabel; queue.append(n) } }
            }
        }

        return (labeled, currentLabel)
    }

    // MARK: - フローフィル（塗りつぶしツール「クリック位置」モード）

    /// クリック位置と類似色の隣接領域マスクを返す（レイヤー座標系）
    static func floodFill(pixels: [UInt8], width: Int, height: Int,
                          startX: Int, startY: Int, tolerance: Int) -> [UInt8] {
        let count = width * height
        var result = [UInt8](repeating: 0, count: count)
        guard startX >= 0, startX < width, startY >= 0, startY < height else { return result }

        let s = (startY * width + startX) * 4
        let sr = Int(pixels[s]), sg = Int(pixels[s + 1]), sb = Int(pixels[s + 2]), sa = Int(pixels[s + 3])

        func matches(_ i: Int) -> Bool {
            abs(Int(pixels[i * 4]) - sr) <= tolerance
                && abs(Int(pixels[i * 4 + 1]) - sg) <= tolerance
                && abs(Int(pixels[i * 4 + 2]) - sb) <= tolerance
                && abs(Int(pixels[i * 4 + 3]) - sa) <= tolerance
        }

        var queue = [startY * width + startX]
        result[queue[0]] = 255
        var head = 0
        while head < queue.count {
            let idx = queue[head]; head += 1
            let x = idx % width, y = idx / width
            if y > 0 { let n = idx - width; if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
            if y < height - 1 { let n = idx + width; if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
            if x > 0 { let n = idx - 1; if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
            if x < width - 1 { let n = idx + 1; if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
        }
        return result
    }
}
