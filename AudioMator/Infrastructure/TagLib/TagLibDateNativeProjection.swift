import Foundation
import TagLibAudioMetadata

/// Exact native projections for the four independent date identities.
///
/// YEAR, DATE, RELEASEDATE and ORIGINALDATE are separate conflict groups. The
/// legacy TagLib PropertyMap `DATE` key can project YEAR on ID3/MP4 while it is
/// the real DATE key on Xiph, so conflict comparison uses structured native
/// frames/atoms/properties instead of the flattened PropertyMap projection.
nonisolated enum TagLibDateNativeProjection {
    static func values(
        for field: MetadataFieldKey,
        snapshot: MetadataSnapshot,
        fileExtension: String
    ) -> [String] {
        values(
            for: field,
            structured: snapshot.structured,
            basicYear: snapshot.basic.year,
            fileExtension: fileExtension
        )
    }

    static func values(
        for field: MetadataFieldKey,
        structured: StructuredMetadata,
        basicYear: String,
        fileExtension: String
    ) -> [String] {
        switch field {
        case .year, .date:
            return yearValues(structured, basicYear: basicYear, fileExtension: fileExtension)
        case .standaloneDate:
            return standaloneDateValues(structured, fileExtension: fileExtension)
        case .releaseDate:
            return releaseDateValues(structured, fileExtension: fileExtension)
        case .originalReleaseDate:
            return originalReleaseDateValues(structured, fileExtension: fileExtension)
        default:
            return []
        }
    }

    static func isDateIdentity(_ field: MetadataFieldKey) -> Bool {
        switch field {
        case .year, .date, .standaloneDate, .releaseDate, .originalReleaseDate:
            return true
        default:
            return false
        }
    }

    static func yearValues(
        _ snapshot: MetadataSnapshot,
        fileExtension ext: String
    ) -> [String] {
        yearValues(snapshot.structured, basicYear: snapshot.basic.year, fileExtension: ext)
    }

    static func yearValues(
        _ structured: StructuredMetadata,
        basicYear: String,
        fileExtension ext: String
    ) -> [String] {
        switch ext.lowercased() {
        case "m4a", "mp4", "m4b", "m4r", "m4p", "m4v":
            return atomValues(structured.mp4Atoms, key: "©day")
        case "mp3", "mp2", "aac", "wav", "aif", "aiff", "aifc", "tta":
            let frames = structured.id3v2Frames.filter {
                $0.frameID == "TDRC" || $0.frameID == "TYER"
            }
            let values = frameValues(frames)
            if !values.isEmpty { return values }
            return basicYear.isEmpty ? [] : [basicYear]
        default:
            let values = propertyValues(structured, key: "YEAR")
            if !values.isEmpty { return values }
            return basicYear.isEmpty ? [] : [basicYear]
        }
    }

    static func standaloneDateValues(
        _ snapshot: MetadataSnapshot,
        fileExtension ext: String
    ) -> [String] {
        standaloneDateValues(snapshot.structured, fileExtension: ext)
    }

    static func standaloneDateValues(
        _ structured: StructuredMetadata,
        fileExtension ext: String
    ) -> [String] {
        switch ext.lowercased() {
        case "m4a", "mp4", "m4b", "m4r", "m4p", "m4v":
            return freeformValues(structured.mp4Atoms, description: "DATE")
        case "mp3", "mp2", "aac", "wav", "aif", "aiff", "aifc", "tta":
            let frames = structured.id3v2Frames.filter { frame in
                frame.frameID == "TDAT"
                    || (frame.frameID == "TXXX"
                        && frame.description?.uppercased() == "DATE")
            }
            return frameValues(frames)
        default:
            return propertyValues(structured, key: "DATE")
        }
    }

    static func releaseDateValues(
        _ snapshot: MetadataSnapshot,
        fileExtension ext: String
    ) -> [String] {
        releaseDateValues(snapshot.structured, fileExtension: ext)
    }

    static func releaseDateValues(
        _ structured: StructuredMetadata,
        fileExtension ext: String
    ) -> [String] {
        switch ext.lowercased() {
        case "m4a", "mp4", "m4b", "m4r", "m4p", "m4v":
            return freeformValues(structured.mp4Atoms, description: "RELEASEDATE")
        case "mp3", "mp2", "aac", "wav", "aif", "aiff", "aifc", "tta":
            return frameValues(structured.id3v2Frames.filter { $0.frameID == "TDRL" })
        default:
            return propertyValues(structured, key: "RELEASEDATE")
        }
    }

    static func originalReleaseDateValues(
        _ snapshot: MetadataSnapshot,
        fileExtension ext: String
    ) -> [String] {
        originalReleaseDateValues(snapshot.structured, fileExtension: ext)
    }

    static func originalReleaseDateValues(
        _ structured: StructuredMetadata,
        fileExtension ext: String
    ) -> [String] {
        switch ext.lowercased() {
        case "m4a", "mp4", "m4b", "m4r", "m4p", "m4v":
            return freeformValues(structured.mp4Atoms, description: "ORIGINALDATE")
        case "mp3", "mp2", "aac", "wav", "aif", "aiff", "aifc", "tta":
            return frameValues(
                structured.id3v2Frames.filter {
                    $0.frameID == "TDOR" || $0.frameID == "TORY"
                }
            )
        default:
            return propertyValues(structured, key: "ORIGINALDATE")
        }
    }

    private static func atomValues(
        _ atoms: [StructuredMP4Atom],
        key: String
    ) -> [String] {
        atoms.filter { !$0.remove && $0.key == key }
            .flatMap { $0.values.isEmpty ? [$0.value] : $0.values }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func freeformValues(
        _ atoms: [StructuredMP4Atom],
        description: String
    ) -> [String] {
        atoms.filter {
            !$0.remove && $0.key.hasPrefix("----:com.apple.iTunes:")
                && String($0.key.dropFirst("----:com.apple.iTunes:".count)).uppercased() == description.uppercased()
        }
        .flatMap { $0.values.isEmpty ? [$0.value] : $0.values }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func frameValues(_ frames: [StructuredID3v2Frame]) -> [String] {
        frames.flatMap { $0.values.isEmpty ? [$0.value] : $0.values }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func propertyValues(
        _ structured: StructuredMetadata,
        key: String
    ) -> [String] {
        structured.properties
            .filter { $0.key == key }
            .flatMap(\.values)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
