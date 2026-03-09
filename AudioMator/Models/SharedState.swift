import Combine

final class SharedState: ObservableObject {
    @Published var selectedSidebarItem: String? = "all"
    @Published var selectedAudioIDs: Set<AudioFile.ID> = []

    // Custom ordering for the middle list (session-only)
    @Published var customOrder: [AudioFile.ID] = []

    // Drag source tracking for row reordering
    @Published var draggingAudioID: AudioFile.ID? = nil
}
