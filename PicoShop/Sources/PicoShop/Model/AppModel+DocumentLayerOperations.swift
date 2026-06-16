import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ドキュメント / レイヤー / 選択 / 編集の操作

extension AppModel {

    // MARK: 新規ドキュメント

    func newDocument(width: Int, height: Int, background: PixelColor) {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.newDocument(width: width, height: height, background: background)
            }
            return
        }
        pushUndo("新規ファイル")
        canvasWidth = max(1, width)
        canvasHeight = max(1, height)
        let layer = Layer(name: "レイヤー1",
                          buffer: PixelBuffer(width: canvasWidth, height: canvasHeight, fill: background))
        layers = [layer]
        selection = nil
        pendingTransform = SelectionTransform()
        floatingLayer = nil
        moveLayerID = nil
        moveStartedWithSelection = false
        originalMoveBuffer = nil
        originalMoveBounds = nil
        activeLayerID = layer.id
        projectURL = nil
        recomposite()
        fitToView()
    }

    // MARK: 画像ファイルの読み込み（新規レイヤーとして追加）

    /// 初回（レイヤーが空 or 全レイヤーが空白 1 枚のみ）ならキャンバスサイズを画像に合わせる
    func openImageFiles(_ urls: [URL]) {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.openImageFiles(urls)
            }
            return
        }
        var added = false
        let pristine = isPristine  // pushUndo の前に判定（undoStack を見るため）
        for url in urls {
            guard let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let buf = PixelBuffer(cgImage: cg) else {
                warn("読み込めませんでした: \(url.lastPathComponent)")
                continue
            }
            if !added { pushUndo("ファイルを開く") }
            if pristine && !added {
                canvasWidth = buf.width
                canvasHeight = buf.height
                layers = []
            }
            let layer = Layer(name: url.deletingPathExtension().lastPathComponent, buffer: buf)
            layers.insert(layer, at: 0)
            activeLayerID = layer.id
            added = true
        }
        if added {
            recomposite()
            fitToView()
        }
    }

    /// まだ何も編集していない初期状態か（空白レイヤー 1 枚のみ）
    private var isPristine: Bool {
        layers.count <= 1 && undoStack.isEmpty
            && (layers.first?.buffer.pixels.allSatisfy { $0 == 0 } ?? true)
    }

    // MARK: レイヤー操作

    func addEmptyLayer() {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.addEmptyLayer()
            }
            return
        }
        pushUndo("新規レイヤー")
        let layer = Layer(name: "レイヤー\(layers.count + 1)",
                          buffer: PixelBuffer(width: canvasWidth, height: canvasHeight))
        layers.insert(layer, at: activeLayerIndex ?? 0)
        activeLayerID = layer.id
        recomposite()
    }

    func addLayerFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        if tool == .move, floatingLayer != nil {
            let urls = panel.urls
            commitMoveTransform { [weak self] in
                self?.addLayerFiles(urls)
            }
            return
        }
        addLayerFiles(panel.urls)
    }

    private func addLayerFiles(_ urls: [URL]) {
        var added = false
        for url in urls {
            guard let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let buf = PixelBuffer(cgImage: cg) else { continue }
            if !added { pushUndo("ファイルから読み込み") }
            let layer = Layer(name: url.deletingPathExtension().lastPathComponent, buffer: buf)
            layers.insert(layer, at: 0)
            activeLayerID = layer.id
            added = true
        }
        if added { recomposite() }
    }

    func deleteActiveLayer() {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.deleteActiveLayer()
            }
            return
        }
        guard layers.count > 1 else {
            warn("最後のレイヤーは削除できません")
            return
        }
        guard let idx = activeLayerIndex else { return }
        if layers[idx].locked {
            warn("レイヤーがロックされています")
            return
        }
        pushUndo("レイヤーを削除")
        layers.remove(at: idx)
        activeLayerID = layers[min(idx, layers.count - 1)].id
        recomposite()
    }

    func duplicateActiveLayer() {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.duplicateActiveLayer()
            }
            return
        }
        guard let idx = activeLayerIndex else { return }
        pushUndo("レイヤーを複製")
        var copy = Layer(name: layers[idx].name + " コピー", buffer: layers[idx].buffer,
                         offsetX: layers[idx].offsetX, offsetY: layers[idx].offsetY)
        copy.opacity = layers[idx].opacity
        copy.blend = layers[idx].blend
        layers.insert(copy, at: idx)
        activeLayerID = copy.id
        recomposite()
    }

    /// up=true で 1 つ上（手前）へ
    func moveActiveLayer(up: Bool) {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.moveActiveLayer(up: up)
            }
            return
        }
        guard let idx = activeLayerIndex else { return }
        let newIdx = up ? idx - 1 : idx + 1
        guard newIdx >= 0, newIdx < layers.count else { return }
        pushUndo("レイヤーの並び替え")
        layers.swapAt(idx, newIdx)
        recomposite()
    }

    func reorderLayers(fromOffsets: IndexSet, toOffset: Int) {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.reorderLayers(fromOffsets: fromOffsets, toOffset: toOffset)
            }
            return
        }
        pushUndo("レイヤーの並び替え")
        layers.move(fromOffsets: fromOffsets, toOffset: toOffset)
        recomposite()
    }

    /// 表示中のレイヤーをすべて 1 つに統合（非表示レイヤーは残す）
    func mergeVisibleLayers() {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.mergeVisibleLayers()
            }
            return
        }
        let visible = layers.filter { $0.visible }
        guard visible.count >= 2 else {
            warn("統合できる表示レイヤーが 2 つ以上ありません")
            return
        }
        if visible.contains(where: { $0.locked }) {
            warn("ロック中のレイヤーが含まれています")
            return
        }
        pushUndo("レイヤーを統合")
        var bounds = visible[0].frame
        for l in visible.dropFirst() { bounds = bounds.union(l.frame) }
        bounds = CGRect(x: bounds.minX.rounded(.down), y: bounds.minY.rounded(.down),
                        width: bounds.width.rounded(.up), height: bounds.height.rounded(.up))
        guard let img = CPUCompositor.composite(layers: visible, bounds: bounds),
              let buf = PixelBuffer(cgImage: img) else { return }
        let merged = Layer(name: "統合レイヤー", buffer: buf,
                           offsetX: Int(bounds.minX), offsetY: Int(bounds.minY))
        let topIdx = layers.firstIndex { $0.visible } ?? 0
        layers.removeAll { $0.visible }
        layers.insert(merged, at: min(topIdx, layers.count))
        activeLayerID = merged.id
        recomposite()
    }

    // MARK: レイヤープロパティ（パレットから）

    func updateLayer(_ id: UUID, _ body: @escaping (inout Layer) -> Void) {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.updateLayer(id, body)
            }
            return
        }
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        body(&layers[idx])
        recomposite()
        if tool == .move, id == activeLayerID {
            refreshMoveTransformTargetForLayerChange()
        }
    }

}
