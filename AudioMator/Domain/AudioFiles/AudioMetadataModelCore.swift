import Foundation

enum AudioMetadataMergeCore {
    static func mergedValue(_ values: [String], mixedPlaceholder: String = "-") -> String {
        guard let first = values.first else { return mixedPlaceholder }
        return values.allSatisfy { $0 == first } ? first : mixedPlaceholder
    }
}
