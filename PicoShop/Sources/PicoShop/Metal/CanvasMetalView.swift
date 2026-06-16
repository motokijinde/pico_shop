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

    weak var model: AppModel?
    weak var view: MTKView?
    let engine = MetalEngine.shared
    var overlay: OverlayRenderer?
    var cancellables: Set<AnyCancellable> = []

    /// B&Wマスクプレビュー用テクスチャ（選択範囲が変わったときだけ再構築）
    var maskTexture: MTLTexture?
    var maskTextureVersion: UInt64 = .max

    /// マーチングアンツ用キャッシュ（選択範囲が変わったときだけ再構築）
    var antsMesh: StrokeMesh?
    var antsMeshVersion: UInt64 = .max

    /// バウンディングボックス破線用キャッシュ（selection != nil のとき）
    var bboxMesh: StrokeMesh?
    var bboxMeshVersion: UInt64 = .max

    /// move ドラッグ中に合成テクスチャを更新せず、表示だけ重ねるための浮動レイヤーテクスチャ
    var movePreviewTextureStore: LayerTextureStore?

    /// selectionTransform + selection == nil のとき使うレイヤー境界メッシュ
    var layerBoundsMesh: StrokeMesh?
    var layerBoundsMeshKey: String = ""

    func attach(model: AppModel, view: MTKView) {
        self.model = model
        self.view = view
        if let engine {
            overlay = OverlayRenderer(engine: engine)
            movePreviewTextureStore = LayerTextureStore(device: engine.device)
        }
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

    func drawOnMain(in view: MTKView) {
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
            encodeMovePreview(enc, model: model, viewSize: viewSize, scale: scale)
            let scene = buildScene(model: model, viewSize: viewSize)
            overlay.encode(scene: scene, encoder: enc, viewSize: viewSize, scale: scale)
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
    }

    /// 選択範囲がある・selectionTransform ツール使用中・ドラッグ中は連続描画（アンツのアニメ）、それ以外はイベント駆動
    func syncAnimationMode(view: MTKView, model: AppModel) {
        let wantsContinuous = model.selection != nil
            || (model.tool == .selectionTransform && model.activeLayer != nil)
            || (model.tool == .move && model.floatingLayer != nil)
            || model.isDraggingTransform
        if wantsContinuous == view.isPaused {
            view.isPaused = !wantsContinuous
            view.enableSetNeedsDisplay = !wantsContinuous
        }
    }

    // MARK: 画像レイヤー

    func canvasViewRect(_ model: AppModel) -> CGRect {
        let tl = model.canvasToView(.zero)
        let br = model.canvasToView(CGPoint(x: CGFloat(model.canvasWidth),
                                            y: CGFloat(model.canvasHeight)))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }
}
