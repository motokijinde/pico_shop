import Metal
import CoreGraphics

struct MetalQuadEncoder {
    let engine: MetalEngine
    let encoder: MTLRenderCommandEncoder
    let viewSize: CGSize

    private var viewUniforms: ViewUniforms {
        ViewUniforms(viewSize: [Float(viewSize.width), Float(viewSize.height)])
    }

    func drawCheckerboard(rect: CGRect, origin: SIMD2<Float>, tile: Float = 8,
                          colorA: SIMD4<Float> = [1, 1, 1, 1],
                          colorB: SIMD4<Float> = [0.82, 0.82, 0.82, 1]) {
        var verts = MetalEngine.quadVertices(rect: rect, uvRect: .zero)
        var viewU = viewUniforms
        var checker = CheckerUniforms(origin: origin, tile: tile, colorA: colorA, colorB: colorB)
        encoder.setRenderPipelineState(engine.checkerPipeline)
        encoder.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
        encoder.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&checker, length: MemoryLayout<CheckerUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }

    func drawTexture(_ texture: MTLTexture, rect: CGRect, uvRect: CGRect,
                     sampler: MTLSamplerState, alpha: Float = 1) {
        var verts = MetalEngine.quadVertices(rect: rect, uvRect: uvRect)
        var viewU = viewUniforms
        var alpha = alpha
        encoder.setRenderPipelineState(engine.quadPipeline)
        encoder.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
        encoder.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }

    func drawPremultipliedTexture(_ texture: MTLTexture, vertices: [QuadVertexIn],
                                  sampler: MTLSamplerState, alpha: Float = 1) {
        drawPremultipliedTexture(texture, vertices: vertices, sampler: sampler,
                                 pipeline: engine.texturePremultiplyCompositePipeline,
                                 alpha: alpha)
    }

    func drawPremultipliedTextureInView(_ texture: MTLTexture, vertices: [QuadVertexIn],
                                        sampler: MTLSamplerState, alpha: Float = 1) {
        drawPremultipliedTexture(texture, vertices: vertices, sampler: sampler,
                                 pipeline: engine.texturePremultiplyViewPipeline,
                                 alpha: alpha)
    }

    private func drawPremultipliedTexture(_ texture: MTLTexture, vertices: [QuadVertexIn],
                                          sampler: MTLSamplerState,
                                          pipeline: MTLRenderPipelineState,
                                          alpha: Float) {
        var verts = vertices
        var viewU = viewUniforms
        var textureU = TextureUniforms(alpha: alpha)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
        encoder.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&textureU, length: MemoryLayout<TextureUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }

    func drawBWMask(_ texture: MTLTexture, rect: CGRect, uvRect: CGRect, sampler: MTLSamplerState) {
        var verts = MetalEngine.quadVertices(rect: rect, uvRect: uvRect)
        var viewU = viewUniforms
        encoder.setRenderPipelineState(engine.bwMaskPipeline)
        encoder.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
        encoder.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }

    func drawBlendPass(destination dst: MTLTexture, source src: MTLTexture,
                       targetSize: CGSize, layer: Layer, bounds: CGRect) {
        var verts = MetalEngine.quadVertices(rect: CGRect(origin: .zero, size: targetSize),
                                             uvRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        var viewU = ViewUniforms(viewSize: [Float(targetSize.width), Float(targetSize.height)])
        var blendU = BlendUniforms(
            compositeSize: [Float(targetSize.width), Float(targetSize.height)],
            layerOrigin: [Float(CGFloat(layer.offsetX) - bounds.minX),
                          Float(CGFloat(layer.offsetY) - bounds.minY)],
            layerSize: [Float(src.width), Float(src.height)],
            opacity: Float(layer.opacity / 100),
            mode: layer.blend.gpuMode
        )

        encoder.setRenderPipelineState(engine.blendPipeline)
        encoder.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
        encoder.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&blendU, length: MemoryLayout<BlendUniforms>.stride, index: 0)
        encoder.setFragmentTexture(dst, index: 0)
        encoder.setFragmentTexture(src, index: 1)
        encoder.setFragmentSamplerState(engine.nearestClampSampler, index: 0)
        encoder.setFragmentSamplerState(engine.nearestBorderSampler, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }
}
