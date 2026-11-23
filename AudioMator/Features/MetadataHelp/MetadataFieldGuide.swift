import Foundation
import TagLibAudioMetadata

/// Offline editorial explanations. Native targets come from the installed package,
/// never from this copy or from a live web page.
nonisolated enum MetadataFieldGuide {
    struct Source: Identifiable, Sendable {
        let id: String
        let title: String
        let url: URL
    }

    struct Example: Identifiable, Sendable {
        let id: String
        let value: String
        let note: String
    }

    struct ValueGuidance: Sendable {
        enum PickerTimeFormat: Sendable {
            case id3OrUTCText
            case utcTextOnly
        }

        let examples: [Example]
        let formatNote: String
        let editingSummary: String
        let pickerAvailabilityNote: String
        let pickerTimeFormat: PickerTimeFormat

        var sharedEditingNote: String {
            switch pickerTimeFormat {
            case .id3OrUTCText:
                String(localized: "Direct typing or pasting adds no format checks, missing parts, or time-zone conversion, though the file’s tag still determines what saves. Where the picker appears, it offers Year, Year & Month, and Full Date (with optional Add Time and Time Zone), keeps pure dates as chosen, converts timed values to UTC in Tag Value Preview (without Z if any target uses ID3v2.4), and updates the draft on Apply until you save.")
            case .utcTextOnly:
                String(localized: "Direct typing or pasting adds no format checks, missing parts, or time-zone conversion, though the file’s tag still determines what saves. Where the picker appears, it offers Year, Year & Month, and Full Date (with optional Add Time and Time Zone), keeps pure dates as chosen, converts timed values to UTC with Z in Tag Value Preview, and updates the draft on Apply until you save.")
            }
        }

        var searchableText: [String] {
            examples.flatMap { [$0.value, $0.note] } + [
                formatNote,
                editingSummary,
                pickerAvailabilityNote,
                sharedEditingNote,
            ]
        }
    }

    struct Entry: Identifiable, Sendable {
        let key: MetadataFieldKey?
        private let displayID: String?
        private let displayTitle: String?
        let purpose: String
        let sourceID: String
        let additionalSourceIDs: [String]
        let valueGuidance: ValueGuidance?

        init(
            key: MetadataFieldKey,
            purpose: String,
            sourceID: String,
            additionalSourceIDs: [String] = [],
            valueGuidance: ValueGuidance? = nil
        ) {
            self.key = key
            self.purpose = purpose
            self.sourceID = sourceID
            self.additionalSourceIDs = additionalSourceIDs
            self.valueGuidance = valueGuidance
            displayID = nil
            displayTitle = nil
        }

        init(displayID: String, title: String, purpose: String) {
            key = nil
            self.displayID = displayID
            displayTitle = title
            self.purpose = purpose
            sourceID = "apple"
            additionalSourceIDs = []
            valueGuidance = nil
        }

        var id: String { key?.rawValue ?? displayID ?? "" }
        var schema: MetadataFieldSchema? { key.flatMap { MetadataFieldRegistry.schema(for: $0) } }
        var sourceIDs: [String] { [sourceID] + additionalSourceIDs }
        var resolvedSources: [Source] {
            sourceIDs.compactMap { id in
                MetadataFieldGuide.sources.first { $0.id == id }
            }
        }
        var title: String {
            guard let key else { return displayTitle ?? id }
            return MetadataFieldGuide.displayName(for: key)
        }
        func matches(_ query: String) -> Bool {
            let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
            let text = ([title, purpose, id, schema?.semanticKey ?? ""]
                + (valueGuidance?.searchableText ?? [])
                + (schema?.propertyMapKeys ?? [])
                + (schema?.nativeTargets.map(\.nativeIdentity) ?? [])).joined(separator: " ")
            return terms.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    static func displayName(forReadOnlyField id: String) -> String {
        entries.first { $0.key == nil && $0.id == id }?.title ?? id
    }

    static func displayName(for key: MetadataFieldKey) -> String {
        switch key {
        case .trackTotal: return L10n.string("Total Tracks")
        case .discTotal: return L10n.string("Total Discs")
        case .explicitContent: return L10n.string("Explicit")
        default: return L10n.string(MetadataFieldRegistry.schema(for: key)?.displayName ?? key.rawValue)
        }
    }

    /// Raw keys remain identities. Only presentation is translated here.
    static func displayName(forRawKey key: String, fileExtensions: [String] = []) -> String {
        let normalized = MetadataFieldRegistry.normalizePropertyMapKey(key)
        if normalized == "RELEASETIME" { return displayName(for: .releaseDate) }
        if normalized == "DATE", !fileExtensions.isEmpty {
            let literalDateFamilies: Set<String> = ["flac", "ogg", "oga", "opus", "spx", "ape", "wv", "mpc"]
            let owners = Set(fileExtensions.map { literalDateFamilies.contains($0.lowercased()) ? MetadataFieldKey.standaloneDate : .year })
            if owners.count > 1 { return displayName(for: .year) + " / " + displayName(for: .standaloneDate) }
            if owners.contains(.standaloneDate) { return displayName(for: .standaloneDate) }
        }
        guard let schema = MetadataFieldRegistry.schema(forPropertyMapKey: normalized) else { return key }
        let name = displayName(for: schema.key)
        if let colon = key.firstIndex(of: ":"), schema.isRoleQualified || schema.key == .comment || schema.key == .lyrics {
            return name + " (" + key[key.index(after: colon)...] + ")"
        }
        return name
    }

    static let sources: [Source] = [
        Source(id: "mapping", title: "MusicBrainz Picard — Tag reference", url: URL(string: "https://picard-docs.musicbrainz.org/en/v2.13/appendices/tag_mapping.html")!),
        Source(id: "artist", title: "MusicBrainz — Artist", url: URL(string: "https://musicbrainz.org/doc/Artist")!),
        Source(id: "id3", title: "ID3.org — ID3v2 frames", url: URL(string: "https://id3.org/id3v2.4.0-frames%C2%A0")!),
        Source(id: "id3Structure", title: "ID3.org — ID3v2.4 main structure (timestamps)", url: URL(string: "https://id3.org/id3v2.4.0-structure")!),
        Source(id: "xiph", title: "Xiph.Org — Vorbis comments", url: URL(string: "https://www.xiph.org/vorbis/doc/Vorbis_I_spec.html")!),
        Source(id: "xiphWiki", title: "XiphWiki — VorbisComment guidance", url: URL(string: "https://wiki.xiph.org/VorbisComment")!),
        Source(id: "basic", title: "MusicBrainz Picard — Basic tags", url: URL(string: "https://picard-docs.musicbrainz.org/en/v2.13/variables/tags_basic.html")!),
        Source(id: "advanced", title: "MusicBrainz Picard — Credits and advanced tags", url: URL(string: "https://picard-docs.musicbrainz.org/en/v2.13/variables/tags_advanced.html")!),
        Source(id: "apple", title: "Apple Developer — Media metadata identifiers", url: URL(string: "https://developer.apple.com/documentation/avfoundation/avmetadataidentifier")!),
        Source(id: "microsoftWMYear", title: "Microsoft Learn — Windows Media WM/Year", url: URL(string: "https://learn.microsoft.com/en-us/windows/win32/wmformat/wm-year")!),
        Source(id: "microsoftWMAttributes", title: "Microsoft Learn — Windows Media metadata attributes", url: URL(string: "https://learn.microsoft.com/en-us/windows/win32/wmformat/attribute-list")!),
        Source(id: "rfc3339", title: "RFC Editor — RFC 3339 timestamps", url: URL(string: "https://www.rfc-editor.org/info/rfc3339")!),
        Source(id: "release", title: "MusicBrainz — Release", url: URL(string: "https://musicbrainz.org/doc/Release")!),
        Source(id: "recording", title: "MusicBrainz — Recording", url: URL(string: "https://musicbrainz.org/doc/Recording")!),
        Source(id: "work", title: "MusicBrainz — Work", url: URL(string: "https://musicbrainz.org/doc/Work")!),
        Source(id: "acoustid", title: "AcoustID — Chromaprint", url: URL(string: "https://acoustid.org/chromaprint")!),
        Source(id: "taglib", title: "TagLib — Property mapping", url: URL(string: "https://taglib.org/api/p_propertymapping.html")!),
    ]

    static let entries: [Entry] = [
        Entry(key: .title, purpose: String(localized: "The track’s name."), sourceID: "xiph"),
        Entry(key: .artist, purpose: String(localized: "Who performs this track."), sourceID: "xiph"),
        Entry(key: .album, purpose: String(localized: "The release this track belongs to."), sourceID: "xiph"),
        Entry(key: .albumArtist, purpose: String(localized: "The main credit for the whole album."), sourceID: "basic"),
        Entry(
            key: .year,
            purpose: String(localized: "The file’s Year value. AudioMator keeps it separate from all date fields; changing it does not change Release Date."),
            sourceID: "id3",
            additionalSourceIDs: ["id3Structure", "microsoftWMYear", "apple", "rfc3339"],
            valueGuidance: yearGuidance
        ),
        Entry(
            key: .standaloneDate,
            purpose: String(localized: "A separate Date value already used by some files. Leave it empty unless you need it; AudioMator never fills it from Year or Release Date."),
            sourceID: "xiph",
            additionalSourceIDs: ["xiphWiki", "mapping", "rfc3339"],
            valueGuidance: standaloneDateGuidance
        ),
        Entry(
            key: .releaseDate,
            purpose: String(localized: "When this edition was released."),
            sourceID: "release",
            additionalSourceIDs: ["id3", "id3Structure", "mapping", "rfc3339"],
            valueGuidance: releaseDateGuidance
        ),
        Entry(
            key: .originalReleaseDate,
            purpose: String(localized: "The earliest release date associated with the release."),
            sourceID: "basic",
            additionalSourceIDs: ["id3", "id3Structure", "mapping", "microsoftWMAttributes", "rfc3339"],
            valueGuidance: originalReleaseDateGuidance
        ),
        Entry(key: .track, purpose: String(localized: "This track’s position within its disc."), sourceID: "basic"),
        Entry(key: .trackTotal, purpose: String(localized: "How many tracks are on that disc."), sourceID: "basic"),
        Entry(key: .disc, purpose: String(localized: "This disc’s position in a multi-disc release."), sourceID: "basic"),
        Entry(key: .discTotal, purpose: String(localized: "How many discs the release contains."), sourceID: "basic"),
        Entry(key: .artwork, purpose: String(localized: "Cover images stored with the audio."), sourceID: "id3"),
        Entry(key: .lyrics, purpose: String(localized: "Song words stored as text."), sourceID: "id3"),
        Entry(key: .comment, purpose: String(localized: "Your notes about the track."), sourceID: "xiph"),
        Entry(key: .genre, purpose: String(localized: "A style used for browsing music."), sourceID: "xiph"),
        Entry(key: .composer, purpose: String(localized: "Who wrote the music."), sourceID: "advanced"),
        Entry(key: .conductor, purpose: String(localized: "Who led the ensemble."), sourceID: "advanced"),
        Entry(key: .remixer, purpose: String(localized: "Who created this remix."), sourceID: "id3"),
        Entry(key: .performer, purpose: String(localized: "People and their instruments or performance roles."), sourceID: "advanced"),
        Entry(key: .producer, purpose: String(localized: "Who oversaw the production."), sourceID: "advanced"),
        Entry(key: .engineer, purpose: String(localized: "Who handled the recording or production engineering."), sourceID: "advanced"),
        Entry(key: .lyricist, purpose: String(localized: "Who wrote the words."), sourceID: "advanced"),
        Entry(key: .involvedPeople, purpose: String(localized: "Production credits paired with their roles."), sourceID: "id3"),
        Entry(key: .musicianCredits, purpose: String(localized: "Musicians paired with instruments or roles."), sourceID: "id3"),
        Entry(key: .publisher, purpose: String(localized: "The label or publisher credited for the release."), sourceID: "basic"),
        Entry(key: .copyright, purpose: String(localized: "A copyright notice, including any year and owner."), sourceID: "id3"),
        Entry(key: .encodedBy, purpose: String(localized: "The person or organisation credited with encoding."), sourceID: "id3"),
        Entry(key: .encoderSettings, purpose: String(localized: "The encoder software or settings used."), sourceID: "id3"),
        Entry(key: .isrc, purpose: String(localized: "A recording’s industry identification code."), sourceID: "basic"),
        Entry(key: .barcode, purpose: String(localized: "The release’s retail barcode."), sourceID: "release"),
        Entry(key: .catalogNumber, purpose: String(localized: "The label’s catalogue reference for this release."), sourceID: "release"),
        Entry(key: .asin, purpose: String(localized: "An Amazon catalogue identifier."), sourceID: "basic"),
        Entry(key: .releaseType, purpose: String(localized: "Whether this is an album, single, EP or another release type."), sourceID: "release"),
        Entry(key: .releaseStatus, purpose: String(localized: "Whether the edition is official, promotional, a bootleg or another status."), sourceID: "release"),
        Entry(key: .releaseCountry, purpose: String(localized: "The market where this edition was released."), sourceID: "release"),
        Entry(key: .mediaType, purpose: String(localized: "The original medium, such as CD or vinyl."), sourceID: "release"),
        Entry(key: .work, purpose: String(localized: "The composition performed, such as a symphony."), sourceID: "work"),
        Entry(key: .movement, purpose: String(localized: "The name of a section within a larger work."), sourceID: "mapping"),
        Entry(key: .movementNumber, purpose: String(localized: "This movement’s position within the work."), sourceID: "mapping"),
        Entry(key: .movementCount, purpose: String(localized: "How many movements the work has."), sourceID: "mapping"),
        Entry(key: .discSubtitle, purpose: String(localized: "A name for this disc within a set."), sourceID: "id3"),
        Entry(key: .subtitle, purpose: String(localized: "Additional title information."), sourceID: "id3"),
        Entry(key: .grouping, purpose: String(localized: "A grouping label for organising related tracks. AudioMator keeps this separate from Work and Content Group."), sourceID: "taglib"),
        Entry(key: .contentGroup, purpose: String(localized: "A content-group label. AudioMator stores it separately from Grouping and Work; other editors may name these slots differently."), sourceID: "id3"),
        Entry(key: .artists, purpose: String(localized: "Individual artist names rather than a joined credit."), sourceID: "basic"),
        Entry(key: .mood, purpose: String(localized: "A mood description for browsing."), sourceID: "id3"),
        Entry(key: .language, purpose: String(localized: "The language of the lyrics or vocal work."), sourceID: "advanced"),
        Entry(key: .musicalKey, purpose: String(localized: "The music’s key, such as C minor."), sourceID: "id3"),
        Entry(key: .bpm, purpose: String(localized: "Tempo in beats per minute."), sourceID: "id3"),
        Entry(key: .compilation, purpose: String(localized: "Marks a track as part of a compilation."), sourceID: "basic"),
        Entry(key: .explicitContent, purpose: String(localized: "A content advisory: Not Explicit (0), Explicit (1), Clean (2), or Unset when absent. This describes the content, not its audio quality."), sourceID: "apple"),
        Entry(key: .sortTitle, purpose: String(localized: "An alternative title used for sorting."), sourceID: "id3"),
        Entry(key: .sortArtist, purpose: String(localized: "An alternative artist name used for sorting."), sourceID: "id3"),
        Entry(key: .sortAlbum, purpose: String(localized: "An alternative album name used for sorting."), sourceID: "id3"),
        Entry(key: .sortAlbumArtist, purpose: String(localized: "A sorting name for the album artist."), sourceID: "basic"),
        Entry(key: .sortComposer, purpose: String(localized: "A sorting name for the composer."), sourceID: "advanced"),
        Entry(key: .musicBrainzArtistID, purpose: String(localized: "Identifies a track artist in MusicBrainz."), sourceID: "basic"),
        Entry(key: .musicBrainzAlbumID, purpose: String(localized: "Identifies a particular MusicBrainz release edition."), sourceID: "release"),
        Entry(key: .musicBrainzAlbumArtistID, purpose: String(localized: "Identifies an album artist in MusicBrainz."), sourceID: "basic"),
        Entry(key: .musicBrainzTrackID, purpose: String(localized: "Identifies a MusicBrainz recording, even though the tag name says Track ID."), sourceID: "recording"),
        Entry(key: .musicBrainzReleaseGroupID, purpose: String(localized: "Identifies the release family that groups related editions."), sourceID: "basic"),
        Entry(key: .musicBrainzReleaseTrackID, purpose: String(localized: "Identifies a track entry on a particular release."), sourceID: "basic"),
        Entry(key: .musicBrainzWorkID, purpose: String(localized: "Identifies the underlying musical work in MusicBrainz."), sourceID: "work"),
        Entry(key: .acoustID, purpose: String(localized: "An AcoustID match identifier."), sourceID: "acoustid"),
        Entry(key: .acoustIDFingerprint, purpose: String(localized: "An audio fingerprint used for matching."), sourceID: "acoustid"),
        Entry(key: .musicIPPUID, purpose: String(localized: "An older MusicIP matching identifier; preserve existing values."), sourceID: "basic"),
        Entry(key: .replayGainTrackGain, purpose: String(localized: "A playback volume adjustment for this track."), sourceID: "mapping"),
        Entry(key: .replayGainAlbumGain, purpose: String(localized: "A shared playback adjustment preserving an album’s relative levels."), sourceID: "mapping"),
        Entry(key: .replayGainTrackPeak, purpose: String(localized: "The measured peak level for this track."), sourceID: "mapping"),
        Entry(key: .replayGainAlbumPeak, purpose: String(localized: "The highest measured peak across the album."), sourceID: "mapping"),
        Entry(key: .itunesAlbumID, purpose: String(localized: "The store’s album identifier."), sourceID: "apple"),
        Entry(key: .itunesArtistID, purpose: String(localized: "The store’s artist identifier."), sourceID: "apple"),
        Entry(key: .itunesCatalogID, purpose: String(localized: "The store’s content identifier; not a label catalogue number."), sourceID: "apple"),
        Entry(key: .itunesGenreID, purpose: String(localized: "The store’s numeric genre identifier."), sourceID: "apple"),
        Entry(key: .itunesMediaType, purpose: String(localized: "The store’s media-kind code."), sourceID: "apple"),
        Entry(
            key: .itunesPurchaseDate,
            purpose: String(localized: "When the item was purchased."),
            sourceID: "apple",
            additionalSourceIDs: ["rfc3339"],
            valueGuidance: itunesPurchaseDateGuidance
        ),
        Entry(key: .itunesNorm, purpose: String(localized: "Existing Sound Check data; leave unchanged unless you know its encoding."), sourceID: "apple"),
        Entry(key: .itunesSMPB, purpose: String(localized: "Existing iTunes playback data associated with encoder delay and padding. Preserve it; AudioMator does not interpret its internal encoding."), sourceID: "taglib"),
        Entry(key: .originalAlbum, purpose: String(localized: "The original release’s album name."), sourceID: "id3"),
        Entry(key: .originalArtist, purpose: String(localized: "The original performance’s artist credit."), sourceID: "id3"),
        Entry(key: .artistType, purpose: String(localized: "Whether a MusicBrainz artist is a person, group or another type."), sourceID: "artist"),
        Entry(key: .trackerName, purpose: String(localized: "The tracker software named in a module header."), sourceID: "taglib"),
        Entry(key: .director, purpose: String(localized: "The credited audio or video director."), sourceID: "advanced"),
        Entry(key: .itunesAccount, purpose: String(localized: "The account text stored with an item."), sourceID: "apple"),
        Entry(key: .itunesComposerID, purpose: String(localized: "The store’s composer identifier."), sourceID: "apple"),
        Entry(key: .itunesCountryID, purpose: String(localized: "The store’s storefront identifier, separate from Release Country."), sourceID: "apple"),
        Entry(key: .itunesGapless, purpose: String(localized: "A stored gapless-playback flag; it does not remove silence."), sourceID: "apple"),
        Entry(key: .itunesHDVideo, purpose: String(localized: "A stored high-definition video flag."), sourceID: "apple"),
        Entry(key: .itunesOwner, purpose: String(localized: "The stored owner name."), sourceID: "apple"),
        Entry(key: .rate, purpose: String(localized: "An existing rating value. AudioMator does not offer typed editing because no rating scale is established."), sourceID: "taglib"),
        Entry(key: .showMovement, purpose: String(localized: "Asks compatible players to display work and movement information."), sourceID: "apple"),
        Entry(key: .storeDescription, purpose: String(localized: "A description supplied for a store item."), sourceID: "apple"),
        Entry(key: .tvEpisode, purpose: String(localized: "The episode number."), sourceID: "apple"),
        Entry(key: .tvEpisodeID, purpose: String(localized: "An episode’s text identifier, separate from its number."), sourceID: "apple"),
        Entry(key: .tvNetwork, purpose: String(localized: "The television network."), sourceID: "apple"),
        Entry(key: .tvSeason, purpose: String(localized: "The season number."), sourceID: "apple"),
        Entry(key: .tvShow, purpose: String(localized: "The television series name."), sourceID: "apple"),
        Entry(key: .tvShowSort, purpose: String(localized: "An alternative series name used for sorting."), sourceID: "taglib"),
        Entry(key: .custom, purpose: String(localized: "A field you name yourself. Use it only when no existing field describes the information."), sourceID: "id3"),
    ] + [
        Entry(displayID: "credits", title: String(localized: "Credits"), purpose: String(localized: "Read-only credits supplied by the file’s system metadata. Edit the specific Composer or Lyricist field when that is what you mean.")),
        Entry(displayID: "duration", title: String(localized: "Duration"), purpose: String(localized: "How long the audio plays. Changing a tag does not change its length.")),
        Entry(displayID: "bitrate", title: String(localized: "Bitrate"), purpose: String(localized: "The amount of encoded audio data per second. This is a property of the audio, not an editable tag.")),
        Entry(displayID: "sampleRate", title: String(localized: "Sample Rate"), purpose: String(localized: "Audio samples per second. Changing this requires audio conversion, not a metadata edit.")),
        Entry(displayID: "channels", title: String(localized: "Channels"), purpose: String(localized: "The number of audio channels, such as two for stereo. This is read-only here.")),
        Entry(displayID: "format", title: String(localized: "Format"), purpose: String(localized: "The audio container or codec reported for the file. Renaming a file does not convert its audio.")),
    ]

    private static let yearGuidance = ValueGuidance(
        examples: [
            Example(
                id: "year-yyyy",
                value: "2024",
                note: String(localized: "Four-digit year. Standard for ID3v2.3 and Windows Media; widely accepted across formats.")
            ),
            Example(
                id: "year-date",
                value: "2024-06-02",
                note: String(localized: "Calendar date (or YYYY-MM). Defined by ID3v2.4 and RIFF INFO; practical convention for MP4, Vorbis, and APEv2.")
            ),
            Example(
                id: "year-id3-utc",
                value: "2024-06-01T16:30:00",
                note: String(localized: "ID3v2.4 UTC timestamp (spec format, no Z). Append Z (RFC 3339) as a practical convention for timed text tags.")
            ),
        ],
        formatNote: String(localized: "MP4 and text tags do not fix one date syntax; treat these as reference examples rather than input rules."),
        editingSummary: String(localized: "Edit in the Inspector (visible by default) or Metadata Editor. Year stays independent of Date, Release Date, and Original Release Date, and routes that support full dates or timestamps keep that precision."),
        pickerAvailabilityNote: String(localized: "The Inspector calendar button requires a writable non-ID3v2.3 route on every selected file, and WAV files need a known ID3v2.4 tag. In Metadata Editor, Choose Date… appears for raw YEAR on Vorbis/APEv2 and raw DATE on MP4/ASF; raw YEAR on ID3v2.4 and mixed MP4/ASF + Vorbis/WavPack raw DATE selections stay text-only."),
        pickerTimeFormat: .id3OrUTCText
    )

    private static let standaloneDateGuidance = ValueGuidance(
        examples: [
            Example(
                id: "date-iso",
                value: "2024-06-02",
                note: String(localized: "Practical recommendation (ISO 8601 date, or YYYY / YYYY-MM) from XiphWiki and MusicBrainz Picard.")
            ),
            Example(
                id: "date-rfc3339",
                value: "2024-06-01T16:30:00Z",
                note: String(localized: "Practical RFC 3339 UTC timestamp when storing a time.")
            ),
        ],
        formatNote: String(localized: "Vorbis comments and other text tags leave syntax unspecified; ID3v2.3 uses DDMM and is read-only here."),
        editingSummary: String(localized: "Show Date in Settings → Interface to edit it in the Inspector, or use Metadata Editor. It stays independent of Year, Release Date, and Original Release Date."),
        pickerAvailabilityNote: String(localized: "The Inspector calendar button requires a writable non-ID3v2.3 route on every selected file. In Metadata Editor, Choose Date… appears for raw DATE on Vorbis comments and WavPack; choosing the named Date suggestion when adding a field uses raw DATE on those files and STANDALONEDATE (text-only) elsewhere. Mixed MP4/ASF + Vorbis/WavPack raw DATE selections stay text-only."),
        pickerTimeFormat: .utcTextOnly
    )

    private static let releaseDateGuidance = ValueGuidance(
        examples: [
            Example(
                id: "release-date-iso",
                value: "2024-06-02",
                note: String(localized: "Calendar date (or YYYY / YYYY-MM). Defined by ID3v2.4; practical convention for text tags.")
            ),
            Example(
                id: "release-date-id3-utc",
                value: "2024-06-01T16:30:00",
                note: String(localized: "ID3v2.4 UTC timestamp (spec format, no Z). Append Z (RFC 3339) as a practical convention for timed text tags.")
            ),
        ],
        formatNote: String(localized: "Non-ID3v2.4 writable tags store freeform text with no mandated syntax. Other tools such as MusicBrainz Picard often map edition release dates to Year or Date instead."),
        editingSummary: String(localized: "Edit in the Inspector (visible by default) or Metadata Editor. Release Date stays independent of Year, Date, and Original Release Date."),
        pickerAvailabilityNote: String(localized: "The Inspector calendar button requires a writable non-ID3v2.3 route on every selected file. In Metadata Editor, Choose Date… appears for raw RELEASEDATE on those formats; existing RELEASETIME rows display as Release Date without renaming their key and stay text-only."),
        pickerTimeFormat: .id3OrUTCText
    )

    private static let originalReleaseDateGuidance = ValueGuidance(
        examples: [
            Example(
                id: "orig-date-iso",
                value: "1973-03-01",
                note: String(localized: "Calendar date (or YYYY / YYYY-MM). Defined by ID3v2.4 and used by MusicBrainz Picard.")
            ),
            Example(
                id: "orig-date-year",
                value: "1973",
                note: String(localized: "Four-digit year. Defined for ID3v2.3 (read-only here) and conventional for Windows Media.")
            ),
            Example(
                id: "orig-date-id3-utc",
                value: "1973-03-01T00:00:00",
                note: String(localized: "ID3v2.4 UTC timestamp (spec format, no Z). Append Z (RFC 3339) as a practical convention for timed text tags.")
            ),
        ],
        formatNote: String(localized: "Windows Media defines a text string traditionally holding a four-digit year; MP4, Vorbis, and APEv2 text tags leave syntax unspecified."),
        editingSummary: String(localized: "Show Original Release Date in Settings → Interface to edit it in the Inspector, or use Metadata Editor. It stays independent of Year, Date, and Release Date."),
        pickerAvailabilityNote: String(localized: "The Inspector calendar button requires a writable non-ID3v2.3 route on every selected file. In Metadata Editor, Choose Date… appears for raw ORIGINALDATE except on ASF/WMA; ASF/WMA raw keys and ORIGINAL YEAR stay text-only."),
        pickerTimeFormat: .id3OrUTCText
    )

    private static let itunesPurchaseDateGuidance = ValueGuidance(
        examples: [
            Example(
                id: "purchase-rfc3339",
                value: "2024-06-01T16:30:00Z",
                note: String(localized: "Practical RFC 3339 UTC timestamp recommendation for text tags (ID3v2.4, Vorbis, APEv2).")
            ),
            Example(
                id: "purchase-date",
                value: "2024-06-02",
                note: String(localized: "Practical calendar-date recommendation for text tags when only the date is known.")
            ),
        ],
        formatNote: String(localized: "Apple’s AVFoundation documentation leaves the native MP4 purd syntax unspecified; store files and tools vary in practice (for example, space-separated date-time strings or ISO 8601 UTC). Conventions for text tags and native MP4 purd do not govern each other."),
        editingSummary: String(localized: "Edit in Metadata Editor only—this field is not an Inspector row and stays separate from all release and recording date fields."),
        pickerAvailabilityNote: String(localized: "Choose Date… appears only for raw ITUNESPURCHASEDATE when every selected file uses ID3v2.4, Vorbis comments, or APEv2. It does not appear for MP4/M4A—where raw ITUNESPURCHASEDATE writes a separate freeform atom rather than native purd—or for existing ID3v2.3 tags, custom keys, or mixed selections with an ineligible file."),
        pickerTimeFormat: .utcTextOnly
    )
}
