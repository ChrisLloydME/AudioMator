import Foundation
import TagLibAudioMetadata

extension MetadataDateText {
    /// Validates an explicitly edited value against its own semantic identity.
    /// It never compares YEAR with DATE or RELEASEDATE.
    nonisolated static func validates(_ value: String, for field: MetadataFieldKey) -> Bool {
        switch field {
        case .year, .date: return isPlausibleYear(value)
        case .standaloneDate: return isPlausibleStandaloneDate(value)
        case .releaseDate, .originalReleaseDate: return isPlausibleDate(value)
        default: return true
        }
    }
}
