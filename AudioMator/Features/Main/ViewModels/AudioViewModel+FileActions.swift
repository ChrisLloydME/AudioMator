import Foundation

extension AudioViewModel {
    // MARK: - Context Menu Actions (Middle List)

    func clearList() {
        guard currentFileSourceMode == .quickImport else { return }

        clearQuickImportFiles()
    }
}
