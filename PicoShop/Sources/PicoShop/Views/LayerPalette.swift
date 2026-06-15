import SwiftUI

// MARK: - レイヤーパレット（仕様 5-1, 5-2）

struct LayerPalette: View {
    @EnvironmentObject var model: AppModel
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("レイヤー")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                HStack(spacing: 1) {
                    LayerIconButton(systemImage: "plus.square", help: "新規レイヤー") { model.addEmptyLayer() }
                    LayerIconButton(systemImage: "photo.badge.plus", help: "ファイルから読み込み") { model.addLayerFromFile() }
                    LayerIconButton(systemImage: "plus.square.on.square", help: "レイヤーを複製") { model.duplicateActiveLayer() }
                    LayerIconButton(systemImage: "trash", help: "レイヤーを削除") { model.deleteActiveLayer() }
                    LayerIconButton(systemImage: "square.stack.3d.down.right", help: "レイヤーを統合") { model.mergeVisibleLayers() }
                    LayerIconButton(systemImage: "arrowtriangle.up", help: "上へ移動") { model.moveActiveLayer(up: true) }
                    LayerIconButton(systemImage: "arrowtriangle.down", help: "下へ移動") { model.moveActiveLayer(up: false) }
                }
            }

            ScrollViewReader { proxy in
                List {
                    ForEach(model.layers) { layer in
                        layerRow(layer)
                            .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                    }
                    .onMove { from, to in
                        model.reorderLayers(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: .infinity)
                .onChange(of: model.layers.count) { _, _ in
                    if let id = model.activeLayerID {
                        proxy.scrollTo(id)
                    }
                }
            }

            if let layer = model.activeLayer {
                LayerDetailView(layer: layer)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func layerRow(_ layer: Layer) -> some View {
        HStack(spacing: 5) {
            // 表示/非表示
            LayerIconButton(systemImage: layer.visible ? "eye" : "eye.slash",
                            help: "表示/非表示",
                            foreground: layer.visible ? .primary : .secondary) {
                model.updateLayer(layer.id) { $0.visible.toggle() }
            }

            // ロック
            LayerIconButton(systemImage: layer.locked ? "lock.fill" : "lock.open",
                            help: "ロック",
                            foreground: layer.locked ? .orange : .secondary) {
                model.updateLayer(layer.id) { $0.locked.toggle() }
            }

            // サムネイル（48×48）
            LayerThumbnailMetalView(layer: layer)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.3)))

            // 名前（ダブルクリックで編集）
            if renamingID == layer.id {
                TextField("", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        model.updateLayer(layer.id) { $0.name = renameText }
                        renamingID = nil
                    }
                    .onExitCommand { renamingID = nil }
            } else {
                Text(layer.name)
                    .font(.caption)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        renameText = layer.name
                        renamingID = layer.id
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(2)
        .background(
            model.activeLayerID == layer.id ? Color.accentColor.opacity(0.2) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.activeLayerID = layer.id }
        .contextMenu {
            Button {
                renameText = layer.name
                renamingID = layer.id
            } label: {
                Label("名前を変更", systemImage: "pencil")
            }
            Button {
                model.activeLayerID = layer.id
                model.duplicateActiveLayer()
            } label: {
                Label("複製", systemImage: "doc.on.doc")
            }
            Button {
                model.activeLayerID = layer.id
                model.deleteActiveLayer()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }
}

private struct LayerIconButton: View {
    let systemImage: String
    let help: String
    var foreground: Color = .primary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 22, height: 22)
                .background(
                    hovering ? Color.secondary.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
