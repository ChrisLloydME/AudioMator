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
        let destinationValue = destination.canonicalImportedValue(sourceValue)
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

        guard !sourceValue.isEmpty else {
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
