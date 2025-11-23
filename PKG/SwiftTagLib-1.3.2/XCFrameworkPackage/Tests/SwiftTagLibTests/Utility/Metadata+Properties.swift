
@testable import SwiftTagLib

extension AudioFile.Metadata {
    static var stringProperties: [WritableKeyPath<Self, String?>] {[
        \.title,
        \.albumTitle,
        \.artist,
        \.genre,
        \.comment,
        \.composer,
        \.albumArtist,
        \.lyrics,
        \.internationalStandardRecordingCode,
        \.mediaCatalogNumber,
        \.musicBrainzReleaseID,
        \.musicBrainzRecordingID,
    ]}

    static var dateProperties: [WritableKeyPath<Self, String?>] {[
        \.releaseDate,
    ]}

    static var intProperties: [WritableKeyPath<Self, Int32?>] {[
        \.beatPerMinute,
        \.rating,
        \.trackNumber,
        \.trackTotal,
        \.discNumber,
        \.discTotal,
    ]}

    static var boolProperties: [WritableKeyPath<Self, Bool?>] {[
        \.compilation,
    ]}
}
