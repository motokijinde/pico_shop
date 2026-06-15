import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppModel {

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
                    let i = (y * l.buffer.width + x) * 4
                    // ソフトエッジ対応：マスク値ぶんアルファを減らす
                    let nextAlpha = UInt8(Int(l.buffer.pixels[i + 3]) * (255 - Int(v)) / 255)
                    l.buffer.pixels[i + 3] = nextAlpha
                    if nextAlpha == 0 {
                        l.buffer.pixels[i] = 0
                        l.buffer.pixels[i + 1] = 0
                        l.buffer.pixels[i + 2] = 0
                    }
                }
            }
            l.markContentChanged()
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
            l.markContentChanged()
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
            l.markContentChanged()
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
            l.buffer = l.buffer.cpuResized(width: width, height: height, quality: resizeOpts.quality)
            l.markContentChanged()
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
            let (buf, dx, dy) = l.buffer.cpuRotated(byDegrees: deg, quality: q)
            l.buffer = buf
            l.offsetX += dx
            l.offsetY += dy
            l.markContentChanged()
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
            l.markContentChanged()
        }
        if ok { recomposite() } else { discardLastUndo() }
    }

}
