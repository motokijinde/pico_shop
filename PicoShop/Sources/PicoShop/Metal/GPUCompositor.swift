import Metal
import CoreGraphics
import Foundation

// MARK: - GPU レイヤー合成器
//
// 全可視レイヤーをピンポン方式で合成テクスチャ（premultiplied sRGB / top-left）に描く。
// ブレンドモードは blend_fragment シェーダで CPUCompositor と同じ式を実装。
// 結果はキャンバス・ルーペ・ナビゲーターの各ビューが共有する。

final class GPUCompositor {

    struct FloatingPreview {
        var layer: Layer
        var originalBounds: CGRect
        var transform: SelectionTransform
    }

    private let engine: MetalEngine
    private let store: LayerTextureStore

    private var texA: MTLTexture?
    private var texB: MTLTexture?
    /// 最初のパスの dst 用 1×1 透明テクスチャ（uv サンプリングなので全面透明として機能）
    private let clearTexture: MTLTexture

    /// 最新の合成結果（mipmap 付き、premultiplied）
    private(set) var compositeTexture: MTLTexture?
    /// 合成結果が変わるたびに増える（ビュー側の再描画判定用）
    private(set) var version: UInt64 = 0

    init?(engine: MetalEngine) {
        self.engine = engine
        self.store = LayerTextureStore(device: engine.device)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalEngine.compositePixelFormat, width: 1, height: 1, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = engine.device.hasUnifiedMemory ? .shared : .managed
        guard let clear = engine.device.makeTexture(descriptor: desc) else { return nil }
        var zero: UInt32 = 0
        clear.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                      withBytes: &zero, bytesPerRow: 4)
        clearTexture = clear
    }

    // MARK: 合成

    /// layers（先頭が最上位）を bounds の範囲で合成する。コミットのみ行い完了は待たない
    /// （以降の描画・読み出しは同一キューなので順序が保証される）。
    func composite(layers: [Layer], bounds: CGRect, floatingPreview: FloatingPreview? = nil) {
        let w = Int(bounds.width.rounded()), h = Int(bounds.height.rounded())
        guard w > 0, h > 0 else { return }
        ensureTargets(width: w, height: h)
        guard let texA, let texB,
              let cmd = engine.queue.makeCommandBuffer() else { return }

        store.prune(keeping: Set(layers.map(\.id)))

        // 下のレイヤー（配列の末尾）から順に重ねる
        let visible = layers.reversed().filter(\.visible)
        var dst: MTLTexture = clearTexture
        var target = texA

        if visible.isEmpty {
            // 透明にクリアするだけ
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texA
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            cmd.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            target = texA
        } else {
            for layer in visible {
                guard let layerTex = store.texture(for: layer) else { continue }
                encodeBlendPass(cmd: cmd, dst: dst, src: layerTex, layer: layer,
                                bounds: bounds, target: target)
                dst = target
                target = (target === texA) ? texB : texA
            }
            target = dst  // 最後に書き込んだテクスチャ
        }

        if let floatingPreview {
            encodeFloatingPreview(cmd: cmd, preview: floatingPreview, bounds: bounds, target: target)
        }

        if target.mipmapLevelCount > 1, let blit = cmd.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: target)
            blit.endEncoding()
        }
        cmd.commit()
        compositeTexture = target
        version &+= 1
    }

    private func encodeBlendPass(cmd: MTLCommandBuffer, dst: MTLTexture, src: MTLTexture,
                                 layer: Layer, bounds: CGRect, target: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare   // 全ピクセル上書き
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let targetSize = CGSize(width: target.width, height: target.height)
        MetalQuadEncoder(engine: engine, encoder: enc, viewSize: targetSize)
            .drawBlendPass(destination: dst, source: src, targetSize: targetSize,
                           layer: layer, bounds: bounds)
        enc.endEncoding()
    }

    private func encodeFloatingPreview(cmd: MTLCommandBuffer, preview: FloatingPreview,
                                       bounds: CGRect, target: MTLTexture) {
        guard let src = store.texture(for: preview.layer) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }

        let vertices = floatingPreviewVertices(preview, compositeBounds: bounds)
        let targetSize = CGSize(width: target.width, height: target.height)
        MetalQuadEncoder(engine: engine, encoder: enc, viewSize: targetSize)
            .drawPremultipliedTexture(src, vertices: vertices,
                                      sampler: engine.linearClampSampler,
                                      alpha: Float(preview.layer.opacity / 100))
        enc.endEncoding()
    }

    private func floatingPreviewVertices(_ preview: FloatingPreview, compositeBounds: CGRect) -> [QuadVertexIn] {
        let b = preview.originalBounds
        let affine = preview.transform.affine(center: CGPoint(x: b.midX, y: b.midY))
        func targetPoint(_ p: CGPoint) -> CGPoint {
            let q = p.applying(affine)
            return CGPoint(x: q.x - compositeBounds.minX, y: q.y - compositeBounds.minY)
        }
        return MetalEngine.quadVertices(
            topLeft: targetPoint(CGPoint(x: b.minX, y: b.minY)),
            topRight: targetPoint(CGPoint(x: b.maxX, y: b.minY)),
            bottomLeft: targetPoint(CGPoint(x: b.minX, y: b.maxY)),
            bottomRight: targetPoint(CGPoint(x: b.maxX, y: b.maxY))
        )
    }

    private func ensureTargets(width: Int, height: Int) {
        if let texA, texA.width == width, texA.height == height { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalEngine.compositePixelFormat,
            width: width, height: height, mipmapped: true)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        texA = engine.device.makeTexture(descriptor: desc)
        texB = engine.device.makeTexture(descriptor: desc)
        compositeTexture = nil
    }

    // MARK: CPU 読み出し

    /// 合成テクスチャの1ピクセルを読む（スポイト・ルーペ情報用）。
    /// 座標は合成テクスチャのピクセル座標（bounds 原点基準）。
    func readPixel(x: Int, y: Int) -> PixelColor? {
        guard let tex = compositeTexture,
              x >= 0, x < tex.width, y >= 0, y < tex.height,
              let buf = engine.device.makeBuffer(length: 4, options: .storageModeShared),
              let cmd = engine.queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: x, y: y, z: 0),
                  sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                  to: buf, destinationOffset: 0,
                  destinationBytesPerRow: 4, destinationBytesPerImage: 4)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        let p = buf.contents().assumingMemoryBound(to: UInt8.self)
        return Self.unpremultiply(r: p[0], g: p[1], b: p[2], a: p[3])
    }

    /// 合成テクスチャ全体を premultiplied RGBA8 のまま読み出す（パリティテスト・コールドパス用）。
    func readAllPremultiplied() -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let tex = compositeTexture else { return nil }
        let w = tex.width, h = tex.height
        guard let buf = engine.device.makeBuffer(length: w * h * 4, options: .storageModeShared),
              let cmd = engine.queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: tex, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: buf, destinationOffset: 0,
                  destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        let p = buf.contents().assumingMemoryBound(to: UInt8.self)
        return (Array(UnsafeBufferPointer(start: p, count: w * h * 4)), w, h)
    }

    /// 合成テクスチャ全体を PixelBuffer（unpremultiplied）として読み出す（コールドパス用）。
    func readAll() -> PixelBuffer? {
        guard let raw = readAllPremultiplied() else { return nil }
        var out = PixelBuffer(width: raw.width, height: raw.height)
        for i in 0..<(raw.width * raw.height) {
            let c = Self.unpremultiply(r: raw.pixels[i * 4], g: raw.pixels[i * 4 + 1],
                                       b: raw.pixels[i * 4 + 2], a: raw.pixels[i * 4 + 3])
            out.pixels[i * 4] = c.r
            out.pixels[i * 4 + 1] = c.g
            out.pixels[i * 4 + 2] = c.b
            out.pixels[i * 4 + 3] = c.a
        }
        return out
    }

    /// PixelBuffer.readRGBA と同じ整数演算でアンプリマルチプライ
    private static func unpremultiply(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> PixelColor {
        guard a > 0 && a < 255 else { return PixelColor(r: r, g: g, b: b, a: a) }
        let ia = Int(a)
        return PixelColor(r: UInt8(min(255, Int(r) * 255 / ia)),
                          g: UInt8(min(255, Int(g) * 255 / ia)),
                          b: UInt8(min(255, Int(b) * 255 / ia)),
                          a: a)
    }
}
