import Foundation
import TagLibAudioMetadata

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
        targetFiles: [AudioFile],
        projector: (any AudioMetadataPipeline)? = nil
    ) -> MetadataExchangeImportPlan {
        guard source.isWritableMetadataField, destination.isWritableMetadataField else {
            return MetadataExchangeImportPlan(
                validationMessage: String(localized: "Choose an editable source field and an editable destination field."),
                rows: []
            )
        }
        guard source != destination else {
            return MetadataExchangeImportPlan(
                validationMessage: String(localized: "Choose a destination field different from the source field."),
                rows: []
            )
        }

        var seenIDs: Set<AudioFile.ID> = []
        let rows = targetFiles.filter { seenIDs.insert($0.id).inserted }.map { file in
            makeRow(
                file: file,
                source: source,
                destination: destination,
                operation: operation,
                projector: projector
            )
        }
        return MetadataExchangeImportPlan(validationMessage: nil, rows: rows)
    }

    private static func makeRow(
        file: AudioFile,
        source: MetadataExchangeField,
        destination: MetadataExchangeField,
        operation: MetadataFieldTransferOperation,
        projector: (any AudioMetadataPipeline)?
    ) -> MetadataExchangeImportPreviewRow {
        let sourceValue = source.value(from: file, index: 0, relativeBasePath: nil)
        // Match the shared writer's text normalization in the preview. In
        // particular, whitespace-only sources must never erase a destination.
        let normalizedSourceValue = sourceValue.trimmingCharacters(in: .whitespacesAndNewlines)
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

        if file.hasUnverifiedIndependentDateProjection,
           source.isIndependentDateField || destination.isIndependentDateField {
            return row(status: .parseError, message: String(localized: "These separate date fields couldn’t be verified in ID3v2.3 tags. Choose other fields to transfer."))
        }

        guard !normalizedSourceValue.isEmpty else {
            return row(status: .unchanged, message: String(localized: "The source field is empty. This file will be skipped without changes."))
        }

        // Resolve the destination as an independent field. Numeric destinations
        // receive one positive component: a transfer carries a value and can
        // never silently convert a copied text `0` into a deletion.
        var operations: [ExchangeResolvedOperation] = []
        let destinationDisplayValue: String
        let maximum = AudioFormatNumberBounds.componentMaximum(forFileExtension: file.url.pathExtension)

        if destination.isNumberField {
            switch MetadataExchangeNumberSpelling.parseComponent(normalizedSourceValue, maximum: maximum) {
            case .failure(let error):
                let message = error == .overflowsDeclaredMaximum
                    ? String(localized: "This destination field accepts one whole number from 1 to \(maximum). It can't accept a larger value or a number/total pair.")
                    : String(localized: "This destination field accepts one whole number from 1 to \(maximum). It can't accept a number/total pair.")
                return row(status: .parseError, message: message)
            case .success(.removal):
                return row(
                    status: .parseError,
                    message: String(localized: "This destination field accepts one whole number from 1 to \(maximum). Copying a zero would delete the destination instead of assigning a value.")
                )
            case .success(.value(let text, let value)):
                destinationDisplayValue = text
                operations.append(.setNumber(destination, value: value, literalText: text))
            }
        } else {
            let canonical = destination.canonicalImportedValue(normalizedSourceValue)
            if destination == .contentAdvisory, ContentAdvisory.fromMetadataText(canonical) == nil {
                return row(
                    status: .parseError,
                    message: String(localized: "For Content Advisory, enter a supported advisory label or a whole-number code from 0 to 255.")
                )
            }
            if let validationMessage = destination.importedValueValidationMessage(canonical) {
                return row(status: .parseError, message: validationMessage)
            }
            destinationDisplayValue = canonical
            operations.append(.setText(destination, text: canonical))
        }

        if operation == .cut {
            if source.isNumberField {
                operations.append(.removeNumber(source))
            } else {
                operations.append(.removeText(source))
            }
        }

        let intent = ExchangeResolvedIntent(
            operations: operations,
            locators: [:],
            isLocatorMode: false
        )
        let outcome = ExchangeWriteTranslator.makeFrozenWrite(
            from: file,
            intent: intent,
            projector: projector
        )

        switch outcome {
        case .unavailable(let message):
            return row(status: .sourceUnavailable, message: message)
        case .rejected(let message):
            return row(status: .parseError, message: message)
        case .unchanged:
            return row(
                status: .unchanged,
                changes: displayChanges(
                    intent: intent,
                    file: file,
                    effectiveFields: [],
                    destinationDisplayValue: destinationDisplayValue
                ),
                message: String(localized: "The destination already has this value. This file will be skipped without changes.")
            )
        case .executable(let frozen):
            var values: [MetadataExchangeField: String] = [destination: destinationDisplayValue]
            if operation == .cut { values[source] = "" }
            let entry = MetadataExchangeWriteEntry(
                fileID: file.id,
                fileName: file.url.lastPathComponent,
                values: values,
                expectedFileFingerprint: file.fileFingerprint,
                preservingNumberPairComponents: true,
                resolvedIntent: intent,
                frozenPayload: frozen.payload,
                frozenProjection: frozen.projection,
                frozenTarget: frozen.target
            )
            return row(
                status: .ready,
                changes: displayChanges(
                    intent: intent,
                    file: file,
                    effectiveFields: frozen.payload.requestedFields,
                    destinationDisplayValue: destinationDisplayValue
                ),
                entry: entry
            )
        }
    }

    private static func displayChanges(
        intent: ExchangeResolvedIntent,
        file: AudioFile,
        effectiveFields: Set<MetadataFieldKey>,
        destinationDisplayValue: String
    ) -> [MetadataExchangeFieldChange] {
        var changesByField: [MetadataExchangeField: MetadataExchangeFieldChange] = [:]
        for operation in intent.operations {
            switch operation {
            case .setText(let field, _):
                let importedValue = field == .contentAdvisory
                    ? destinationDisplayValue
                    : destinationDisplayValue
                changesByField[field] = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: importedValue,
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title)
                )
            case .removeText(let field):
                changesByField[field] = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: "",
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title),
                    isExplicitRemoval: true
                )
            case .setNumber(let field, _, let literalText):
                changesByField[field] = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: literalText,
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title)
                )
            case .removeNumber(let field):
                changesByField[field] = MetadataExchangeFieldChange(
                    field: field,
                    currentValue: field.value(from: file, index: 0, relativeBasePath: nil),
                    importedValue: "",
                    willWrite: effectiveFields.contains(field.semanticFieldKey ?? .title),
                    isExplicitRemoval: true
                )
            }
        }
        return MetadataExchangeField.allCases.compactMap { changesByField[$0] }
    }
}

extension MetadataExchangeField {
    func fieldTransferValidationMessage(_ value: String) -> String? {
        // Number and total are independent fields here, unlike text/CSV pair imports.
        if self == .trackNumber || self == .discNumber {
            if MetadataExchangeField.trackTotal.importedValueValidationMessage(value) != nil {
                return String(localized: "This destination field accepts one whole number from 0 to 2147483647. It can't accept a number/total pair.")
            }
        }
        return importedValueValidationMessage(value)
    }
}
