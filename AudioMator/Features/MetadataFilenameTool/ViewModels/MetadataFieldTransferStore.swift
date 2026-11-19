import Combine
import Foundation

@MainActor
final class MetadataFieldTransferStore: ObservableObject {
    @Published var source: MetadataExchangeField = .artist
    @Published var destination: MetadataExchangeField = .albumArtist
    @Published var operation: MetadataFieldTransferOperation = .copy

    func reset() {
        source = .artist
        destination = .albumArtist
        operation = .copy
    }
}
