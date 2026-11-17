import Foundation
import TagLibAudioMetadata

extension ContentAdvisory {
    nonisolated var displayName: String {
        switch self {
        case .notExplicit: L10n.string("Not Explicit")
        case .explicit: L10n.string("Explicit")
        case .clean: L10n.string("Clean")
        }
    }

    nonisolated var currentValueDescription: String {
        switch self {
        case .notExplicit: L10n.string("Current value: Not Explicit")
        case .explicit: L10n.string("Current value: Explicit")
        case .clean: L10n.string("Current value: Clean")
        }
    }

    nonisolated static var inspectorSelectionOrder: [ContentAdvisory] { [.explicit, .clean, .notExplicit] }

    nonisolated static func fromDisplayName(_ value: String) -> ContentAdvisory? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        } ?? fromMetadataText(value)
    }
}

extension ExplicitInspectorSelection {
    var displayName: String {
        switch self {
        case .unset: L10n.string("Unset")
        case .advisory(let advisory): advisory.displayName
        case .unknown(let rawValue):
            String(localized: "Unknown") + " (\(rawValue))"
        }
    }

    static var inspectorSelectionOrder: [ExplicitInspectorSelection] {
        [.unset] + ContentAdvisory.inspectorSelectionOrder.map(ExplicitInspectorSelection.advisory)
    }
}

extension MultiFileEditableTextField {
    var displayName: String {
        switch self {
        case .title: MetadataFieldGuide.displayName(for: .title)
        case .artist: MetadataFieldGuide.displayName(for: .artist)
        case .album: MetadataFieldGuide.displayName(for: .album)
        case .composer: MetadataFieldGuide.displayName(for: .composer)
        case .genre: MetadataFieldGuide.displayName(for: .genre)
        case .year: MetadataFieldGuide.displayName(for: .year)
        case .date: MetadataFieldGuide.displayName(for: .standaloneDate)
        case .originalReleaseDate: MetadataFieldGuide.displayName(for: .originalReleaseDate)
        case .contentGroup: MetadataFieldGuide.displayName(for: .contentGroup)
        case .grouping: MetadataFieldGuide.displayName(for: .grouping)
        case .work: MetadataFieldGuide.displayName(for: .work)
        case .trackNumber: MetadataFieldGuide.displayName(for: .track)
        case .trackTotal: MetadataFieldGuide.displayName(for: .trackTotal)
        case .discNumber: MetadataFieldGuide.displayName(for: .disc)
        case .discTotal: MetadataFieldGuide.displayName(for: .discTotal)
        case .comment: MetadataFieldGuide.displayName(for: .comment)
        case .albumArtist: MetadataFieldGuide.displayName(for: .albumArtist)
        case .releaseDate: MetadataFieldGuide.displayName(for: .releaseDate)
        case .publisher: MetadataFieldGuide.displayName(for: .publisher)
        case .copyright: MetadataFieldGuide.displayName(for: .copyright)
        }
    }
}

extension MultiFileExplicitEditState {
    var displayName: String {
        switch self {
        case .keepExisting: L10n.string("Keep Existing")
        case .set(.none): L10n.string("Unset")
        case .set(.some(let advisory)): advisory.displayName
        }
    }
}

extension MultiFileEditModel {
    func placeholder(for field: MultiFileEditableTextField) -> String? {
        guard mixedTextFields.contains(field), !modifiedTextFields.contains(field) else { return nil }
        return L10n.string("Multiple Values")
    }

    var explicitCurrentValueDescription: String {
        switch initialContentAdvisory {
        case .some(.some(let advisory)): advisory.currentValueDescription
        case .some(.none): L10n.string("Current value: Unset")
        case .none: L10n.string("Current values differ")
        }
    }

    var artworkSummary: String {
        switch artworkEditAction {
        case .unchanged:
            switch initialArtworkState {
            case .none: L10n.string("No artwork in the current selection")
            case .shared: L10n.string("Shared artwork across selected files")
            case .mixed: L10n.string("Artwork differs across selected files")
            }
        case .replace: L10n.string("This artwork will be applied to all selected files")
        case .remove: L10n.string("Artwork will be removed from all selected files")
        }
    }

    var artworkPlaceholderSymbolName: String {
        switch artworkEditAction {
        case .unchanged:
            switch initialArtworkState {
            case .none: "photo.badge.exclamationmark"
            case .shared: "photo"
            case .mixed: "photo.on.rectangle.angled"
            }
        case .replace: "photo"
        case .remove: "trash"
        }
    }
}
