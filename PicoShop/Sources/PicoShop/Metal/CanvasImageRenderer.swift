import SwiftUI
import MetalKit

extension CanvasRenderer {
    func encodeCheckerboard(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize) {
        guard let engine else { return }
        let rect = canvasViewRect(model)
        guard rect.width > 0, rect.height > 0 else { return }
        MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)
            .drawCheckerboard(rect: rect, origin: [Float(rect.minX), Float(rect.minY)])
    }

    func encodeComposite(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize) {
        guard let engine, let texture = model.gpuCompositor?.compositeTexture else { return }

        // B&Wマスクプレビューモード（色域選択ツール）
        if model.colorRangePreviewOn {
            updateMaskTexture(model: model, engine: engine)
            let cw = model.canvasWidth, ch = model.canvasHeight
            guard cw > 0, ch > 0 else { return }
            let topLeft = model.canvasToView(.zero)
            let rect = CGRect(x: topLeft.x, y: topLeft.y,
                              width: CGFloat(cw) * model.zoom, height: CGFloat(ch) * model.zoom)
            let maskTex = maskTexture ?? engine.blackR8Texture
            MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)
                .drawBWMask(maskTex, rect: rect, uvRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                            sampler: model.zoom >= 1 ? engine.nearestClampSampler : engine.linearMipSampler)
            return
        }

        // 通常モード
        let b = model.compositeBounds
        let topLeft = model.canvasToView(CGPoint(x: b.minX, y: b.minY))
        let rect = CGRect(x: topLeft.x, y: topLeft.y,
                          width: b.width * model.zoom, height: b.height * model.zoom)
        MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)
            .drawTexture(texture, rect: rect, uvRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                         sampler: model.zoom >= 1 ? engine.nearestClampSampler : engine.linearMipSampler)
    }

    func encodeMovePreview(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize) {
        guard let engine,
              model.isDraggingTransform,
              model.tool == .move,
              let preview = model.currentMoveFloatingPreview() else {
            movePreviewTextureStore?.prune(keeping: Set<UUID>())
            return
        }
        movePreviewTextureStore?.prune(keeping: Set([preview.layer.id]))
        guard let texture = movePreviewTextureStore?.texture(for: preview.layer) else { return }

        let b = preview.originalBounds
        let affine = preview.transform.affine(center: CGPoint(x: b.midX, y: b.midY))
        func viewPoint(_ p: CGPoint) -> CGPoint {
            model.canvasToView(p.applying(affine))
        }
        let vertices = MetalEngine.quadVertices(
            topLeft: viewPoint(CGPoint(x: b.minX, y: b.minY)),
            topRight: viewPoint(CGPoint(x: b.maxX, y: b.minY)),
            bottomLeft: viewPoint(CGPoint(x: b.minX, y: b.maxY)),
            bottomRight: viewPoint(CGPoint(x: b.maxX, y: b.maxY))
        )
        MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)
            .drawPremultipliedTextureInView(texture, vertices: vertices,
                                            sampler: engine.linearClampSampler,
                                            alpha: Float(preview.layer.opacity / 100))
    }

    func updateMaskTexture(model: AppModel, engine: MetalEngine) {
        guard maskTextureVersion != model.selectionVersion else { return }
        maskTextureVersion = model.selectionVersion

        guard let sel = model.selection else {
            maskTexture = nil
            return
        }
        let w = max(1, sel.width), h = max(1, sel.height)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = engine.device.hasUnifiedMemory ? .shared : .managed
        guard let tex = engine.device.makeTexture(descriptor: desc) else { return }
        sel.data.withUnsafeBytes { ptr in
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: ptr.baseAddress!, bytesPerRow: w)
        }
        maskTexture = tex
    }

    // MARK: オーバーレイ（CanvasView の drawOverlays / drawMarchingAnts / drawRulers の移植）
}
