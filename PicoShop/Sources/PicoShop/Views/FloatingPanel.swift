import SwiftUI
import AppKit

// MARK: - 汎用フローティング NSPanel マネージャー
//
// デスクトップスペース追従・位置保存・×ボタン同期つき。
// ルーペ・ナビゲーター・レイヤーパレットで共用。

struct FloatingPanelManager<Content: View>: NSViewRepresentable {
    @Binding var isVisible: Bool
    let title: String
    let autosaveName: String
    let minSize: NSSize
    let defaultSize: NSSize
    let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(
            binding: $isVisible,
            hostView: nsView,
            title: title,
            autosaveName: autosaveName,
            minSize: minSize,
            defaultSize: defaultSize,
            makeContent: content
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?
        private weak var parentWindow: NSWindow?
        private var spaceObserver: Any?
        private var closeObserver: Any?
        private var binding: Binding<Bool>?

        func sync(binding: Binding<Bool>, hostView: NSView, title: String, autosaveName: String, minSize: NSSize, defaultSize: NSSize, makeContent: () -> Content) {
            self.binding = binding
            guard let window = hostView.window else { return }

            if parentWindow !== window {
                parentWindow = window
                installSpaceObserver()
            }

            if binding.wrappedValue {
                if panel == nil {
                    panel = buildPanel(
                        content: makeContent(),
                        parent: window,
                        title: title,
                        autosaveName: autosaveName,
                        minSize: minSize,
                        defaultSize: defaultSize
                    )
                }
                if let p = panel, !p.isVisible, window.isOnActiveSpace {
                    let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(p.frame) }
                    if !onScreen {
                        p.setFrameOrigin(NSPoint(x: window.frame.midX + 40, y: window.frame.midY))
                    }
                    p.orderFront(nil)
                }
            } else {
                if let p = panel, p.isVisible { p.orderOut(nil) }
            }
        }

        private func installSpaceObserver() {
            if let obs = spaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
            }
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let panel = self.panel else { return }
                    guard self.binding?.wrappedValue == true else { return }
                    if self.parentWindow?.isOnActiveSpace == true {
                        if !panel.isVisible { panel.orderFront(nil) }
                    } else {
                        if panel.isVisible { panel.orderOut(nil) }
                    }
                }
            }
        }

        func cleanup() {
            if let obs = spaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(obs)
                spaceObserver = nil
            }
            if let obs = closeObserver {
                NotificationCenter.default.removeObserver(obs)
                closeObserver = nil
            }
            panel?.orderOut(nil)
            panel = nil
            parentWindow = nil
            binding = nil
        }

        private func buildPanel(content: Content, parent: NSWindow, title: String, autosaveName: String, minSize: NSSize, defaultSize: NSSize) -> NSPanel {
            let hv = NSHostingView(rootView: content)
            hv.frame = NSRect(origin: .zero, size: defaultSize)

            let p = NSPanel(
                contentRect: NSRect(origin: .zero, size: defaultSize),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.contentView = hv
            hv.autoresizingMask = [.width, .height]
            p.title = title
            p.level = .floating
            p.hasShadow = true
            p.isReleasedWhenClosed = false
            p.contentMinSize = minSize

            p.setFrameOrigin(NSPoint(x: parent.frame.midX + 40, y: parent.frame.midY))
            p.setFrameAutosaveName(autosaveName)
            let f = p.frame
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(f) }
            let tooSmall = f.width < minSize.width || f.height < minSize.height
            if !onScreen || tooSmall {
                p.setContentSize(defaultSize)
                p.setFrameOrigin(NSPoint(x: parent.frame.midX + 40, y: parent.frame.midY))
            }

            // ×ボタンで閉じたときに isVisible を false に同期し、
            // パネルを破棄して次回に再構築（closed NSPanel の Metal view が壊れるのを防ぐ）
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: p,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.binding?.wrappedValue = false
                    if let obs = self?.closeObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self?.closeObserver = nil
                    }
                    self?.panel = nil
                }
            }

            return p
        }
    }
}
