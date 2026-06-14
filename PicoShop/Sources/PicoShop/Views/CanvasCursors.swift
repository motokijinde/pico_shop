import SwiftUI
import AppKit

// MARK: - カスタムカーソル

extension CanvasView {
    static let selectionBaseCursor:     NSCursor = makeSelectionCursor()
    static let selectionAddCursor:      NSCursor = makeSelectionCursor(badge: "+")
    static let selectionSubtractCursor: NSCursor = makeSelectionCursor(badge: "−")
    static let colorRangeBaseCursor:    NSCursor = makeWandCursor()
    static let colorRangeAddCursor:     NSCursor = makeWandCursor(badge: "+")
    static let colorRangeSubtractCursor:NSCursor = makeWandCursor(badge: "−")
    static let rotateCursor:            NSCursor = makeRotateCursor()
    static let resizeNWSECursor:        NSCursor = makeDiagonalCursor(nwse: true)
    static let resizeNESWCursor:        NSCursor = makeDiagonalCursor(nwse: false)

    /// 魔法の杖カーソル（色域選択ツール用）
    /// ホットスポット：杖の先端（スパークル中心）
    static func makeWandCursor(badge: String? = nil) -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // y-up 座標系（flipped: false）
            // スティック: (3, 3) → (12, 12)  スパークル中心: (15, 15)
            ctx.setLineCap(.round); ctx.setLineJoin(.round)

            func drawWand() {
                // スティック
                ctx.move(to: CGPoint(x: 3, y: 3))
                ctx.addLine(to: CGPoint(x: 11, y: 11))
                // スパークル（上下左右4本）
                ctx.move(to: CGPoint(x: 15, y: 12)); ctx.addLine(to: CGPoint(x: 15, y: 18))
                ctx.move(to: CGPoint(x: 12, y: 15)); ctx.addLine(to: CGPoint(x: 18, y: 15))
                // スパークル（斜め2本）
                ctx.move(to: CGPoint(x: 13, y: 17)); ctx.addLine(to: CGPoint(x: 17, y: 13))
                ctx.move(to: CGPoint(x: 13, y: 13)); ctx.addLine(to: CGPoint(x: 17, y: 17))
            }

            ctx.setLineWidth(2.5)
            ctx.setStrokeColor(NSColor.white.cgColor)
            drawWand(); ctx.strokePath()

            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(NSColor.black.cgColor)
            drawWand(); ctx.strokePath()

            if let badge {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 8),
                    .foregroundColor: NSColor.black,
                    .strokeColor: NSColor.white,
                    .strokeWidth: -2.5,
                ]
                NSAttributedString(string: badge, attributes: attrs)
                    .draw(at: NSPoint(x: 1, y: 1))
            }
            return true
        }
        img.isTemplate = false
        // ホットスポット: スパークル中心 (15, 15) y-up → 画面座標 (15, size-15) = (15, 5)
        return NSCursor(image: img, hotSpot: NSPoint(x: 15, y: 5))
    }

    static func makeSelectionCursor(badge: String? = nil) -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = size / 2, cy = size / 2
            let gap: CGFloat = 4  // 中心の空白

            ctx.setLineCap(.round)

            // 白ハロー
            ctx.setLineWidth(2.5)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.move(to: CGPoint(x: cx, y: 1));        ctx.addLine(to: CGPoint(x: cx, y: cy - gap))
            ctx.move(to: CGPoint(x: cx, y: cy + gap)); ctx.addLine(to: CGPoint(x: cx, y: size - 1))
            ctx.move(to: CGPoint(x: 1, y: cy));        ctx.addLine(to: CGPoint(x: cx - gap, y: cy))
            ctx.move(to: CGPoint(x: cx + gap, y: cy)); ctx.addLine(to: CGPoint(x: size - 1, y: cy))
            ctx.strokePath()

            // 黒クロスヘア
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.move(to: CGPoint(x: cx, y: 1));        ctx.addLine(to: CGPoint(x: cx, y: cy - gap))
            ctx.move(to: CGPoint(x: cx, y: cy + gap)); ctx.addLine(to: CGPoint(x: cx, y: size - 1))
            ctx.move(to: CGPoint(x: 1, y: cy));        ctx.addLine(to: CGPoint(x: cx - gap, y: cy))
            ctx.move(to: CGPoint(x: cx + gap, y: cy)); ctx.addLine(to: CGPoint(x: size - 1, y: cy))
            ctx.strokePath()

            // バッジ（+/− のみ、通常選択はなし）
            if let badge {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 8),
                    .foregroundColor: NSColor.black,
                    .strokeColor: NSColor.white,
                    .strokeWidth: -2.5
                ]
                NSAttributedString(string: badge, attributes: attrs)
                    .draw(at: NSPoint(x: cx + 3, y: 1))
            }
            return true
        }
        img.isTemplate = false
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    /// 回転カーソル：円弧 + 先端に矢印
    static func makeRotateCursor() -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = size / 2, cy = size / 2, r: CGFloat = 6.5
            // y-down 座標: 0°=右, 90°=下, 180°=左, 270°=上
            // 20°→340° の CW 円弧（ほぼ一周）
            let startDeg: CGFloat = 20, endDeg: CGFloat = 340
            func buildArc() {
                let steps = 24
                for i in 0...steps {
                    let deg = startDeg + (endDeg - startDeg) * CGFloat(i) / CGFloat(steps)
                    let rad = deg * .pi / 180
                    let p = CGPoint(x: cx + r * cos(rad), y: cy + r * sin(rad))
                    i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
                }
            }
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2.5)
            buildArc(); ctx.strokePath()
            ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(1.5)
            buildArc(); ctx.strokePath()

            // 340° の位置に矢印（CW の接線方向 = 340° + 90° = 70°）
            let endRad = endDeg * .pi / 180
            let tip = CGPoint(x: cx + r * cos(endRad), y: cy + r * sin(endRad))
            let tangent = endRad + .pi / 2
            for (sz, col) in [(CGFloat(4.5), NSColor.white), (3.5, NSColor.black)] {
                ctx.setFillColor(col.cgColor)
                ctx.move(to: tip)
                ctx.addLine(to: CGPoint(x: tip.x + sz * cos(tangent + 0.5),
                                        y: tip.y + sz * sin(tangent + 0.5)))
                ctx.addLine(to: CGPoint(x: tip.x + sz * cos(tangent - 0.5),
                                        y: tip.y + sz * sin(tangent - 0.5)))
                ctx.closePath(); ctx.fillPath()
            }
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    /// 斜めリサイズカーソル（nwse: ↖↘ / !nwse: ↗↙）
    static func makeDiagonalCursor(nwse: Bool) -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let m: CGFloat = 3
            // flipped:true (y-down): (m,m)=左上, (size-m,size-m)=右下
            let (p1, p2): (CGPoint, CGPoint) = nwse
                ? (CGPoint(x: m, y: m), CGPoint(x: size - m, y: size - m))
                : (CGPoint(x: size - m, y: m), CGPoint(x: m, y: size - m))
            let dir = atan2(p2.y - p1.y, p2.x - p1.x)

            func drawLine(lw: CGFloat, col: CGColor) {
                ctx.setLineWidth(lw); ctx.setLineCap(.round)
                ctx.setStrokeColor(col)
                ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
            }
            func drawHead(at tip: CGPoint, toward: CGFloat, sz: CGFloat, col: CGColor) {
                ctx.setFillColor(col)
                ctx.move(to: tip)
                ctx.addLine(to: CGPoint(x: tip.x + sz * cos(toward + .pi + 0.45),
                                        y: tip.y + sz * sin(toward + .pi + 0.45)))
                ctx.addLine(to: CGPoint(x: tip.x + sz * cos(toward + .pi - 0.45),
                                        y: tip.y + sz * sin(toward + .pi - 0.45)))
                ctx.closePath(); ctx.fillPath()
            }

            drawLine(lw: 2.5, col: NSColor.white.cgColor)
            drawHead(at: p1, toward: dir + .pi, sz: 4.5, col: NSColor.white.cgColor)
            drawHead(at: p2, toward: dir,       sz: 4.5, col: NSColor.white.cgColor)
            drawLine(lw: 1.5, col: NSColor.black.cgColor)
            drawHead(at: p1, toward: dir + .pi, sz: 3.5, col: NSColor.black.cgColor)
            drawHead(at: p2, toward: dir,       sz: 3.5, col: NSColor.black.cgColor)
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}
