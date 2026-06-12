import AppKit
import Metal
import simd

// MARK: - テキストスプライトキャッシュ
//
// CoreText（NSAttributedString）でラスタライズした文字列をテクスチャとして保持する。
// 定規ラベルは数値の有限集合、ルーペ情報は直近1件なのでキャッシュは小さく収まる。

final class TextSpriteCache {

    struct Sprite {
        let texture: MTLTexture
        let pointSize: CGSize   // 描画時のポイントサイズ
    }

    private struct Key: Hashable {
        var text: String
        var fontSize: CGFloat
        var rgba: UInt32
        var mono: Bool
        var scale: CGFloat
    }

    private let device: MTLDevice
    private var cache: [Key: Sprite] = [:]
    private let maxEntries = 512

    init(device: MTLDevice) {
        self.device = device
    }

    func sprite(text: String, fontSize: CGFloat, color: NSColor,
                monospacedDigit: Bool, scale: CGFloat) -> Sprite? {
        let srgb = color.usingColorSpace(.sRGB) ?? .white
        let rgba = UInt32(srgb.redComponent * 255) << 24
            | UInt32(srgb.greenComponent * 255) << 16
            | UInt32(srgb.blueComponent * 255) << 8
            | UInt32(srgb.alphaComponent * 255)
        let key = Key(text: text, fontSize: fontSize, rgba: rgba, mono: monospacedDigit, scale: scale)
        if let hit = cache[key] { return hit }
        guard let sprite = rasterize(text: text, fontSize: fontSize, color: srgb,
                                     monospacedDigit: monospacedDigit, scale: scale) else { return nil }
        if cache.count >= maxEntries { cache.removeAll() }  // 単純な全消し（実用上ほぼ起きない）
        cache[key] = sprite
        return sprite
    }

    private func rasterize(text: String, fontSize: CGFloat, color: NSColor,
                           monospacedDigit: Bool, scale: CGFloat) -> Sprite? {
        let font = monospacedDigit
            ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            : NSFont.systemFont(ofSize: fontSize)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let bounds = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let pw = max(1, Int(ceil(bounds.width * scale)))
        let ph = max(1, Int(ceil(bounds.height * scale)))
        guard let ctx = CGContext(
            data: nil, width: pw, height: ph,
            bitsPerComponent: 8, bytesPerRow: pw * 4,
            space: PixelBuffer.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attributed.draw(with: CGRect(x: -bounds.minX, y: -bounds.minY,
                                     width: bounds.width, height: bounds.height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()

        guard let data = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalEngine.compositePixelFormat, width: pw, height: ph, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        // CGBitmapContext のメモリは行0=上端なのでそのまま転送できる
        texture.replace(region: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0,
                        withBytes: data, bytesPerRow: pw * 4)
        return Sprite(texture: texture,
                      pointSize: CGSize(width: CGFloat(pw) / scale, height: CGFloat(ph) / scale))
    }
}

// MARK: - オーバーレイレンダラー
//
// OverlayScene を Metal の描画コマンドに変換する。Metal API への依存はここに閉じる。

final class OverlayRenderer {

    private let engine: MetalEngine
    let textCache: TextSpriteCache

    init(engine: MetalEngine) {
        self.engine = engine
        self.textCache = TextSpriteCache(device: engine.device)
    }

    /// scene を encoder に積む。viewSize はポイント、scale はバッキングスケール。
    func encode(scene: OverlayScene, encoder: MTLRenderCommandEncoder,
                viewSize: CGSize, scale: CGFloat) {
        var viewU = ViewUniforms(viewSize: [Float(viewSize.width), Float(viewSize.height)])

        for item in scene.items {
            switch item {
            case .stroke(let points, let closed, let width, let color, let dash):
                var verts: [ShapeVertexIn] = []
                StrokeTessellator.tessellate(points: points, closed: closed, into: &verts)
                drawShape(encoder: encoder, verts: verts, buffer: nil, vertexCount: verts.count,
                          transform: .identity, width: width, color: color, dash: dash,
                          viewSize: viewSize)

            case .fill(let rects, let color):
                var verts: [ShapeVertexIn] = []
                StrokeTessellator.tessellateFill(rects: rects, into: &verts)
                drawShape(encoder: encoder, verts: verts, buffer: nil, vertexCount: verts.count,
                          transform: .identity, width: 0, color: color, dash: nil,
                          viewSize: viewSize)

            case .strokeCached(let mesh, let width, let color, let dash, let transform):
                drawShape(encoder: encoder, verts: nil, buffer: mesh.buffer,
                          vertexCount: mesh.vertexCount,
                          transform: transform, width: width, color: color, dash: dash,
                          viewSize: viewSize)

            case .text(let string, let position, let anchor, let fontSize, let color, let mono):
                guard let sprite = textCache.sprite(text: string, fontSize: fontSize, color: color,
                                                    monospacedDigit: mono, scale: scale) else { continue }
                var origin = position
                switch anchor {
                case .topLeading:
                    break
                case .leading:
                    origin.y -= sprite.pointSize.height / 2
                case .bottomLeading:
                    origin.y -= sprite.pointSize.height
                }
                var verts = MetalEngine.quadVertices(
                    rect: CGRect(origin: origin, size: sprite.pointSize),
                    uvRect: CGRect(x: 0, y: 0, width: 1, height: 1))
                var alpha: Float = 1
                encoder.setRenderPipelineState(engine.quadPipeline)
                encoder.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
                encoder.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
                encoder.setFragmentTexture(sprite.texture, index: 0)
                encoder.setFragmentSamplerState(engine.linearClampSampler, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
            }
        }
    }

    private func drawShape(encoder: MTLRenderCommandEncoder,
                           verts: [ShapeVertexIn]?, buffer: MTLBuffer?, vertexCount: Int,
                           transform: OverlayScene.Transform2D, width: CGFloat, color: NSColor,
                           dash: OverlayScene.Dash?, viewSize: CGSize) {
        guard vertexCount > 0 else { return }
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        var uniforms = ShapeUniforms(
            mat: transform.mat,
            translate: transform.translate,
            viewSize: [Float(viewSize.width), Float(viewSize.height)],
            halfWidth: Float(width / 2),
            arcScale: transform.arcScale,
            color: SIMD4(Float(srgb.redComponent), Float(srgb.greenComponent),
                         Float(srgb.blueComponent), Float(srgb.alphaComponent)),
            dashOn: Float(dash?.on ?? 0),
            dashOff: Float(dash?.off ?? 0),
            dashPhase: Float(dash?.phase ?? 0)
        )
        encoder.setRenderPipelineState(engine.shapePipeline)
        if let buffer {
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        } else if let verts {
            let byteCount = MemoryLayout<ShapeVertexIn>.stride * verts.count
            if byteCount < 4096 {
                verts.withUnsafeBytes { raw in
                    encoder.setVertexBytes(raw.baseAddress!, length: byteCount, index: 0)
                }
            } else {
                // コマンドバッファが保持するので使い捨てでよい
                guard let buf = engine.device.makeBuffer(bytes: verts, length: byteCount,
                                                         options: .storageModeShared) else { return }
                encoder.setVertexBuffer(buf, offset: 0, index: 0)
            }
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShapeUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
    }
}
