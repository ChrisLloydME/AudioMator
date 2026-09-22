import AppKit
import Foundation

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
        }
    }

    static var inspectorSelectionOrder: [ExplicitInspectorSelection] {
        [.unset] + ContentAdvisory.inspectorSelectionOrder.map(ExplicitInspectorSelection.advisory)
    }
}

extension MultiFileEditableTextField {
    var displayName: String {
        switch self {
        case .title: L10n.string("Title")
        case .artist: L10n.string("Artist")
        case .album: L10n.string("Album")
        case .composer: L10n.string("Composer")
        case .genre: L10n.string("Genre")
        case .year: L10n.string("Year")
        case .trackNumber: L10n.string("Track Number")
        case .trackTotal: L10n.string("Total Tracks")
        case .discNumber: L10n.string("Disc Number")
        case .discTotal: L10n.string("Total Discs")
        case .comment: L10n.string("Comment")
        case .albumArtist: L10n.string("Album Artist")
        case .releaseDate: L10n.string("Release Date")
        case .publisher: L10n.string("Publisher")
        case .copyright: L10n.string("Copyright")
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

    var displayedArtwork: NSImage? {
        let data: Data?
        switch artworkEditAction {
        case .unchanged:
            if case .shared(let sharedData) = initialArtworkState {
                data = sharedData
            } else {
                data = nil
            }
        case .replace(let artwork):
            data = artwork.data
        case .remove:
            data = nil
        }
        return data.flatMap(NSImage.init(data:))
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
