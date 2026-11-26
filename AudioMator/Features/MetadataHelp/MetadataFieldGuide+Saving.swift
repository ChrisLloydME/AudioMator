import Foundation
import TagLibAudioMetadata

extension MetadataFieldGuide.Entry {
    /// Help copy for the standard write path. The package registry supplies
    /// field types and common bounds. Native exceptions are documented in the
    /// pinned package's field-level write validation reference.
    func savingNote(for family: MetadataNativeFamily) -> String? {
        guard let key, let schema else { return nil }
        if family == .matroska, !schema.targets(for: family).isEmpty {
            return String(localized: "Editing this field in Matroska is unavailable.")
        }
        if key == .custom {
            guard !schema.targets(for: family).isEmpty else { return nil }
            if family == .riffInfo {
                return String(localized: "Use Metadata Editor to add a named field to the ID3 tag in a WAV file. RIFF INFO fields are read-only here.")
            }
            return String(localized: "In Metadata Editor, choose Add Field and enter a name. Use an existing field when it already describes your value.")
        }
        guard !schema.targets(for: family).isEmpty else { return nil }
        if family == .riffInfo {
            return String(localized: "AudioMator reads this RIFF INFO field. To edit the same information in a WAV file, use its ID3 tag where supported.")
        }
        if family == .id3v23, [.year, .standaloneDate, .releaseDate, .originalReleaseDate].contains(key) {
            return String(localized: "AudioMator keeps existing date values in this older ID3 tag read-only.")
        }
        if schema.isRoleQualified {
            return String(localized: "This field includes a role or instrument. In Metadata Editor, look for the name that includes the role.")
        }
        if key == .rate || schema.capability(for: family) == .readOnly {
            return String(localized: "AudioMator displays this value as read-only.")
        }

        switch key {
        case .track, .trackTotal, .disc, .discTotal:
            let maximum = family == .mp4
                ? AudioFormatNumberBounds.mp4ComponentMaximum
                : AudioFormatNumberBounds.int32ComponentMaximum
            let range = String(localized: "Enter a whole number from 1 to \(maximum.formatted()). Clear the field to remove its value.")
            if family == .asf {
                return range + " " + String(localized: "WMA files need a number whenever a total is set. Keep the number or clear both values.")
            }
            return range
        case .artwork:
            return String(localized: "If artwork editing is available for your file, add an image in the Inspector or choose Clear Artwork to remove it. Replacing artwork saves one cover per file.")
        case .explicitContent:
            return String(localized: "Choose Not Explicit, Clean, or Explicit. Choose Unset to remove the setting.")
        case .itunesNorm, .itunesSMPB:
            return String(localized: "Keep the value supplied by the app that created the file. A guessed value can change playback.")
        default:
            break
        }

        let kinds = schema.acceptedPatchValueKinds
        if kinds == [.integer], let constraint = schema.integerConstraint {
            let maximum: Int
            switch (family, key) {
            case (.mp4, .bpm), (.mp4, .movementNumber), (.mp4, .movementCount):
                maximum = Int(Int16.max)
            case (.mp4, .itunesArtistID), (.mp4, .itunesGenreID):
                maximum = Int(UInt32.max)
            default:
                maximum = constraint.maximum
            }
            return String(localized: "Enter a whole number from \(constraint.minimum.formatted()) to \(maximum.formatted()).")
        }
        if kinds == [.boolean] {
            return String(localized: "Choose Yes or No. In Metadata Editor, use the stored value for this format.")
        }
        if valueGuidance != nil {
            return String(localized: "Enter date text. See the examples above for this tag format.")
        }
        if family == .asf, kinds.contains(.values) {
            return String(localized: "Save one text value at a time. A list of values can fail to save in WMA.")
        }
        if kinds.contains(.values) {
            return String(localized: "Enter text. When the tag supports separate values, you can edit them individually in Metadata Editor.")
        }
        if kinds.contains(.text) {
            return String(localized: "Enter one text value. The Inspector removes spaces and line breaks at the beginning and end.")
        }
        return nil
    }

    var numberingSavingNote: String? {
        switch key {
        case .track, .trackTotal, .disc, .discTotal:
            String(localized: "If the number contains letters, such as A1, the Inspector can’t save changes to the number or total. Enter a whole number, or use Metadata Editor to work with the stored tag.")
        default:
            nil
        }
    }

    var trackerSavingNote: String? {
        switch key {
        case .title, .comment:
            String(localized: "XM, S3M, and IT files can save this field as text. The file’s own layout can limit how much text it keeps.")
        case .trackerName:
            String(localized: "XM files can save a tracker name. AudioMator displays the name from S3M and IT files as read-only.")
        default:
            nil
        }
    }
}
