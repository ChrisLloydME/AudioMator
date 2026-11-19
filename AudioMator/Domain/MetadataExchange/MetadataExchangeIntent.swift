import Foundation
import TagLibAudioMetadata

// MARK: – Typed captures

/// One lexical capture for a named exchange field.
///
/// Absence is represented by “no capture”. The private string sentinel is not
/// used: a literal formerly equal to it can never be interpreted as a removal.
nonisolated enum ExchangeCapture: Equatable, Sendable {
    /// Ordinary lexical text. Edge trimming for semantic fields happens when the
    /// resolved intent is built, matching the production adapter.
    case literal(String)
    /// Captured, but semantically empty for a writable field.
    case blank
    /// Profile-v2 unescaped (text) or unquoted (CSV) removal token.
    case explicitRemoval
    /// Locator identity text. Never produces a write operation.
    case locator(String)
}

nonisolated struct ExchangeCapturedRecord: Sendable, Equatable {
    let sourceIndex: Int
    let displayText: String
    let captures: [MetadataExchangeField: ExchangeCapture]
    var warning: String?
}

// MARK: – Resolved operations

/// One typed keep/set/remove operation for the planner intent.
///
/// “Keep” is implied by omission. Number operations are per semantic component:
/// clearing Track Number never touches Total Tracks and vice versa.
nonisolated enum ExchangeResolvedOperation: Equatable, Sendable {
    case setText(MetadataExchangeField, text: String)
    case removeText(MetadataExchangeField)
    case setNumber(MetadataExchangeField, value: Int, literalText: String)
    case removeNumber(MetadataExchangeField)
}

nonisolated struct ExchangeResolvedIntent: Sendable, Equatable {
    let operations: [ExchangeResolvedOperation]
    let locators: [MetadataExchangeField: String]
    let isLocatorMode: Bool
}

nonisolated struct ExchangeIntentRejection: Error, Equatable, Sendable {
    let message: String
}

// MARK: – Field mapping

extension MetadataExchangeField {
    /// The package semantic identity this exchange field edits.
    nonisolated var semanticFieldKey: MetadataFieldKey? {
        switch self {
        case .title: .title
        case .artist: .artist
        case .album: .album
        case .albumArtist: .albumArtist
        case .composer: .composer
        case .lyricist: .lyricist
        case .producer: .producer
        case .engineer: .engineer
        case .remixer: .remixer
        case .genre: .genre
        case .year: .year
        case .date: .standaloneDate
        case .originalReleaseDate: .originalReleaseDate
        case .trackNumber: .track
        case .trackTotal: .trackTotal
        case .discNumber: .disc
        case .discTotal: .discTotal
        case .comment: .comment
        case .releaseDate: .releaseDate
        case .publisher: .publisher
        case .copyright: .copyright
        case .isrc: .isrc
        case .barcode: .barcode
        case .language: .language
        case .mediaType: .mediaType
        case .releaseType: .releaseType
        case .catalogNumber: .catalogNumber
        case .releaseCountry: .releaseCountry
        case .itunesAlbumID: .itunesAlbumID
        case .itunesArtistID: .itunesArtistID
        case .itunesCatalogID: .itunesCatalogID
        case .musicBrainzAlbumID: .musicBrainzAlbumID
        case .musicBrainzTrackID: .musicBrainzTrackID
        case .musicBrainzReleaseGroupID: .musicBrainzReleaseGroupID
        case .contentAdvisory: .explicitContent
        case .fileName, .baseName, .path, .relativePath, .index, .ignore: nil
        }
    }

    nonisolated var isNumberField: Bool {
        switch self {
        case .trackNumber, .trackTotal, .discNumber, .discTotal: true
        default: false
        }
    }

    nonisolated var isDiscNumberField: Bool {
        self == .discNumber || self == .discTotal
    }

    nonisolated var pairedTotalField: MetadataExchangeField? {
        switch self {
        case .trackNumber: .trackTotal
        case .discNumber: .discTotal
        default: nil
        }
    }

    nonisolated var pairedNumberField: MetadataExchangeField? {
        switch self {
        case .trackTotal: .trackNumber
        case .discTotal: .discNumber
        default: nil
        }
    }

    nonisolated static func field(forSemanticKey key: MetadataFieldKey) -> MetadataExchangeField? {
        allCases.first { $0.semanticFieldKey == key }
    }
}

/// Exact semantic component represented by a number operation.
extension MetadataExchangeField {
    nonisolated var numberComponentKey: MetadataFieldKey? {
        isNumberField ? semanticFieldKey : nil
    }
}

// MARK: – Resolver

nonisolated enum ExchangeIntentResolver {
    /// Resolves one imported record's typed captures into the planner intent.
    ///
    /// The reviewed file supplies only comparison context that cannot be expressed
    /// lexically: content-advisory same-code no-ops. The intent itself is frozen
    /// before the eventual write; the executor never reinterprets raw strings.
    nonisolated static func resolveImportedRow(
        captures: [MetadataExchangeField: ExchangeCapture],
        clearBlankImportedValues: Bool,
        reviewedFile: AudioFile,
        maximumComponentValue: Int
    ) -> Result<ExchangeResolvedIntent, ExchangeIntentRejection> {
        var locators: [MetadataExchangeField: String] = [:]
        for (field, capture) in captures where field.isLocatorField {
            if case .locator(let text) = capture {
                locators[field] = text
            }
        }

        var operations: [ExchangeResolvedOperation] = []

        // Number pairs: resolve the number column and the total column, then apply
        // total-column precedence before any baseline comparison.
        for group in [
            (number: MetadataExchangeField.trackNumber, total: MetadataExchangeField.trackTotal),
            (number: MetadataExchangeField.discNumber, total: MetadataExchangeField.discTotal)
        ] {
            let numberCapture = captures[group.number]
            let totalCapture = captures[group.total]
            guard numberCapture != nil || totalCapture != nil else { continue }

            let numberIntent: NumberIntent
            var embeddedTotal: NumberIntent?
            do {
                (numberIntent, embeddedTotal) = try resolveNumberColumn(
                    numberCapture,
                    field: group.number,
                    clearBlankImportedValues: clearBlankImportedValues,
                    maximumComponentValue: maximumComponentValue
                )
            } catch let rejection as ExchangeIntentRejection {
                return .failure(rejection)
            } catch {
                return .failure(ExchangeIntentRejection(message: error.localizedDescription))
            }

            let totalIntent: NumberIntent
            do {
                totalIntent = try resolveTotalColumn(
                    totalCapture,
                    field: group.total,
                    clearBlankImportedValues: clearBlankImportedValues,
                    maximumComponentValue: maximumComponentValue
                )
            } catch let rejection as ExchangeIntentRejection {
                return .failure(rejection)
            } catch {
                return .failure(ExchangeIntentRejection(message: error.localizedDescription))
            }

            // An explicit total column (literal or removal) wins over the total
            // embedded in the number column. A disabled blank does not override.
            let resolvedTotal: NumberIntent = switch totalIntent {
            case .keep: embeddedTotal ?? .keep
            default: totalIntent
            }

            appendNumberOperation(numberIntent, field: group.number, to: &operations)
            appendNumberOperation(resolvedTotal, field: group.total, to: &operations)
        }

        // Text fields and the content advisory.
        for field in MetadataExchangeField.allCases where field.isWritableMetadataField && !field.isNumberField {
            guard let capture = captures[field] else { continue }
            switch capture {
            case .locator:
                continue
            case .blank:
                guard clearBlankImportedValues else { continue }
                operations.append(.removeText(field))
            case .explicitRemoval:
                operations.append(.removeText(field))
            case .literal(let rawText):
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                if field == .contentAdvisory {
                    switch resolveAdvisoryLiteral(trimmed, reviewedFile: reviewedFile) {
                    case .success(let operation?):
                        operations.append(operation)
                    case .success(nil):
                        continue
                    case .failure(let rejection):
                        return .failure(rejection)
                    }
                    continue
                }
                if let validationMessage = field.importedValueValidationMessage(trimmed) {
                    return .failure(ExchangeIntentRejection(message: validationMessage))
                }
                operations.append(.setText(field, text: trimmed))
            }
        }

        return .success(
            ExchangeResolvedIntent(
                operations: operations,
                locators: locators,
                isLocatorMode: !locators.isEmpty
            )
        )
    }

    /// True when two repeated captures for one writable field have the same typed
    /// meaning, so a repeated template token is not a conflicting duplicate.
    nonisolated static func capturesHaveSameTypedMeaning(
        field: MetadataExchangeField,
        lhs: ExchangeCapture,
        rhs: ExchangeCapture
    ) -> Bool {
        switch (lhs, rhs) {
        case (.blank, .blank), (.explicitRemoval, .explicitRemoval):
            return true
        case (.literal(let left), .literal(let right)):
            let leftText = stripCaptureWhitespace(left)
            let rightText = stripCaptureWhitespace(right)
            if field.isNumberField,
               let leftValue = numberValueForComparison(leftText),
               let rightValue = numberValueForComparison(rightText) {
                return leftValue == rightValue
            }
            return field.canonicalImportedValue(leftText) == field.canonicalImportedValue(rightText)
        default:
            return false
        }
    }

    nonisolated static func stripCaptureWhitespace(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func numberValueForComparison(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        if let value = Int(text) { return String(value) }
        if text.first == "+", let value = Int(text.dropFirst()) { return String(value) }
        return nil
    }

    // MARK: Number resolution

    private enum NumberIntent {
        case keep
        case removal
        case value(text: String, value: Int)
    }

    private static func resolveNumberColumn(
        _ capture: ExchangeCapture?,
        field: MetadataExchangeField,
        clearBlankImportedValues: Bool,
        maximumComponentValue: Int
    ) throws -> (NumberIntent, embeddedTotal: NumberIntent?) {
        guard let capture else { return (.keep, nil) }
        switch capture {
        case .blank:
            return (clearBlankImportedValues ? .removal : .keep, nil)
        case .explicitRemoval:
            return (.removal, nil)
        case .locator:
            return (.keep, nil)
        case .literal(let rawText):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch MetadataExchangeNumberSpelling.parseNumberColumn(trimmed, maximum: maximumComponentValue) {
            case .failure(let error):
                throw ExchangeIntentRejection(
                    message: numberSpellingMessage(error, field: field, maximumComponentValue: maximumComponentValue)
                )
            case .success(.number(let number, let embedded)):
                return (
                    numberIntent(from: number),
                    embedded.map(numberIntent(from:))
                )
            }
        }
    }

    private static func resolveTotalColumn(
        _ capture: ExchangeCapture?,
        field: MetadataExchangeField,
        clearBlankImportedValues: Bool,
        maximumComponentValue: Int
    ) throws -> NumberIntent {
        guard let capture else { return .keep }
        switch capture {
        case .blank:
            return clearBlankImportedValues ? .removal : .keep
        case .explicitRemoval:
            return .removal
        case .locator:
            return .keep
        case .literal(let rawText):
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch MetadataExchangeNumberSpelling.parseTotalColumn(trimmed, maximum: maximumComponentValue) {
            case .failure(let error):
                throw ExchangeIntentRejection(
                    message: numberSpellingMessage(error, field: field, maximumComponentValue: maximumComponentValue)
                )
            case .success(let component):
                return numberIntent(from: component)
            }
        }
    }

    private static func numberIntent(
        from component: MetadataExchangeNumberSpelling.Component
    ) -> NumberIntent {
        switch component {
        case .removal: .removal
        case .value(let text, let value): .value(text: text, value: value)
        }
    }

    private static func appendNumberOperation(
        _ intent: NumberIntent,
        field: MetadataExchangeField,
        to operations: inout [ExchangeResolvedOperation]
    ) {
        switch intent {
        case .keep:
            return
        case .removal:
            operations.append(.removeNumber(field))
        case .value(let text, let value):
            operations.append(.setNumber(field, value: value, literalText: text))
        }
    }

    nonisolated static func numberSpellingMessage(
        _ error: MetadataExchangeNumberSpelling.SpellingError,
        field: MetadataExchangeField,
        maximumComponentValue: Int
    ) -> String {
        switch error {
        case .negativeMagnitude:
            return String(localized: "For \(field.displayName), enter a whole number from 1 to \(maximumComponentValue). Negative values can’t be imported.")
        case .notAnInteger:
            return String(localized: "For \(field.displayName), enter a whole number from 1 to \(maximumComponentValue).")
        case .overflowsDeclaredMaximum:
            return String(localized: "For \(field.displayName), enter a whole number from 1 to \(maximumComponentValue). This file format can’t store the larger value.")
        case .emptySlashComponent:
            return String(localized: "For \(field.displayName), put a whole number on each side of the slash, such as 3/12.")
        case .multipleSlashes:
            return String(localized: "For \(field.displayName), use at most one slash with a number and total, such as 3/12.")
        case .pairInTotalColumn:
            return String(localized: "For \(field.displayName), enter one whole number without a total.")
        }
    }

    // MARK: Advisory

    private static func resolveAdvisoryLiteral(
        _ text: String,
        reviewedFile: AudioFile
    ) -> Result<ExchangeResolvedOperation?, ExchangeIntentRejection> {
        let canonical = MetadataExchangeField.contentAdvisory.canonicalImportedValue(text)
        if let advisory = ContentAdvisory.fromMetadataText(canonical) {
            return .success(.setText(.contentAdvisory, text: String(advisory.rawValue)))
        }
        // An unknown native code can stay in its original file but cannot be
        // assigned to another value; the same code is a no-op.
        if canonical == reviewedFile.advisoryRawValue {
            return .success(nil)
        }
        return .failure(
            ExchangeIntentRejection(
                message: String(localized: "This content advisory code can stay in its original file, but it can't be copied to another file. Choose a supported advisory option to set a new value.")
            )
        )
    }
}

// MARK: – Translator

nonisolated struct FrozenExchangeWrite: Sendable {
    let target: ReviewedMetadataTarget
    let payload: MetadataEditPayload
    let projection: MetadataWriteProjection

    nonisolated var reviewedWrite: ReviewedMetadataWrite {
        ReviewedMetadataWrite(target: target, intent: .semantic(payload), projection: projection)
    }
}

nonisolated enum ExchangeFrozenWriteOutcome: Sendable {
    case executable(FrozenExchangeWrite)
    case unchanged
    case rejected(String)
    case unavailable(String)
}

nonisolated enum ExchangeWriteTranslator {
    /// Builds the edit model from the reviewed file and applies the typed
    /// operations through the component setters. The payload is then frozen
    /// against the same reviewed file, so preview and the future strict executor
    /// consume one intent.
    nonisolated static func makeFrozenWrite(
        from reviewedFile: AudioFile,
        intent: ExchangeResolvedIntent,
        projector: (any AudioMetadataPipeline)?
    ) -> ExchangeFrozenWriteOutcome {
        var edit = SingleFileEditModel(from: reviewedFile)
        for operation in intent.operations {
            apply(operation, to: &edit, reviewedFile: reviewedFile)
        }
        var payload = MetadataEditPayload(edit, comparedTo: reviewedFile)
        payload.explicitComponentRemovals = explicitComponentRemovals(
            for: intent.operations,
            reviewedFile: reviewedFile
        )
        return makeFrozenWrite(
            from: reviewedFile,
            payload: payload,
            projector: projector
        )
    }

    /// Builds a frozen write for an already-built edit model (filename
    /// extraction keeps its whole-text number setter contract).
    nonisolated static func makeFrozenWrite(
        from reviewedFile: AudioFile,
        edit: SingleFileEditModel,
        projector: (any AudioMetadataPipeline)?
    ) -> ExchangeFrozenWriteOutcome {
        makeFrozenWrite(
            from: reviewedFile,
            payload: MetadataEditPayload(edit, comparedTo: reviewedFile),
            projector: projector
        )
    }

    private nonisolated static func makeFrozenWrite(
        from reviewedFile: AudioFile,
        payload: MetadataEditPayload,
        projector: (any AudioMetadataPipeline)?
    ) -> ExchangeFrozenWriteOutcome {
        guard let target = ReviewedMetadataTarget(verified: reviewedFile) else {
            return .unavailable(
                String(localized: "The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before continuing.")
            )
        }

        if let projector {
            let projection: MetadataWriteProjection
            do {
                projection = try projector.projectMetadataWrite(
                    .semantic(payload),
                    fileExtension: reviewedFile.url.pathExtension
                )
            } catch {
                return .rejected((error as NSError).localizedDescription)
            }
            switch projection.validation {
            case .executable:
                if projection.isNoOp { return .unchanged }
                return .executable(
                    FrozenExchangeWrite(target: target, payload: payload, projection: projection)
                )
            case .rejected(let message):
                return .rejected(message)
            case .unsupported(let fields):
                return .rejected(unsupportedFieldsMessage(fields))
            }
        }

        // Without an adapter projection (for example a pure planner test), fall
        // back to the same fail-closed declared capability check.
        let requested = payload.requestedFields
        guard !requested.isEmpty else { return .unchanged }
        let unsupported = unsupportedRequestedFields(
            requested,
            fileExtension: reviewedFile.url.pathExtension
        )
        guard unsupported.isEmpty else {
            return .rejected(unsupportedFieldsMessage(unsupported))
        }
        let projection = MetadataWriteProjection(
            requestedFields: requested,
            effectiveFields: requested,
            validation: .executable,
            isEncoderNoOp: false
        )
        return .executable(
            FrozenExchangeWrite(target: target, payload: payload, projection: projection)
        )
    }

    nonisolated static func apply(
        _ operation: ExchangeResolvedOperation,
        to edit: inout SingleFileEditModel,
        reviewedFile: AudioFile
    ) {
        switch operation {
        case .setText(let field, let text):
            applyText(field, text: text, to: &edit)
        case .removeText(let field):
            if field == .contentAdvisory {
                edit.contentAdvisory = nil
                edit.clearsUnknownAdvisory = reviewedFile.advisoryRawValue != nil
            } else {
                applyText(field, text: "", to: &edit)
            }
        case .setNumber(let field, _, let literalText):
            applyNumberField(field, text: literalText, to: &edit)
        case .removeNumber(let field):
            applyNumberField(field, text: "", to: &edit)
        }
    }

    private nonisolated static func applyText(
        _ field: MetadataExchangeField,
        text: String,
        to edit: inout SingleFileEditModel
    ) {
        switch field {
        case .title: edit.title = text
        case .artist: edit.artist = text
        case .album: edit.album = text
        case .albumArtist: edit.albumArtist = text
        case .composer: edit.composer = text
        case .lyricist: edit.lyricist = text
        case .producer: edit.producer = text
        case .engineer: edit.engineer = text
        case .remixer: edit.remixer = text
        case .genre: edit.genre = text
        case .year: edit.year = text
        case .date: edit.date = text
        case .originalReleaseDate: edit.originalReleaseDate = text
        case .comment: edit.comment = text
        case .releaseDate: edit.releaseDate = text
        case .publisher: edit.publisher = text
        case .copyright: edit.copyright = text
        case .isrc: edit.isrc = text
        case .barcode: edit.barcode = text
        case .language: edit.language = text
        case .mediaType: edit.mediaType = text
        case .releaseType: edit.releaseType = text
        case .catalogNumber: edit.catalogNumber = text
        case .releaseCountry: edit.releaseCountry = text
        case .itunesAlbumID: edit.itunesAlbumID = text
        case .itunesArtistID: edit.itunesArtistID = text
        case .itunesCatalogID: edit.itunesCatalogID = text
        case .musicBrainzAlbumID: edit.musicBrainzAlbumID = text
        case .musicBrainzTrackID: edit.musicBrainzTrackID = text
        case .musicBrainzReleaseGroupID: edit.musicBrainzReleaseGroupID = text
        case .contentAdvisory:
            if let advisory = ContentAdvisory.fromMetadataText(text) {
                edit.contentAdvisory = advisory
                edit.unsupportedAdvisoryImport = nil
            } else if text.isEmpty {
                edit.contentAdvisory = nil
                edit.unsupportedAdvisoryImport = nil
            } else {
                edit.contentAdvisory = nil
                edit.unsupportedAdvisoryImport = text
            }
        case .trackNumber, .trackTotal, .discNumber, .discTotal,
                .fileName, .baseName, .path, .relativePath, .index, .ignore:
            break
        }
    }

    private nonisolated static func applyNumberField(
        _ field: MetadataExchangeField,
        text: String,
        to edit: inout SingleFileEditModel
    ) {
        switch field {
        case .trackNumber: edit.setTrackNumberFieldText(text)
        case .trackTotal: edit.setTrackTotalFieldText(text)
        case .discNumber: edit.setDiscNumberFieldText(text)
        case .discTotal: edit.setDiscTotalFieldText(text)
        default: break
        }
    }

    /// Component removals the numeric comparison cannot infer (for example a
    /// malformed loaded raw component that projects numerically to zero).
    nonisolated static func explicitComponentRemovals(
        for operations: [ExchangeResolvedOperation],
        reviewedFile: AudioFile
    ) -> Set<MetadataFieldKey> {
        var removals: Set<MetadataFieldKey> = []
        for operation in operations {
            guard case .removeNumber(let field) = operation,
                  let key = field.numberComponentKey else { continue }
            let baselineValue: Int
            switch key {
            case .track: baselineValue = reviewedFile.track
            case .trackTotal: baselineValue = reviewedFile.trackTotal
            case .disc: baselineValue = reviewedFile.disc
            case .discTotal: baselineValue = reviewedFile.discTotal
            default: continue
            }
            guard baselineValue == 0 else { continue }
            let rawText = field.isDiscNumberField
                ? reviewedFile.discNumberText
                : reviewedFile.trackNumberText
            let components = AudioTagNumberText.components(from: rawText)
            let componentIsPresent: Bool = switch key {
            case .track, .disc: !components.number.isEmpty
            case .trackTotal, .discTotal: !(components.total?.isEmpty ?? true)
            default: false
            }
            if componentIsPresent {
                removals.insert(key)
            }
        }
        return removals
    }

    nonisolated private static func unsupportedRequestedFields(
        _ requested: Set<MetadataFieldKey>,
        fileExtension: String
    ) -> Set<MetadataFieldKey> {
        guard let writableFields = AudioFormatSupport.writableMetadataFields(for: fileExtension) else {
            // Missing concrete-format capability information is not permission to
            // write: treat every requested field as unsupported (fail closed).
            return requested
        }
        return requested.subtracting(writableFields)
    }

    nonisolated static func unsupportedFieldsMessage(_ fields: Set<MetadataFieldKey>) -> String {
        let labels = ListFormatter.localizedString(
            byJoining: fields.map { field in
                MetadataExchangeField.field(forSemanticKey: field)?.displayName
                    ?? String(localized: "Metadata field")
            }.sorted()
        )
        return String(localized: "Changes to \(labels) can’t be saved in this file format. No changes were saved.")
    }
}
