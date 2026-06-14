import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {

    // MARK: - ドキュメント状態

    @Published var layers: [Layer] = []          // 先頭が最上位レイヤー
    @Published var canvasWidth: Int = 1024
    @Published var canvasHeight: Int = 768
    @Published var selection: SelectionMask? {
        didSet {
            selectionBounds = selection?.bounds()
            selectionPath = nil
            selectionVersion &+= 1
            if selection == nil { colorRangePreviewOn = false }
            let ver = selectionVersion
            guard let sel = selection else { return }
            Task.detached(priority: .userInitiated) { [weak self] in
                let path = sel.boundaryPath()
                await MainActor.run { [weak self] in
                    guard let self, self.selectionVersion == ver else { return }
                    self.selectionPath = path
                }
            }
        }
    }

    /// 選択範囲の世代番号（Metal 側のアンツメッシュ再構築判定用）
    private(set) var selectionVersion: UInt64 = 0
    @Published var activeLayerID: UUID? {
        didSet { if activeLayerID != oldValue { colorRangeLastPoint = nil } }
    }

    /// マーチングアンツ用の境界パス（selection 変更時に非同期で再計算されるキャッシュ）
    @Published private(set) var selectionPath: Path?

    /// 選択範囲の bbox キャッシュ（selection 変更時に同期更新、StatusBar 等が毎レンダーで呼ばないように）
    private(set) var selectionBounds: CGRect?

    @Published private(set) var compositeBounds: CGRect = CGRect(x: 0, y: 0, width: 1024, height: 768)

    /// GPU レイヤー合成器（キャンバス・ルーペ・ナビゲーターの共有テクスチャ源）
    let gpuCompositor: GPUCompositor? = MetalEngine.shared.flatMap { GPUCompositor(engine: $0) }

    @Published var projectURL: URL?

    // MARK: - ビュー状態

    @Published var zoom: CGFloat = 1
    @Published var panOffset: CGSize = .zero
    @Published var viewSize: CGSize = .zero

    /// マウス座標（高頻度更新のため AppModel ではなく HoverState が publish する）
    let hover = HoverState()
    var mouseCanvasPos: CGPoint? {
        get { hover.mouseCanvasPos }
        set { hover.mouseCanvasPos = newValue }
    }

    @Published var tool: Tool = .rectSelect {
        didSet {
            if tool != .colorRangeSelect { colorRangePreviewOn = false }
            if oldValue == .selectionTransform && tool != .selectionTransform {
                applySelectionTransform()
            }
            if oldValue == .move && tool != .move {
                commitMoveTransform()
            }
            if tool == .move {
                beginMoveTransform()
            }
        }
    }
    @Published var selectionOperationMode: SelectionOperationMode = .replace

    /// move ツールのプレビュー用フローティングレイヤー（ツールアクティブ中は常に有効）
    @Published var floatingLayer: Layer?

    struct PixelMovePreview {
        var initialLayerOffsetX: Int
        var initialLayerOffsetY: Int
    }
    var pixelMovePreview: PixelMovePreview?

    /// move ツール起動時に抽出した元ピクセル（リセット・再ラスタライズの基準）
    var originalMoveBuffer: PixelBuffer? = nil
    /// move ツール起動時の対象領域（キャンバス座標）
    @Published var originalMoveBounds: CGRect? = nil
    /// バックグラウンドタスク（抽出・プレビュー・確定）の競合防止用バージョン番号
    /// cleanup 時にインクリメントすることで飛行中タスクを一括キャンセルする
    var rasterizeVersion: UInt64 = 0
    /// ピクセル抽出バックグラウンドタスクの再入防止フラグ
    var isMoveExtracting = false

    @Published var showLoupe = false
    @Published var showOptionsPanel = true
    @Published var showLayersPanel = true
    @Published var showToolbar = true
    @Published var loupeZoom: Int = 400      // 100/200/400/800

    @Published var statusMessage: String?

    // MARK: - ダイアログ表示フラグ

    @Published var showNewFileDialog = false
    @Published var showCanvasSizeDialog = false
    @Published var showModifySelectionDialog = false
    @Published var showExportDialog = false

    // MARK: - ツールオプション

    @Published var colorRangeOpts = ColorRangeOptions()
    @Published var brushOpts = BrushOptions()
    @Published var fillOpts = FillOptions()
    @Published var resizeOpts = ResizeOptions()
    @Published var textOpts = TextOptions()
    @Published var rotateOpts = RotateOptions()
    @Published var foregroundColor = PixelColor.black

    /// 選択範囲変形（適用前のプレビュー状態）
    @Published var pendingTransform = SelectionTransform()

    /// ドラッグ中の変形プレビュー（非 @Published — SwiftUI 全体再評価を避けるため）
    /// Metal が毎フレーム読む。nil のとき pendingTransform を使う。
    var dragPreviewTransform: SelectionTransform? = nil
    /// ドラッグ中フラグ（連続描画モードの判定用）
    var isDraggingTransform: Bool = false

    /// 変形パネル・矩形選択のオプション
    @Published var transformKeepAspect = false
    @Published var rectSelKeepAspect = false
    @Published var rectSelFromCenter = false
    /// 変形前のマスク bbox（数値フィールド用）— selectionBounds キャッシュを参照
    var selectionBaseBounds: CGRect? { selectionBounds }

    /// クロップツールの保留矩形（キャンバス座標）

    /// 色域選択：B&Wマスクプレビューフラグ
    @Published var colorRangePreviewOn = false
    /// 色域選択：直前のクリック座標（再実行ボタン用）
    @Published var colorRangeLastPoint: CGPoint?

    /// ルーペ：選択境界表示フラグ
    @Published var loupeShowSelection: Bool = true
    /// ルーペ：グリッド表示フラグ
    @Published var loupeShowGrid: Bool = true

    /// 選択範囲 拡大/縮小の最後に使った値（クイックメニュー用）
    @Published var lastGrowShrinkAmount: Int = 8

    // MARK: - アンドゥ / リドゥ

    struct Snapshot {
        var layers: [Layer]
        var canvasWidth: Int
        var canvasHeight: Int
        var selection: SelectionMask?
        var activeLayerID: UUID?
        var label: String
    }

    @Published private(set) var undoStack: [Snapshot] = []
    @Published private(set) var redoStack: [Snapshot] = []
    var undoLabel: String? { undoStack.last?.label }
    var redoLabel: String? { redoStack.last?.label }

    private var coalesceKey: String?
    private var coalesceTime: Date = .distantPast

    // MARK: - キーボード

    private var keyDownMonitor: Any?
    @Published var spaceKeyDown = false

    init() {
        let layer = Layer(name: "レイヤー1", buffer: PixelBuffer(width: 1024, height: 768))
        layers = [layer]
        activeLayerID = layer.id
        recomposite()
        installKeyMonitors()
        openCommandLineFiles()
    }

    /// CLI からの起動用：PICOSHOP_OPEN（コロン区切りパス）で渡されたファイルを起動時に開く。
    /// argv にパスを渡すと AppKit がファイルオープンイベントとして解釈し
    /// WindowGroup のウィンドウ生成が抑制されるため、環境変数を使う。
    private func openCommandLineFiles() {
        guard let env = ProcessInfo.processInfo.environment["PICOSHOP_OPEN"] else { return }
        let urls = env.split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        if let pic = urls.first(where: { $0.pathExtension.lowercased() == "pic" }) {
            openProject(url: pic)
        }
        let images = urls.filter { $0.pathExtension.lowercased() != "pic" }
        if !images.isEmpty {
            openImageFiles(images)
        }
    }

    // MARK: - レイヤーアクセス

    var activeLayer: Layer? {
        guard let id = activeLayerID else { return nil }
        return layers.first { $0.id == id }
    }

    var activeLayerIndex: Int? {
        guard let id = activeLayerID else { return nil }
        return layers.firstIndex { $0.id == id }
    }

    /// アクティブレイヤーを変更（ロック検査つき）。ロック中なら警告して false。
    func withActiveLayer(checkLock: Bool = true, _ body: (inout Layer) -> Void) -> Bool {
        guard let idx = activeLayerIndex else {
            warn("レイヤーが選択されていません")
            return false
        }
        if checkLock && layers[idx].locked {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return false
        }
        body(&layers[idx])
        return true
    }

    /// 手動マスク編集の開始（選択がなければ空のマスクを作る）
    func beginBrushStroke() {
        pushUndo("手動マスク編集", coalesceKey: "brush")
        if selection == nil {
            selection = SelectionMask(width: canvasWidth, height: canvasHeight)
        }
    }

    func warn(_ message: String) {
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.statusMessage == message { self?.statusMessage = nil }
        }
    }

    // MARK: - 合成

    /// レイヤー変更後に呼ぶ。floatingLayer が存在する場合は最上位に追加して合成する。
    func recomposite() {
        var allLayers = layers
        if let fl = floatingLayer { allLayers.insert(fl, at: 0) }
        compositeBounds = Compositor.unionBounds(layers: allLayers, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        gpuCompositor?.composite(layers: allLayers, bounds: compositeBounds)
    }

    /// キャンバス座標の合成済みピクセル色（ルーペ・スポイト用、GPU から1ピクセル読み出し）
    func compositeColor(atCanvas p: CGPoint) -> PixelColor? {
        let x = Int(p.x.rounded(.down)) - Int(compositeBounds.minX)
        let y = Int(p.y.rounded(.down)) - Int(compositeBounds.minY)
        return gpuCompositor?.readPixel(x: x, y: y)
    }

    // MARK: - 座標変換（キャンバス座標 ↔ ビュー座標）

    var canvasCenter: CGPoint {
        CGPoint(x: CGFloat(canvasWidth) / 2, y: CGFloat(canvasHeight) / 2)
    }

    func canvasToView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - canvasCenter.x) * zoom + viewSize.width / 2 + panOffset.width,
                y: (p.y - canvasCenter.y) * zoom + viewSize.height / 2 + panOffset.height)
    }

    func viewToCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - viewSize.width / 2 - panOffset.width) / zoom + canvasCenter.x,
                y: (p.y - viewSize.height / 2 - panOffset.height) / zoom + canvasCenter.y)
    }

    /// 現在ビューに見えているキャンバス座標の矩形
    var visibleCanvasRect: CGRect {
        let tl = viewToCanvas(.zero)
        let br = viewToCanvas(CGPoint(x: viewSize.width, y: viewSize.height))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    // MARK: - ズーム / パン

    func setZoom(_ z: CGFloat, around viewPoint: CGPoint? = nil) {
        let newZoom = max(0.02, min(64, z))
        if let vp = viewPoint {
            // ポイント下のキャンバス座標を固定してズーム
            let c = viewToCanvas(vp)
            zoom = newZoom
            let after = canvasToView(c)
            panOffset.width += vp.x - after.x
            panOffset.height += vp.y - after.y
        } else {
            zoom = newZoom
        }
    }

    func zoomIn() { setZoom(zoom * 1.5) }
    func zoomOut() { setZoom(zoom / 1.5) }

    func fitToView() {
        guard viewSize.width > 0 else { return }
        let b = compositeBounds
        let s = min(viewSize.width / b.width, viewSize.height / b.height) * 0.92
        zoom = max(0.02, min(64, s))
        // composite の中心がビュー中心に来るように
        let bCenter = CGPoint(x: b.midX, y: b.midY)
        panOffset = CGSize(width: -(bCenter.x - canvasCenter.x) * zoom,
                           height: -(bCenter.y - canvasCenter.y) * zoom)
    }

    func zoomActualSize() {
        zoom = 1
        panOffset = .zero
    }

    /// ナビゲーターから：キャンバス座標 c がビュー中心に来るようにパン
    func scrollTo(canvasPoint c: CGPoint) {
        panOffset = CGSize(width: -(c.x - canvasCenter.x) * zoom,
                           height: -(c.y - canvasCenter.y) * zoom)
    }

    // MARK: - アンドゥ / リドゥ

    /// 変更前に呼ぶ。coalesceKey が同じ操作が 1 秒以内に続く場合はまとめる（カーソルキー連打用）
    func pushUndo(_ label: String, coalesceKey key: String? = nil) {
        if let key, key == coalesceKey, Date().timeIntervalSince(coalesceTime) < 1.0 {
            coalesceTime = Date()
            return
        }
        coalesceKey = key
        coalesceTime = Date()
        undoStack.append(currentSnapshot(label: label))
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        redoStack.removeAll()
    }

    private func currentSnapshot(label: String) -> Snapshot {
        Snapshot(layers: layers, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                 selection: selection, activeLayerID: activeLayerID, label: label)
    }

    /// 操作が失敗（ロック等）した場合に直前の pushUndo を取り消す
    func discardLastUndo() {
        guard !undoStack.isEmpty else { return }
        undoStack.removeLast()
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot(label: snap.label))
        restore(snap)
    }

    func redo() {
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot(label: snap.label))
        restore(snap)
    }

    private func restore(_ snap: Snapshot) {
        layers = snap.layers
        canvasWidth = snap.canvasWidth
        canvasHeight = snap.canvasHeight
        selection = snap.selection
        activeLayerID = snap.activeLayerID
        pendingTransform = SelectionTransform()
        floatingLayer = nil
        pixelMovePreview = nil
        originalMoveBuffer = nil
        originalMoveBounds = nil
        coalesceKey = nil
        recomposite()
        if tool == .move { beginMoveTransform() }
    }

    // MARK: - キーボード操作（カーソルキー 1px 調整）

    private func installKeyMonitors() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // テキスト編集中は何もしない
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            return event
        }

        // スペースキー（パン用）
        if event.keyCode == 49 {
            spaceKeyDown = (event.type == .keyDown)
            return nil
        }

        guard event.type == .keyDown else { return event }

        switch event.keyCode {
        case 123: return handleArrow(dx: -1, dy: 0, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 124: return handleArrow(dx: 1, dy: 0, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 125: return handleArrow(dx: 0, dy: 1, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 126: return handleArrow(dx: 0, dy: -1, shift: event.modifierFlags.contains(.shift)) ? nil : event
        case 51, 117:  // Delete / Forward Delete → カット
            if selection != nil {
                cutSelection()
                return nil
            }
            return event
        default:
            return event
        }
    }

    /// カーソルキー：位置移動（1px）、Shift+カーソルキー：サイズ変更（1px）
    /// 戻り値：イベントを消費したか
    @discardableResult
    func handleArrow(dx: Int, dy: Int, shift: Bool) -> Bool {
        // 選択変形ツール・選択系ツール・マスクブラシ → 選択マスクを操作
        let targetSelectionMask =
            (tool == .selectionTransform && selection != nil) ||
            (tool.isSelectionTool && selection != nil) ||
            (tool == .maskBrush && selection != nil)

        if targetSelectionMask {
            guard let sel = selection, let b = sel.bounds() else { return false }
            if shift {
                let newW = max(1, b.width + CGFloat(dx))
                let newH = max(1, b.height + CGFloat(dy))
                pushUndo("選択範囲のサイズ変更", coalesceKey: "sel-resize")
                selection = sel.transformed(
                    dx: 0, dy: 0,
                    scaleX: Double(newW / b.width), scaleY: Double(newH / b.height),
                    rotationDegrees: 0,
                    center: CGPoint(x: b.minX, y: b.minY)
                )
            } else {
                pushUndo("選択範囲の移動", coalesceKey: "sel-move")
                selection = sel.translated(dx: dx, dy: dy)
            }
            return true
        }

        // move ツール：floatingLayer の位置を 1px 動かす
        if tool == .move, originalMoveBounds != nil, !shift {
            extractMovePixels()  // ドラッグ前に矢印キーが押された場合も抽出を開始する
            pendingTransform.dx += Double(dx)
            pendingTransform.dy += Double(dy)
            if let buf = floatingLayer?.buffer, let bounds = originalMoveBounds {
                let midX = bounds.midX + pendingTransform.dx
                let midY = bounds.midY + pendingTransform.dy
                floatingLayer?.offsetX = Int((midX - Double(buf.width)  / 2).rounded())
                floatingLayer?.offsetY = Int((midY - Double(buf.height) / 2).rounded())
            }
            recomposite()
            return true
        }

        // レイヤー操作
        guard activeLayer != nil else { return false }
        if shift {
            guard let layer = activeLayer else { return false }
            let newW = max(1, layer.buffer.width + dx)
            let newH = max(1, layer.buffer.height + dy)
            pushUndo("レイヤーのサイズ変更", coalesceKey: "layer-resize")
            let ok = withActiveLayer { l in
                l.buffer = l.buffer.resized(width: newW, height: newH, quality: resizeOpts.quality)
                l.refreshCache()
            }
            if ok { recomposite() }
            return ok
        } else {
            pushUndo("レイヤーの移動", coalesceKey: "layer-move")
            let ok = withActiveLayer { l in
                l.offsetX += dx
                l.offsetY += dy
            }
            if ok { recomposite() }
            return ok
        }
    }

    deinit {
        // monitor は アプリ終了まで生存するため明示解放は不要だが念のため
        if let m = keyDownMonitor {
            NSEvent.removeMonitor(m)
        }
    }
}

// MARK: - ビュー幾何ヘルパー（CanvasView と Metal レンダラーで共用）

extension AppModel {

    /// キャンバス座標 → ビュー座標のアフィン変換
    var canvasToViewAffine: CGAffineTransform {
        let c = canvasCenter
        return CGAffineTransform(translationX: viewSize.width / 2 + panOffset.width - c.x * zoom,
                                 y: viewSize.height / 2 + panOffset.height - c.y * zoom)
            .scaledBy(x: zoom, y: zoom)
    }

    struct TransformHandles {
        var corners: [CGPoint]
        var edges: [CGPoint]
        var center: CGPoint
        var cornersBase: [CGPoint]
        var edgesBase: [CGPoint]
        var bounds: CGRect
    }

    /// 変形ツールのハンドル位置（ビュー座標）。
    /// transform ツールは selection == nil のときアクティブレイヤーの frame を使う。
    func transformHandles() -> TransformHandles? {
        let b: CGRect
        if let selBounds = selectionBaseBounds {
            b = selBounds
        } else if tool == .move, let mb = originalMoveBounds {
            b = mb
        } else if (tool == .transform || tool == .selectionTransform), let layer = activeLayer {
            b = CGRect(x: CGFloat(layer.offsetX), y: CGFloat(layer.offsetY),
                       width: CGFloat(layer.buffer.width), height: CGFloat(layer.buffer.height))
        } else {
            return nil
        }
        let t = pendingTransform
        let center = CGPoint(x: b.midX, y: b.midY)
        let affine = t.affine(center: center).concatenating(canvasToViewAffine)

        let cornersBase = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                           CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
        let edgesBase = [CGPoint(x: b.midX, y: b.minY), CGPoint(x: b.maxX, y: b.midY),
                         CGPoint(x: b.midX, y: b.maxY), CGPoint(x: b.minX, y: b.midY)]
        return TransformHandles(
            corners: cornersBase.map { $0.applying(affine) },
            edges: edgesBase.map { $0.applying(affine) },
            center: center.applying(t.affine(center: center)).applying(canvasToViewAffine),
            cornersBase: cornersBase,
            edgesBase: edgesBase,
            bounds: b
        )
    }
}
