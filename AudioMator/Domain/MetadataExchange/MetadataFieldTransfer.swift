import Foundation

enum MetadataFieldTransferOperation: String, CaseIterable, Identifiable {
    case copy
    case cut

    var id: String { rawValue }

    var progressTitle: String {
        switch self {
        case .copy:
            return String(localized: "Copying Metadata")
        case .cut:
            return String(localized: "Moving Metadata")
        }
    }

    var title: String {
        switch self {
        case .copy:
            return String(localized: "Copy")
        case .cut:
            return String(localized: "Cut")
        }
    }
}

enum MetadataFieldTransferPlanner {
    static let fields = MetadataExchangeField.allCases.filter(\.isWritableMetadataField)

    static func makePlan(
        source: MetadataExchangeField,
        destination: MetadataExchangeField,
        operation: MetadataFieldTransferOperation,
        targetFiles: [AudioFile]
    ) -> MetadataExchangeImportPlan {
        guard source.isWritableMetadataField, destination.isWritableMetadataField else {
            return MetadataExchangeImportPlan(
                validationMessage: String(localized: "Choose two writable metadata fields."),
                rows: []
            )
        }
        guard source != destination else {
            return MetadataExchangeImportPlan(
                validationMessage: String(localized: "Choose a different destination field."),
                rows: []
            )
        }

        var seenIDs: Set<AudioFile.ID> = []
        let rows = targetFiles.filter { seenIDs.insert($0.id).inserted }.map { file in
            makeRow(file: file, source: source, destination: destination, operation: operation)
        }
        return MetadataExchangeImportPlan(validationMessage: nil, rows: rows)
    }

    private static func makeRow(
        file: AudioFile,
        source: MetadataExchangeField,
        destination: MetadataExchangeField,
        operation: MetadataFieldTransferOperation
    ) -> MetadataExchangeImportPreviewRow {
        let sourceValue = source.value(from: file, index: 0, relativeBasePath: nil)
        // Match the shared writer's text normalization in the preview. In
        // particular, whitespace-only sources must never erase a destination.
        let normalizedSourceValue = sourceValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationValue = destination.canonicalImportedValue(normalizedSourceValue)
        let currentDestinationValue = destination.value(from: file, index: 0, relativeBasePath: nil)

        func row(
            status: MetadataExchangePreviewStatus,
            changes: [MetadataExchangeFieldChange] = [],
            message: String? = nil,
            entry: MetadataExchangeWriteEntry? = nil
        ) -> MetadataExchangeImportPreviewRow {
            MetadataExchangeImportPreviewRow(
                id: UUID(),
                fileID: file.id,
                fileName: file.url.lastPathComponent,
                externalRecord: "\(source.displayName) → \(destination.displayName)",
                status: status,
                changes: changes,
                issueMessage: message,
                writeEntry: entry
            )
        }

        guard !normalizedSourceValue.isEmpty else {
            return row(status: .unchanged, message: String(localized: "The source field is empty. This file will be skipped."))
        }

        if let message = destination.fieldTransferValidationMessage(sourceValue) {
            return row(status: .parseError, message: message)
        }

        var changes = [MetadataExchangeFieldChange(
            field: destination,
            currentValue: currentDestinationValue,
            importedValue: destinationValue,
            willWrite: currentDestinationValue != destinationValue
        )]
        if operation == .cut {
            changes.append(MetadataExchangeFieldChange(
                field: source,
                currentValue: sourceValue,
                importedValue: "",
                willWrite: true
            ))
        }
        let values = Dictionary(uniqueKeysWithValues: changes.filter(\.willWrite).map { ($0.field, $0.importedValue) })
        guard !values.isEmpty else { return row(status: .unchanged, changes: changes) }
        var edit = SingleFileEditModel(from: file)
        for field in MetadataExchangeField.allCases {
            guard let value = values[field] else { continue }
            field.applyImportedValue(value, to: &edit, preservingNumberPairComponents: true)
        }
        if let message = writeSafetyValidationMessage(values: values, edit: edit) {
            return row(status: .parseError, changes: changes, message: message)
        }
        guard let fingerprint = file.fileFingerprint else {
            return row(
                status: .sourceUnavailable,
                changes: changes,
                message: String(localized: "The file version could not be verified. Reload the file and try again.")
            )
        }

        return row(
            status: .ready,
            changes: changes,
            entry: MetadataExchangeWriteEntry(
                fileID: file.id,
                fileName: file.url.lastPathComponent,
                values: values,
                expectedFileFingerprint: fingerprint,
                preservingNumberPairComponents: true
            )
        )
    }

    static func writeSafetyValidationMessage(
        values: [MetadataExchangeField: String],
        edit: SingleFileEditModel
    ) -> String? {
        let changesTrackPair = values[.trackNumber] != nil || values[.trackTotal] != nil
        let changesDiscPair = values[.discNumber] != nil || values[.discTotal] != nil
        // TagLib's current patch API cannot reliably round-trip a total-only
        // pair. Block it before writing rather than dropping the retained total.
        guard (changesTrackPair && edit.track == 0 && edit.trackTotal > 0) ||
              (changesDiscPair && edit.disc == 0 && edit.discTotal > 0) else { return nil }
        return String(localized: "A total without a number cannot be saved safely. Choose different fields; no changes were made.")
    }
}

extension MetadataExchangeField {
    func fieldTransferValidationMessage(_ value: String) -> String? {
        // Number and total are independent fields here, unlike text/CSV pair imports.
        if self == .trackNumber || self == .discNumber {
            if MetadataExchangeField.trackTotal.importedValueValidationMessage(value) != nil {
                return String(localized: "The destination number field requires a single integer from 0 through 2147483647.")
            }
        }
        return importedValueValidationMessage(value)
    }
}
