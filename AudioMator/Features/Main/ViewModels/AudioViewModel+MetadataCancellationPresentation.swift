import Foundation

extension AudioViewModel {
    /// Reports a precommit cancellation structurally, without a save-failure log
    /// entry and without implying that a started commit failed.
    func presentMetadataWriteCancellation(
        for fileName: String,
        operation: BatchMetadataOperationKind = .write
    ) {
        let reason = MetadataCancellation.message
        presentMetadataWriteHUD(
            style: .warning,
            title: String(localized: "Operation Cancelled"),
            subtitle: fileName + "\n" + reason,
            summary: fileName,
            details: reason
        )
    }
}
