import SwiftUI
import AppKit

// MARK: - メインキャンバス

struct CanvasView: View {
    @EnvironmentObject var model: AppModel

    enum DragAction {
        case pan(base: CGSize)
        case rectSelect(start: CGPoint, aspect: CGFloat?, fromCenter: Bool)
        case lasso
        case brush
        case moveLayer(baseX: Int, baseY: Int, start: CGPoint)
        case transformMove(t0: SelectionTransform, p0: CGPoint)
        case transformScale(t0: SelectionTransform, p0: CGPoint, anchorBase: CGPoint,
                            center: CGPoint, axisX: Bool, axisY: Bool)
        case transformRotate(t0: SelectionTransform, p0: CGPoint, center: CGPoint)
        case ignore
    }

    @State var dragAction: DragAction?
    @State var previewRect: CGRect?
    @State var lassoPoints: [CGPoint] = []
    @State var lastBrushPoint: CGPoint?
    @State var hovering = false
    @State var lastHoverViewPoint: CGPoint = .zero
    @State var scrollMonitor: Any?
    @GestureState private var pinchDelta: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                // チェッカーボード・合成画像・オーバーレイ・定規はすべて Metal で描画
                CanvasMetalView(previewRect: previewRect,
                                lassoPoints: lassoPoints,
                                hovering: hovering)
            }
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    hovering = true
                    lastHoverViewPoint = p
                    model.mouseCanvasPos = model.viewToCanvas(p)
                    updateCursor()
                case .ended:
                    hovering = false
                    model.mouseCanvasPos = nil
                    NSCursor.arrow.set()
                @unknown default:
                    break
                }
            }
            .gesture(canvasDrag)
            .contextMenu {
                Button { model.cutSelection() } label: {
                    Label("カット", systemImage: "scissors")
                }
                    .disabled(model.selection == nil)
                Button { model.copySelectionToPasteboard() } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }
                    .disabled(model.selection == nil)
                Button { model.pasteFromPasteboard() } label: {
                    Label("ペースト", systemImage: "doc.on.clipboard")
                }
                Divider()
                Button { model.selectAll() } label: {
                    Label("すべてを選択", systemImage: "circle.dashed")
                }
                Button { model.invertSelection() } label: {
                    Label("選択を反転", systemImage: "circle.lefthalf.filled")
                }
                    .disabled(model.selection == nil)
                Button { model.clearSelection() } label: {
                    Label("選択をクリア", systemImage: "xmark.circle")
                }
                    .disabled(model.selection == nil)
                Button { model.cropActiveLayerToSelection() } label: {
                    Label("選択範囲をクロップ", systemImage: "crop")
                }
                    .disabled(model.selection == nil)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinchDelta) { v, s, _ in s = v }
                    .onEnded { v in model.setZoom(model.zoom * v, around: lastHoverViewPoint) }
            )
            .onAppear {
                model.viewSize = geo.size
                installScrollMonitor()
                if model.gpuCompositor?.compositeTexture != nil { model.fitToView() }
            }
            .onDisappear { removeScrollMonitor() }
            .onChange(of: geo.size) { _, s in model.viewSize = s }
        }
    }

}
