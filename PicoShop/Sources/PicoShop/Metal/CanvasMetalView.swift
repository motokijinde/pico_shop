import SwiftUI
import MetalKit
import Combine

// MARK: - メインキャンバスの Metal 描画
//
// チェッカーボード → 合成画像 → オーバーレイ（枠・選択・定規等）を 1 つの MTKView で描く。
// 入力（ジェスチャー・ホバー）は従来どおり SwiftUI 側で処理するため、
// この NSView はヒットテストを素通しする。
// 描画は常に draw() 時点の最新状態のスナップショットを使う（latest-wins）。

/// マウスイベントを下の SwiftUI ジェスチャーに通す MTKView
final class PassthroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct CanvasMetalView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel
    var previewRect: CGRect?
    var lassoPoints: [CGPoint]
    var hovering: Bool

    func makeCoordinator() -> CanvasRenderer { CanvasRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = PassthroughMTKView(frame: .zero, device: MetalEngine.shared?.device)
        view.colorPixelFormat = MetalEngine.viewPixelFormat
        view.preferredFramesPerSecond = 30   // マーチングアンツのアニメ用（選択中のみ連続描画）
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.delegate = context.coordinator
        context.coordinator.attach(model: model, view: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.previewRect = previewRect
        context.coordinator.lassoPoints = lassoPoints
        context.coordinator.hovering = hovering
        view.needsDisplay = true
    }
}

// MARK: - レンダラー

@MainActor
final class CanvasRenderer: NSObject, MTKViewDelegate {

    var previewRect: CGRect?
    var lassoPoints: [CGPoint] = []
    var hovering = false

    private weak var model: AppModel?
    private weak var view: MTKView?
    private let engine = MetalEngine.shared
    private var overlay: OverlayRenderer?
    private var cancellables: Set<AnyCancellable> = []

    /// マーチングアンツ用キャッシュ（選択範囲が変わったときだけ再構築）
    private var antsMesh: StrokeMesh?
    private var antsMeshVersion: UInt64 = .max

    func attach(model: AppModel, view: MTKView) {
        self.model = model
        self.view = view
        if let engine { overlay = OverlayRenderer(engine: engine) }
        // モデル変更（ズーム・パン・合成・ツール状態）で再描画。
        // 連続描画モード中は冗長な needsDisplay になるだけで害はない。
        model.objectWillChange.sink { [weak view] _ in
            view?.needsDisplay = true
        }.store(in: &cancellables)
        // マウス移動はブラシカーソル追従用（描画は GPU なので毎イベントでも軽い）
        model.hover.objectWillChange.sink { [weak view] _ in
            view?.needsDisplay = true
        }.store(in: &cancellables)
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

        syncAnimationMode(view: view, model: model)

        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = engine.queue.makeCommandBuffer() else { return }

        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let bg = (NSColor.underPageBackgroundColor.usingColorSpace(.sRGB)) ?? .darkGray
            rpd.colorAttachments[0].clearColor = MTLClearColor(
                red: Double(bg.redComponent) * Double(bg.alphaComponent),
                green: Double(bg.greenComponent) * Double(bg.alphaComponent),
                blue: Double(bg.blueComponent) * Double(bg.alphaComponent),
                alpha: 1)

            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
            let viewSize = view.bounds.size
            let scale = view.window?.backingScaleFactor ?? 2

            encodeCheckerboard(enc, model: model, viewSize: viewSize)
            encodeComposite(enc, model: model, viewSize: viewSize)
            let scene = buildScene(model: model, viewSize: viewSize)
            overlay.encode(scene: scene, encoder: enc, viewSize: viewSize, scale: scale)
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
    }

    /// 選択範囲があるときだけ連続描画（アンツのアニメ）、それ以外はイベント駆動
    private func syncAnimationMode(view: MTKView, model: AppModel) {
        let wantsContinuous = model.selection != nil
        if wantsContinuous == view.isPaused {
            view.isPaused = !wantsContinuous
            view.enableSetNeedsDisplay = !wantsContinuous
        }
    }

    // MARK: 画像レイヤー

    private func canvasViewRect(_ model: AppModel) -> CGRect {
        let tl = model.canvasToView(.zero)
        let br = model.canvasToView(CGPoint(x: CGFloat(model.canvasWidth),
                                            y: CGFloat(model.canvasHeight)))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    private func encodeCheckerboard(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize) {
        guard let engine else { return }
        let rect = canvasViewRect(model)
        guard rect.width > 0, rect.height > 0 else { return }
        var verts = MetalEngine.quadVertices(rect: rect, uvRect: .zero)
        var viewU = ViewUniforms(viewSize: [Float(viewSize.width), Float(viewSize.height)])
        var checker = CheckerUniforms(
            origin: [Float(rect.minX), Float(rect.minY)],
            tile: 8,
            colorA: [1, 1, 1, 1],
            colorB: [0.82, 0.82, 0.82, 1]
        )
        enc.setRenderPipelineState(engine.checkerPipeline)
        enc.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
        enc.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        enc.setFragmentBytes(&checker, length: MemoryLayout<CheckerUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }

    private func encodeComposite(_ enc: MTLRenderCommandEncoder, model: AppModel, viewSize: CGSize) {
        guard let engine, let texture = model.gpuCompositor?.compositeTexture else { return }
        let b = model.compositeBounds
        let topLeft = model.canvasToView(CGPoint(x: b.minX, y: b.minY))
        let rect = CGRect(x: topLeft.x, y: topLeft.y,
                          width: b.width * model.zoom, height: b.height * model.zoom)
        var verts = MetalEngine.quadVertices(rect: rect, uvRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        var viewU = ViewUniforms(viewSize: [Float(viewSize.width), Float(viewSize.height)])
        var alpha: Float = 1
        enc.setRenderPipelineState(engine.quadPipeline)
        enc.setVertexBytes(&verts, length: MemoryLayout<QuadVertexIn>.stride * verts.count, index: 0)
        enc.setVertexBytes(&viewU, length: MemoryLayout<ViewUniforms>.stride, index: 1)
        enc.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        // 拡大はドット感維持で nearest、縮小は mipmap 補間
        enc.setFragmentSamplerState(model.zoom >= 1 ? engine.nearestClampSampler
                                                    : engine.linearMipSampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }

    // MARK: オーバーレイ（CanvasView の drawOverlays / drawMarchingAnts / drawRulers の移植）

    private func buildScene(model: AppModel, viewSize: CGSize) -> OverlayScene {
        var s = OverlayScene()
        let canvasRect = canvasViewRect(model)
        let toView = model.canvasToViewAffine
        let accent = NSColor.controlAccentColor

        // キャンバス外の暗転 + 点線枠
        s.dimOutside(canvasRect, in: viewSize, color: NSColor.black.withAlphaComponent(0.35))
        s.strokeRect(canvasRect, width: 1, color: .white, dash: .init(on: 5, off: 4))

        // 中心の十字（破線）
        let center = model.canvasToView(model.canvasCenter)
        let crossColor = NSColor.gray.withAlphaComponent(0.55)
        let crossDash = OverlayScene.Dash(on: 3, off: 3)
        s.stroke([CGPoint(x: canvasRect.minX, y: center.y), CGPoint(x: canvasRect.maxX, y: center.y)],
                 color: crossColor, dash: crossDash)
        s.stroke([CGPoint(x: center.x, y: canvasRect.minY), CGPoint(x: center.x, y: canvasRect.maxY)],
                 color: crossColor, dash: crossDash)

        // ドラッグ中の矩形プレビュー
        if let r = previewRect {
            let vr = r.applying(toView)
            s.fill(vr, color: accent.withAlphaComponent(0.12))
            s.strokeRect(vr, width: 1, color: accent)
        }

        // クロップ範囲
        if model.tool == .crop, let r = model.cropRect {
            let vr = r.applying(toView)
            s.dimOutside(vr, in: viewSize, color: NSColor.black.withAlphaComponent(0.3))
            s.strokeRect(vr, width: 1.5, color: .yellow, dash: .init(on: 6, off: 3))
        }

        // フリーハンド選択の軌跡
        if lassoPoints.count >= 2 {
            s.stroke(lassoPoints.map { $0.applying(toView) }, width: 1, color: accent)
        }

        // ブラシカーソル（マスクブラシツールのみ）
        if model.tool == .maskBrush, hovering, let mp = model.mouseCanvasPos {
            let r = CGFloat(model.brushOpts.size) / 2 * model.zoom
            let c = model.canvasToView(mp)
            s.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2),
                            width: 1, color: model.brushOpts.add ? .green : .red)
        }

        // 変形ハンドル（変形ツールのみ）
        if model.tool == .transform, let h = model.transformHandles() {
            for p in h.corners + h.edges {
                let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                s.fill(r, color: .white)
                s.strokeRect(r, width: 1, color: .black)
            }
            let cr = CGRect(x: h.center.x - 5, y: h.center.y - 5, width: 10, height: 10)
            s.fillEllipse(in: cr, color: .white)
            s.strokeEllipse(in: cr, width: 1, color: .black)
        }

        buildMarchingAnts(&s, model: model)
        buildRulers(&s, model: model, viewSize: viewSize)
        return s
    }

    private func buildMarchingAnts(_ s: inout OverlayScene, model: AppModel) {
        guard model.selection != nil, let path = model.selectionPath else { return }

        if antsMeshVersion != model.selectionVersion {
            antsMesh = engine.flatMap { StrokeMesh(device: $0.device,
                                                   polylines: Self.polylines(from: path),
                                                   closed: false) }
            antsMeshVersion = model.selectionVersion
        }
        guard let mesh = antsMesh else { return }

        // pendingTransform のプレビューは変形ツールのみ適用
        var affine = model.canvasToViewAffine
        if model.tool == .transform, !model.pendingTransform.isIdentity,
           let b = model.selectionBaseBounds {
            affine = model.pendingTransform
                .affine(center: CGPoint(x: b.midX, y: b.midY))
                .concatenating(affine)
        }
        let transform = OverlayScene.Transform2D(affine: affine)
        let phase = CGFloat(CACurrentMediaTime() * 20).truncatingRemainder(dividingBy: 10)
        s.items.append(.strokeCached(mesh: mesh, width: 1, color: .white,
                                     dash: .init(on: 5, off: 5, phase: phase), transform: transform))
        s.items.append(.strokeCached(mesh: mesh, width: 1, color: .black,
                                     dash: .init(on: 5, off: 5, phase: phase + 5), transform: transform))
    }

    /// SwiftUI Path（move/line/close 前提）→ ポリライン列。close は先頭点を末尾に複製して表現。
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
                current.append(to)  // 境界パスには現れない想定の保険
            case .closeSubpath:
                if let first = current.first { current.append(first) }
                flush()
            }
        }
        flush()
        return lines
    }

    private static let rulerSize: CGFloat = 20

    private func buildRulers(_ s: inout OverlayScene, model: AppModel, viewSize: CGSize) {
        let rulerSize = Self.rulerSize
        let bg = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        s.fill(CGRect(x: 0, y: 0, width: viewSize.width, height: rulerSize), color: bg)
        s.fill(CGRect(x: 0, y: 0, width: rulerSize + 4, height: viewSize.height), color: bg)

        let candidates: [CGFloat] = [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
        let step = candidates.first { $0 * model.zoom >= 42 } ?? 5000
        let visible = model.visibleCanvasRect
        let tickColor = NSColor.secondaryLabelColor
        let labelColor = NSColor.secondaryLabelColor

        var x = (visible.minX / step).rounded(.down) * step
        while x <= visible.maxX {
            let vx = model.canvasToView(CGPoint(x: x, y: 0)).x
            if vx >= rulerSize {
                s.stroke([CGPoint(x: vx, y: rulerSize - 6), CGPoint(x: vx, y: rulerSize)],
                         color: tickColor)
                s.text(String(Int(x)), at: CGPoint(x: vx + 2, y: 6), anchor: .leading,
                       fontSize: 9, color: labelColor)
            }
            x += step
        }

        var y = (visible.minY / step).rounded(.down) * step
        while y <= visible.maxY {
            let vy = model.canvasToView(CGPoint(x: 0, y: y)).y
            if vy >= rulerSize {
                s.stroke([CGPoint(x: rulerSize - 2, y: vy), CGPoint(x: rulerSize + 4, y: vy)],
                         color: tickColor)
                s.text(String(Int(y)), at: CGPoint(x: 2, y: vy + 2), anchor: .topLeading,
                       fontSize: 9, color: labelColor)
            }
            y += step
        }

        let borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.4)
        s.stroke([CGPoint(x: 0, y: rulerSize), CGPoint(x: viewSize.width, y: rulerSize)],
                 color: borderColor)
        s.stroke([CGPoint(x: rulerSize + 4, y: 0), CGPoint(x: rulerSize + 4, y: viewSize.height)],
                 color: borderColor)
    }
}
