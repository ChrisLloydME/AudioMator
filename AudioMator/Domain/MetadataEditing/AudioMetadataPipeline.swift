import Foundation
import TagLibAudioMetadata

enum MetadataArtworkChange: Sendable {
    case unchanged
    case replace(data: Data, mimeType: String)
    case remove
}

struct MetadataEditPayload: Sendable {
    var title: String
    var artist: String
    var album: String
    var composer: String
    var genre: String
    var comment: String
    /// Complete stored YEAR text. Sent as `.year`; never as the legacy `.date`
    /// YEAR-slot alias.
    var year: String
    /// Independent DATE identity. Sent as `.standaloneDate`.
    var date: String
    var trackNumber: Int
    var trackTotal: Int
    var discNumber: Int
    var discTotal: Int
    /// Baseline pair components from the compared source, when known. A
    /// component whose value did not change is omitted so a number-only edit
    /// never removes or rewrites its untouched sibling.
    var originalTrackNumber: Int?
    var originalTrackTotal: Int?
    var originalDiscNumber: Int?
    var originalDiscTotal: Int?
    var trackNumberText: String
    var discNumberText: String
    var albumArtist: String
    var releaseDate: String
    var originalReleaseDate: String
    var contentGroup: String
    var grouping: String
    var work: String
    var publisher: String
    var isrc: String
    var barcode: String
    var itunesAlbumID: String
    var itunesArtistID: String
    var itunesCatalogID: String
    var musicBrainzAlbumID: String
    var musicBrainzTrackID: String
    var musicBrainzReleaseGroupID: String
    var lyricist: String
    var remixer: String
    var producer: String
    var engineer: String
    var language: String
    var mediaType: String
    var releaseType: String
    var catalogNumber: String
    var releaseCountry: String
    var copyright: String
    var unsupportedAdvisoryImport: String?
    var contentAdvisory: ContentAdvisory?
    /// Typed MP4-exclusive and role-aware field intents. Values are already
    /// shape-validated by the semantic editor.
    var containerFields: [MetadataFieldKey: MetadataPatchValue]
    var artwork: MetadataArtworkChange
    var changedFields: Set<MetadataFieldKey>
    var contentAdvisoryChanged: Bool
    var trackNumberTextChanged: Bool
    var discNumberTextChanged: Bool
    /// Number components whose removal cannot be inferred from numeric
    /// comparison (for example malformed loaded raw text that projects
    /// numerically to zero). Only `.track`/`.trackTotal`/`.disc`/`.discTotal`
    /// may appear here; the adapter emits an explicit component removal for
    /// each entry that the numeric comparison did not already produce.
    var explicitComponentRemovals: Set<MetadataFieldKey> = []

    /// Preserve numeric text validation while allowing total-only pairs.
    nonisolated var numberPairValidationMessage: String? {
        if trackNumberTextChanged, !AudioTagNumberText.components(from: trackNumberText).number.isEmpty,
           !AudioTagNumberText.hasIntegerSyntax(AudioTagNumberText.components(from: trackNumberText).number) {
            return String(localized: "This numbering change can’t be saved while Track Number contains text such as “A1”. Enter a numeric track number, or edit these fields in the Metadata Editor.")
        }
        if discNumberTextChanged, !AudioTagNumberText.components(from: discNumberText).number.isEmpty,
           !AudioTagNumberText.hasIntegerSyntax(AudioTagNumberText.components(from: discNumberText).number) {
            return String(localized: "This numbering change can’t be saved while Disc Number contains text such as “B2”. Enter a numeric disc number, or edit these fields in the Metadata Editor.")
        }
        for (changed, text, label, numberLabel) in [
            (trackNumberTextChanged, trackNumberText, "Total Tracks", "Track Number"),
            (discNumberTextChanged, discNumberText, "Total Discs", "Disc Number")
        ] where changed {
            let pair = AudioTagNumberText.components(from: text)
            if let total = pair.total, !AudioTagNumberText.isWritableComponent(total) {
                return String(localized: "For \(label), enter a whole number from 0 to 2147483647, or clear the field.")
            }
            if !AudioTagNumberText.isWritableComponent(pair.number) {
                return String(localized: "For \(numberLabel), enter a whole number from 0 to 2147483647, or clear the field.")
            }
        }
        return nil
    }

    /// Validates only the explicitly edited date field against its own shape.
    /// It never compares one date identity with another or completes a value.
    nonisolated var dateValidationMessage: String? {
        let editedDates: [(MetadataFieldKey, String, String)] = [
            (.year, year, String(localized: "Year")),
            (.standaloneDate, date, String(localized: "Date")),
            (.releaseDate, releaseDate, String(localized: "Release Date")),
            (.originalReleaseDate, originalReleaseDate, String(localized: "Original Release Date")),
        ]
        for (field, value, label) in editedDates where changedFields.contains(field) {
            guard MetadataDateText.validates(value, for: field) else {
                return label + " " + String(localized: "uses a date format that can’t be saved here. Enter a supported date or clear the field.")
            }
        }
        return nil
    }

    /// Every semantic field this payload will touch. Used by conflict groups
    /// and the all-or-nothing capability preflight.
    nonisolated var requestedFields: Set<MetadataFieldKey> {
        var fields = changedFields
        if contentAdvisoryChanged { fields.insert(.explicitContent) }
        if trackNumberTextChanged {
            if originalTrackNumber != trackNumber { fields.insert(.track) }
            if originalTrackTotal != trackTotal { fields.insert(.trackTotal) }
        }
        if discNumberTextChanged {
            if originalDiscNumber != discNumber { fields.insert(.disc) }
            if originalDiscTotal != discTotal { fields.insert(.discTotal) }
        }
        if case .unchanged = artwork {} else { fields.insert(.artwork) }
        fields.formUnion(containerFields.keys)
        fields.formUnion(explicitComponentRemovals)
        return fields
    }
}


enum AudioMetadataCommitStatus: Equatable, Sendable {
    case durable
    case durabilityUncertain(String)
}

struct AudioMetadataWriteResult: Sendable {
    let warnings: [String]
    let commitStatus: AudioMetadataCommitStatus

    nonisolated init(
        warnings: [String],
        commitStatus: AudioMetadataCommitStatus = .durable
    ) {
        self.warnings = warnings
        self.commitStatus = commitStatus
    }
}

typealias RawMetadataValueMap = [String: [String]]

protocol AudioMetadataPipeline: Sendable {
    nonisolated var requiresTransactionalDirectoryAccess: Bool { get }
    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile
    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot
    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion
    nonisolated func rawMetadataDumpText(for url: URL) -> String?
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult
    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult

    // MARK: – Reviewed writes (strict, captured nonoptional revision)

    /// Projects a frozen write intent through the adapter's deterministic encoder
    /// and concrete-format capability information. The projection is plan-time
    /// truth only; it never authorizes a write by itself.
    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection

    /// Strict semantic write: the captured nonoptional revision is the only
    /// expected version. Never substitutes a different revision.
    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult

    /// Strict raw patch write with the captured nonoptional revision.
    nonisolated func writeReviewedRawPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult

    /// Strict erase-all with the captured nonoptional revision. Best effort by
    /// container; the package performs the verified write.
    nonisolated func eraseAllMetadataReviewed(
        at url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult
}

extension AudioMetadataPipeline {
    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult {
        throw MetadataAudioContentError.unavailable
    }
    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult {
        throw MetadataAudioContentError.unavailable
    }

    nonisolated var requiresTransactionalDirectoryAccess: Bool { false }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        throw CocoaError(.featureUnsupported)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        throw CocoaError(.featureUnsupported)
    }

    nonisolated func writeRawMetadataValueMap(
        _ valueMap: RawMetadataValueMap,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        let original = try rawMetadataValueMap(for: url)
        let changedValues = valueMap.filter { original[$0.key] != $0.value }
        let removedKeys = Set(original.keys).subtracting(valueMap.keys)
        return try writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: changedValues, removingKeys: removedKeys),
            to: url,
            expectedVersion: expectedVersion
        )
    }

    // MARK: – Reviewed write defaults

    /// Fakes that do not implement plan-time projection fail closed instead of
    /// guessing capability.
    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        throw CocoaError(.featureUnsupported)
    }

    /// Default forwarding for fakes that only implement the optional-version
    /// methods during the migration. Production adapters forward the nonoptional
    /// token directly to the package.
    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try writeMetadata(edit, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeReviewedRawPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func eraseAllMetadataReviewed(
        at url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try eraseAllMetadata(at: url, expectedVersion: expectedVersion)
    }
}
