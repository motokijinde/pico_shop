import SwiftUI
import AppKit

extension AppModel {

    /// CLI からの起動用：PICOSHOP_OPEN（コロン区切りパス）で渡されたファイルを起動時に開く。
    /// argv にパスを渡すと AppKit がファイルオープンイベントとして解釈し
    /// WindowGroup のウィンドウ生成が抑制されるため、環境変数を使う。
    func openCommandLineFiles() {
        guard let env = ProcessInfo.processInfo.environment["PICOSHOP_OPEN"] else { return }
        let urls = env.split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        if let pic = urls.first(where: { $0.pathExtension.lowercased() == "pic" }) {
            openProject(url: pic)
        } else {
            let images = urls.filter { $0.pathExtension.lowercased() != "pic" }
            openImageFiles(images)
        }
    }
}
