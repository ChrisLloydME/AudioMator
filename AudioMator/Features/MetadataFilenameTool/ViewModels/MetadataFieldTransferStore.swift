import Combine
import Foundation

@MainActor
final class MetadataFieldTransferStore: ObservableObject {
    @Published var source: MetadataExchangeField = .artist
    @Published var destination: MetadataExchangeField = .albumArtist
    @Published var operation: MetadataFieldTransferOperation = .copy

    func makePlan(targetFiles: [AudioFile]) -> MetadataExchangeImportPlan {
        MetadataFieldTransferPlanner.makePlan(
            source: source,
            destination: destination,
            operation: operation,
            targetFiles: targetFiles
        )
    }

    func reset() {
        source = .artist
        destination = .albumArtist
        operation = .copy
    }
}
