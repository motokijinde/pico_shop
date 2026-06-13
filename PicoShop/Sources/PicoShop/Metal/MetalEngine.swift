import Metal
import CoreGraphics

// MARK: - Metal エンジン（device / queue / pipeline のラッパー）
//
// Metal の生 API はこのファイルと GPUCompositor / OverlayRenderer に閉じ込め、
// ビュー側は OverlayScene と高レベル API だけを使う。
// メインスレッドからの利用を前提とする（SwiftUI 非依存・ヘッドレステスト可能）。

final class MetalEngine {

    enum Error: Swift.Error {
        case noDevice
        case pipelineCreationFailed(String)
    }

    static let shared: MetalEngine? = {
        do {
            return try MetalEngine()
        } catch {
            print("MetalEngine の初期化に失敗: \(error)")
            return nil
        }
    }()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    /// 画面描画用（ターゲット: bgra8Unorm、premultiplied over ブレンド）
    let quadPipeline: MTLRenderPipelineState
    let checkerPipeline: MTLRenderPipelineState
    let shapePipeline: MTLRenderPipelineState
    /// B&Wマスクプレビュー用（色域選択ツール）
    let bwMaskPipeline: MTLRenderPipelineState
    /// オフスクリーン合成用（ターゲット: rgba8Unorm、全ピクセル上書き）
    let blendPipeline: MTLRenderPipelineState
    /// 1×1 r8Unorm value=0（B&Wプレビューで選択なし時の黒テクスチャ）
    let blackR8Texture: MTLTexture

    let nearestClampSampler: MTLSamplerState
    let nearestBorderSampler: MTLSamplerState   // 範囲外 = 透明（ルーペ・レイヤー合成用）
    let linearMipSampler: MTLSamplerState       // ズームアウト時の縮小表示用
    let linearClampSampler: MTLSamplerState     // テキストスプライト用

    /// 画面用レンダーターゲットのピクセルフォーマット（MTKView と合わせる）
    static let viewPixelFormat: MTLPixelFormat = .bgra8Unorm
    /// 合成テクスチャのフォーマット（PixelBuffer の RGBA 順と一致）
    static let compositePixelFormat: MTLPixelFormat = .rgba8Unorm

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw Error.noDevice
        }
        self.device = device
        self.queue = queue
        library = try device.makeLibrary(source: picoShaderSource, options: nil)

        let lib = library
        quadPipeline = try Self.makePipeline(device: device, library: lib,
                                             vertex: "quad_vertex", fragment: "quad_fragment",
                                             format: Self.viewPixelFormat, blending: true)
        checkerPipeline = try Self.makePipeline(device: device, library: lib,
                                                vertex: "quad_vertex", fragment: "checker_fragment",
                                                format: Self.viewPixelFormat, blending: true)
        shapePipeline = try Self.makePipeline(device: device, library: lib,
                                              vertex: "shape_vertex", fragment: "shape_fragment",
                                              format: Self.viewPixelFormat, blending: true)
        blendPipeline = try Self.makePipeline(device: device, library: lib,
                                              vertex: "quad_vertex", fragment: "blend_fragment",
                                              format: Self.compositePixelFormat, blending: false)
        bwMaskPipeline = try Self.makePipeline(device: device, library: lib,
                                               vertex: "quad_vertex", fragment: "bw_mask_fragment",
                                               format: Self.viewPixelFormat, blending: true)

        let r8Desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
        r8Desc.usage = .shaderRead
        r8Desc.storageMode = device.hasUnifiedMemory ? .shared : .managed
        guard let r8Tex = device.makeTexture(descriptor: r8Desc) else { throw Error.noDevice }
        var zeroR8: UInt8 = 0
        r8Tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                      withBytes: &zeroR8, bytesPerRow: 1)
        blackR8Texture = r8Tex

        nearestClampSampler = Self.makeSampler(device: device, filter: .nearest,
                                               mip: .notMipmapped, address: .clampToEdge)
        nearestBorderSampler = Self.makeSampler(device: device, filter: .nearest,
                                                mip: .notMipmapped, address: .clampToBorderColor)
        linearMipSampler = Self.makeSampler(device: device, filter: .linear,
                                            mip: .linear, address: .clampToEdge)
        linearClampSampler = Self.makeSampler(device: device, filter: .linear,
                                              mip: .notMipmapped, address: .clampToEdge)
    }

    private static func makePipeline(device: MTLDevice, library: MTLLibrary,
                                     vertex: String, fragment: String,
                                     format: MTLPixelFormat, blending: Bool) throws -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.label = "\(vertex)/\(fragment)"
        guard let vfn = library.makeFunction(name: vertex),
              let ffn = library.makeFunction(name: fragment) else {
            throw Error.pipelineCreationFailed("関数が見つからない: \(vertex)/\(fragment)")
        }
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        let att = desc.colorAttachments[0]!
        att.pixelFormat = format
        if blending {
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one          // プリマルチプライ済み前提
            att.sourceAlphaBlendFactor = .one
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try device.makeRenderPipelineState(descriptor: desc)
    }

    private static func makeSampler(device: MTLDevice, filter: MTLSamplerMinMagFilter,
                                    mip: MTLSamplerMipFilter,
                                    address: MTLSamplerAddressMode) -> MTLSamplerState {
        let d = MTLSamplerDescriptor()
        d.minFilter = filter
        d.magFilter = filter
        d.mipFilter = mip
        d.sAddressMode = address
        d.tAddressMode = address
        if address == .clampToBorderColor { d.borderColor = .transparentBlack }
        return device.makeSamplerState(descriptor: d)!
    }

    /// 左上原点のクアッド頂点（2三角形 = 6頂点）
    static func quadVertices(rect: CGRect, uvRect: CGRect) -> [QuadVertexIn] {
        let x0 = Float(rect.minX), y0 = Float(rect.minY)
        let x1 = Float(rect.maxX), y1 = Float(rect.maxY)
        let u0 = Float(uvRect.minX), v0 = Float(uvRect.minY)
        let u1 = Float(uvRect.maxX), v1 = Float(uvRect.maxY)
        return [
            QuadVertexIn(pos: [x0, y0], uv: [u0, v0]),
            QuadVertexIn(pos: [x1, y0], uv: [u1, v0]),
            QuadVertexIn(pos: [x0, y1], uv: [u0, v1]),
            QuadVertexIn(pos: [x1, y0], uv: [u1, v0]),
            QuadVertexIn(pos: [x1, y1], uv: [u1, v1]),
            QuadVertexIn(pos: [x0, y1], uv: [u0, v1]),
        ]
    }
}
