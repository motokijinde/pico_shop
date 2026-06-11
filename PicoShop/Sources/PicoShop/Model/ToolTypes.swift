import SwiftUI

// MARK: - ツール

enum Tool: String, CaseIterable, Identifiable {
    case rectSelect
    case freehandSelect
    case colorRangeSelect
    case maskBrush
    case move
    case transform
    case fill
    case resize
    case text
    case crop
    case rotate
    case flip
    case eyedropper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectSelect:       return "矩形選択"
        case .freehandSelect:   return "フリーハンド選択"
        case .colorRangeSelect: return "色域選択"
        case .maskBrush:        return "マスクブラシ"
        case .move:             return "移動"
        case .transform:        return "変形"
        case .fill:             return "塗りつぶし"
        case .resize:           return "リサイズ"
        case .text:             return "テキスト"
        case .crop:             return "クロップ"
        case .rotate:           return "回転"
        case .flip:             return "反転"
        case .eyedropper:       return "スポイト"
        }
    }

    var systemImage: String {
        switch self {
        case .rectSelect:       return "rectangle.dashed"
        case .freehandSelect:   return "lasso"
        case .colorRangeSelect: return "wand.and.rays"
        case .maskBrush:        return "paintbrush.pointed"
        case .move:             return "arrow.up.and.down.and.arrow.left.and.right"
        case .transform:        return "crop.rotate"
        case .fill:             return "paintbrush.fill"
        case .resize:           return "arrow.up.left.and.arrow.down.right"
        case .text:             return "textformat"
        case .crop:             return "crop"
        case .rotate:           return "rotate.right"
        case .flip:             return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .eyedropper:       return "eyedropper"
        }
    }

    /// 選択系ツールか（矩形・フリーハンド・色域）
    var isSelectionTool: Bool {
        switch self {
        case .rectSelect, .freehandSelect, .colorRangeSelect: return true
        default: return false
        }
    }

    /// レイヤー/選択モード切り替えの対象ツール（仕様 12-4-3）
    var supportsModeSwitch: Bool {
        switch self {
        case .move, .rotate, .resize, .flip: return true
        default: return false
        }
    }
}

// MARK: - 選択操作モード（新規・追加・除外）

enum SelectionOperationMode: String, CaseIterable, Identifiable {
    case replace
    case add
    case subtract

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .replace:  return "新規"
        case .add:      return "追加"
        case .subtract: return "除外"
        }
    }

    var systemImage: String {
        switch self {
        case .replace:  return "rectangle.dashed"
        case .add:      return "rectangle.badge.plus"
        case .subtract: return "rectangle.badge.minus"
        }
    }
}

// MARK: - レイヤーモード / 選択モード（仕様 12-4）

enum ToolTargetMode: String, CaseIterable, Identifiable {
    case layer
    case selection

    var id: String { rawValue }
    var displayName: String { self == .layer ? "レイヤーモード" : "選択モード" }
}

// MARK: - ツールオプション

struct ColorRangeOptions {
    var bgColor: PixelColor = .white
    var level: Double = 30      // 1–100
    var erosion: Double = 0     // 0–10
    var inside: Bool = false
}

struct BrushOptions {
    var add: Bool = true
    var size: Double = 20       // 1–100 px
    var hardness: Double = 100  // 0–100 %
    var opacity: Double = 100   // 0–100 %
}

struct FillOptions {
    enum Scope: String, CaseIterable, Identifiable {
        case selection, click
        var id: String { rawValue }
        var displayName: String { self == .selection ? "選択範囲内" : "クリック位置（隣接色）" }
    }
    var color: PixelColor = .black
    var scope: Scope = .selection
    var antialias: Bool = false
    var tolerance: Double = 20  // 0–100
}

struct ResizeOptions {
    var scalePercent: String = "100"
    var widthText: String = ""
    var heightText: String = ""
    var keepAspect: Bool = true
    var quality: ResampleQuality = .lanczos
}

struct TextOptions {
    var fontFamily: String = "Hiragino Sans"
    var sizeText: String = "32"
    var weight: TextWeight = .regular
    var color: PixelColor = .black
    var antialias: Bool = true
    var anchor: Int = 0  // 0–8（3×3 グリッド、0=左上）
    var xText: String = "0"
    var yText: String = "0"
    var text: String = ""
}

enum TextWeight: String, CaseIterable, Identifiable {
    case light = "Light"
    case regular = "Regular"
    case medium = "Medium"
    case bold = "Bold"
    case heavy = "Heavy"

    var id: String { rawValue }

    /// NSFontManager の weight 値（0–15）
    var managerWeight: Int {
        switch self {
        case .light: return 3
        case .regular: return 5
        case .medium: return 7
        case .bold: return 9
        case .heavy: return 12
        }
    }
}

struct RotateOptions {
    var angleText: String = "0"
}

// MARK: - 選択範囲の変形（保留中トランスフォーム）

struct SelectionTransform: Equatable {
    var dx: Double = 0
    var dy: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    var rotation: Double = 0  // degrees

    var isIdentity: Bool {
        dx == 0 && dy == 0 && scaleX == 1 && scaleY == 1 && rotation == 0
    }

    /// top-left 座標系での変形（center を基準にスケール・回転後、移動）
    func affine(center: CGPoint) -> CGAffineTransform {
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: dx, y: dy)
        t = t.translatedBy(x: center.x, y: center.y)
        t = t.rotated(by: rotation * .pi / 180)
        t = t.scaledBy(x: scaleX, y: scaleY)
        t = t.translatedBy(x: -center.x, y: -center.y)
        return t
    }
}
