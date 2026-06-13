import SwiftUI
import MetalKit
import Combine

// MARK: - ルーペの Metal 描画
//
// 合成テクスチャからカーソル周辺を nearest サンプリングで拡大表示する。
// draw() は常にその時点の最新マウス位置（HoverState）を読むため、
// マウスが速く動いても古い位置のフレームを描き続けることがない（latest-wins）。

struct LoupeMetalView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> LoupeRenderer { LoupeRenderer() }

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

// MARK: - レンダラー

@MainActor
final class LoupeRenderer: NSObject, MTKViewDelegate {

    private weak var model: AppModel?
    private weak var view: MTKView?
    private let engine = MetalEngine.shared
    private var overlay: OverlayRenderer?
    private var cancellables: Set<AnyCancellable> = []

    func attach(model: AppModel, view: MTKView) {
        self.model = model
        self.view = view
        if let engine { overlay = OverlayRenderer(engine: engine) }
        // マウス移動・合成更新・ズーム切り替えのどれでも再描画
        model.objectWillChange.sink { [weak view] _ in
            view?.needsDisplay = true
        }.store(in: &cancellables)
        model.hover.objectWillChange.sink { [weak view] _ in
            view?.needsDisplay = true
        }.store(in: &cancellables)
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        Task { @MainActor [weak view] in view?.needsDisplay = true }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            drawOnMain(in: view)
        }
    }

    /// カーソル位置（キャンバス外なら境界にクランプ）
    private func cursorPos(_ model: AppModel) -> CGPoint {
        let p = model.mouseCanvasPos ?? model.canvasCenter
        return CGPoint(
            x: min(max(p.x, 0), CGFloat(model.canvasWidth) - 0.001),
            y: min(max(p.y, 0), CGFloat(model.canvasHeight) - 0.001)
        )
    }

    private func drawOnMain(in view: MTKView) {
        guard let model, let engine, let overlay,
              view.bounds.width > 0, view.bounds.height > 0 else { return }
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = engine.queue.makeCommandBuffer() else { return }

        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let viewSize = view.bounds.size
        let scale = view.window?.backingScaleFactor ?? 2
        // メイン画面倍率と合算：ルーペが常に主画面よりさらに拡大された状態になる
        let factor = CGFloat(model.loupeZoom) / 100 * model.zoom
        let p = cursorPos(model)
        var viewU = ViewUniforms(viewSize: [Float(viewSize.width), Float(viewSize.height)])

        // 背景チェッカー
        var checkerVerts = MetalEngine.quadVertices(
            rect: CGRect(origin: .zero, size: viewSize), uvRect: .zero)
        var checker = CheckerUniforms(origin: .zero, tile: 8,
                                      colorA: [1, 1, 1, 1], colorB: [0.82, 0.82, 0.82, 1])
        enc.setRenderPipelineState(engine.checkerPipeline)
        enc.setVertexBytes(&checkerVerts, length: MemoryLayout<QuadVertexIn>.stride * checkerVerts.count, index: 0)
        enc.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        enc.setFragmentBytes(&checker, length: MemoryLayout<CheckerUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: checkerVerts.count)

        // カーソル周辺の拡大像（uv が [0,1] を超えた部分は border=透明 → チェッカーが見える）
        if let texture = model.gpuCompositor?.compositeTexture {
            let b = model.compositeBounds
            let cropW = viewSize.width / factor
            let cropH = viewSize.height / factor
            let texW = CGFloat(texture.width), texH = CGFloat(texture.height)
            let uvRect = CGRect(
                x: (p.x - cropW / 2 - b.minX) / texW,
                y: (p.y - cropH / 2 - b.minY) / texH,
                width: cropW / texW,
                height: cropH / texH
            )
            var verts = MetalEngine.quadVertices(rect: CGRect(origin: .zero, size: viewSize),
                                                 uvRect: uvRect)
            var alpha: Float = 1
            enc.setRenderPipelineState(engine.quadPipeline)
            enc.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
            enc.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
            enc.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
            enc.setFragmentTexture(texture, index: 0)
            enc.setFragmentSamplerState(engine.nearestBorderSampler, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
        }

        // グリッド・十字マーカー（色情報は SwiftUI の LoupeInfoBar に移行）
        let scene = buildOverlay(model: model, viewSize: viewSize, factor: factor, cursor: p)
        overlay.encode(scene: scene, encoder: enc, viewSize: viewSize, scale: scale)

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func buildOverlay(model: AppModel, viewSize: CGSize,
                              factor: CGFloat, cursor: CGPoint) -> OverlayScene {
        var s = OverlayScene()

        // ピクセルグリッド（200% 以上かつグリッド表示ON）
        // factor を整数に丸めることで線がサブピクセル位置に落ちず縞々にならない
        if factor >= 2 {
            let g = max(2, factor.rounded())
            var gx: CGFloat = fmod(viewSize.width / 2 + g / 2, g)
            while gx < viewSize.width {
                // 白→黒を同位置に重ねて描くと α合成により結果が [69,115] に収束し
                // 背景が黒・白どちらでも必ず視認できる中間トーンになる
                s.stroke([CGPoint(x: gx, y: 0), CGPoint(x: gx, y: viewSize.height)],
                         width: 1, color: NSColor.white.withAlphaComponent(0.55))
                s.stroke([CGPoint(x: gx, y: 0), CGPoint(x: gx, y: viewSize.height)],
                         width: 1, color: NSColor.black.withAlphaComponent(0.5))
                gx += g
            }
            var gy: CGFloat = fmod(viewSize.height / 2 + g / 2, g)
            while gy < viewSize.height {
                s.stroke([CGPoint(x: 0, y: gy), CGPoint(x: viewSize.width, y: gy)],
                         width: 1, color: NSColor.white.withAlphaComponent(0.55))
                s.stroke([CGPoint(x: 0, y: gy), CGPoint(x: viewSize.width, y: gy)],
                         width: 1, color: NSColor.black.withAlphaComponent(0.5))
                gy += g
            }
        }

        // 中央の十字マーカー
        let cx = viewSize.width / 2, cy = viewSize.height / 2
        s.stroke([CGPoint(x: cx - 10, y: cy), CGPoint(x: cx + 10, y: cy)], width: 1.5, color: .red)
        s.stroke([CGPoint(x: cx, y: cy - 10), CGPoint(x: cx, y: cy + 10)], width: 1.5, color: .red)
        s.strokeEllipse(in: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10),
                        width: 1.5, color: .red)

        return s
    }
}
