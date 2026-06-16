import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ファイルメニュー操作（開く / 保存 / エクスポート）

extension AppModel {

    static let picType = UTType(filenameExtension: "pic") ?? .zip

    // MARK: 開く

    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, AppModel.picType]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let picURLs = panel.urls.filter { $0.pathExtension.lowercased() == "pic" }
        let imageURLs = panel.urls.filter { $0.pathExtension.lowercased() != "pic" }
        if let pic = picURLs.first {
            openProject(url: pic)
        }
        if !imageURLs.isEmpty {
            openImageFiles(imageURLs)
        }
    }

    func openProject(url: URL) {
        if tool == .move, floatingLayer != nil {
            commitMoveTransform { [weak self] in
                self?.openProject(url: url)
            }
            return
        }
        do {
            let (loadedLayers, w, h) = try ProjectIO.load(from: url)
            guard !loadedLayers.isEmpty else {
                warn("プロジェクトにレイヤーがありません")
                return
            }
            pushUndo("プロジェクトを開く")
            layers = loadedLayers
            canvasWidth = w
            canvasHeight = h
            selection = nil
            pendingTransform = SelectionTransform()
            floatingLayer = nil
            moveLayerID = nil
            moveStartedWithSelection = false
            originalMoveBuffer = nil
            originalMoveBounds = nil
            activeLayerID = loadedLayers.first?.id
            projectURL = url
            recomposite()
            fitToView()
        } catch {
            warn("プロジェクトを開けません: \(error.localizedDescription)")
        }
    }

    // MARK: 保存（.pic）

    func saveProject(forceDialog: Bool = false) {
        var url = projectURL
        if url == nil || forceDialog {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [AppModel.picType]
            panel.nameFieldStringValue = projectURL?.lastPathComponent ?? "project.pic"
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            url = chosen
        }
        guard let url else { return }
        commitMoveTransformIfNeeded { [weak self] in
            self?.saveProject(to: url)
        }
    }

    private func saveProject(to url: URL) {
        do {
            try ProjectIO.save(layers: layers, canvasWidth: canvasWidth, canvasHeight: canvasHeight, to: url)
            projectURL = url
            warn("保存しました: \(url.lastPathComponent)")
        } catch {
            warn("保存に失敗: \(error.localizedDescription)")
        }
    }

    // MARK: エクスポート

    func exportImage(format: ExportFormat, sizeMode: ExportSizeMode, jpegQuality: Double, fileName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(fileName).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        commitMoveTransformIfNeeded { [weak self] in
            self?.exportImage(format: format, sizeMode: sizeMode, jpegQuality: jpegQuality, to: url)
        }
    }

    private func exportImage(format: ExportFormat, sizeMode: ExportSizeMode, jpegQuality: Double, to url: URL) {
        do {
            try Exporter.export(layers: layers, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                                format: format, sizeMode: sizeMode, jpegQuality: jpegQuality, to: url)
            warn("エクスポートしました: \(url.lastPathComponent)")
        } catch {
            warn("エクスポートに失敗: \(error.localizedDescription)")
        }
    }
}
