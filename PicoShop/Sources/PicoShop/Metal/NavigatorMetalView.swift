import SwiftUI
import MetalKit
import Combine

// MARK: - ナビゲーターサムネイルの Metal 描画
//
// 合成テクスチャをスケールフィットで描き、現在の可視範囲を赤枠で重ねる。
// クリック/ドラッグでのスクロールは SwiftUI 側（NavigatorPanel）が処理する。

struct NavigatorMetalView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> NavigatorRenderer { NavigatorRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = PassthroughMTKView(frame: .zero, device: MetalEngine.shared?.device)
        view.colorPixelFormat = MetalEngine.viewPixelFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.delegate = context.coordinator
        context.coordinator.attach(model: model, view: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        view.needsDisplay = true
    }
}

@MainActor
final class NavigatorRenderer: NSObject, MTKViewDelegate {

    private weak var model: AppModel?
    private weak var view: MTKView?
    private let engine = MetalEngine.shared
    private var overlay: OverlayRenderer?
    private var cancellable: AnyCancellable?

    func attach(model: AppModel, view: MTKView) {
        self.model = model
        self.view = view
        if let engine { overlay = OverlayRenderer(engine: engine) }
        cancellable = model.objectWillChange.sink { [weak view] _ in
            view?.needsDisplay = true
        }
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawOnMain(in: view)
        }
    }

    private func drawOnMain(in view: MTKView) {
        guard let model, let engine, let overlay,
              view.bounds.width > 0, view.bounds.height > 0 else { return }
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = engine.queue.makeCommandBuffer() else { return }

        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let bg = NSColor.underPageBackgroundColor.usingColorSpace(.sRGB) ?? .darkGray
            rpd.colorAttachments[0].clearColor = MTLClearColor(
                red: Double(bg.redComponent), green: Double(bg.greenComponent),
                blue: Double(bg.blueComponent), alpha: 1)

            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
            let viewSize = view.bounds.size
            var viewU = ViewUniforms(viewSize: [Float(viewSize.width), Float(viewSize.height)])

            let b = model.compositeBounds
            let scale = min(viewSize.width / max(1, b.width), viewSize.height / max(1, b.height))
            let thumbSize = CGSize(width: b.width * scale, height: b.height * scale)
            let origin = CGPoint(x: (viewSize.width - thumbSize.width) / 2,
                                 y: (viewSize.height - thumbSize.height) / 2)

            if let texture = model.gpuCompositor?.compositeTexture {
                var verts = MetalEngine.quadVertices(
                    rect: CGRect(origin: origin, size: thumbSize),
                    uvRect: CGRect(x: 0, y: 0, width: 1, height: 1))
                var alpha: Float = 1
                enc.setRenderPipelineState(engine.quadPipeline)
                enc.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
                enc.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
                enc.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
                enc.setFragmentTexture(texture, index: 0)
                enc.setFragmentSamplerState(engine.linearMipSampler, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
            }

            // 赤枠：現在見えている範囲
            var s = OverlayScene()
            let visible = model.visibleCanvasRect.intersection(
                CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height))
            if !visible.isNull, visible.width > 0 {
                let r = CGRect(x: origin.x + (visible.minX - b.minX) * scale,
                               y: origin.y + (visible.minY - b.minY) * scale,
                               width: max(4, visible.width * scale),
                               height: max(4, visible.height * scale))
                s.strokeRect(r, width: 1.5, color: .red)
            }
            let backingScale = view.window?.backingScaleFactor ?? 2
            overlay.encode(scene: s, encoder: enc, viewSize: viewSize, scale: backingScale)
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
    }
}
