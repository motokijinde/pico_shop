import CoreGraphics
import Foundation

// MARK: - 合成モード

enum LayerBlendMode: String, CaseIterable, Identifiable, Codable {
    case normal
    case multiply
    case screen
    case overlay
    case addition

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "標準"
        case .multiply: return "乗算"
        case .screen: return "スクリーン"
        case .overlay: return "オーバーレイ"
        case .addition: return "加算"
        }
    }

    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .addition: return .plusLighter
        }
    }
}

// MARK: - レイヤー

/// contentVersion 用のグローバル単調増加カウンター。
/// アンドゥで古い Layer 構造体が復元されても値が衝突しないよう、常に新しい値を払い出す。
private var layerContentVersionCounter: UInt64 = 0

private func nextLayerContentVersion() -> UInt64 {
    layerContentVersionCounter += 1
    return layerContentVersionCounter
}

struct Layer: Identifiable {
    let id: UUID
    var name: String
    var buffer: PixelBuffer
    var offsetX: Int = 0
    var offsetY: Int = 0
    var opacity: Double = 100  // 0–100 (%)
    var blend: LayerBlendMode = .normal
    var visible: Bool = true
    var locked: Bool = false

    /// 表示用キャッシュ（buffer 変更時に refreshCache() で更新）
    var cachedImage: CGImage?

    /// ピクセル内容の世代番号（GPU テクスチャの再アップロード判定用）。
    /// buffer を書き換えたら refreshCache() で更新すること。
    private(set) var contentVersion: UInt64 = nextLayerContentVersion()

    init(name: String, buffer: PixelBuffer, offsetX: Int = 0, offsetY: Int = 0) {
        self.id = UUID()
        self.name = name
        self.buffer = buffer
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.cachedImage = buffer.makeCGImage()
    }

    mutating func refreshCache() {
        cachedImage = buffer.makeCGImage()
        contentVersion = nextLayerContentVersion()
    }

    /// キャンバス座標系でのレイヤー矩形
    var frame: CGRect {
        CGRect(x: offsetX, y: offsetY, width: buffer.width, height: buffer.height)
    }
}

// MARK: - 合成エンジン

enum Compositor {

    /// 表示レイヤーを bounds（キャンバス座標系の矩形）の範囲で合成する。
    /// 戻り値の画像サイズは bounds のサイズ。
    static func composite(layers: [Layer], bounds: CGRect) -> CGImage? {
        let w = Int(bounds.width.rounded()), h = Int(bounds.height.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: PixelBuffer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .none

        // 下のレイヤー（配列の末尾）から順に描画
        for layer in layers.reversed() where layer.visible {
            guard let img = layer.cachedImage else { continue }
            ctx.setAlpha(CGFloat(layer.opacity / 100))
            ctx.setBlendMode(layer.blend.cgBlendMode)
            // top-left 座標系 → CG（y-up）座標系
            let f = layer.frame
            let cgRect = CGRect(x: f.minX - bounds.minX,
                                y: bounds.maxY - f.maxY,
                                width: f.width, height: f.height)
            ctx.draw(img, in: cgRect)
        }
        return ctx.makeImage()
    }

    /// 全表示レイヤーとキャンバスの union 矩形（キャンバス座標系）
    static func unionBounds(layers: [Layer], canvasWidth: Int, canvasHeight: Int) -> CGRect {
        var rect = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        for layer in layers where layer.visible {
            rect = rect.union(layer.frame)
        }
        return CGRect(x: rect.minX.rounded(.down), y: rect.minY.rounded(.down),
                      width: rect.width.rounded(.up), height: rect.height.rounded(.up))
    }
}
