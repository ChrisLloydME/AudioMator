import Foundation

extension AudioViewModel {
    func refreshInspectorArtworkPreview() {
        inspectorArtworkPreview.update(inspectorArtworkSource)
    }

    private var inspectorArtworkSource: InspectorArtworkSource? {
        let action: ArtworkEditAction
        let originalData: Data?
        let originalID: UUID?
        if selectedAudioIDs.count == 1 {
            guard let id = selectedAudioIDs.first, let file = inspectorEditSourceFilesByID[id] else { return nil }
            action = edit?.artworkEditAction ?? .unchanged
            originalData = file.artworkData
            originalID = file.snapshotID
        } else {
            guard !selectedAudioIDs.isEmpty, let multiEdit else { return nil }
            action = multiEdit.artworkEditAction
            if case .shared(let data) = multiEdit.initialArtworkState {
                originalData = data
                originalID = inspectorEditSourceFilesByID.values.first?.snapshotID
            } else {
                originalData = nil
                originalID = nil
            }
        }

        switch action {
        case .unchanged:
            guard let data = originalData, let id = originalID else { return nil }
            return InspectorArtworkSource(id: id, data: data)
        case .replace(let artwork):
            return InspectorArtworkSource(id: artwork.id, data: artwork.data)
        case .remove:
            return nil
        }
    }
}
