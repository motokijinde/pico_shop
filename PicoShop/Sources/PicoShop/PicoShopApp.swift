import SwiftUI
import AppKit

private class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PicoShopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                Button { model.showNewFileDialog = true } label: {
                    Label("新規...", systemImage: "doc.badge.plus")
                }
                    .keyboardShortcut("n", modifiers: .command)
                Button { model.openFileDialog() } label: {
                    Label("開く...", systemImage: "folder")
                }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button { model.saveProject() } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                    .keyboardShortcut("s", modifiers: .command)
                Button { model.saveProject(forceDialog: true) } label: {
                    Label("別名で保存...", systemImage: "square.and.arrow.down.on.square")
                }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button { model.showExportDialog = true } label: {
                    Label("エクスポート...", systemImage: "square.and.arrow.up")
                }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // MARK: 編集（システムの Edit メニューを空にして独自メニューを立てる）
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandMenu("編集") {
                Button { model.undo() } label: {
                    Label("アンドゥ\(model.undoLabel.map { " \($0)" } ?? "")", systemImage: "arrow.uturn.backward")
                }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.undoStack.isEmpty)
                Button { model.redo() } label: {
                    Label("リドゥ\(model.redoLabel.map { " \($0)" } ?? "")", systemImage: "arrow.uturn.forward")
                }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(model.redoStack.isEmpty)
                Divider()
                Button { model.cutSelection() } label: {
                    Label("カット", systemImage: "scissors")
                }
                    .keyboardShortcut("x", modifiers: .command)
                    .disabled(model.selection == nil)
                Button { model.copySelectionToPasteboard() } label: {
                    Label("コピー", systemImage: "doc.on.doc")
                }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(model.selection == nil)
                Button { model.pasteFromPasteboard() } label: {
                    Label("ペースト", systemImage: "doc.on.clipboard")
                }
                    .keyboardShortcut("v", modifiers: .command)
                Divider()
                Menu {
                    Button { model.flip(horizontal: true) } label: {
                        Label("水平反転", systemImage: "arrow.left.and.right")
                    }
                    Button { model.flip(horizontal: false) } label: {
                        Label("垂直反転", systemImage: "arrow.up.and.down")
                    }
                } label: {
                    Label("反転", systemImage: "arrow.left.and.right")
                }
            }

            // MARK: キャンバス
            CommandMenu("キャンバス") {
                Button { model.showCanvasSizeDialog = true } label: {
                    Label("キャンバスサイズ...", systemImage: "rectangle")
                }
                Button { model.fitCanvasToLayers() } label: {
                    Label("キャンバスを画像に合わせる", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                Button { model.clearActiveLayerTransparent() } label: {
                    Label("キャンバスを透明でクリア", systemImage: "eraser")
                }
            }

            // MARK: 選択
            CommandMenu("選択") {
                Button { model.selectAll() } label: {
                    Label("すべてを選択", systemImage: "circle.dashed")
                }
                    .keyboardShortcut("a", modifiers: .command)
                Button { model.invertSelection() } label: {
                    Label("選択を反転", systemImage: "circle.lefthalf.filled")
                }
                    .keyboardShortcut("i", modifiers: .command)
                    .disabled(model.selection == nil)
                Button { model.clearSelection() } label: {
                    Label("選択をクリア", systemImage: "xmark.circle")
                }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(model.selection == nil)
            }

            // MARK: レイヤー
            CommandMenu("レイヤー") {
                Button { model.addEmptyLayer() } label: {
                    Label("新規レイヤー", systemImage: "plus.square")
                }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button { model.addLayerFromFile() } label: {
                    Label("ファイルから読み込み...", systemImage: "photo.badge.plus")
                }
                Button { model.deleteActiveLayer() } label: {
                    Label("レイヤーを削除", systemImage: "trash")
                }
                Button { model.duplicateActiveLayer() } label: {
                    Label("レイヤーを複製", systemImage: "plus.square.on.square")
                }
                    .keyboardShortcut("j", modifiers: .command)
                Divider()
                Button { model.mergeVisibleLayers() } label: {
                    Label("レイヤーを統合", systemImage: "square.stack.3d.down.right")
                }
                    .keyboardShortcut("e", modifiers: .command)
            }

            // MARK: ウィンドウ
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button {
                    model.showLoupe.toggle()
                } label: {
                    Label(model.showLoupe ? "ルーペを隠す" : "ルーペを表示", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button {
                    model.showNavigatorPanel.toggle()
                } label: {
                    Label(model.showNavigatorPanel ? "ナビゲーターを隠す" : "ナビゲーターを表示", systemImage: "map")
                }
                Button {
                    model.showLayersPanel.toggle()
                } label: {
                    Label(model.showLayersPanel ? "レイヤーを隠す" : "レイヤーを表示", systemImage: "square.stack.3d.up")
                }
                Button {
                    model.showToolbar.toggle()
                } label: {
                    Label(model.showToolbar ? "ツールバーを隠す" : "ツールバーを表示", systemImage: "wrench.and.screwdriver")
                }
            }
        }
    }
}
