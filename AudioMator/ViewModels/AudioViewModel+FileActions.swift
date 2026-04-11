#if os(macOS)
import AppKit
#else
internal import UIKit
#endif

extension AudioViewModel {
    // MARK: - Context Menu Actions (Middle List)

    func openWithDefaultApp(_ file: AudioFile) {
        #if os(macOS)
        NSWorkspace.shared.open(file.url)
        #else
        UIApplication.shared.open(file.url)
        #endif
    }

    func revealInFinder(_ file: AudioFile) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
        #else
        UIApplication.shared.open(file.url)
        #endif
    }

    func copyFilePath(_ file: AudioFile) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.url.path, forType: .string)
        #else
        UIPasteboard.general.string = file.url.path
        #endif
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
