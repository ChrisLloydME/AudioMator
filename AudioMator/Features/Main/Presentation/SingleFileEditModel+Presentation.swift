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
