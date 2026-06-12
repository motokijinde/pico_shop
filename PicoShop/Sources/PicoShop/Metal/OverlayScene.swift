import AppKit
import Metal
import simd

// MARK: - オーバーレイ表示リスト
//
// ビュー側は OverlayScene に「何を描くか」を積むだけで、Metal の詳細は OverlayRenderer が隠蔽する。
// 座標は基本的にビュー座標（ポイント、左上原点）。大きなパス（マーチングアンツ）だけは
// キャンバス座標でテッセレーション済みの StrokeMesh + 変換行列を使い、毎フレームの再構築を避ける。

struct OverlayScene {

    struct Dash {
        var on: CGFloat
        var off: CGFloat
        var phase: CGFloat = 0
    }

    /// 2×2 + 平行移動のアフィン変換（シェーダに渡す形式）
    struct Transform2D {
        var mat: SIMD4<Float>          // 列優先 2x2
        var translate: SIMD2<Float>
        var arcScale: Float            // 弧長 → ビューポイント（破線の間隔用）

        static let identity = Transform2D(mat: ShapeUniforms.identityMat,
                                          translate: .zero, arcScale: 1)

        init(mat: SIMD4<Float>, translate: SIMD2<Float>, arcScale: Float) {
            self.mat = mat
            self.translate = translate
            self.arcScale = arcScale
        }

        init(affine t: CGAffineTransform) {
            mat = SIMD4(Float(t.a), Float(t.b), Float(t.c), Float(t.d))
            translate = SIMD2(Float(t.tx), Float(t.ty))
            // 非等方スケールでは平均（破線間隔の近似。アンツ用途では十分）
            arcScale = Float((abs(t.a * t.d - t.b * t.c)).squareRoot())
        }
    }

    enum TextAnchor {
        case topLeading
        case leading       // 縦センター
        case bottomLeading
    }

    enum Item {
        case stroke(points: [CGPoint], closed: Bool, width: CGFloat, color: NSColor, dash: Dash?)
        case fill(rects: [CGRect], color: NSColor)
        case strokeCached(mesh: StrokeMesh, width: CGFloat, color: NSColor,
                          dash: Dash?, transform: Transform2D)
        case text(string: String, position: CGPoint, anchor: TextAnchor,
                  fontSize: CGFloat, color: NSColor, monospacedDigit: Bool)
    }

    var items: [Item] = []

    // MARK: 組み立てヘルパー

    mutating func stroke(_ points: [CGPoint], closed: Bool = false, width: CGFloat = 1,
                         color: NSColor, dash: Dash? = nil) {
        guard points.count >= 2 else { return }
        items.append(.stroke(points: points, closed: closed, width: width, color: color, dash: dash))
    }

    mutating func strokeRect(_ rect: CGRect, width: CGFloat = 1, color: NSColor, dash: Dash? = nil) {
        stroke([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)],
               closed: true, width: width, color: color, dash: dash)
    }

    mutating func strokeEllipse(in rect: CGRect, width: CGFloat = 1, color: NSColor,
                                segments: Int = 48) {
        var pts: [CGPoint] = []
        pts.reserveCapacity(segments)
        for i in 0..<segments {
            let a = CGFloat(i) / CGFloat(segments) * 2 * .pi
            pts.append(CGPoint(x: rect.midX + cos(a) * rect.width / 2,
                               y: rect.midY + sin(a) * rect.height / 2))
        }
        stroke(pts, closed: true, width: width, color: color)
    }

    mutating func fill(_ rect: CGRect, color: NSColor) {
        items.append(.fill(rects: [rect], color: color))
    }

    mutating func fillEllipse(in rect: CGRect, color: NSColor, segments: Int = 48) {
        // 中心からの扇形をクアッド近似（小さい円専用なので fill rect の集合で十分な精度にしない）
        // 楕円塗りはハンドル中心点（直径10）だけなので、ストローク幅で擬似的に塗る
        strokeEllipse(in: rect.insetBy(dx: rect.width / 4, dy: rect.height / 4),
                      width: rect.width / 2, color: color, segments: segments)
    }

    /// rect の外側を塗る（選択範囲外の暗転など）。viewSize 全体から rect をくり抜いた4矩形。
    mutating func dimOutside(_ rect: CGRect, in viewSize: CGSize, color: NSColor) {
        let full = CGRect(origin: .zero, size: viewSize)
        let r = rect.intersection(full)
        guard !r.isNull, r.width > 0, r.height > 0 else {
            fill(full, color: color)
            return
        }
        var rects: [CGRect] = []
        if r.minY > 0 {
            rects.append(CGRect(x: 0, y: 0, width: full.width, height: r.minY))
        }
        if r.maxY < full.height {
            rects.append(CGRect(x: 0, y: r.maxY, width: full.width, height: full.height - r.maxY))
        }
        if r.minX > 0 {
            rects.append(CGRect(x: 0, y: r.minY, width: r.minX, height: r.height))
        }
        if r.maxX < full.width {
            rects.append(CGRect(x: r.maxX, y: r.minY, width: full.width - r.maxX, height: r.height))
        }
        if !rects.isEmpty {
            items.append(.fill(rects: rects, color: color))
        }
    }

    mutating func text(_ string: String, at position: CGPoint, anchor: TextAnchor = .topLeading,
                       fontSize: CGFloat = 9, color: NSColor, monospacedDigit: Bool = false) {
        items.append(.text(string: string, position: position, anchor: anchor,
                           fontSize: fontSize, color: color, monospacedDigit: monospacedDigit))
    }
}

// MARK: - ストロークのテッセレーション

enum StrokeTessellator {

    /// ポリラインを太さ付き三角形列に変換する。offsetDir に単位法線を入れ、
    /// 実際の太さはシェーダ側（halfWidth uniform）で与える。
    static func tessellate(points: [CGPoint], closed: Bool,
                           into verts: inout [ShapeVertexIn]) {
        guard points.count >= 2 else { return }
        var arc: Float = 0
        let n = points.count
        let segCount = closed ? n : n - 1
        verts.reserveCapacity(verts.count + segCount * 6)
        for i in 0..<segCount {
            let p0 = points[i]
            let p1 = points[(i + 1) % n]
            let dx = Float(p1.x - p0.x), dy = Float(p1.y - p0.y)
            let len = (dx * dx + dy * dy).squareRoot()
            guard len > 0 else { continue }
            let nx = -dy / len, ny = dx / len
            let a0 = arc, a1 = arc + len
            arc = a1
            let v00 = ShapeVertexIn(pos: SIMD2(Float(p0.x), Float(p0.y)), offsetDir: SIMD2(nx, ny), arcLen: a0)
            let v01 = ShapeVertexIn(pos: SIMD2(Float(p0.x), Float(p0.y)), offsetDir: SIMD2(-nx, -ny), arcLen: a0)
            let v10 = ShapeVertexIn(pos: SIMD2(Float(p1.x), Float(p1.y)), offsetDir: SIMD2(nx, ny), arcLen: a1)
            let v11 = ShapeVertexIn(pos: SIMD2(Float(p1.x), Float(p1.y)), offsetDir: SIMD2(-nx, -ny), arcLen: a1)
            verts.append(contentsOf: [v00, v10, v01, v10, v11, v01])
        }
    }

    static func tessellateFill(rects: [CGRect], into verts: inout [ShapeVertexIn]) {
        verts.reserveCapacity(verts.count + rects.count * 6)
        for r in rects {
            let x0 = Float(r.minX), y0 = Float(r.minY), x1 = Float(r.maxX), y1 = Float(r.maxY)
            let v00 = ShapeVertexIn(pos: SIMD2(x0, y0), offsetDir: .zero, arcLen: 0)
            let v10 = ShapeVertexIn(pos: SIMD2(x1, y0), offsetDir: .zero, arcLen: 0)
            let v01 = ShapeVertexIn(pos: SIMD2(x0, y1), offsetDir: .zero, arcLen: 0)
            let v11 = ShapeVertexIn(pos: SIMD2(x1, y1), offsetDir: .zero, arcLen: 0)
            verts.append(contentsOf: [v00, v10, v01, v10, v11, v01])
        }
    }
}

// MARK: - 事前テッセレーション済みストローク（マーチングアンツ用）
//
// 選択範囲の境界パスは数万セグメントになり得るので、選択が変わったときに一度だけ
// キャンバス座標でメッシュ化し、毎フレームは変換行列と dashPhase だけ変える。

final class StrokeMesh {
    let buffer: MTLBuffer
    let vertexCount: Int

    init?(device: MTLDevice, polylines: [[CGPoint]], closed: Bool) {
        var verts: [ShapeVertexIn] = []
        for line in polylines {
            StrokeTessellator.tessellate(points: line, closed: closed, into: &verts)
        }
        guard !verts.isEmpty,
              let buf = device.makeBuffer(bytes: verts,
                                          length: MemoryLayout<ShapeVertexIn>.stride * verts.count,
                                          options: .storageModeShared) else { return nil }
        self.buffer = buf
        self.vertexCount = verts.count
    }
}
