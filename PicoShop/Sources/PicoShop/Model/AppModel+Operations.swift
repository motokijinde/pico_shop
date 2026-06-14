import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - ドキュメント / レイヤー / 選択 / 編集の操作

extension AppModel {

    // MARK: 新規ドキュメント

    func newDocument(width: Int, height: Int, background: PixelColor) {
        pushUndo("新規ファイル")
        canvasWidth = max(1, width)
        canvasHeight = max(1, height)
        let layer = Layer(name: "レイヤー1",
                          buffer: PixelBuffer(width: canvasWidth, height: canvasHeight, fill: background))
        layers = [layer]
        activeLayerID = layer.id
        selection = nil
        pendingTransform = SelectionTransform()
        projectURL = nil
        recomposite()
        fitToView()
    }

    // MARK: 画像ファイルの読み込み（新規レイヤーとして追加）

    /// 初回（レイヤーが空 or 全レイヤーが空白 1 枚のみ）ならキャンバスサイズを画像に合わせる
    func openImageFiles(_ urls: [URL]) {
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
        var added = false
        for url in panel.urls {
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
        guard let idx = activeLayerIndex else { return }
        let newIdx = up ? idx - 1 : idx + 1
        guard newIdx >= 0, newIdx < layers.count else { return }
        pushUndo("レイヤーの並び替え")
        layers.swapAt(idx, newIdx)
        recomposite()
    }

    func reorderLayers(fromOffsets: IndexSet, toOffset: Int) {
        pushUndo("レイヤーの並び替え")
        layers.move(fromOffsets: fromOffsets, toOffset: toOffset)
        recomposite()
    }

    /// 表示中のレイヤーをすべて 1 つに統合（非表示レイヤーは残す）
    func mergeVisibleLayers() {
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
        guard let img = Compositor.composite(layers: visible, bounds: bounds),
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

    func updateLayer(_ id: UUID, _ body: (inout Layer) -> Void) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        body(&layers[idx])
        recomposite()
    }

    // MARK: キャンバス操作

    /// anchor: 0–8（3×3 グリッド、0=左上, 4=中央, 8=右下）
    func resizeCanvas(width: Int, height: Int, anchor: Int) {
        let w = max(1, width), h = max(1, height)
        pushUndo("キャンバスサイズ変更")
        let ax = Double(anchor % 3) / 2.0   // 0, 0.5, 1
        let ay = Double(anchor / 3) / 2.0
        let dx = Int((Double(w - canvasWidth) * ax).rounded())
        let dy = Int((Double(h - canvasHeight) * ay).rounded())
        for i in layers.indices {
            layers[i].offsetX += dx
            layers[i].offsetY += dy
        }
        if let sel = selection {
            var newSel = SelectionMask(width: w, height: h)
            for y in 0..<sel.height {
                let ny = y + dy
                guard ny >= 0, ny < h else { continue }
                for x in 0..<sel.width {
                    let nx = x + dx
                    guard nx >= 0, nx < w else { continue }
                    newSel.data[ny * w + nx] = sel.data[y * sel.width + x]
                }
            }
            selection = newSel.isEmpty ? nil : newSel
        }
        canvasWidth = w
        canvasHeight = h
        recomposite()
    }

    /// 全表示レイヤーの結合範囲でキャンバスを自動リサイズ
    func fitCanvasToLayers() {
        let visible = layers.filter { $0.visible }
        guard !visible.isEmpty else { return }
        var bounds = visible[0].frame
        for l in visible.dropFirst() { bounds = bounds.union(l.frame) }
        pushUndo("キャンバスを画像に合わせる")
        let ox = Int(bounds.minX.rounded(.down)), oy = Int(bounds.minY.rounded(.down))
        for i in layers.indices {
            layers[i].offsetX -= ox
            layers[i].offsetY -= oy
        }
        canvasWidth = Int(bounds.width.rounded(.up))
        canvasHeight = Int(bounds.height.rounded(.up))
        selection = nil
        recomposite()
    }

    /// アクティブレイヤーを透明でクリア（選択がある場合は選択範囲のみ）
    func clearActiveLayerTransparent() {
        pushUndo("透明でクリア")
        if selection != nil {
            cutSelection()
            return
        }
        let ok = withActiveLayer { l in
            l.buffer = PixelBuffer(width: l.buffer.width, height: l.buffer.height)
            l.refreshCache()
        }
        if ok { recomposite() }
    }

    // MARK: 選択操作

    func setSelection(_ mask: SelectionMask?, label: String) {
        pushUndo(label)
        selection = (mask?.isEmpty ?? true) ? nil : mask
        pendingTransform = SelectionTransform()
    }

    /// selectionOperationMode に従って選択を適用（新規/追加/除外）
    func applySelection(_ mask: SelectionMask, label: String) {
        let result: SelectionMask
        switch selectionOperationMode {
        case .replace:
            result = mask
        case .add:
            result = (selection ?? SelectionMask(width: mask.width, height: mask.height)).union(mask)
        case .subtract:
            guard let existing = selection else { return }
            result = existing.subtracting(mask)
        }
        setSelection(result, label: label)
    }

    func selectAll() {
        setSelection(.all(width: canvasWidth, height: canvasHeight), label: "すべてを選択")
    }

    func invertSelection() {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        setSelection(sel.inverted(), label: "選択を反転")
    }

    func clearSelection() {
        guard selection != nil else { return }
        pushUndo("選択をクリア")
        selection = nil
        pendingTransform = SelectionTransform()
    }

    func growSelection(by px: Int) {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        lastGrowShrinkAmount = px
        setSelection(sel.grown(by: px), label: "選択範囲を拡大")
    }

    func shrinkSelection(by px: Int) {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        lastGrowShrinkAmount = px
        setSelection(sel.shrunk(by: px), label: "選択範囲を縮小")
    }

    // MARK: 選択範囲の変形

    /// 保留中の変形を適用してマスクを再ラスタライズ。
    /// selectionTransform ツールで selection == nil のときはレイヤー全体を選択してから変形する。
    func applySelectionTransform() {
        if selection == nil, tool == .selectionTransform, let layer = activeLayer {
            selection = .rect(width: canvasWidth, height: canvasHeight,
                              rect: CGRect(x: layer.offsetX, y: layer.offsetY,
                                           width: layer.buffer.width, height: layer.buffer.height))
        }
        guard let sel = selection, let b = sel.bounds(), !pendingTransform.isIdentity else { return }
        pushUndo("選択範囲の変形")
        selection = sel.transformed(
            dx: pendingTransform.dx, dy: pendingTransform.dy,
            scaleX: pendingTransform.scaleX, scaleY: pendingTransform.scaleY,
            rotationDegrees: pendingTransform.rotation,
            center: CGPoint(x: b.midX, y: b.midY)
        )
        pendingTransform = SelectionTransform()
        if selection?.isEmpty ?? true {
            selection = nil
            warn("変形の結果、選択範囲が空になりました")
        }
    }

    func resetSelectionTransform() {
        pendingTransform = SelectionTransform()
    }

    // MARK: カット

    func cutSelection() {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        copySelectionToPasteboard()
        pushUndo("カット")
        let ok = withActiveLayer { l in
            for y in 0..<l.buffer.height {
                let cy = y + l.offsetY
                for x in 0..<l.buffer.width {
                    let v = sel.value(x: x + l.offsetX, y: cy)
                    guard v > 0 else { continue }
                    let i = (y * l.buffer.width + x) * 4 + 3
                    // ソフトエッジ対応：マスク値ぶんアルファを減らす
                    l.buffer.pixels[i] = UInt8(Int(l.buffer.pixels[i]) * (255 - Int(v)) / 255)
                }
            }
            l.refreshCache()
        }
        if ok {
            recomposite()
        } else {
            discardLastUndo()  // ロック等で失敗した場合は履歴を戻す
        }
    }

    // MARK: 塗りつぶし

    /// 選択範囲内を塗りつぶし
    func fillSelection() {
        applySelectionTransform()
        guard let sel = selection else {
            warn("選択範囲がありません")
            return
        }
        pushUndo("塗りつぶし")
        let c = fillOpts.color
        let ok = withActiveLayer { l in
            for y in 0..<l.buffer.height {
                let cy = y + l.offsetY
                for x in 0..<l.buffer.width {
                    let v = sel.value(x: x + l.offsetX, y: cy)
                    guard v >= 128 else { continue }
                    l.buffer.setColor(x: x, y: y, c)
                }
            }
            l.refreshCache()
        }
        if ok { recomposite() } else { discardLastUndo() }
    }

    /// クリック位置の隣接類似色を塗りつぶし（フローフィル）
    func floodFill(atCanvas p: CGPoint) {
        guard let layer = activeLayer else { return }
        let lx = Int(p.x.rounded(.down)) - layer.offsetX
        let ly = Int(p.y.rounded(.down)) - layer.offsetY
        guard lx >= 0, lx < layer.buffer.width, ly >= 0, ly < layer.buffer.height else { return }
        pushUndo("塗りつぶし")
        let region = ColorRangeEngine.floodFill(
            pixels: layer.buffer.pixels, width: layer.buffer.width, height: layer.buffer.height,
            startX: lx, startY: ly, tolerance: Int(fillOpts.tolerance * 2.55), contiguous: true
        )
        let c = fillOpts.color
        let ok = withActiveLayer { l in
            for i in 0..<(l.buffer.width * l.buffer.height) where region[i] >= 128 {
                l.buffer.pixels[i * 4] = c.r
                l.buffer.pixels[i * 4 + 1] = c.g
                l.buffer.pixels[i * 4 + 2] = c.b
                l.buffer.pixels[i * 4 + 3] = c.a
            }
            l.refreshCache()
        }
        if ok { recomposite() } else { discardLastUndo() }
    }

    // MARK: リサイズ / 回転 / 反転（selection != nil で選択範囲に適用、nil でレイヤー全体）

    func resizeActiveLayer(width: Int, height: Int) {
        guard width > 0, height > 0 else {
            warn("サイズが不正です")
            return
        }
        if let sel = selection, let b = sel.bounds() {
            pushUndo("選択範囲のリサイズ")
            selection = sel.transformed(
                dx: 0, dy: 0,
                scaleX: Double(width) / Double(b.width), scaleY: Double(height) / Double(b.height),
                rotationDegrees: 0, center: CGPoint(x: b.minX, y: b.minY)
            )
            return
        }
        pushUndo("リサイズ")
        let ok = withActiveLayer { l in
            l.buffer = l.buffer.resized(width: width, height: height, quality: resizeOpts.quality)
            l.refreshCache()
        }
        if ok { recomposite() } else { discardLastUndo() }
    }

    func rotate(byDegrees deg: Double) {
        if let sel = selection, let b = sel.bounds() {
            pushUndo("選択範囲の回転")
            selection = sel.transformed(dx: 0, dy: 0, scaleX: 1, scaleY: 1,
                                        rotationDegrees: deg,
                                        center: CGPoint(x: b.midX, y: b.midY))
            return
        }
        pushUndo("回転")
        let q = resizeOpts.quality
        let ok = withActiveLayer { l in
            let (buf, dx, dy) = l.buffer.rotated(byDegrees: deg, quality: q)
            l.buffer = buf
            l.offsetX += dx
            l.offsetY += dy
            l.refreshCache()
        }
        if ok { recomposite() } else { discardLastUndo() }
    }

    func flip(horizontal: Bool) {
        if let sel = selection, let b = sel.bounds() {
            pushUndo(horizontal ? "選択範囲の水平反転" : "選択範囲の垂直反転")
            selection = sel.transformed(dx: 0, dy: 0,
                                        scaleX: horizontal ? -1 : 1, scaleY: horizontal ? 1 : -1,
                                        rotationDegrees: 0,
                                        center: CGPoint(x: b.midX, y: b.midY))
            return
        }
        pushUndo(horizontal ? "水平反転" : "垂直反転")
        let ok = withActiveLayer { l in
            l.buffer = horizontal ? l.buffer.flippedHorizontally() : l.buffer.flippedVertically()
            l.refreshCache()
        }
        if ok { recomposite() } else { discardLastUndo() }
    }

    // MARK: ピクセル移動（move ツール + selection != nil）

    /// ドラッグ開始時：選択内ピクセルをフローティングレイヤーに切り出す
    func beginPixelMove() -> Bool {
        guard let sel = selection, let idx = activeLayerIndex else { return false }
        guard !layers[idx].locked else {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return false
        }
        let layer = layers[idx]
        pushUndo("ピクセルを移動")

        var floatBuf = PixelBuffer(width: layer.buffer.width, height: layer.buffer.height)
        for y in 0..<layer.buffer.height {
            for x in 0..<layer.buffer.width {
                let cx = x + layer.offsetX, cy = y + layer.offsetY
                let v = Int(sel.value(x: cx, y: cy))
                guard v > 0 else { continue }
                let base = (y * layer.buffer.width + x) * 4
                floatBuf.pixels[base]     = layer.buffer.pixels[base]
                floatBuf.pixels[base + 1] = layer.buffer.pixels[base + 1]
                floatBuf.pixels[base + 2] = layer.buffer.pixels[base + 2]
                floatBuf.pixels[base + 3] = UInt8(Int(layer.buffer.pixels[base + 3]) * v / 255)
                layers[idx].buffer.pixels[base + 3] = 0
            }
        }
        layers[idx].refreshCache()

        floatingLayer = Layer(name: "_floating", buffer: floatBuf,
                              offsetX: layer.offsetX, offsetY: layer.offsetY)
        pixelMovePreview = PixelMovePreview(
            initialLayerOffsetX: layer.offsetX,
            initialLayerOffsetY: layer.offsetY
        )
        recomposite()
        return true
    }

    /// ドラッグ中：フローティングレイヤーのオフセットを更新
    func updatePixelMoveOffset(dx: Int, dy: Int) {
        guard let preview = pixelMovePreview else { return }
        floatingLayer?.offsetX = preview.initialLayerOffsetX + dx
        floatingLayer?.offsetY = preview.initialLayerOffsetY + dy
        recomposite()
    }

    /// ドラッグ終了：フローティングレイヤーをアクティブレイヤーに合成して確定
    func commitPixelMove() {
        guard let fl = floatingLayer, let idx = activeLayerIndex else {
            floatingLayer = nil
            pixelMovePreview = nil
            return
        }
        let layer = layers[idx]
        for y in 0..<fl.buffer.height {
            for x in 0..<fl.buffer.width {
                guard fl.buffer.pixels[(y * fl.buffer.width + x) * 4 + 3] > 0 else { continue }
                let cx = x + fl.offsetX, cy = y + fl.offsetY
                let lx = cx - layer.offsetX, ly = cy - layer.offsetY
                guard lx >= 0, lx < layer.buffer.width,
                      ly >= 0, ly < layer.buffer.height else { continue }
                let src = (y * fl.buffer.width + x) * 4
                let dst = (ly * layer.buffer.width + lx) * 4
                layers[idx].buffer.pixels[dst]     = fl.buffer.pixels[src]
                layers[idx].buffer.pixels[dst + 1] = fl.buffer.pixels[src + 1]
                layers[idx].buffer.pixels[dst + 2] = fl.buffer.pixels[src + 2]
                layers[idx].buffer.pixels[dst + 3] = fl.buffer.pixels[src + 3]
            }
        }
        layers[idx].refreshCache()

        if let sel = selection, let preview = pixelMovePreview {
            let dx = fl.offsetX - preview.initialLayerOffsetX
            let dy = fl.offsetY - preview.initialLayerOffsetY
            selection = sel.translated(dx: dx, dy: dy)
        }
        floatingLayer = nil
        pixelMovePreview = nil
        recomposite()
    }

    /// カーソルキー用：1px 単位の破壊的ピクセル移動
    func applyPixelMoveImmediate(dx: Int, dy: Int) {
        guard let sel = selection, let idx = activeLayerIndex else { return }
        let layer = layers[idx]
        var newBuf = layer.buffer  // 値コピー
        // 選択ピクセルを元バッファ上でクリア
        for y in 0..<layer.buffer.height {
            for x in 0..<layer.buffer.width {
                let cx = x + layer.offsetX, cy = y + layer.offsetY
                guard sel.value(x: cx, y: cy) > 0 else { continue }
                newBuf.pixels[(y * layer.buffer.width + x) * 4 + 3] = 0
            }
        }
        // 元バッファから読んで新バッファの新位置に書く
        for y in 0..<layer.buffer.height {
            for x in 0..<layer.buffer.width {
                let cx = x + layer.offsetX, cy = y + layer.offsetY
                guard sel.value(x: cx, y: cy) > 0 else { continue }
                let nlx = cx + dx - layer.offsetX
                let nly = cy + dy - layer.offsetY
                guard nlx >= 0, nlx < layer.buffer.width,
                      nly >= 0, nly < layer.buffer.height else { continue }
                let src = (y * layer.buffer.width + x) * 4
                let dst = (nly * layer.buffer.width + nlx) * 4
                newBuf.pixels[dst]     = layer.buffer.pixels[src]
                newBuf.pixels[dst + 1] = layer.buffer.pixels[src + 1]
                newBuf.pixels[dst + 2] = layer.buffer.pixels[src + 2]
                newBuf.pixels[dst + 3] = layer.buffer.pixels[src + 3]
            }
        }
        layers[idx].buffer = newBuf
        layers[idx].refreshCache()
        selection = sel.translated(dx: dx, dy: dy)
        recomposite()
    }

    // MARK: ピクセル移動変形（move ツール）

    /// move ツール選択時：バウンズだけ記録してハンドルを表示（ロック中は何もしない）
    func beginMoveTransform() {
        guard floatingLayer == nil else { return }
        guard let idx = activeLayerIndex else { return }
        guard !layers[idx].locked else { return }
        let layer = layers[idx]

        if let sel = selection, let b = sel.bounds() {
            originalMoveBounds = b
        } else {
            originalMoveBounds = CGRect(x: CGFloat(layer.offsetX), y: CGFloat(layer.offsetY),
                                        width: CGFloat(layer.buffer.width),
                                        height: CGFloat(layer.buffer.height))
        }
        pendingTransform = SelectionTransform()
    }

    /// ドラッグ開始時（遅延実行）：ピクセル抽出をバックグラウンドで行い floatingLayer をセット
    func extractMovePixels() {
        guard !isMoveExtracting, floatingLayer == nil,
              let idx = activeLayerIndex, originalMoveBounds != nil else { return }

        isMoveExtracting = true

        // スナップショットをメインスレッドで取得（値コピーなので安全）
        let snapshot  = layers[idx].buffer
        let offsetX   = layers[idx].offsetX
        let offsetY   = layers[idx].offsetY
        let sel       = self.selection

        rasterizeVersion &+= 1
        let ver = rasterizeVersion

        Task.detached(priority: .userInitiated) { [snapshot, offsetX, offsetY, sel, weak self] in
            let floatBuf:   PixelBuffer
            let clearedBuf: PixelBuffer
            let floatOX:    Int
            let floatOY:    Int

            if let sel = sel, let b = sel.bounds() {
                // 選択あり：選択ピクセルを抽出、元バッファから選択部分のアルファをクリア
                let sw = max(1, Int(b.width)), sh = max(1, Int(b.height))
                var extracted = PixelBuffer(width: sw, height: sh)
                var cleared   = snapshot  // 値コピー（スレッドセーフ）
                for y in 0..<sh {
                    for x in 0..<sw {
                        let cx = Int(b.minX) + x, cy = Int(b.minY) + y
                        guard sel.isSelected(x: cx, y: cy) else { continue }
                        let lx = cx - offsetX, ly = cy - offsetY
                        guard lx >= 0, lx < snapshot.width,
                              ly >= 0, ly < snapshot.height else { continue }
                        let src = (ly * snapshot.width + lx) * 4
                        let dst = (y * sw + x) * 4
                        extracted.pixels[dst]     = snapshot.pixels[src]
                        extracted.pixels[dst + 1] = snapshot.pixels[src + 1]
                        extracted.pixels[dst + 2] = snapshot.pixels[src + 2]
                        extracted.pixels[dst + 3] = snapshot.pixels[src + 3]
                        cleared.pixels[src + 3]   = 0
                    }
                }
                floatBuf   = extracted
                clearedBuf = cleared
                floatOX    = Int(b.minX.rounded())
                floatOY    = Int(b.minY.rounded())
            } else {
                // 選択なし：スナップショットをそのまま使い、空バッファで元レイヤーをクリア
                floatBuf   = snapshot
                clearedBuf = PixelBuffer(width: snapshot.width, height: snapshot.height)
                floatOX    = offsetX
                floatOY    = offsetY
            }

            await MainActor.run { [weak self, floatBuf, clearedBuf, floatOX, floatOY] in
                guard let self, self.rasterizeVersion == ver else {
                    self?.isMoveExtracting = false
                    return
                }
                self.isMoveExtracting = false
                self.layers[idx].buffer = clearedBuf
                self.layers[idx].refreshCache()
                self.originalMoveBuffer = floatBuf
                self.floatingLayer = Layer(name: "_floating", buffer: floatBuf,
                                          offsetX: floatOX, offsetY: floatOY)
                // 抽出中にドラッグ・矢印キー操作が走っていた場合は即再ラスタライズ
                if !self.pendingTransform.isIdentity {
                    self.rasterizePreview()
                } else {
                    self.recomposite()
                }
            }
        }
    }

    /// ドラッグ終了・数値入力確定時：pendingTransform を originalMoveBuffer に適用して floatingLayer を更新
    /// 回転・スケールはバックグラウンドスレッドで処理してメインスレッドをブロックしない。
    func rasterizePreview() {
        guard let orig = originalMoveBuffer, let bounds = originalMoveBounds else { return }
        let t = pendingTransform
        let midX = bounds.midX + t.dx
        let midY = bounds.midY + t.dy

        // 平行移動のみ：再ラスタライズ不要、offsetX/Y だけ更新
        if t.rotation == 0 && abs(t.scaleX - 1) < 0.001 && abs(t.scaleY - 1) < 0.001 {
            floatingLayer?.offsetX = Int((midX - Double(orig.width)  / 2).rounded())
            floatingLayer?.offsetY = Int((midY - Double(orig.height) / 2).rounded())
            recomposite()
            return
        }

        // 回転・スケールはバックグラウンドで実行
        let q = resizeOpts.quality
        rasterizeVersion &+= 1
        let ver = rasterizeVersion

        Task.detached(priority: .userInitiated) { [orig, t, q, midX, midY, weak self] in
            var buf = orig
            if t.rotation != 0 {
                let (rotated, _, _) = buf.rotated(byDegrees: t.rotation, quality: q)
                buf = rotated
            }
            if abs(t.scaleX - 1) > 0.001 || abs(t.scaleY - 1) > 0.001 {
                let nw = max(1, Int((Double(buf.width)  * abs(t.scaleX)).rounded()))
                let nh = max(1, Int((Double(buf.height) * abs(t.scaleY)).rounded()))
                buf = buf.resized(width: nw, height: nh, quality: q)
            }
            let newLayer = Layer(name: "_floating", buffer: buf,
                                 offsetX: Int((midX - Double(buf.width)  / 2).rounded()),
                                 offsetY: Int((midY - Double(buf.height) / 2).rounded()))
            await MainActor.run { [weak self] in
                guard let self, self.rasterizeVersion == ver else { return }
                self.floatingLayer = newLayer
                self.recomposite()
            }
        }
    }

    /// 確定：floatingLayer をキャンバスクリップしてアクティブレイヤーに書き込む
    func commitMoveTransform() {
        guard originalMoveBounds != nil else { return }
        guard let fl = floatingLayer, let bounds = originalMoveBounds else {
            cleanupMoveTransform()
            beginMoveTransform()
            return
        }
        guard let idx = activeLayerIndex else {
            cleanupMoveTransform()
            beginMoveTransform()
            return
        }
        guard !layers[idx].locked else {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return
        }

        pushUndo("移動")

        // バックグラウンドに渡す値をキャプチャしてから、すぐに状態をクリア（二重コミット防止）
        let layerBuf    = layers[idx].buffer
        let layerOX     = layers[idx].offsetX
        let layerOY     = layers[idx].offsetY
        let floatBuf    = fl.buffer
        let floatOX     = fl.offsetX
        let floatOY     = fl.offsetY
        let cw = canvasWidth, ch = canvasHeight
        let sel = selection
        let t   = pendingTransform
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        cleanupMoveTransform()
        // bounds は確定前にキャプチャ・検証済みのため、beginMoveTransform のガードをバイパスして直接復元
        originalMoveBounds = bounds

        Task.detached(priority: .userInitiated) { [layerBuf, floatBuf, weak self] in
            // ピクセル書き込み（値コピーで操作）
            var result = layerBuf
            for y in 0..<floatBuf.height {
                for x in 0..<floatBuf.width {
                    guard floatBuf.pixels[(y * floatBuf.width + x) * 4 + 3] > 0 else { continue }
                    let cx = x + floatOX, cy = y + floatOY
                    guard cx >= 0, cx < cw, cy >= 0, cy < ch else { continue }
                    let lx = cx - layerOX, ly = cy - layerOY
                    guard lx >= 0, lx < layerBuf.width,
                          ly >= 0, ly < layerBuf.height else { continue }
                    let src = (y * floatBuf.width + x) * 4
                    let dst = (ly * layerBuf.width + lx) * 4
                    result.pixels[dst]     = floatBuf.pixels[src]
                    result.pixels[dst + 1] = floatBuf.pixels[src + 1]
                    result.pixels[dst + 2] = floatBuf.pixels[src + 2]
                    result.pixels[dst + 3] = floatBuf.pixels[src + 3]
                }
            }

            // 選択マスク変換（CoreGraphics なのでバックグラウンドでも OK）
            let newSel: SelectionMask?
            if let sel {
                newSel = sel.transformed(dx: t.dx, dy: t.dy,
                                         scaleX: t.scaleX, scaleY: t.scaleY,
                                         rotationDegrees: t.rotation, center: center)
            } else {
                let base = SelectionMask.rect(width: cw, height: ch, rect: bounds)
                newSel = base.transformed(dx: t.dx, dy: t.dy,
                                          scaleX: t.scaleX, scaleY: t.scaleY,
                                          rotationDegrees: t.rotation, center: center)
            }

            await MainActor.run { [weak self, result, newSel] in
                guard let self else { return }
                self.layers[idx].buffer = result
                self.layers[idx].refreshCache()
                self.selection = newSel
                self.recomposite()
                self.beginMoveTransform()  // 確定後も move ツールが継続できるよう即再初期化
            }
        }
    }

    /// リセット：originalMoveBuffer から floatingLayer を復元、pendingTransform をクリア
    func resetMoveTransform() {
        guard let orig = originalMoveBuffer, let bounds = originalMoveBounds else { return }
        floatingLayer = Layer(name: "_floating", buffer: orig,
                              offsetX: Int(bounds.minX.rounded()),
                              offsetY: Int(bounds.minY.rounded()))
        pendingTransform = SelectionTransform()
        recomposite()
    }

    private func cleanupMoveTransform() {
        rasterizeVersion &+= 1   // 飛行中の抽出・プレビュー・確定タスクを一括キャンセル
        isMoveExtracting = false
        floatingLayer = nil
        originalMoveBuffer = nil
        originalMoveBounds = nil
        pendingTransform = SelectionTransform()
    }

    // MARK: ピクセル変形（transform ツール）

    /// pendingTransform を選択内ピクセルまたはレイヤー全体に適用
    func applyPixelTransform() {
        guard !pendingTransform.isIdentity else { return }
        guard let idx = activeLayerIndex else { return }
        guard !layers[idx].locked else {
            warn("レイヤーがロックされています")
            NSSound.beep()
            return
        }

        if let sel = selection, let b = sel.bounds() {
            // 選択内ピクセルを変形
            let sw = max(1, Int(b.width)), sh = max(1, Int(b.height))
            let layer = layers[idx]
            var srcBuf = PixelBuffer(width: sw, height: sh)

            // 選択ピクセルを抽出
            for y in 0..<sh {
                for x in 0..<sw {
                    let cx = Int(b.minX) + x, cy = Int(b.minY) + y
                    guard sel.isSelected(x: cx, y: cy) else { continue }
                    let lx = cx - layer.offsetX, ly = cy - layer.offsetY
                    guard lx >= 0, lx < layer.buffer.width,
                          ly >= 0, ly < layer.buffer.height else { continue }
                    let src = (ly * layer.buffer.width + lx) * 4
                    let dst = (y * sw + x) * 4
                    srcBuf.pixels[dst]     = layer.buffer.pixels[src]
                    srcBuf.pixels[dst + 1] = layer.buffer.pixels[src + 1]
                    srcBuf.pixels[dst + 2] = layer.buffer.pixels[src + 2]
                    srcBuf.pixels[dst + 3] = layer.buffer.pixels[src + 3]
                }
            }

            pushUndo("変形")
            let ok = withActiveLayer { l in
                // 選択ピクセルをクリア
                for y in 0..<sh {
                    for x in 0..<sw {
                        let cx = Int(b.minX) + x, cy = Int(b.minY) + y
                        guard sel.isSelected(x: cx, y: cy) else { continue }
                        let lx = cx - l.offsetX, ly = cy - l.offsetY
                        guard lx >= 0, lx < l.buffer.width, ly >= 0, ly < l.buffer.height else { continue }
                        l.buffer.pixels[(ly * l.buffer.width + lx) * 4 + 3] = 0
                    }
                }

                // 回転適用
                let q = resizeOpts.quality
                var transformedBuf = srcBuf
                if pendingTransform.rotation != 0 {
                    let (rotated, _, _) = srcBuf.rotated(byDegrees: pendingTransform.rotation, quality: q)
                    transformedBuf = rotated
                }

                // スケール適用
                if abs(pendingTransform.scaleX - 1) > 0.001 || abs(pendingTransform.scaleY - 1) > 0.001 {
                    let nw = max(1, Int((Double(transformedBuf.width) * abs(pendingTransform.scaleX)).rounded()))
                    let nh = max(1, Int((Double(transformedBuf.height) * abs(pendingTransform.scaleY)).rounded()))
                    transformedBuf = transformedBuf.resized(width: nw, height: nh, quality: q)
                }

                // 変形後ピクセルを中心座標（+ 移動オフセット）に貼り付け
                let destCX = b.midX + CGFloat(pendingTransform.dx)
                let destCY = b.midY + CGFloat(pendingTransform.dy)
                let destLX = Int(destCX - CGFloat(transformedBuf.width) / 2) - l.offsetX
                let destLY = Int(destCY - CGFloat(transformedBuf.height) / 2) - l.offsetY
                for y in 0..<transformedBuf.height {
                    for x in 0..<transformedBuf.width {
                        let lx = destLX + x, ly = destLY + y
                        guard lx >= 0, lx < l.buffer.width, ly >= 0, ly < l.buffer.height else { continue }
                        let src = (y * transformedBuf.width + x) * 4
                        guard transformedBuf.pixels[src + 3] > 0 else { continue }
                        let dst = (ly * l.buffer.width + lx) * 4
                        l.buffer.pixels[dst]     = transformedBuf.pixels[src]
                        l.buffer.pixels[dst + 1] = transformedBuf.pixels[src + 1]
                        l.buffer.pixels[dst + 2] = transformedBuf.pixels[src + 2]
                        l.buffer.pixels[dst + 3] = transformedBuf.pixels[src + 3]
                    }
                }
                l.refreshCache()
            }
            if ok {
                selection = nil
                pendingTransform = SelectionTransform()
                recomposite()
            } else {
                discardLastUndo()
            }

        } else {
            // レイヤー全体を変形
            pushUndo("変形")
            let q = resizeOpts.quality

            if pendingTransform.rotation != 0 {
                let (rotated, rdx, rdy) = layers[idx].buffer.rotated(byDegrees: pendingTransform.rotation, quality: q)
                layers[idx].buffer = rotated
                layers[idx].offsetX += rdx
                layers[idx].offsetY += rdy
                layers[idx].refreshCache()
            }

            if abs(pendingTransform.scaleX - 1) > 0.001 || abs(pendingTransform.scaleY - 1) > 0.001 {
                let buf = layers[idx].buffer
                let nw = max(1, Int((Double(buf.width) * abs(pendingTransform.scaleX)).rounded()))
                let nh = max(1, Int((Double(buf.height) * abs(pendingTransform.scaleY)).rounded()))
                layers[idx].buffer = buf.resized(width: nw, height: nh, quality: q)
                layers[idx].refreshCache()
            }

            if pendingTransform.dx != 0 || pendingTransform.dy != 0 {
                layers[idx].offsetX += Int(pendingTransform.dx.rounded())
                layers[idx].offsetY += Int(pendingTransform.dy.rounded())
            }

            pendingTransform = SelectionTransform()
            recomposite()
        }
    }

    // MARK: クロップ

    func cropToSelection() {
        guard let sel = selection, let b = sel.bounds() else {
            warn("選択範囲がありません")
            return
        }
        let ox = Int(b.minX.rounded()), oy = Int(b.minY.rounded())
        let w = max(1, Int(b.width.rounded())), h = max(1, Int(b.height.rounded()))

        pushUndo("選択範囲でクロップ")
        for i in layers.indices {
            let srcX = ox - layers[i].offsetX
            let srcY = oy - layers[i].offsetY
            layers[i].buffer  = layers[i].buffer.cropped(srcX: srcX, srcY: srcY, width: w, height: h)
            layers[i].offsetX = 0
            layers[i].offsetY = 0
            layers[i].refreshCache()
        }
        canvasWidth  = w
        canvasHeight = h

        // 選択範囲を新キャンバス座標にずらして残す
        var newSel = SelectionMask(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                newSel.data[y * w + x] = sel.value(x: ox + x, y: oy + y)
            }
        }
        selection = newSel

        recomposite()
        fitToView()
    }

    func trimActiveLayer() {
        guard let idx = activeLayerIndex,
              let b = layers[idx].buffer.opaqueBounds() else {
            warn("トリムできる不透明ピクセルがありません")
            return
        }
        pushUndo("透明部分をトリム")
        layers[idx].offsetX += b.x
        layers[idx].offsetY += b.y
        layers[idx].buffer   = layers[idx].buffer.cropped(srcX: b.x, srcY: b.y, width: b.w, height: b.h)
        layers[idx].refreshCache()

        // トリム後に全表示レイヤーの frame でキャンバスもリサイズ
        let visible = layers.filter { $0.visible }
        if !visible.isEmpty {
            var bounds = visible[0].frame
            for l in visible.dropFirst() { bounds = bounds.union(l.frame) }
            let ox = Int(bounds.minX.rounded(.down)), oy = Int(bounds.minY.rounded(.down))
            for i in layers.indices {
                layers[i].offsetX -= ox
                layers[i].offsetY -= oy
            }
            canvasWidth  = max(1, Int(bounds.width.rounded(.up)))
            canvasHeight = max(1, Int(bounds.height.rounded(.up)))
        }

        recomposite()
        fitToView()
    }

    // MARK: 色域選択

    /// キャンバス座標 p のアクティブレイヤーピクセルを基準色としてflood fill選択を実行
    func applyColorRangeSelection(atCanvas p: CGPoint) {
        guard let layer = activeLayer else {
            warn("レイヤーが選択されていません")
            return
        }
        let lx = Int(p.x.rounded(.down)) - layer.offsetX
        let ly = Int(p.y.rounded(.down)) - layer.offsetY
        guard lx >= 0, lx < layer.buffer.width,
              ly >= 0, ly < layer.buffer.height else { return }

        let w = layer.buffer.width, h = layer.buffer.height
        let ox = layer.offsetX, oy = layer.offsetY
        let cw = canvasWidth, ch = canvasHeight
        let opts = colorRangeOpts

        var mask = ColorRangeEngine.floodFill(
            pixels: layer.buffer.pixels, width: w, height: h,
            startX: lx, startY: ly,
            tolerance: Int(opts.level),
            contiguous: opts.contiguous
        )

        let adj = Int(opts.boundaryAdjust.rounded())
        if adj != 0 {
            ColorRangeEngine.adjustBoundary(mask: &mask, width: w, height: h, amount: -adj)
        }

        var canvasData = [UInt8](repeating: 0, count: cw * ch)
        for y in 0..<h {
            let cy = y + oy
            guard cy >= 0, cy < ch else { continue }
            for x in 0..<w {
                let cx = x + ox
                guard cx >= 0, cx < cw else { continue }
                canvasData[cy * cw + cx] = mask[y * w + x]
            }
        }

        let result = SelectionMask(width: cw, height: ch, data: canvasData)
        colorRangeLastPoint = p
        applySelection(result, label: "色域選択")
    }

    func retryColorRangeSelection() {
        guard let p = colorRangeLastPoint else { return }
        applyColorRangeSelection(atCanvas: p)
    }

    // MARK: テキスト

    func commitText() {
        let str = textOpts.text
        guard !str.isEmpty else {
            warn("テキストが入力されていません")
            return
        }
        guard let size = Double(textOpts.sizeText), size > 0 else {
            warn("フォントサイズが不正です")
            return
        }
        guard let buf = TextRenderer.render(
            text: str, fontFamily: textOpts.fontFamily, size: size,
            weight: textOpts.weight, color: textOpts.color, antialias: textOpts.antialias
        ) else {
            warn("テキストを描画できませんでした")
            return
        }
        let px = Int(Double(textOpts.xText) ?? 0)
        let py = Int(Double(textOpts.yText) ?? 0)
        // 配置基準（3×3）：anchor 位置がテキスト矩形のどこに当たるか
        let ax = Double(textOpts.anchor % 3) / 2.0
        let ay = Double(textOpts.anchor / 3) / 2.0
        let ox = px - Int((Double(buf.width) * ax).rounded())
        let oy = py - Int((Double(buf.height) * ay).rounded())

        pushUndo("テキスト追加")
        let name = str.split(separator: "\n").first.map(String.init) ?? "テキスト"
        let layer = Layer(name: name, buffer: buf, offsetX: ox, offsetY: oy)
        layers.insert(layer, at: 0)
        activeLayerID = layer.id
        recomposite()
    }

    // MARK: クリップボード

    func copySelectionToPasteboard() {
        applySelectionTransform()
        guard let layer = activeLayer else { return }
        var buf: PixelBuffer
        if let sel = selection, let b = sel.bounds() {
            // 選択範囲（アクティブレイヤーとの交差）を切り出し
            let w = Int(b.width), h = Int(b.height)
            buf = PixelBuffer(width: w, height: h)
            for y in 0..<h {
                let cy = Int(b.minY) + y
                for x in 0..<w {
                    let cx = Int(b.minX) + x
                    guard sel.isSelected(x: cx, y: cy),
                          let c = layer.buffer.color(x: cx - layer.offsetX, y: cy - layer.offsetY) else { continue }
                    buf.setColor(x: x, y: y, c)
                }
            }
        } else {
            buf = layer.buffer
        }
        guard let cg = buf.makeCGImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }

    func pasteFromPasteboard() {
        let pb = NSPasteboard.general
        guard let img = NSImage(pasteboard: pb),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let pasted = PixelBuffer(cgImage: cg) else {
            warn("クリップボードに画像がありません")
            return
        }
        guard activeLayer != nil else {
            warn("レイヤーがありません")
            return
        }
        pushUndo("ペースト")
        // アクティブレイヤーへの貼り付け：レイヤー左上に合成
        let ok = withActiveLayer { l in
            guard let base = l.buffer.makeCGImage(), let overlay = pasted.makeCGImage() else { return }
            let w = l.buffer.width, h = l.buffer.height
            guard let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: PixelBuffer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(overlay, in: CGRect(x: 0, y: CGFloat(h - pasted.height),
                                         width: CGFloat(pasted.width), height: CGFloat(pasted.height)))
            if let out = ctx.makeImage(), let newBuf = PixelBuffer(cgImage: out) {
                l.buffer = newBuf
                l.refreshCache()
            }
        }
        if ok { recomposite() } else { discardLastUndo() }
    }

    // MARK: スポイト

    func sampleColor(atCanvas p: CGPoint) {
        guard let c = compositeColor(atCanvas: p) else { return }
        foregroundColor = c
        fillOpts.color = c
        textOpts.color = c
        warn("色を取得: \(c.hexString)")
    }
}
