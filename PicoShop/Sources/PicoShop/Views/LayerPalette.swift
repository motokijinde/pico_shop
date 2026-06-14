import SwiftUI

// MARK: - レイヤーパレット（仕様 5-1, 5-2）

struct LayerPalette: View {
    @EnvironmentObject var model: AppModel
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("レイヤー")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.addEmptyLayer() } label: { Image(systemName: "plus") }
                    .help("新規レイヤー")
                Button { model.deleteActiveLayer() } label: { Image(systemName: "trash") }
                    .help("レイヤーを削除")
                Button { model.moveActiveLayer(up: true) } label: { Image(systemName: "arrowtriangle.up") }
                    .help("上へ移動")
                Button { model.moveActiveLayer(up: false) } label: { Image(systemName: "arrowtriangle.down") }
                    .help("下へ移動")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

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
            Button {
                model.updateLayer(layer.id) { $0.visible.toggle() }
            } label: {
                Image(systemName: layer.visible ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(layer.visible ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("表示/非表示")

            // ロック
            Button {
                model.updateLayer(layer.id) { $0.locked.toggle() }
            } label: {
                Image(systemName: layer.locked ? "lock.fill" : "lock.open")
                    .font(.system(size: 10))
                    .foregroundStyle(layer.locked ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("ロック")

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
            Button("名前を変更") {
                renameText = layer.name
                renamingID = layer.id
            }
            Button("複製") {
                model.activeLayerID = layer.id
                model.duplicateActiveLayer()
            }
            Button("削除") {
                model.activeLayerID = layer.id
                model.deleteActiveLayer()
            }
        }
    }
}

