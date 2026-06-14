import AppKit
import CoreGraphics

// MARK: - PixelColor

/// RGBA（非プリマルチプライ、各 0–255）
struct PixelColor: Equatable, Codable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8 = 255

    static let clear = PixelColor(r: 0, g: 0, b: 0, a: 0)
    static let white = PixelColor(r: 255, g: 255, b: 255)
    static let black = PixelColor(r: 0, g: 0, b: 0)

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    var hexString: String {
        String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? .black
        r = UInt8(max(0, min(255, c.redComponent * 255)))
        g = UInt8(max(0, min(255, c.greenComponent * 255)))
        b = UInt8(max(0, min(255, c.blueComponent * 255)))
        a = UInt8(max(0, min(255, c.alphaComponent * 255)))
    }
}

// MARK: - リサンプリング

enum ResampleQuality: String, CaseIterable, Identifiable {
    case nearest = "Nearest"
    case bilinear = "Bilinear"
    case bicubic = "Bicubic"
    case lanczos = "Lanczos"

    var id: String { rawValue }

    var cgQuality: CGInterpolationQuality {
        switch self {
        case .nearest: return .none
        case .bilinear: return .low
        case .bicubic: return .medium
        case .lanczos: return .high
        }
    }
}

// MARK: - PixelBuffer

/// RGBA8（非プリマルチプライ）のピクセルバッファ。
/// 色比較・透明化処理を正確に行うため、内部は常に sRGB / unpremultiplied で保持する。
struct PixelBuffer {
    var width: Int
    var height: Int
    var pixels: [UInt8]  // RGBA, count == width * height * 4

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    init(width: Int, height: Int, fill: PixelColor = .clear) {
        self.width = max(1, width)
        self.height = max(1, height)
        if fill == .clear {
            pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
        } else {
            pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
            for i in 0..<(self.width * self.height) {
                pixels[i * 4] = fill.r
                pixels[i * 4 + 1] = fill.g
                pixels[i * 4 + 2] = fill.b
                pixels[i * 4 + 3] = fill.a
            }
        }
    }

    init?(cgImage: CGImage) {
        guard let px = PixelBuffer.readRGBA(cgImage: cgImage) else { return nil }
        width = cgImage.width
        height = cgImage.height
        pixels = px
    }

    // MARK: ピクセルアクセス

    func color(x: Int, y: Int) -> PixelColor? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let i = (y * width + x) * 4
        return PixelColor(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
    }

    mutating func setColor(x: Int, y: Int, _ c: PixelColor) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let i = (y * width + x) * 4
        pixels[i] = c.r; pixels[i + 1] = c.g; pixels[i + 2] = c.b; pixels[i + 3] = c.a
    }

    // MARK: CGImage 変換

    /// CGImage（sRGB / unpremultiplied alpha）を生成
    func makeCGImage() -> CGImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: PixelBuffer.sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// CGImage を sRGB / RGBA8（unpremultiplied）として読み出す
    static func readRGBA(cgImage: CGImage) -> [UInt8]? {
        let w = cgImage.width
        let h = cgImage.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &px, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        // unpremultiply（色比較を正しく行うため）
        for i in 0..<(w * h) {
            let a = Int(px[i * 4 + 3])
            guard a > 0 && a < 255 else { continue }
            px[i * 4] = UInt8(min(255, Int(px[i * 4]) * 255 / a))
            px[i * 4 + 1] = UInt8(min(255, Int(px[i * 4 + 1]) * 255 / a))
            px[i * 4 + 2] = UInt8(min(255, Int(px[i * 4 + 2]) * 255 / a))
        }
        return px
    }

    // MARK: CPU/CoreGraphics 変形

    func cpuResized(width newW: Int, height newH: Int, quality: ResampleQuality) -> PixelBuffer {
        guard newW > 0, newH > 0, let src = makeCGImage() else {
            return PixelBuffer(width: max(1, newW), height: max(1, newH))
        }
        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: PixelBuffer.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        ctx.interpolationQuality = quality.cgQuality
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let out = ctx.makeImage(), let buf = PixelBuffer(cgImage: out) else { return self }
        return buf
    }

    func flippedHorizontally() -> PixelBuffer {
        var out = self
        for y in 0..<height {
            for x in 0..<(width / 2) {
                let i = (y * width + x) * 4
                let j = (y * width + (width - 1 - x)) * 4
                for k in 0..<4 { out.pixels.swapAt(i + k, j + k) }
            }
        }
        return out
    }

    func flippedVertically() -> PixelBuffer {
        var out = self
        for y in 0..<(height / 2) {
            let i = y * width * 4
            let j = (height - 1 - y) * width * 4
            for k in 0..<(width * 4) { out.pixels.swapAt(i + k, j + k) }
        }
        return out
    }

    /// 中心を基準に任意角度回転。バウンディングボックスは拡張される。
    /// 戻り値は新バッファと、レイヤーオフセットに加算すべき補正値。
    func cpuRotated(byDegrees deg: Double, quality: ResampleQuality) -> (PixelBuffer, dx: Int, dy: Int) {
        let rad = deg * .pi / 180
        let c = abs(cos(rad)), s = abs(sin(rad))
        let newW = max(1, Int((Double(width) * c + Double(height) * s).rounded()))
        let newH = max(1, Int((Double(width) * s + Double(height) * c).rounded()))
        guard let src = makeCGImage(),
              let ctx = CGContext(
                data: nil, width: newW, height: newH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: PixelBuffer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return (self, 0, 0) }
        ctx.interpolationQuality = quality.cgQuality
        ctx.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        // CG は y-up なので回転方向を反転して「画面上で時計回り」を維持
        ctx.rotate(by: -rad)
        ctx.draw(src, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2,
                                 width: CGFloat(width), height: CGFloat(height)))
        guard let out = ctx.makeImage(), let buf = PixelBuffer(cgImage: out) else { return (self, 0, 0) }
        return (buf, (width - newW) / 2, (height - newH) / 2)
    }

    /// 透明部分のトリム（非透明ピクセルの最小バウンディングボックス）
    func cropped(srcX: Int, srcY: Int, width: Int, height: Int) -> PixelBuffer {
        var result = PixelBuffer(width: width, height: height)
        for ny in 0..<height {
            for nx in 0..<width {
                let ox = srcX + nx, oy = srcY + ny
                guard ox >= 0, ox < self.width, oy >= 0, oy < self.height else { continue }
                let si = (oy * self.width + ox) * 4
                let di = (ny * width + nx) * 4
                result.pixels[di]     = pixels[si]
                result.pixels[di + 1] = pixels[si + 1]
                result.pixels[di + 2] = pixels[si + 2]
                result.pixels[di + 3] = pixels[si + 3]
            }
        }
        return result
    }

    func opaqueBounds() -> (x: Int, y: Int, w: Int, h: Int)? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}
