import Foundation
import AppKit
import UniformTypeIdentifiers

extension AudioViewModel {
    // MARK: - 文件导入

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.mp3,
            UTType.mpeg4Audio,
            UTType.wav,
            UTType.aiff,
        ]
        panel.title = "选择音频文件"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls

        Task {
            var loaded: [AudioFile] = []
            for url in urls {
                if let file = try? await AudioFile(url: url) {
                    loaded.append(file)
                }
            }

            await MainActor.run {
                self.files.append(contentsOf: loaded)
            }
        }
    }
}
