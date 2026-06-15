import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension AppModel {

    // MARK: クロップ

    func cropActiveLayerToSelection() {
        applySelectionTransform()
        guard let sel = selection, let b = sel.bounds() else {
            warn("選択範囲がありません")
            return
        }
        let ox = Int(b.minX.rounded()), oy = Int(b.minY.rounded())
        let w = max(1, Int(b.width.rounded())), h = max(1, Int(b.height.rounded()))

        pushUndo("選択範囲をクロップ")
        let ok = withActiveLayer { l in
            let srcX = ox - l.offsetX
            let srcY = oy - l.offsetY
            l.buffer = l.buffer.cropped(srcX: srcX, srcY: srcY, width: w, height: h)
            l.offsetX = ox
            l.offsetY = oy
            l.markContentChanged()
        }
        if ok {
            recomposite()
        } else {
            discardLastUndo()
        }
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
        if floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.pasteFromPasteboard()
            }
            return
        }

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
        var pastedRect: CGRect?
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
                l.markContentChanged()
            }
            pastedRect = CGRect(x: CGFloat(l.offsetX), y: CGFloat(l.offsetY),
                                width: CGFloat(pasted.width), height: CGFloat(pasted.height))
        }
        if ok {
            if let pastedRect {
                selection = SelectionMask.rect(width: canvasWidth, height: canvasHeight, rect: pastedRect)
                tool = .move
            }
            recomposite()
        } else {
            discardLastUndo()
        }
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
