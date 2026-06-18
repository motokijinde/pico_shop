import SwiftUI

// MARK: - Transform numeric field helpers

enum TransformDimension {
    case width
    case height
}

struct TransformFieldSnapshot {
    var widthText: String
    var heightText: String
    var xText: String
    var yText: String
    var rotationText: String
    var widthPercentText: String
    var heightPercentText: String
}

enum TransformFieldMath {
    static func transformedRect(base: CGRect, transform t: SelectionTransform) -> CGRect {
        let w = Double(base.width) * abs(t.scaleX)
        let h = Double(base.height) * abs(t.scaleY)
        return CGRect(x: base.midX + t.dx - w / 2,
                      y: base.midY + t.dy - h / 2,
                      width: w,
                      height: h)
    }

    static func snapshot(base: CGRect, transform: SelectionTransform) -> TransformFieldSnapshot {
        let rect = transformedRect(base: base, transform: transform)
        return TransformFieldSnapshot(
            widthText: integerString(rect.width),
            heightText: integerString(rect.height),
            xText: integerString(rect.minX),
            yText: integerString(rect.minY),
            rotationText: integerString(transform.rotation),
            widthPercentText: percentString(abs(transform.scaleX)),
            heightPercentText: percentString(abs(transform.scaleY))
        )
    }

    static func resizing(base: CGRect, current: SelectionTransform, edited: TransformDimension,
                         widthText: String, heightText: String, keepAspect: Bool) -> SelectionTransform? {
        guard base.width > 0, base.height > 0 else { return nil }

        let sx: Double
        let sy: Double
        switch edited {
        case .width:
            guard let width = Double(widthText), width >= 1 else { return nil }
            sx = signedScale(magnitude: max(0.01, width / Double(base.width)),
                             preservingSignOf: current.scaleX)
            sy = keepAspect
                ? signedScale(magnitude: abs(sx), preservingSignOf: current.scaleY)
                : signedScale(from: heightText, fallback: abs(current.scaleY),
                              baseLength: Double(base.height), preservingSignOf: current.scaleY)
        case .height:
            guard let height = Double(heightText), height >= 1 else { return nil }
            sy = signedScale(magnitude: max(0.01, height / Double(base.height)),
                             preservingSignOf: current.scaleY)
            sx = keepAspect
                ? signedScale(magnitude: abs(sy), preservingSignOf: current.scaleX)
                : signedScale(from: widthText, fallback: abs(current.scaleX),
                              baseLength: Double(base.width), preservingSignOf: current.scaleX)
        }

        var next = current
        next.scaleX = sx
        next.scaleY = sy
        return next
    }

    static func resizingByPercent(base: CGRect, current: SelectionTransform, edited: TransformDimension,
                                  widthPercentText: String, heightPercentText: String,
                                  keepAspect: Bool) -> SelectionTransform? {
        guard base.width > 0, base.height > 0 else { return nil }

        let sx: Double
        let sy: Double
        switch edited {
        case .width:
            guard let pct = Double(widthPercentText), pct >= 0.1 else { return nil }
            sx = signedScale(magnitude: max(0.01, pct / 100),
                             preservingSignOf: current.scaleX)
            sy = keepAspect
                ? signedScale(magnitude: abs(sx), preservingSignOf: current.scaleY)
                : current.scaleY
        case .height:
            guard let pct = Double(heightPercentText), pct >= 0.1 else { return nil }
            sy = signedScale(magnitude: max(0.01, pct / 100),
                             preservingSignOf: current.scaleY)
            sx = keepAspect
                ? signedScale(magnitude: abs(sy), preservingSignOf: current.scaleX)
                : current.scaleX
        }

        var next = current
        next.scaleX = sx
        next.scaleY = sy
        return next
    }

    static func repositioning(base: CGRect, current: SelectionTransform,
                              xText: String, yText: String) -> SelectionTransform? {
        guard let x = Double(xText), let y = Double(yText) else { return nil }
        let w = Double(base.width) * abs(current.scaleX)
        let h = Double(base.height) * abs(current.scaleY)
        var next = current
        next.dx = x + w / 2 - Double(base.midX)
        next.dy = y + h / 2 - Double(base.midY)
        return next
    }

    static func rotating(current: SelectionTransform, rotationText: String) -> SelectionTransform? {
        guard let value = Double(rotationText) else { return nil }
        var next = current
        next.rotation = normalizedDegrees(value)
        return next
    }

    static func normalizedDegrees(_ value: Double) -> Double {
        var deg = value.truncatingRemainder(dividingBy: 360)
        if deg < 0 { deg += 360 }
        return deg
    }

    private static func scale(from text: String, fallback: Double, baseLength: Double) -> Double {
        guard let value = Double(text), value >= 1 else { return max(0.01, fallback) }
        return max(0.01, value / baseLength)
    }

    private static func signedScale(from text: String, fallback: Double,
                                    baseLength: Double, preservingSignOf current: Double) -> Double {
        signedScale(magnitude: scale(from: text, fallback: fallback, baseLength: baseLength),
                    preservingSignOf: current)
    }

    private static func signedScale(magnitude: Double, preservingSignOf current: Double) -> Double {
        current < 0 ? -magnitude : magnitude
    }

    private static func integerString(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
    }

    private static func integerString(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static func percentString(_ scale: Double) -> String {
        String(format: "%.1f", scale * 100)
    }
}
