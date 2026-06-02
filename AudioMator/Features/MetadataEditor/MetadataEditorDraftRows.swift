import Foundation

struct MetadataEditorRow: Identifiable, Hashable {
    let key: String
    let value: String
    let isMixed: Bool

    var id: String { key }

    var displayValue: String {
        isMixed ? "Multiple Values" : value
    }
}

enum MetadataEditorDraftRows {
    static func makeRows(
        targets: [MetadataEditorTarget],
        draftPropertyMaps: [AudioFile.ID: [String: String]]
    ) -> [MetadataEditorRow] {
        let allKeys = Set(draftPropertyMaps.values.flatMap(\.keys))

        return allKeys
            .map { key in
                let values = targets.compactMap { draftPropertyMaps[$0.id]?[key] }
                let firstValue = values.first ?? ""
                let isUniform = values.count == targets.count && values.dropFirst().allSatisfy { $0 == firstValue }

                return MetadataEditorRow(
                    key: key,
                    value: firstValue,
                    isMixed: !isUniform
                )
            }
            .sorted { lhs, rhs in
                lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
    }

    static func realignedSelection(
        currentSelection: Set<String>,
        preferred: String?,
        rows: [MetadataEditorRow]
    ) -> Set<String> {
        let validKeys = Set(rows.map(\.key))
        let validSelection = currentSelection.intersection(validKeys)

        if !validSelection.isEmpty {
            return validSelection
        }

        if let preferred, validKeys.contains(preferred) {
            return [preferred]
        }

        if let firstKey = rows.first?.key {
            return [firstKey]
        }

        return []
    }
}
