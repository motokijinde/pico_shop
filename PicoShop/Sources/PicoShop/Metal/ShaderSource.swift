import simd

// MARK: - シェーダーと共有するユニフォーム構造体
// MSL 側の構造体とメモリレイアウトを一致させること（float2=8B align, float4=16B align）

struct ViewUniforms {
    var viewSize: SIMD2<Float>
}

struct QuadVertexIn {
    var pos: SIMD2<Float>   // ビュー座標（ポイント）またはターゲットピクセル座標
    var uv: SIMD2<Float>
}

struct CheckerUniforms {
    var origin: SIMD2<Float>
    var tile: Float
    var pad: Float = 0
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
}

struct ShapeVertexIn {
    var pos: SIMD2<Float>        // uniform の scale/translate が適用される空間
    var offsetDir: SIMD2<Float>  // 線の太さ方向の単位ベクトル（ビュー空間で halfWidth 倍）
    var arcLen: Float            // pos 空間での弧長（破線用）
}

struct ShapeUniforms {
    /// 2×2 アフィン行列（列優先）: viewX = mat.x*x + mat.z*y, viewY = mat.y*x + mat.w*y
    var mat: SIMD4<Float>
    var translate: SIMD2<Float>
    var viewSize: SIMD2<Float>
    var halfWidth: Float
    var arcScale: Float          // arcLen → ビューポイントへの倍率
    var pad0: SIMD2<Float> = .zero
    var color: SIMD4<Float>      // 非プリマルチプライ RGBA
    var dashOn: Float            // 0 なら実線
    var dashOff: Float
    var dashPhase: Float
    var pad1: Float = 0

    static let identityMat = SIMD4<Float>(1, 0, 0, 1)
}

struct BlendUniforms {
    var compositeSize: SIMD2<Float>
    var layerOrigin: SIMD2<Float>   // 合成テクスチャピクセル座標でのレイヤー左上
    var layerSize: SIMD2<Float>
    var opacity: Float
    var mode: Int32                 // LayerBlendMode と対応（下記 gpuMode）
}

extension LayerBlendMode {
    var gpuMode: Int32 {
        switch self {
        case .normal: return 0
        case .multiply: return 1
        case .screen: return 2
        case .overlay: return 3
        case .addition: return 4
        }
    }
}

// MARK: - MSL ソース（SwiftPM executable では metallib バンドルが扱いにくいため実行時コンパイル）

let picoShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct ViewUniforms { float2 viewSize; };

struct QuadVertexIn { float2 pos; float2 uv; };

struct QuadVaryings {
    float4 position [[position]];
    float2 uv;
    float2 viewPos;
};

// 左上原点のビュー座標（ポイント）→ NDC。y 反転はここで一元処理。
vertex QuadVaryings quad_vertex(uint vid [[vertex_id]],
                                const device QuadVertexIn *verts [[buffer(0)]],
                                constant ViewUniforms &u [[buffer(1)]]) {
    QuadVertexIn v = verts[vid];
    QuadVaryings out;
    out.position = float4(v.pos.x / u.viewSize.x * 2.0 - 1.0,
                          1.0 - v.pos.y / u.viewSize.y * 2.0, 0.0, 1.0);
    out.uv = v.uv;
    out.viewPos = v.pos;
    return out;
}

// テクスチャ付きクアッド（プリマルチプライ済みテクスチャ前提）
fragment float4 quad_fragment(QuadVaryings in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              sampler smp [[sampler(0)]],
                              constant float &alpha [[buffer(0)]]) {
    return tex.sample(smp, in.uv) * alpha;
}

struct CheckerUniforms {
    float2 origin;
    float tile;
    float pad;
    float4 colorA;
    float4 colorB;
};

fragment float4 checker_fragment(QuadVaryings in [[stage_in]],
                                 constant CheckerUniforms &u [[buffer(0)]]) {
    float2 p = floor((in.viewPos - u.origin) / u.tile);
    int c = int(p.x) + int(p.y);
    return ((c & 1) == 0) ? u.colorA : u.colorB;
}

struct ShapeVertexIn { float2 pos; float2 offsetDir; float arcLen; };

struct ShapeUniforms {
    float4 mat;          // 2x2 列優先: viewX = mat.x*x + mat.z*y, viewY = mat.y*x + mat.w*y
    float2 translate;
    float2 viewSize;
    float halfWidth;
    float arcScale;
    float2 pad0;
    float4 color;
    float dashOn;
    float dashOff;
    float dashPhase;
    float pad1;
};

struct ShapeVaryings {
    float4 position [[position]];
    float arc;
};

vertex ShapeVaryings shape_vertex(uint vid [[vertex_id]],
                                  const device ShapeVertexIn *verts [[buffer(0)]],
                                  constant ShapeUniforms &u [[buffer(1)]]) {
    ShapeVertexIn v = verts[vid];
    float2 p = float2(u.mat.x * v.pos.x + u.mat.z * v.pos.y,
                      u.mat.y * v.pos.x + u.mat.w * v.pos.y) + u.translate;
    // 線の太さは変換後のビュー空間で一定（方向だけ行列で回す）
    if (v.offsetDir.x != 0.0 || v.offsetDir.y != 0.0) {
        float2 d = float2(u.mat.x * v.offsetDir.x + u.mat.z * v.offsetDir.y,
                          u.mat.y * v.offsetDir.x + u.mat.w * v.offsetDir.y);
        p += normalize(d) * u.halfWidth;
    }
    ShapeVaryings out;
    out.position = float4(p.x / u.viewSize.x * 2.0 - 1.0,
                          1.0 - p.y / u.viewSize.y * 2.0, 0.0, 1.0);
    out.arc = v.arcLen * u.arcScale;
    return out;
}

fragment float4 shape_fragment(ShapeVaryings in [[stage_in]],
                               constant ShapeUniforms &u [[buffer(1)]]) {
    if (u.dashOn > 0.0) {
        float period = u.dashOn + u.dashOff;
        float t = fmod(in.arc + u.dashPhase, period);
        if (t < 0.0) t += period;
        if (t >= u.dashOn) discard_fragment();
    }
    return float4(u.color.rgb * u.color.a, u.color.a);
}

struct BlendUniforms {
    float2 compositeSize;
    float2 layerOrigin;
    float2 layerSize;
    float opacity;
    int mode;
};

// レイヤー合成（ピンポン1パス）。dst = 前段の合成結果（premultiplied）、
// src = レイヤー（unpremultiplied、範囲外は border=transparent）。
// CPU 版（CGContext sRGB 8bit）と一致させるため sRGB エンコード値のまま計算する。
fragment float4 blend_fragment(QuadVaryings in [[stage_in]],
                               texture2d<float> dstTex [[texture(0)]],
                               texture2d<float> srcTex [[texture(1)]],
                               sampler dstSmp [[sampler(0)]],
                               sampler srcSmp [[sampler(1)]],
                               constant BlendUniforms &u [[buffer(0)]]) {
    float4 dst = dstTex.sample(dstSmp, in.uv);
    float2 layerUV = (in.uv * u.compositeSize - u.layerOrigin) / u.layerSize;
    float4 src = srcTex.sample(srcSmp, layerUV);

    float as_ = src.a * u.opacity;
    float3 Cs = src.rgb;
    float ab = dst.a;
    float3 Cb = ab > 0.0 ? dst.rgb / ab : float3(0.0);

    if (u.mode == 4) {
        // plusLighter: プリマルチプライ値の加算（クランプ）
        float4 sp = float4(Cs * as_, as_);
        return min(dst + sp, float4(1.0));
    }

    float3 B;
    switch (u.mode) {
        case 1: B = Cb * Cs; break;                       // multiply
        case 2: B = Cb + Cs - Cb * Cs; break;             // screen
        case 3: B = select(1.0 - 2.0 * (1.0 - Cb) * (1.0 - Cs),
                           2.0 * Cb * Cs,
                           Cb <= 0.5); break;             // overlay
        default: B = Cs; break;                            // normal
    }
    float3 co = as_ * (1.0 - ab) * Cs + ab * (1.0 - as_) * Cb + as_ * ab * B;
    float ao = as_ + ab * (1.0 - as_);
    return float4(co, ao);
}
"""
