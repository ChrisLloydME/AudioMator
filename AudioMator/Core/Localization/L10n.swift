import Foundation

enum L10n {
    nonisolated static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

extension String {
    nonisolated var localizedUI: String {
        L10n.string(self)
    }
}
