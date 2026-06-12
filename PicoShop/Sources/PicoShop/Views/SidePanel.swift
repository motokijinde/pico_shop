import SwiftUI

// MARK: - サイドパネル（ナビゲーター + レイヤー + オプション）

struct SidePanelView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            NavigatorPanel()
            Divider()
            if model.showLayersPanel {
                LayerPalette()
                Divider()
            }
            if model.showOptionsPanel {
                ScrollView {
                    OptionsPanel()
                        .padding(8)
                }
            }
            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - ナビゲーターパネル（仕様 5-0）

struct NavigatorPanel: View {
    @EnvironmentObject var model: AppModel

    private let thumbHeight: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ナビゲーター")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let b = model.compositeBounds
                let scale = min(geo.size.width / max(1, b.width), geo.size.height / max(1, b.height))
                let thumbSize = CGSize(width: b.width * scale, height: b.height * scale)
                let origin = CGPoint(x: (geo.size.width - thumbSize.width) / 2,
                                     y: (geo.size.height - thumbSize.height) / 2)

                // サムネイルと赤枠（可視範囲）は Metal で描画
                NavigatorMetalView()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            // ドラッグ位置のキャンバス座標をビュー中心へスクロール
                            let cx = (v.location.x - origin.x) / scale + b.minX
                            let cy = (v.location.y - origin.y) / scale + b.minY
                            model.scrollTo(canvasPoint: CGPoint(x: cx, y: cy))
                        }
                )
            }
            .frame(height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text("Zoom: \(Int((model.zoom * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }
}

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
            .frame(height: 150)

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
            ZStack {
                CheckerboardSmall()
                if let img = layer.cachedImage {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                }
            }
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

// MARK: - レイヤー詳細（仕様 5-1）

struct LayerDetailView: View {
    @EnvironmentObject var model: AppModel
    let layer: Layer

    @State private var offsetXText = ""
    @State private var offsetYText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("名前: \(layer.name)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("画像サイズ: \(String(layer.buffer.width)) × \(String(layer.buffer.height)) px")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("表示サイズ: \(String(layer.buffer.width)) × \(String(layer.buffer.height)) px")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("合成", selection: Binding(
                get: { layer.blend },
                set: { newValue in model.updateLayer(layer.id) { $0.blend = newValue } }
            )) {
                ForEach(LayerBlendMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .font(.caption)
            .controlSize(.small)

            HStack {
                Text("不透明度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { layer.opacity },
                    set: { newValue in model.updateLayer(layer.id) { $0.opacity = newValue } }
                ), in: 0...100)
                Text("\(Int(layer.opacity))%")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            .controlSize(.mini)

            HStack(spacing: 6) {
                NumberField(label: "X", text: $offsetXText, width: 48) {
                    if let v = Int(offsetXText) {
                        model.pushUndo("レイヤーの移動")
                        model.updateLayer(layer.id) { $0.offsetX = v }
                    }
                }
                NumberField(label: "Y", text: $offsetYText, width: 48) {
                    if let v = Int(offsetYText) {
                        model.pushUndo("レイヤーの移動")
                        model.updateLayer(layer.id) { $0.offsetY = v }
                    }
                }
            }
        }
        .onAppear { syncOffsets() }
        .onChange(of: layer.offsetX) { syncOffsets() }
        .onChange(of: layer.offsetY) { syncOffsets() }
        .onChange(of: layer.id) { syncOffsets() }
    }

    private func syncOffsets() {
        offsetXText = String(layer.offsetX)
        offsetYText = String(layer.offsetY)
    }
}

// MARK: - 小さいチェッカーボード（サムネイル背景）

struct CheckerboardSmall: View {
    var body: some View {
        Canvas { ctx, size in
            drawCheckerboard(&ctx, in: CGRect(origin: .zero, size: size), tile: 4)
        }
    }
}
