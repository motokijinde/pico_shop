import Metal
import Foundation

// MARK: - レイヤーテクスチャキャッシュ
//
// Layer.id → MTLTexture。Layer.contentVersion が変わったときだけ再アップロードする。
// PixelBuffer は unpremultiplied sRGB / top-left なのでそのまま転送できる。

final class LayerTextureStore {

    private struct Entry {
        var texture: MTLTexture
        var version: UInt64
    }

    private let device: MTLDevice
    private var entries: [UUID: Entry] = [:]

    init(device: MTLDevice) {
        self.device = device
    }

    /// レイヤーのテクスチャを返す（必要ならアップロード）
    func texture(for layer: Layer) -> MTLTexture? {
        if let entry = entries[layer.id],
           entry.version == layer.contentVersion,
           entry.texture.width == layer.buffer.width,
           entry.texture.height == layer.buffer.height {
            return entry.texture
        }
        guard let texture = upload(buffer: layer.buffer, reusing: entries[layer.id]?.texture) else {
            return nil
        }
        entries[layer.id] = Entry(texture: texture, version: layer.contentVersion)
        return texture
    }

    /// 存在しないレイヤーのテクスチャを破棄
    func prune(keeping ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    private func upload(buffer: PixelBuffer, reusing old: MTLTexture?) -> MTLTexture? {
        let texture: MTLTexture
        if let old, old.width == buffer.width, old.height == buffer.height {
            texture = old
        } else {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: MetalEngine.compositePixelFormat,
                width: buffer.width, height: buffer.height, mipmapped: false)
            desc.usage = .shaderRead
            desc.storageMode = device.hasUnifiedMemory ? .shared : .managed
            guard let t = device.makeTexture(descriptor: desc) else { return nil }
            texture = t
        }
        buffer.pixels.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, buffer.width, buffer.height),
                            mipmapLevel: 0,
                            withBytes: raw.baseAddress!,
                            bytesPerRow: buffer.width * 4)
        }
        return texture
    }
}
