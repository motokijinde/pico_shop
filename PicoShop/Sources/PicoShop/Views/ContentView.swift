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
                    if model.showLoupe || model.showNavigatorPanel || model.showLayersPanel {
                        Divider()
                        InspectorPanel()
                            .frame(width: 240)
                    }
                }
                Divider()
                StatusBarView(hover: model.hover)
            }
        }
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
            if let pic = pics.first {
                model.openProject(url: pic)
            } else if !images.isEmpty {
                model.openImageFiles(images)
            }
        }
        return found
    }
}

// MARK: - 右インスペクタ

private struct InspectorPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.showLoupe {
                InspectorSectionHeader(title: "ルーペ")
                LoupePanelContent()
                    .frame(height: 208)
                if model.showNavigatorPanel || model.showLayersPanel {
                    panelDivider
                }
            }

            if model.showNavigatorPanel {
                NavigatorPanel()
                    .frame(height: 200)
                if model.showLayersPanel {
                    panelDivider
                }
            }

            if model.showLayersPanel {
                LayerPalette()
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var panelDivider: some View {
        Divider()
            .padding(.vertical, 2)
    }
}

private struct InspectorSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - ツールバー

struct ToolbarView: View {
    @EnvironmentObject var model: AppModel
    @State private var growShrinkText = "8"
    @State private var showingToolOptions = false

    var body: some View {
        HStack(spacing: 8) {
            Label(model.tool.displayName, systemImage: model.tool.systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(minWidth: 116, alignment: .leading)

            Divider().frame(height: 18)

            if model.tool.isSelectionTool {
                SelectionModeButtons()
                    .frame(width: 104)

                Divider().frame(height: 18)
            }

            toolSpecificControls

            transformCommitControls

            if model.tool.hasToolbarOptionsPopover {
                Button {
                    showingToolOptions.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("\(model.tool.displayName)の詳細設定")
                .popover(isPresented: $showingToolOptions, arrowEdge: .bottom) {
                    ToolOptionsPopoverContent()
                        .environmentObject(model)
                        .padding(10)
                        .frame(width: 220)
                }
            }

            if (model.selection != nil || model.tool.isSelectionTool || model.tool == .selectionTransform)
                && model.tool != .move && model.tool != .transform {
                Divider().frame(height: 18)
                selectionActions
            }

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 34)
        .onAppear { growShrinkText = String(model.lastGrowShrinkAmount) }
    }

    @ViewBuilder
    private var toolSpecificControls: some View {
        switch model.tool {
        case .rectSelect:
            Toggle("比率", isOn: $model.rectSelKeepAspect)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("アスペクト比維持")
            Toggle("中央", isOn: $model.rectSelFromCenter)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("中央から選択")
        case .colorRangeSelect:
            HStack(spacing: 4) {
                Text("レベル")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $model.colorRangeOpts.level, in: 1...100)
                    .frame(width: 104)
                Text("\(Int(model.colorRangeOpts.level))")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 24, alignment: .trailing)

Toggle("隣接", isOn: $model.colorRangeOpts.contiguous)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("ONのとき、クリック点から隣接するピクセルのみ選択")

            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var transformCommitControls: some View {
        switch model.tool {
        case .move:
            HStack(spacing: 4) {
                Button { model.commitMoveTransform() } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(model.floatingLayer == nil)
                .help("移動を確定")

                Button { model.resetMoveTransform() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(model.pendingTransform.isIdentity)
                .help("移動をリセット")
            }
        case .selectionTransform:
            HStack(spacing: 4) {
                Button { model.applySelectionTransform() } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(model.pendingTransform.isIdentity)
                .help("選択変形を確定")

                Button { model.resetSelectionTransform() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(model.pendingTransform.isIdentity)
                .help("選択変形をリセット")
            }
        case .transform:
            HStack(spacing: 4) {
                Button { model.applyPixelTransform() } label: {
                    Image(systemName: "checkmark")
                }
                .disabled(model.pendingTransform.isIdentity)
                .help("変形を適用")

                Button { model.resetSelectionTransform() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(model.pendingTransform.isIdentity)
                .help("変形をリセット")
            }
        default:
            EmptyView()
        }
    }

    private var selectionActions: some View {
        HStack(spacing: 6) {
            NumberField(label: "px", text: $growShrinkText, width: 42, labelWidth: 20) {
                commitGrowShrinkPixels()
            }

            Button { model.growSelection(by: growShrinkPixels) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(model.selection == nil)
            .help("選択範囲を拡大")

            Button { model.shrinkSelection(by: growShrinkPixels) } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(model.selection == nil)
            .help("選択範囲を縮小")

            Button { model.invertSelection() } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .disabled(model.selection == nil)
            .help("選択を反転")

            Button { model.clearSelection() } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(model.selection == nil)
            .help("選択をクリア")
        }
        .frame(height: 24)
    }

    private var growShrinkPixels: Int {
        max(1, Int(growShrinkText) ?? model.lastGrowShrinkAmount)
    }

    private func commitGrowShrinkPixels() {
        model.lastGrowShrinkAmount = growShrinkPixels
        growShrinkText = String(growShrinkPixels)
    }
}

private struct ToolOptionsPopoverContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        switch model.tool {
        case .maskBrush:
            MaskBrushOptionsView()
        case .selectionTransform:
            SelectionTransformOptionsView()
        case .move:
            MoveTransformPanel()
        case .transform:
            TransformToolOptionsView()
        case .fill:
            FillToolOptions()
        case .resize:
            ResizeToolOptions()
        case .text:
            TextToolOptions()
        case .rotate:
            RotateToolOptions()
        case .flip:
            FlipToolOptions()
        case .rectSelect, .freehandSelect, .colorRangeSelect, .layerMove, .eyedropper:
            EmptyView()
        }
    }
}

// MARK: - 選択操作モードボタン（新規・追加・除外）

struct SelectionModeButtons: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SelectionOperationMode.allCases) { mode in
                Button {
                    model.selectionOperationMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 24)
                        .background(
                            model.selectionOperationMode == mode
                                ? Color.accentColor.opacity(0.3)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.displayName)
            }
        }
        .frame(height: 24)
    }
}

// MARK: - ステータスバー

struct StatusBarView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var hover: HoverState

    init(hover: HoverState) {
        self.hover = hover
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(model.statusMessage == nil ? Color.secondary : Color.orange)
                .lineLimit(1)

            Spacer()

            if let p = hover.mouseCanvasPos {
                Text("X \(Int(p.x))  Y \(Int(p.y))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text("\(Int(model.zoom * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusText: String {
        model.statusMessage ?? model.tool.statusHelp
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
