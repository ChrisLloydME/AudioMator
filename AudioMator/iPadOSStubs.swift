#if !os(macOS)
import SwiftUI
import Combine

@MainActor
final class MetadataFilenameToolStore: ObservableObject {
    @Published private(set) var targetFileIDs: [AudioFile.ID] = []

    func present(targetFileIDs: [AudioFile.ID]) {
        self.targetFileIDs = targetFileIDs
    }
}

@MainActor
final class MetadataEditorStore: ObservableObject {
    func present(targetFiles: [AudioFile]) {
        _ = targetFiles
    }
}
#endif
