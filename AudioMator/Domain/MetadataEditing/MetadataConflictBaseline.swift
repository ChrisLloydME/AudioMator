import Foundation
import TagLibAudioMetadata

/// Exact supported values, cardinality, roles and artwork from the same read as
/// the editable fields. This is a semantic baseline, not a file-content digest.
struct MetadataConflictBaseline: Hashable, Sendable {
    let values: RawMetadataValueMap
    let structured: StructuredMetadata

    nonisolated init(_ snapshot: MetadataSnapshot) {
        values = snapshot.raw.properties.reduce(into: [:]) { result, entry in
            let key = entry.key.uppercased()
            guard !key.isEmpty else { return }
            result[key, default: []].append(contentsOf: entry.values.isEmpty ? [entry.value] : entry.values)
        }
        structured = snapshot.structured
    }
}
