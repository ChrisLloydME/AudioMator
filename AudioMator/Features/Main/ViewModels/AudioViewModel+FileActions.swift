import Foundation

extension AudioViewModel {
    // MARK: - Context Menu Actions (Middle List)

    func openWithDefaultApp(_ file: AudioFile) {
        PlatformWorkspace.open(file.url)
    }

    func revealInFinder(_ file: AudioFile) {
        PlatformWorkspace.reveal([file.url])
    }

    func copyFilePath(_ file: AudioFile) {
        PlatformPasteboard.copy(file.url.path)
    }

    func removeFromList(_ file: AudioFile) {
        guard currentFileSourceMode == .quickImport else { return }

        removeQuickImportFile(id: file.id)
    }

    func clearList() {
        guard currentFileSourceMode == .quickImport else { return }

        clearQuickImportFiles()
    }
}
