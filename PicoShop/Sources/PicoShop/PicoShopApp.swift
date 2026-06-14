import SwiftUI

@main
struct PicoShopApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("PicoShop") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1024, minHeight: 768)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            // MARK: ファイル
            CommandGroup(replacing: .newItem) {
                Button("新規...") { model.showNewFileDialog = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("開く...") { model.openFileDialog() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存") { model.saveProject() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("別名で保存...") { model.saveProject(forceDialog: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("エクスポート...") { model.showExportDialog = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // MARK: 編集（システムの Edit メニューを空にして独自メニューを立てる）
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandMenu("編集") {
                Button("アンドゥ\(model.undoLabel.map { " \($0)" } ?? "")") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.undoStack.isEmpty)
                Button("リドゥ\(model.redoLabel.map { " \($0)" } ?? "")") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(model.redoStack.isEmpty)
                Divider()
                Button("カット") { model.cutSelection() }
                    .keyboardShortcut("x", modifiers: .command)
                Button("コピー") { model.copySelectionToPasteboard() }
                    .keyboardShortcut("c", modifiers: .command)
                Button("ペースト") { model.pasteFromPasteboard() }
                    .keyboardShortcut("v", modifiers: .command)
                Divider()
                Menu("反転") {
                    Button("水平反転") { model.flip(horizontal: true) }
                    Button("垂直反転") { model.flip(horizontal: false) }
                }
            }

            // MARK: キャンバス
            CommandMenu("キャンバス") {
                Button("キャンバスサイズ...") { model.showCanvasSizeDialog = true }
                Button("キャンバスを画像に合わせる") { model.fitCanvasToLayers() }
                Button("キャンバスを透明でクリア") { model.clearActiveLayerTransparent() }
            }

            // MARK: 選択
            CommandMenu("選択") {
                Button("すべてを選択") { model.selectAll() }
                    .keyboardShortcut("a", modifiers: .command)
                Button("選択を反転") { model.invertSelection() }
                    .keyboardShortcut("i", modifiers: .command)
                Button("選択をクリア") { model.clearSelection() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("選択範囲を拡大（\(model.lastGrowShrinkAmount)px）") {
                    model.growSelection(by: model.lastGrowShrinkAmount)
                }
                Button("選択範囲を縮小（\(model.lastGrowShrinkAmount)px）") {
                    model.shrinkSelection(by: model.lastGrowShrinkAmount)
                }
                Button("選択範囲を変更...") { model.showModifySelectionDialog = true }
                Divider()
                Button("選択範囲でクロップ") { model.cropToSelection() }
                    .disabled(model.selection == nil)
            }

            // MARK: レイヤー
            CommandMenu("レイヤー") {
                Button("新規レイヤー") { model.addEmptyLayer() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("ファイルから読み込み...") { model.addLayerFromFile() }
                Button("レイヤーを削除") { model.deleteActiveLayer() }
                Button("レイヤーを複製") { model.duplicateActiveLayer() }
                    .keyboardShortcut("j", modifiers: .command)
                Divider()
                Button("レイヤーを統合") { model.mergeVisibleLayers() }
                    .keyboardShortcut("e", modifiers: .command)
                Divider()
                Button("透明部分をトリム") { model.trimActiveLayer() }
                    .disabled(model.activeLayer == nil)
            }

            // MARK: ウィンドウ
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button(model.showLoupe ? "ルーペを隠す" : "ルーペを表示") {
                    model.showLoupe.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button(model.showLayersPanel ? "レイヤーを隠す" : "レイヤーを表示") {
                    model.showLayersPanel.toggle()
                }
                Button(model.showOptionsPanel ? "オプションを隠す" : "オプションを表示") {
                    model.showOptionsPanel.toggle()
                }
                Button(model.showToolbar ? "ツールバーを隠す" : "ツールバーを表示") {
                    model.showToolbar.toggle()
                }
            }
        }
    }
}
