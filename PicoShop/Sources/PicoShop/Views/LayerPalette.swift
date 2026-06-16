import SwiftUI
import UniformTypeIdentifiers

// MARK: - レイヤーパレット（仕様 5-1, 5-2）

struct LayerPalette: View {
    @EnvironmentObject var model: AppModel
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var draggingLayerID: UUID?
    @State private var dropTargetID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("レイヤー")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 1) {
                Spacer(minLength: 0)
                LayerIconButton(systemImage: "plus.square", help: "新規レイヤー") { model.addEmptyLayer() }
                LayerIconButton(systemImage: "photo.badge.plus", help: "ファイルから読み込み") { model.addLayerFromFile() }
                LayerIconButton(systemImage: "plus.square.on.square", help: "レイヤーを複製") { model.duplicateActiveLayer() }
                LayerIconButton(systemImage: "trash", help: "レイヤーを削除") { model.deleteActiveLayer() }
                LayerIconButton(systemImage: "square.stack.3d.down.right", help: "レイヤーを統合") { model.mergeVisibleLayers() }
                LayerIconButton(systemImage: "arrowtriangle.up", help: "前面へ") { model.moveActiveLayer(up: true) }
                LayerIconButton(systemImage: "arrowtriangle.down", help: "背面へ") { model.moveActiveLayer(up: false) }
            }

            ScrollViewReader { proxy in
                List {
                    ForEach(model.layers) { layer in
                        layerRow(layer)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
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
                Divider()
                LayerDetailView(layer: layer)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    /// ドラッグ方向に応じて挿入ラインを行の上端／下端どちらに出すか
    /// （上へ動かす＝対象行の上、下へ動かす＝対象行の下。reorderLayers の挿入位置と一致）
    private func insertionAlignment(_ layer: Layer) -> Alignment {
        guard let dragID = draggingLayerID,
              let from = model.layers.firstIndex(where: { $0.id == dragID }),
              let to = model.layers.firstIndex(where: { $0.id == layer.id }) else { return .top }
        return from > to ? .top : .bottom
    }

    @ViewBuilder
    private func layerRow(_ layer: Layer) -> some View {
        HStack(spacing: 5) {
            // ドラッグハンドル（掴んで並び替え）
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 44)
                .contentShape(Rectangle())
                .onDrag {
                    draggingLayerID = layer.id
                    return NSItemProvider(object: layer.id.uuidString as NSString)
                }
                .help("ドラッグで並び替え")

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
        .overlay(alignment: insertionAlignment(layer)) {
            if dropTargetID == layer.id {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.activeLayerID = layer.id }
        .onDrop(
            of: [.text],
            delegate: LayerRowDropDelegate(
                targetID: layer.id,
                draggingID: $draggingLayerID,
                dropTargetID: $dropTargetID,
                model: model
            )
        )
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

private struct LayerRowDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    @Binding var dropTargetID: UUID?
    let model: AppModel

    // ドラッグ中: ドロップ先の行を目印としてハイライト
    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        dropTargetID = targetID
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID { dropTargetID = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    // ドロップ確定時に 1 回だけ並び替え（Undo も 1 回）
    func performDrop(info: DropInfo) -> Bool {
        defer { draggingID = nil; dropTargetID = nil }
        guard let draggingID, draggingID != targetID,
              let from = model.layers.firstIndex(where: { $0.id == draggingID }),
              let to = model.layers.firstIndex(where: { $0.id == targetID }) else { return false }
        model.reorderLayers(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        return true
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
