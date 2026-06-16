import SwiftUI
import MetalKit

extension CanvasRenderer {
    func encodeCheckerboard(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize) {
        guard let engine else { return }
        let rect = canvasViewRect(model)
        guard rect.width > 0, rect.height > 0 else { return }
        let quad = MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)
        quad.drawCheckerboard(rect: rect,
                              origin: [Float(rect.minX), Float(rect.minY)],
                              tile: 8,
                              colorA: [0.90, 0.96, 1.0, 1],
                              colorB: [0.70, 0.82, 0.92, 1])

        if let activeLayer = model.activeLayer, activeLayer.visible {
            let layerRect = activeLayer.frame.applying(model.canvasToViewAffine)
            let visibleLayerRect = layerRect.intersection(rect)
            if !visibleLayerRect.isNull, visibleLayerRect.width > 0, visibleLayerRect.height > 0 {
                quad.drawCheckerboard(rect: visibleLayerRect,
                                      origin: [Float(layerRect.minX), Float(layerRect.minY)])
            }
        }
    }

    func encodeComposite(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize) {
        guard let engine, let texture = model.gpuCompositor?.compositeTexture else { return }

        // B&Wマスクプレビューモード（全選択ツール共通）
        if model.bwPreviewOn {
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

    func encodeMovePreview(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize, scale: CGFloat) {
        guard let engine,
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
        let quad = MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)
        let fullRect = CGRect(origin: .zero, size: viewSize)
        let canvasRect = canvasViewRect(model).intersection(fullRect)
        let alpha = Float(preview.layer.opacity / 100)

        if !canvasRect.isNull, canvasRect.width > 0, canvasRect.height > 0 {
            let destinationFrame = model.moveLayer?.frame
                .applying(model.canvasToViewAffine)
            let committedRect = destinationFrame?.intersection(canvasRect) ?? canvasRect

            if !committedRect.isNull, committedRect.width > 0, committedRect.height > 0 {
                drawMovePreview(texture, vertices: vertices, quad: quad, encoder: enc,
                                rect: committedRect, viewSize: viewSize, scale: scale,
                                alpha: alpha)
            }

            if let destinationFrame {
                for clippedByLayerRect in outsideRects(of: destinationFrame, in: canvasRect) {
                    drawMovePreview(texture, vertices: vertices, quad: quad, encoder: enc,
                                    rect: clippedByLayerRect, viewSize: viewSize, scale: scale,
                                    alpha: alpha * 0.45)
                }
            }

            for outsideRect in outsideRects(of: canvasRect, in: fullRect) {
                drawMovePreview(texture, vertices: vertices, quad: quad, encoder: enc,
                                rect: outsideRect, viewSize: viewSize, scale: scale,
                                alpha: alpha * 0.2)
            }
            setScissor(fullRect, viewSize: viewSize, scale: scale, encoder: enc)
        } else {
            quad.drawPremultipliedTextureInView(texture, vertices: vertices,
                                                sampler: engine.linearClampSampler,
                                                alpha: alpha * 0.2)
        }
    }

    private func drawMovePreview(_ texture: MTLTexture, vertices: [QuadVertexIn],
                                 quad: MetalQuadEncoder, encoder: MTLRenderCommandEncoder,
                                 rect: CGRect, viewSize: CGSize, scale: CGFloat, alpha: Float) {
        setScissor(rect, viewSize: viewSize, scale: scale, encoder: encoder)
        quad.drawPremultipliedTextureInView(texture, vertices: vertices,
                                            sampler: quad.engine.linearClampSampler,
                                            alpha: alpha)
    }

    private func outsideRects(of rect: CGRect, in full: CGRect) -> [CGRect] {
        let rect = rect.intersection(full)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else {
            return full.width > 0 && full.height > 0 ? [full] : []
        }
        var rects: [CGRect] = []
        if rect.minY > full.minY {
            rects.append(CGRect(x: full.minX, y: full.minY, width: full.width, height: rect.minY - full.minY))
        }
        if rect.maxY < full.maxY {
            rects.append(CGRect(x: full.minX, y: rect.maxY, width: full.width, height: full.maxY - rect.maxY))
        }
        if rect.minX > full.minX {
            rects.append(CGRect(x: full.minX, y: rect.minY, width: rect.minX - full.minX, height: rect.height))
        }
        if rect.maxX < full.maxX {
            rects.append(CGRect(x: rect.maxX, y: rect.minY, width: full.maxX - rect.maxX, height: rect.height))
        }
        return rects.filter { $0.width > 0 && $0.height > 0 }
    }

    private func setScissor(_ rect: CGRect, viewSize: CGSize, scale: CGFloat, encoder: MTLRenderCommandEncoder) {
        let full = CGRect(origin: .zero, size: viewSize)
        let r = rect.intersection(full)
        guard !r.isNull, r.width > 0, r.height > 0 else { return }
        let x = max(0, Int((r.minX * scale).rounded(.down)))
        let y = max(0, Int((r.minY * scale).rounded(.down)))
        let maxX = min(Int((viewSize.width * scale).rounded(.up)), Int((r.maxX * scale).rounded(.up)))
        let maxY = min(Int((viewSize.height * scale).rounded(.up)), Int((r.maxY * scale).rounded(.up)))
        encoder.setScissorRect(MTLScissorRect(x: x, y: y, width: max(1, maxX - x), height: max(1, maxY - y)))
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
