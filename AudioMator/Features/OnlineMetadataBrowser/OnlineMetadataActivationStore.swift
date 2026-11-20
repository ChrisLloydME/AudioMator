import Foundation
import Combine

/// Consume-once handoff from a main-window command to the singleton Online Metadata
/// window. Publishing replaces any older unconsumed intent; taking clears it atomically
/// on the main actor so presentation, onAppear and source selection cannot both act on
/// the same request.
@MainActor
final class OnlineMetadataActivationStore: ObservableObject {
    enum Action {
        case showProviderPicker
        case findInMusicBrainz(MusicBrainzSearchSeed)
    }

    struct Intent: Identifiable {
        let id: UUID
        let action: Action
    }

    @Published private(set) var pendingIntentID: UUID?
    private var pendingIntent: Intent?

    @discardableResult
    func publish(_ action: Action) -> UUID {
        let intent = Intent(id: UUID(), action: action)
        pendingIntent = intent
        pendingIntentID = intent.id
        return intent.id
    }

    func takePendingIntent() -> Intent? {
        guard let intent = pendingIntent else { return nil }
        pendingIntent = nil
        pendingIntentID = nil
        return intent
    }
}
