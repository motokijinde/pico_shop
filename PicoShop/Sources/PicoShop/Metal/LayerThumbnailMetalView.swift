import SwiftUI
import MetalKit

// MARK: - レイヤーサムネイルの Metal 描画

struct LayerThumbnailMetalView: NSViewRepresentable {
    var layer: Layer

    func makeCoordinator() -> LayerThumbnailRenderer { LayerThumbnailRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = PassthroughMTKView(frame: .zero, device: MetalEngine.shared?.device)
        view.colorPixelFormat = MetalEngine.viewPixelFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.delegate = context.coordinator
        context.coordinator.layer = layer
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.layer = layer
        view.needsDisplay = true
    }
}

@MainActor
final class LayerThumbnailRenderer: NSObject, MTKViewDelegate {
    var layer: Layer?

    private let engine = MetalEngine.shared
    private var textureStore: LayerTextureStore?

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawOnMain(in: view)
        }
    }

    private func drawOnMain(in view: MTKView) {
        guard let engine,
              let layer,
              view.bounds.width > 0,
              view.bounds.height > 0,
              let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = engine.queue.makeCommandBuffer() else { return }

        if textureStore == nil { textureStore = LayerTextureStore(device: engine.device) }
        guard let texture = textureStore?.texture(for: layer),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let viewSize = view.bounds.size
        let quad = MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)
        quad.drawCheckerboard(rect: CGRect(origin: .zero, size: viewSize), origin: .zero, tile: 4)

        let scale = min(viewSize.width / max(1, CGFloat(layer.buffer.width)),
                        viewSize.height / max(1, CGFloat(layer.buffer.height)))
        let size = CGSize(width: CGFloat(layer.buffer.width) * scale,
                          height: CGFloat(layer.buffer.height) * scale)
        let origin = CGPoint(x: (viewSize.width - size.width) / 2,
                             y: (viewSize.height - size.height) / 2)
        quad.drawTexture(texture,
                         rect: CGRect(origin: origin, size: size),
                         uvRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                         sampler: engine.nearestClampSampler)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
