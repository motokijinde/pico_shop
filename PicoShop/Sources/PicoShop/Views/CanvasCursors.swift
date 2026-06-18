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
        let sparkle = CGPoint(x: 6.5, y: 13.5)  // y-up: 左上のキラキラ中心
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setLineCap(.round); ctx.setLineJoin(.round)

            let stickW: CGFloat = 1.8
            let halo: CGFloat = 1.3

            // 杖の柄（キラキラの右下から右下へ伸びる棒）
            func stickPath() -> CGPath {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 9.5, y: 10.5))
                p.addLine(to: CGPoint(x: 17, y: 3))
                return p
            }
            // 4 点星（上下左右）
            func starPath() -> CGPath {
                let outerR: CGFloat = 5.6, innerR: CGFloat = 1.3
                let p = CGMutablePath()
                for i in 0..<8 {
                    let r = (i % 2 == 0) ? outerR : innerR
                    let ang = CGFloat(i) * .pi / 4
                    let pt = CGPoint(x: sparkle.x + r * cos(ang), y: sparkle.y + r * sin(ang))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
                return p
            }

            // 白ハロー
            ctx.addPath(stickPath()); ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(stickW + 2 * halo); ctx.strokePath()
            ctx.addPath(starPath()); ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2 * halo); ctx.drawPath(using: .fillStroke)

            // 黒本体
            ctx.addPath(stickPath()); ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(stickW); ctx.strokePath()
            ctx.addPath(starPath()); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()

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
        // ホットスポット: スパークル中心 (y-up) → 画面座標 (y-down)
        return NSCursor(image: img, hotSpot: NSPoint(x: sparkle.x, y: size - sparkle.y))
    }

    static func makeSelectionCursor(badge: String? = nil) -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = size / 2, cy = size / 2
            let gap: CGFloat = 2  // 中心の空白

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

    static let brushReplaceCursor: NSCursor = makeSelectionCursor(badge: nil)
    static let brushAddCursor: NSCursor = makeSelectionCursor(badge: "+")
    static let brushSubtractCursor: NSCursor = makeSelectionCursor(badge: "−")

    /// ブラシカーソル（クロスヘア＋選択操作モードバッジ）
    static func brushCursor(for mode: SelectionOperationMode) -> NSCursor {
        switch mode {
        case .replace: return brushReplaceCursor
        case .add: return brushAddCursor
        case .subtract: return brushSubtractCursor
        }
    }

    /// 回転カーソル：滑らかな円弧 + 接線方向の矢印（時計回り ↻）
    static func makeRotateCursor() -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: size / 2, y: size / 2)
            let r: CGFloat = 6
            let lineW: CGFloat = 2.0
            let halo: CGFloat = 1.3

            // 上(90°)に隙間を空け、そこから時計回りにほぼ一周する円弧
            let gapCenter: CGFloat = 90, gapHalf: CGFloat = 24
            let d2r: (CGFloat) -> CGFloat = { $0 * .pi / 180 }
            let endRad = d2r(gapCenter + gapHalf)             // 矢印を置く端
            let startRad = d2r(gapCenter - gapHalf + 360)     // 反対の端（CW で一周）

            // 円弧の端点・接線・半径方向から矢印を組み立て
            let e = CGPoint(x: center.x + r * cos(endRad), y: center.y + r * sin(endRad))
            let tangent = CGPoint(x: sin(endRad), y: -cos(endRad))   // CW の進行方向
            let normal  = CGPoint(x: cos(endRad), y: sin(endRad))    // 半径方向
            let arrowLen: CGFloat = 5.0, arrowHalf: CGFloat = 3.4

            func arcPath() -> CGPath {
                let p = CGMutablePath()
                p.addArc(center: center, radius: r, startAngle: startRad, endAngle: endRad, clockwise: true)
                return p
            }
            func headPath() -> CGPath {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: e.x + arrowLen * tangent.x, y: e.y + arrowLen * tangent.y))
                p.addLine(to: CGPoint(x: e.x + arrowHalf * normal.x, y: e.y + arrowHalf * normal.y))
                p.addLine(to: CGPoint(x: e.x - arrowHalf * normal.x, y: e.y - arrowHalf * normal.y))
                p.closeSubpath()
                return p
            }

            ctx.setLineCap(.round); ctx.setLineJoin(.round)

            // 白ハロー
            ctx.addPath(arcPath()); ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(lineW + 2 * halo); ctx.strokePath()
            ctx.addPath(headPath()); ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(2 * halo); ctx.drawPath(using: .fillStroke)

            // 黒本体
            ctx.addPath(arcPath()); ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(lineW); ctx.strokePath()
            ctx.addPath(headPath()); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    /// 斜めリサイズカーソル（nwse: ↖↘ / !nwse: ↗↙）
    static func makeDiagonalCursor(nwse: Bool) -> NSCursor {
        let size: CGFloat = 20
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: size / 2, y: size / 2)
            let angle: CGFloat = nwse ? .pi / 4 : .pi * 3 / 4
            let ux = cos(angle), uy = sin(angle)
            // offset > length で 2 つの三角形の間に隙間を空ける
            let offset: CGFloat = 9.0

            func trianglePath(tip: CGPoint, outward: CGFloat) -> CGPath {
                let length: CGFloat = 6.5
                let halfWidth: CGFloat = 4.3
                let ax = cos(outward), ay = sin(outward)
                let bx = -ay, by = ax
                let base = CGPoint(x: tip.x - length * ax, y: tip.y - length * ay)
                let path = CGMutablePath()
                path.move(to: tip)
                path.addLine(to: CGPoint(x: base.x + halfWidth * bx,
                                         y: base.y + halfWidth * by))
                path.addLine(to: CGPoint(x: base.x - halfWidth * bx,
                                         y: base.y - halfWidth * by))
                path.closeSubpath()
                return path
            }

            func drawTriangle(tip: CGPoint, outward: CGFloat) {
                let path = trianglePath(tip: tip, outward: outward)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)

                // 白ハロー（縁取り）
                ctx.addPath(path)
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(2.6)
                ctx.strokePath()

                // 黒で塗りつぶし
                ctx.addPath(path)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillPath()
            }

            let tip1 = CGPoint(x: center.x - offset * ux, y: center.y - offset * uy)
            let tip2 = CGPoint(x: center.x + offset * ux, y: center.y + offset * uy)
            drawTriangle(tip: tip1, outward: angle + .pi)
            drawTriangle(tip: tip2, outward: angle)
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }
}
