import AppKit
import CoreGraphics

/// テキストのラスタライズ（仕様 9-5）
enum TextRenderer {

    static func render(text: String, fontFamily: String, size: Double,
                       weight: TextWeight, color: PixelColor, antialias: Bool) -> PixelBuffer? {
        let manager = NSFontManager.shared
        let font = manager.font(withFamily: fontFamily, traits: [], weight: weight.managerWeight, size: size)
            ?? NSFont.systemFont(ofSize: size)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.nsColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let bounds = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let w = max(1, Int(ceil(bounds.width)))
        let h = max(1, Int(ceil(bounds.height)))

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: PixelBuffer.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setShouldAntialias(antialias)
        ctx.setAllowsAntialiasing(antialias)
        ctx.setShouldSmoothFonts(antialias)
        ctx.setAllowsFontSmoothing(antialias)
        ctx.setShouldSubpixelPositionFonts(antialias)
        ctx.setShouldSubpixelQuantizeFonts(!antialias)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attributed.draw(with: CGRect(x: -bounds.minX, y: -bounds.minY, width: bounds.width, height: bounds.height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()

        guard let img = ctx.makeImage(), let buf = PixelBuffer(cgImage: img) else { return nil }
        return buf
    }

    /// 利用可能なフォントファミリー一覧
    static var availableFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }
}
