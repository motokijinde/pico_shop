import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - .pic プロジェクトファイル（ZIP + manifest.json）

enum ProjectIO {

    // MARK: manifest.json（仕様 v6：JSON 形式、Codable）

    struct Manifest: Codable {
        var version: String = "1.0"
        var canvas: Canvas
        var layers: [LayerEntry]

        struct Canvas: Codable {
            var width: Int
            var height: Int
        }

        struct LayerEntry: Codable {
            var id: Int
            var name: String
            var blend: String
            var opacity: Double
            var offsetX: Int
            var offsetY: Int
            var visible: Bool
            var locked: Bool
            var src: String
        }
    }

    enum IOError: Error, LocalizedError {
        case zipFailed
        case invalidProject
        case pngEncodeFailed

        var errorDescription: String? {
            switch self {
            case .zipFailed: return "ZIP アーカイブの処理に失敗しました"
            case .invalidProject: return "プロジェクトファイルが不正です"
            case .pngEncodeFailed: return "PNG エンコードに失敗しました"
            }
        }
    }

    // MARK: 保存

    static func save(layers: [Layer], canvasWidth: Int, canvasHeight: Int, to url: URL) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("PicoShop-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: workDir) }

        let layersDir = workDir.appendingPathComponent("layers")
        try fm.createDirectory(at: layersDir, withIntermediateDirectories: true)

        var entries: [Manifest.LayerEntry] = []
        for (i, layer) in layers.enumerated() {
            let fileName = "layer\(i + 1).png"
            guard let cg = layer.buffer.makeCGImage() else { throw IOError.pngEncodeFailed }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw IOError.pngEncodeFailed
            }
            try data.write(to: layersDir.appendingPathComponent(fileName))
            entries.append(Manifest.LayerEntry(
                id: i + 1, name: layer.name, blend: layer.blend.rawValue,
                opacity: layer.opacity, offsetX: layer.offsetX, offsetY: layer.offsetY,
                visible: layer.visible, locked: layer.locked,
                src: "layers/\(fileName)"
            ))
        }

        let manifest = Manifest(
            canvas: Manifest.Canvas(width: canvasWidth, height: canvasHeight),
            layers: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: workDir.appendingPathComponent("manifest.json"))

        // ditto で ZIP 化（macOS 標準。ユーザーが手動解凍できる素の ZIP になる）
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try runDitto(["-c", "-k", "--sequesterRsrc", workDir.path, url.path])
    }

    // MARK: 読み込み

    static func load(from url: URL) throws -> (layers: [Layer], canvasWidth: Int, canvasHeight: Int) {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("PicoShop-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: workDir) }
        try runDitto(["-x", "-k", url.path, workDir.path])

        // manifest.json はルートまたは 1 階層下にある可能性がある
        var root = workDir
        if !fm.fileExists(atPath: root.appendingPathComponent("manifest.json").path) {
            let children = (try? fm.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)) ?? []
            if let sub = children.first(where: {
                fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
            }) {
                root = sub
            } else {
                throw IOError.invalidProject
            }
        }

        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        var layers: [Layer] = []
        for entry in manifest.layers {
            let imgURL = root.appendingPathComponent(entry.src)
            guard let img = NSImage(contentsOf: imgURL),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let buf = PixelBuffer(cgImage: cg) else { throw IOError.invalidProject }
            var layer = Layer(name: entry.name, buffer: buf,
                              offsetX: entry.offsetX, offsetY: entry.offsetY)
            layer.blend = LayerBlendMode(rawValue: entry.blend) ?? .normal
            layer.opacity = entry.opacity
            layer.visible = entry.visible
            layer.locked = entry.locked
            layers.append(layer)
        }
        return (layers, manifest.canvas.width, manifest.canvas.height)
    }

    private static func runDitto(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw IOError.zipFailed }
    }
}

// MARK: - エクスポート（PNG / JPEG / TIFF）

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"
    case tiff = "TIFF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }
}

enum ExportSizeMode: String, CaseIterable, Identifiable {
    case canvas
    case allLayers

    var id: String { rawValue }
    var displayName: String { self == .canvas ? "キャンバスサイズで出力" : "レイヤー全体で出力" }
}

enum Exporter {

    static func export(layers: [Layer], canvasWidth: Int, canvasHeight: Int,
                       format: ExportFormat, sizeMode: ExportSizeMode,
                       jpegQuality: Double, to url: URL) throws {
        let bounds: CGRect
        switch sizeMode {
        case .canvas:
            bounds = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        case .allLayers:
            bounds = Compositor.unionBounds(layers: layers, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        }
        guard let cg = Compositor.composite(layers: layers, bounds: bounds) else {
            throw ProjectIO.IOError.pngEncodeFailed
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let data: Data?
        switch format {
        case .png:
            data = rep.representation(using: .png, properties: [:])
        case .jpeg:
            data = rep.representation(using: .jpeg,
                                      properties: [.compressionFactor: jpegQuality / 100])
        case .tiff:
            data = rep.representation(using: .tiff,
                                      properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])
        }
        guard let data else { throw ProjectIO.IOError.pngEncodeFailed }
        try data.write(to: url)
    }
}
