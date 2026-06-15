import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if model.showToolbar {
                    ToolbarView()
                    Divider()
                }
                HStack(spacing: 0) {
                    ToolPaletteView()
                        .frame(width: 44)
                    Divider()
                    CanvasView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    SidePanelView()
                        .frame(width: 200)
                }
            }
        }
        // ルーペ・ナビゲーター・レイヤーを NSPanel として管理
        .background(
            ZStack {
                FloatingPanelManager(
                    isVisible: $model.showLoupe,
                    title: "ルーペ",
                    autosaveName: "LoupePanel",
                    minSize: NSSize(width: 160, height: 216),
                    defaultSize: NSSize(width: 200, height: 256)
                ) { LoupePanelContent().environmentObject(model) }
                FloatingPanelManager(
                    isVisible: $model.showNavigatorPanel,
                    title: "ナビゲーター",
                    autosaveName: "NavigatorPanel",
                    minSize: NSSize(width: 210, height: 170),
                    defaultSize: NSSize(width: 220, height: 220)
                ) { NavigatorPanel().environmentObject(model) }
                FloatingPanelManager(
                    isVisible: $model.showLayersPanel,
                    title: "レイヤー",
                    autosaveName: "LayerPanel",
                    minSize: NSSize(width: 180, height: 200),
                    defaultSize: NSSize(width: 220, height: 280)
                ) { LayerPalette().environmentObject(model) }
            }
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $model.showNewFileDialog) { NewFileDialog() }
        .sheet(isPresented: $model.showCanvasSizeDialog) { CanvasSizeDialog() }
        .sheet(isPresented: $model.showExportDialog) { ExportDialog() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var found = false
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            found = true
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let images = urls.filter { ["png", "jpg", "jpeg", "tiff", "tif", "bmp"].contains($0.pathExtension.lowercased()) }
            let pics = urls.filter { $0.pathExtension.lowercased() == "pic" }
            if let pic = pics.first { model.openProject(url: pic) }
            if !images.isEmpty { model.openImageFiles(images) }
        }
        return found
    }
}

// MARK: - ツールバー

struct ToolbarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.undo()
            } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(model.undoStack.isEmpty)
                .help("アンドゥ")
            Button {
                model.redo()
            } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(model.redoStack.isEmpty)
                .help("リドゥ")

            Divider().frame(height: 16)

            Button {
                model.bwPreviewOn.toggle()
            } label: {
                Text(model.bwPreviewOn ? "B&W中" : "B&W")
                    .frame(width: 48)
            }
            .disabled(model.selection == nil)
            .help("選択範囲のB&Wプレビュー")

            Divider().frame(height: 16)

            Spacer()

            if let msg = model.statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

// MARK: - ツールパレット（左 44px）

struct ToolPaletteView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                ToolButton(tool: tool, currentTool: $model.tool) {
                    model.tool = tool
                }
            }
            Spacer()
            Divider().padding(.horizontal, 6).padding(.bottom, 2)
            PaletteToggleButton(systemImage: "magnifyingglass", help: "ルーペ", isOn: $model.showLoupe)
            PaletteToggleButton(systemImage: "map", help: "ナビゲーター", isOn: $model.showNavigatorPanel)
            PaletteToggleButton(systemImage: "square.stack.3d.up", help: "レイヤー", isOn: $model.showLayersPanel)
            Divider().padding(.horizontal, 6).padding(.vertical, 2)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: model.foregroundColor.nsColor))
                .frame(width: 26, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5)))
                .help("前景色 \(model.foregroundColor.hexString)")
                .padding(.bottom, 8)
                .padding(.top, 4)
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PaletteToggleButton: View {
    let systemImage: String
    let help: String
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14))
                .frame(width: 34, height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isOn       { return Color.accentColor.opacity(0.35) }
        if isHovering { return Color.secondary.opacity(0.18) }
        return .clear
    }
}

// MARK: - ツールボタン（ホバーエフェクトつき）

private struct ToolButton: View {
    let tool: Tool
    @Binding var currentTool: Tool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 14))
                .frame(width: 34, height: 28)
                .background(buttonBackground, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
        .onHover { hovering in isHovering = hovering }
    }

    private var buttonBackground: Color {
        if currentTool == tool {
            return Color.accentColor.opacity(0.35)
        } else if isHovering {
            return Color.secondary.opacity(0.18)
        } else {
            return .clear
        }
    }
}
