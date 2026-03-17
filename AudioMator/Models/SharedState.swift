import Combine
import Foundation

final class SharedState: ObservableObject {
    @Published var selectedSidebarItem: SidebarSelection? = .quickImport
    @Published var selectedAudioIDs: Set<AudioFile.ID> = []

    // Custom ordering for the middle list (session-only)
    @Published var customOrder: [AudioFile.ID] = []

    // Drag source tracking for row reordering
    @Published var draggingAudioID: AudioFile.ID? = nil

    var currentFileSourceMode: FileSourceMode {
        (selectedSidebarItem ?? .quickImport).sourceMode
    }
}
