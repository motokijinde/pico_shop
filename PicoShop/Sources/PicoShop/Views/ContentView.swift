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
                Divider()
                StatusBarView()
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
                    minSize: NSSize(width: 160, height: 140),
                    defaultSize: NSSize(width: 200, height: 180)
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
        .sheet(isPresented: $model.showModifySelectionDialog) { ModifySelectionDialog() }
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
    @State private var zoomText = ""
    @State private var editingZoom = false

    var body: some View {
        HStack(spacing: 8) {
            Button("新規") { model.showNewFileDialog = true }
            Button("開く") { model.openFileDialog() }
            Button("保存") { model.saveProject() }

            Divider().frame(height: 16)

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

            if editingZoom {
                TextField("", text: $zoomText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .onSubmit {
                        if let v = Double(zoomText.replacingOccurrences(of: "%", with: "")) {
                            model.setZoom(v / 100)
                        }
                        editingZoom = false
                    }
            } else {
                Button {
                    zoomText = String(Int((model.zoom * 100).rounded()))
                    editingZoom = true
                } label: {
                    Text("\(Int((model.zoom * 100).rounded()))%")
                        .font(.callout.monospacedDigit())
                        .frame(width: 52)
                }
                .help("ズーム率を直接入力")
            }

            Button {
                model.zoomOut()
            } label: { Image(systemName: "minus.magnifyingglass") }.help("ズームアウト")
            Button {
                model.zoomIn()
            } label: { Image(systemName: "plus.magnifyingglass") }.help("ズームイン")
            Button("全体") { model.fitToView() }.help("全体表示")
            Button("1:1") { model.zoomActualSize() }.help("等倍表示")

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

// MARK: - ステータスバー（仕様 13）

struct StatusBarView: View {
    @EnvironmentObject var model: AppModel

    private var selectionText: String? {
        guard let b = model.selectionBounds else { return nil }
        return "\(Int(b.width))×\(Int(b.height))"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            statusLine(canvasLabel: "キャンバス", zoomLabel: "Zoom", selLabel: "選択", noneLabel: "なし")
            statusLine(canvasLabel: "K", zoomLabel: "Z", selLabel: "S", noneLabel: nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statusLine(canvasLabel: String, zoomLabel: String,
                            selLabel: String, noneLabel: String?) -> some View {
        HStack(spacing: 6) {
            Text("\(canvasLabel): \(String(model.canvasWidth))×\(String(model.canvasHeight))")
            Text("|").foregroundStyle(.tertiary)
            // マウス座標は高頻度更新なので HoverState だけを観測する小ビューに分離
            MouseCoordText(hover: model.hover)
            Text("|").foregroundStyle(.tertiary)
            Text("\(zoomLabel): \(Int((model.zoom * 100).rounded()))%")
            if let sel = selectionText {
                Text("|").foregroundStyle(.tertiary)
                Text("\(selLabel): \(sel)")
            } else if let none = noneLabel {
                Text("|").foregroundStyle(.tertiary)
                Text("\(selLabel): \(none)")
            }
            Spacer(minLength: 0)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - マウス座標表示（HoverState のみ観測）

private struct MouseCoordText: View {
    @ObservedObject var hover: HoverState

    var body: some View {
        if let p = hover.mouseCanvasPos {
            Text("X: \(Int(p.x.rounded(.down))) Y: \(Int(p.y.rounded(.down)))")
        } else {
            Text("X: - Y: -")
        }
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
            PaletteToggleButton(systemImage: "magnifyingglass.circle", help: "ルーペ", isOn: $model.showLoupe)
            PaletteToggleButton(systemImage: "map", help: "ナビゲーター", isOn: $model.showNavigatorPanel)
            PaletteToggleButton(systemImage: "square.stack", help: "レイヤー", isOn: $model.showLayersPanel)
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
