import Foundation
import TagLibAudioMetadata

/// Exact supported values, cardinality, roles and artwork from the same read as
/// the editable fields. The optional package token also guards audio continuity.
struct MetadataConflictBaseline: Hashable, Sendable {
    let values: RawMetadataValueMap
    let yearText: String
    let structured: StructuredMetadata
    let audioContentIdentity: MetadataAudioContentIdentity?

    nonisolated init(_ snapshot: MetadataSnapshot) {
        yearText = snapshot.basic.year
        values = snapshot.raw.properties.reduce(into: [:]) { result, entry in
            let key = entry.key.uppercased()
            guard !key.isEmpty else { return }
            result[key, default: []].append(contentsOf: entry.values.isEmpty ? [entry.value] : entry.values)
        }
        structured = snapshot.structured
        audioContentIdentity = snapshot.audioContentIdentity
    }
}
