import CoreGraphics

enum ColorRangeEngine {

    struct Result {
        var mask: [UInt8]
        var bounds: CGRect?
    }

    /// クリック点と類似色の選択マスクと、その有効範囲を返す（レイヤー座標系）
    /// contiguous=true: BFSで隣接ピクセルのみ選択（Magic Wand）
    /// contiguous=false: レイヤー全体から類似色を選択
    static func floodFillResult(pixels: [UInt8], width: Int, height: Int,
                                startX: Int, startY: Int, tolerance: Int,
                                contiguous: Bool) -> Result {
        let count = width * height
        var result = [UInt8](repeating: 0, count: count)
        guard startX >= 0, startX < width, startY >= 0, startY < height else {
            return Result(mask: result, bounds: nil)
        }

        let s = (startY * width + startX) * 4
        let sr = Int(pixels[s]), sg = Int(pixels[s + 1])
        let sb = Int(pixels[s + 2]), sa = Int(pixels[s + 3])
        var minX = width, maxX = -1, minY = height, maxY = -1

        func mark(_ idx: Int) {
            result[idx] = 255
            let x = idx % width
            let y = idx / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }

        func matches(_ i: Int) -> Bool {
            abs(Int(pixels[i * 4])     - sr) <= tolerance &&
            abs(Int(pixels[i * 4 + 1]) - sg) <= tolerance &&
            abs(Int(pixels[i * 4 + 2]) - sb) <= tolerance &&
            abs(Int(pixels[i * 4 + 3]) - sa) <= tolerance
        }

        if contiguous {
            var queue = [startY * width + startX]
            queue.reserveCapacity(min(count, 4096))
            mark(queue[0])
            var head = 0
            while head < queue.count {
                let idx = queue[head]; head += 1
                let x = idx % width, y = idx / width
                if y > 0        { let n = idx - width; if result[n] == 0 && matches(n) { mark(n); queue.append(n) } }
                if y < height-1 { let n = idx + width; if result[n] == 0 && matches(n) { mark(n); queue.append(n) } }
                if x > 0        { let n = idx - 1;     if result[n] == 0 && matches(n) { mark(n); queue.append(n) } }
                if x < width-1  { let n = idx + 1;     if result[n] == 0 && matches(n) { mark(n); queue.append(n) } }
            }
        } else {
            for i in 0..<count where matches(i) {
                mark(i)
            }
        }
        let bounds = maxX >= minX
            ? CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            : nil
        return Result(mask: result, bounds: bounds)
    }

}
