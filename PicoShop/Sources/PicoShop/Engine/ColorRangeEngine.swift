import Foundation

enum ColorRangeEngine {

    /// クリック点と類似色の選択マスクを返す（レイヤー座標系）
    /// contiguous=true: BFSで隣接ピクセルのみ選択（Magic Wand）
    /// contiguous=false: レイヤー全体から類似色を選択
    static func floodFill(pixels: [UInt8], width: Int, height: Int,
                          startX: Int, startY: Int, tolerance: Int,
                          contiguous: Bool) -> [UInt8] {
        let count = width * height
        var result = [UInt8](repeating: 0, count: count)
        guard startX >= 0, startX < width, startY >= 0, startY < height else { return result }

        let s = (startY * width + startX) * 4
        let sr = Int(pixels[s]), sg = Int(pixels[s + 1])
        let sb = Int(pixels[s + 2]), sa = Int(pixels[s + 3])

        func matches(_ i: Int) -> Bool {
            abs(Int(pixels[i * 4])     - sr) <= tolerance &&
            abs(Int(pixels[i * 4 + 1]) - sg) <= tolerance &&
            abs(Int(pixels[i * 4 + 2]) - sb) <= tolerance &&
            abs(Int(pixels[i * 4 + 3]) - sa) <= tolerance
        }

        if contiguous {
            var queue = [startY * width + startX]
            result[queue[0]] = 255
            var head = 0
            while head < queue.count {
                let idx = queue[head]; head += 1
                let x = idx % width, y = idx / width
                if y > 0        { let n = idx - width; if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
                if y < height-1 { let n = idx + width; if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
                if x > 0        { let n = idx - 1;     if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
                if x < width-1  { let n = idx + 1;     if result[n] == 0 && matches(n) { result[n] = 255; queue.append(n) } }
            }
        } else {
            for i in 0..<count where matches(i) { result[i] = 255 }
        }
        return result
    }

}
