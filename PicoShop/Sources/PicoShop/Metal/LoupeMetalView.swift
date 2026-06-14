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

    private var antsMesh: StrokeMesh?
    private var antsMeshVersion: UInt64 = .max

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

    private func syncAnimationMode(view: MTKView, model: AppModel) {
        let wantsContinuous = model.loupeShowSelection && model.selection != nil
        if wantsContinuous == view.isPaused {
            view.isPaused = !wantsContinuous
            view.enableSetNeedsDisplay = !wantsContinuous
        }
    }

    private func drawOnMain(in view: MTKView) {
        guard let model, let engine, let overlay,
              view.bounds.width > 0, view.bounds.height > 0 else { return }
        syncAnimationMode(view: view, model: model)
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
        let quad = MetalQuadEncoder(engine: engine, encoder: enc, viewSize: viewSize)

        // 背景チェッカー
        quad.drawCheckerboard(rect: CGRect(origin: .zero, size: viewSize), origin: .zero)

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
            quad.drawTexture(texture, rect: CGRect(origin: .zero, size: viewSize),
                             uvRect: uvRect, sampler: engine.nearestBorderSampler)
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
        if factor >= 2 && model.loupeShowGrid {
            let g = max(2, factor.rounded())
            var gx: CGFloat = fmod(viewSize.width / 2 + g / 2, g)
            while gx < viewSize.width {
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

        // 選択境界（マーチングアンツ）
        if model.loupeShowSelection, model.selection != nil, let path = model.selectionPath {
            if antsMeshVersion != model.selectionVersion {
                antsMesh = engine.flatMap {
                    StrokeMesh(device: $0.device,
                               polylines: Self.polylines(from: path),
                               closed: false)
                }
                antsMeshVersion = model.selectionVersion
            }
            if let mesh = antsMesh {
                let tx = -factor * cursor.x + viewSize.width / 2
                let ty = -factor * cursor.y + viewSize.height / 2
                let affine = CGAffineTransform(a: factor, b: 0, c: 0, d: factor, tx: tx, ty: ty)
                let transform = OverlayScene.Transform2D(affine: affine)
                let phase = CGFloat(CACurrentMediaTime() * 20).truncatingRemainder(dividingBy: 10)
                s.items.append(.strokeCached(mesh: mesh, width: 1, color: .white,
                                             dash: .init(on: 5, off: 5, phase: phase), transform: transform))
                s.items.append(.strokeCached(mesh: mesh, width: 1, color: .black,
                                             dash: .init(on: 5, off: 5, phase: phase + 5), transform: transform))
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

    private static func polylines(from path: Path) -> [[CGPoint]] {
        var lines: [[CGPoint]] = []
        var current: [CGPoint] = []
        func flush() {
            if current.count >= 2 { lines.append(current) }
            current = []
        }
        path.forEach { element in
            switch element {
            case .move(let to):
                flush()
                current = [to]
            case .line(let to):
                current.append(to)
            case .quadCurve(let to, _), .curve(let to, _, _):
                current.append(to)
            case .closeSubpath:
                if let first = current.first { current.append(first) }
                flush()
            }
        }
        flush()
        return lines
    }
}
