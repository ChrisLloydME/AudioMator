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
    var year: String
    var trackNumber: Int
    var trackTotal: Int
    var discNumber: Int
    var discTotal: Int
    var trackNumberText: String
    var discNumberText: String
    var albumArtist: String
    var releaseDate: String
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
    var contentAdvisory: ContentAdvisory?
    nonisolated var isExplicit: Bool { contentAdvisory?.isExplicit ?? false }
    var artwork: MetadataArtworkChange
    var changedFields: Set<MetadataFieldKey>
    var contentAdvisoryChanged: Bool
    var trackNumberTextChanged: Bool
    var discNumberTextChanged: Bool

    /// Preserve numeric text validation while allowing total-only pairs in 0.6.0.
    nonisolated var numberPairValidationMessage: String? {
        if trackNumberTextChanged, !AudioTagNumberText.components(from: trackNumberText).number.isEmpty,
           Int(AudioTagNumberText.components(from: trackNumberText).number) == nil {
            return String(localized: "Non-numeric track number text is not supported for this edit. Use the Metadata Editor to preserve text values.")
        }
        if discNumberTextChanged, !AudioTagNumberText.components(from: discNumberText).number.isEmpty,
           Int(AudioTagNumberText.components(from: discNumberText).number) == nil {
            return String(localized: "Non-numeric disc number text is not supported for this edit. Use the Metadata Editor to preserve text values.")
        }
        return nil
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
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String]
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
    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool,
        expectedVersion: MetadataFileVersion?
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

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        try rawMetadataValueMap(for: url).mapValues { $0.joined(separator: "; ") }
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        try writeMetadata(edit, to: url, expectedVersion: nil)
    }

    nonisolated func writeRawMetadataPropertyMap(
        _ propertyMap: [String: String],
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        try writeRawMetadataValueMap(
            propertyMap.mapValues { [$0] },
            to: url,
            expectedVersion: nil
        )
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

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        try eraseAllMetadata(at: url, expectedVersion: nil)
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        try writeTrackNumberText(
            trackNumberText,
            discNumberText: discNumberText,
            to: url,
            verifyAfterWrite: verifyAfterWrite,
            expectedVersion: nil
        )
    }
}
