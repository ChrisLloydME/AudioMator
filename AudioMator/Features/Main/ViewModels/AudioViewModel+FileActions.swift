import Foundation

extension AudioViewModel {
    // MARK: - Context Menu Actions (Middle List)

    func removeFromList(_ file: AudioFile) {
        guard currentFileSourceMode == .quickImport else { return }

        removeQuickImportFile(id: file.id)
    }

    func clearList() {
        guard currentFileSourceMode == .quickImport else { return }

        clearQuickImportFiles()
    }
}
