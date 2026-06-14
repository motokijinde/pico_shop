import SwiftUI
import AppKit

// MARK: - PixelColor ↔ SwiftUI Color バインディング

extension Binding where Value == PixelColor {
    var swiftUIColor: Binding<Color> {
        Binding<Color>(
            get: { Color(nsColor: wrappedValue.nsColor) },
            set: { wrappedValue = PixelColor(nsColor: NSColor($0)) }
        )
    }
}

// MARK: - 数値スピナーフィールド（テキスト入力 + macOS 標準 NSStepper）

struct NumberField: View {
    let label: String
    @Binding var text: String
    var width: CGFloat = 56
    var labelWidth: CGFloat? = nil
    var step: Double = 1
    var onCommit: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: labelWidth, alignment: .trailing)
            }
            HStack(spacing: 0) {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospacedDigit())
                    .frame(width: width)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .onSubmit { onCommit() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { onCommit() }
                    }
                Stepper("", onIncrement: { stepValue(step) },
                              onDecrement: { stepValue(-step) })
                    .labelsHidden()
                    .controlSize(.mini)
            }
        }
    }

    private func stepValue(_ delta: Double) {
        let current = Double(text) ?? 0
        let next = current + delta
        text = next == next.rounded() ? String(Int(next.rounded())) : String(next)
        onCommit()
    }
}

// MARK: - オプションパネルのセクション見出し

struct OptionSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - アンカーポイント選択（3×3 グリッド）

struct AnchorGrid: View {
    @Binding var anchor: Int  // 0–8

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let idx = row * 3 + col
                        Button {
                            anchor = idx
                        } label: {
                            Image(systemName: anchor == idx ? "circle.fill" : "circle")
                                .font(.system(size: 9))
                                .frame(width: 18, height: 18)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - チェッカーボード（透明部分の表現）

func drawCheckerboard(_ ctx: inout GraphicsContext, in rect: CGRect, tile: CGFloat = 8) {
    guard rect.width > 0, rect.height > 0 else { return }
    ctx.clip(to: Path(rect))
    var y = rect.minY
    var rowIndex = 0
    while y < rect.maxY {
        var x = rect.minX
        var colIndex = 0
        while x < rect.maxX {
            let light = (rowIndex + colIndex) % 2 == 0
            ctx.fill(Path(CGRect(x: x, y: y, width: tile, height: tile)),
                     with: .color(light ? Color.white : Color(white: 0.82)))
            x += tile
            colIndex += 1
        }
        y += tile
        rowIndex += 1
    }
}
