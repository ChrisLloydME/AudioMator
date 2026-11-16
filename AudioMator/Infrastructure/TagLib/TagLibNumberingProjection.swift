import Foundation
import TagLibAudioMetadata

/// Internal compatibility projection. Reading never migrates or rewrites a file.
/// The package has already validated and classified historical candidates.
nonisolated enum TagLibNumberingProjection {
    struct Pair {
        let number: Int
        let total: Int
        let text: String
    }

    static func pair(number: Int, total: Int, text: String,
                     inventory: MetadataNumberGroupInventory?) -> Pair {
        guard let inventory else { return Pair(number: number, total: total, text: text) }
        func resolved(_ component: MetadataNumberComponentInventory, fallback: Int) -> Int {
            // A canonical value is authoritative even when provenance disagrees.
            if let native = component.nativeValue { return native }
            switch component.state {
            case .recoveredLegacy: return component.recoveredValue ?? fallback
            case .ambiguous: return 0 // Never display a guessed first candidate.
            default: return fallback // Retain malformed text for inspection/correction.
            }
        }
        let projectedNumber = resolved(inventory.number, fallback: number)
        let projectedTotal = resolved(inventory.total, fallback: total)
        let ambiguous = (inventory.number.state == .ambiguous && inventory.number.nativeValue == nil)
            || (inventory.total.state == .ambiguous && inventory.total.nativeValue == nil)
        if projectedNumber == number, projectedTotal == total, !ambiguous {
            return Pair(number: number, total: total, text: text)
        }
        let numberText = projectedNumber > 0 ? String(projectedNumber) : ""
        let totalText = projectedTotal > 0 ? "/\(projectedTotal)" : ""
        return Pair(number: projectedNumber, total: projectedTotal, text: numberText + totalText)
    }
}
