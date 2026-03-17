import AppKit

extension AudioViewModel {
    // MARK: - Context Menu Actions (Middle List)

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
        guard currentFileSourceMode == .quickImport else { return }

        removeQuickImportFile(id: file.id)
        selectedAudioIDs.remove(file.id)
        if selectedAudioIDs.isEmpty {
            edit = nil
            multiEdit = nil
        }
    }

    func clearList() {
        guard currentFileSourceMode == .quickImport else { return }

        clearQuickImportFiles()
        selectedAudioIDs.removeAll()
        edit = nil
        multiEdit = nil
    }
}
