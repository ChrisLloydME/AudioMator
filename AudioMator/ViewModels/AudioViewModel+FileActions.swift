import AppKit

extension AudioViewModel {
    // MARK: - 右键菜单动作（中间列表）

    func openWithDefaultApp(_ file: AudioFile) {
        NSWorkspace.shared.open(file.url)
    }

    func revealInFinder(_ file: AudioFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func copyFilePath(_ file: AudioFile) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.url.path, forType: .string)
    }

    func removeFromList(_ file: AudioFile) {
        files.removeAll { $0.id == file.id }
        selectedAudioIDs.remove(file.id)
        if selectedAudioIDs.isEmpty {
            edit = nil
        }
    }
}
