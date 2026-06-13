import SwiftUI
import AppKit

private let loupeInfoBarH: CGFloat = 56
private let loupeInitialSize: CGFloat = 200
private let loupeMinCanvasW: CGFloat  = 160   // ズームピッカーが収まる最小幅
private let loupeMinCanvasH: CGFloat  = 160   // 最小時にキャンバスが正方形になる高さ

// MARK: - NSPanel ライフサイクル管理

struct LoupePanelManager: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(model: model, hostView: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?

        func sync(model: AppModel, hostView: NSView) {
            guard let parentWindow = hostView.window else { return }

            if model.showLoupe {
                if panel == nil {
                    panel = buildPanel(model: model, parent: parentWindow)
                }
                if let p = panel, !p.isVisible {
                    // 画面外に出ていたら親ウィンドウ近くに戻す
                    let onScreen = NSScreen.screens.contains {
                        $0.visibleFrame.intersects(p.frame)
                    }
                    if !onScreen {
                        p.setFrameOrigin(NSPoint(
                            x: parentWindow.frame.midX + 120,
                            y: parentWindow.frame.midY + 40
                        ))
                    }
                    p.orderFront(nil)
                }
            } else {
                if let p = panel, p.isVisible { p.orderOut(nil) }
            }
        }

        func cleanup() {
            panel?.orderOut(nil)
            panel = nil
        }

        private func buildPanel(model: AppModel, parent: NSWindow) -> NSPanel {
            let contentSize = NSSize(
                width: loupeInitialSize,
                height: loupeInitialSize + loupeInfoBarH
            )
            let hv = NSHostingView(
                rootView: LoupePanelContent().environmentObject(model)
            )
            hv.frame = NSRect(origin: .zero, size: contentSize)

            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.contentView = hv
            hv.autoresizingMask = [.width, .height]
            p.title = "ルーペ"
            p.level = .floating
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces]
            p.contentMinSize = NSSize(
                width: loupeMinCanvasW,
                height: loupeMinCanvasH + loupeInfoBarH
            )

            p.setFrameOrigin(NSPoint(
                x: parent.frame.midX + 120,
                y: parent.frame.midY + 40
            ))
            return p
        }
    }
}

// MARK: - パネルコンテンツ

struct LoupePanelContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            LoupeCanvasView()
                .frame(minWidth: loupeMinCanvasW, maxWidth: .infinity, minHeight: loupeMinCanvasH, maxHeight: .infinity)
            Divider()
            LoupeInfoBar(hover: model.hover)
                .frame(minWidth: loupeMinCanvasW, maxWidth: .infinity,
                       minHeight: loupeInfoBarH, maxHeight: loupeInfoBarH)
        }
    }
}

// MARK: - ルーペキャンバス（グリッドボタン＋ズームピッカーオーバーレイ）

private struct LoupeCanvasView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        LoupeMetalView()
            .overlay(alignment: .top) {
                HStack(spacing: 4) {
                    Spacer()
                    Picker("", selection: $model.loupeZoom) {
                        Text("1×").tag(100)
                        Text("2×").tag(200)
                        Text("4×").tag(400)
                        Text("8×").tag(800)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 110)
                }
                .padding(4)
            }
            .background(Color.black)
    }
}

// MARK: - カラー情報バー（3行：Hex / XY / RGBA）

private struct LoupeInfoBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var hover: HoverState

    var body: some View {
        let pos = hover.mouseCanvasPos ?? model.canvasCenter
        let px  = Int(pos.x.rounded(.down))
        let py  = Int(pos.y.rounded(.down))
        let c   = model.compositeColor(atCanvas: pos)

        VStack(alignment: .leading, spacing: 3) {
            // Row 1: スウォッチ + Hex
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(c.map { Color(nsColor: $0.nsColor) } ?? Color.secondary.opacity(0.15))
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
                    )
                Text(c?.hexString ?? "—")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
            }
            // Row 2: X/Y 座標
            HStack(spacing: 0) {
                coordView("X", px)
                coordView("Y", py)
            }
            // Row 3: RGBA（ラベルに色付け）
            HStack(spacing: 0) {
                channelView("R", c?.r, Color.red)
                channelView("G", c?.g, Color(nsColor: .systemGreen))
                channelView("B", c?.b, Color.blue)
                channelView("A", c?.a, nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func coordView(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(":").foregroundStyle(.tertiary)
            Text(String(value))
        }
        .frame(width: 35, alignment: .leading)
        .font(.system(size: 9).monospacedDigit())
    }

    private func channelView(_ label: String, _ value: UInt8?, _ color: Color?) -> some View {
        HStack(spacing: 1) {
            Text(label).foregroundColor(color ?? Color(nsColor: .tertiaryLabelColor))
            Text(":").foregroundStyle(.tertiary)
            Text(value.map { String($0) } ?? "—")
        }
        .frame(width: 35, alignment: .leading)
        .font(.system(size: 9).monospacedDigit())
    }
}
