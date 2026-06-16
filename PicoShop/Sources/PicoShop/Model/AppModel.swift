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
            if selection == nil { bwPreviewOn = false }
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
        didSet {
            guard activeLayerID != oldValue else { return }
            colorRangeLastPoint = nil
            refreshMoveTransformTargetForLayerChange()
        }
    }

    /// マーチングアンツ用の境界パス（selection 変更時に非同期で再計算されるキャッシュ）
    @Published private(set) var selectionPath: Path?

    /// 選択範囲の bbox キャッシュ（selection 変更時に同期更新、StatusBar 等が毎レンダーで呼ばないように）
    private(set) var selectionBounds: CGRect?

    @Published var compositeBounds: CGRect = CGRect(x: 0, y: 0, width: 1024, height: 768)

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
            if tool != .colorRangeSelect { colorRangeLastPoint = nil }
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
    /// move ツールで現在ピクセルを持ち上げている元レイヤー
    var moveLayerID: UUID?
    /// move 開始時に選択範囲を対象にしていたか。未選択のレイヤー全体移動では選択を作らない。
    var moveStartedWithSelection = false

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

    @Published var showLoupe: Bool = UserDefaults.standard.bool(forKey: "loupeVisible") {
        didSet { UserDefaults.standard.set(showLoupe, forKey: "loupeVisible") }
    }
    @Published var showNavigatorPanel: Bool = UserDefaults.standard.object(forKey: "navigatorPanelVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showNavigatorPanel, forKey: "navigatorPanelVisible") }
    }
    @Published var showLayersPanel: Bool = UserDefaults.standard.object(forKey: "layerPanelVisible") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showLayersPanel, forKey: "layerPanelVisible") }
    }
    @Published var showToolbar = true
    @Published var loupeZoom: Int = 400      // 100/200/400/800

    @Published var statusMessage: String?

    // MARK: - ダイアログ表示フラグ

    @Published var showNewFileDialog = false
    @Published var showCanvasSizeDialog = false
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

    /// 選択範囲：B&Wマスクプレビューフラグ
    @Published var bwPreviewOn = false
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

    @Published var undoStack: [Snapshot] = []
    @Published var redoStack: [Snapshot] = []
    var undoLabel: String? { undoStack.last?.label }
    var redoLabel: String? { redoStack.last?.label }

    var coalesceKey: String?
    var coalesceTime: Date = .distantPast

    // MARK: - キーボード

    var keyDownMonitor: Any?
    @Published var spaceKeyDown = false

    init() {
        let layer = Layer(name: "レイヤー1", buffer: PixelBuffer(width: 1024, height: 768))
        layers = [layer]
        activeLayerID = layer.id
        recomposite()
        installKeyMonitors()
        openCommandLineFiles()
    }


    deinit {
        // monitor は アプリ終了まで生存するため明示解放は不要だが念のため
        if let m = keyDownMonitor {
            NSEvent.removeMonitor(m)
        }
    }
}
