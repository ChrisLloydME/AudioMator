import Foundation
import SwiftUI

enum L10n {
    nonisolated static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

enum AppWindowTitle {
    static let onlineMetadataKey: LocalizedStringKey = "Online Metadata"
    static let filenameMetadataKey: LocalizedStringKey = "Filename & Metadata"
    static let metadataEditorKey: LocalizedStringKey = "Metadata Editor"

    nonisolated static var onlineMetadata: String { L10n.string("Online Metadata") }
    nonisolated static var filenameMetadata: String { L10n.string("Filename & Metadata") }
    nonisolated static var metadataEditor: String { L10n.string("Metadata Editor") }
    nonisolated static var rawMetadata: String { L10n.string("Raw Metadata") }
    nonisolated static var renumberTracks: String { L10n.string("Renumber Tracks") }
    nonisolated static var settings: String { L10n.string("Settings") }
}

extension String {
    nonisolated var localizedUI: String {
        L10n.string(self)
    }
}
