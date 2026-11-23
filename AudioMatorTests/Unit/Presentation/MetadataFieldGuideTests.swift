import XCTest
import TagLibAudioMetadata
@testable import AudioMator

nonisolated final class MetadataFieldGuideTests: XCTestCase {
    func testEveryPackageFieldHasOneExplanationAndAnOfficialSource() {
        let entries = MetadataFieldGuide.entries
        XCTAssertEqual(entries.count, MetadataFieldKey.allCases.count + 6)
        XCTAssertEqual(Set(entries.compactMap(\.key)), Set(MetadataFieldKey.allCases))
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(Set(entries.filter { $0.key == nil }.map(\.id)), ["credits", "duration", "bitrate", "sampleRate", "channels", "format"])
        XCTAssertEqual(Set(entries.filter { $0.key == nil }.map(\.title)).count, 6)
        let sources = Dictionary(uniqueKeysWithValues: MetadataFieldGuide.sources.map { ($0.id, $0) })
        let officialHosts: Set<String> = [
            "id3.org",
            "www.xiph.org",
            "wiki.xiph.org",
            "picard-docs.musicbrainz.org",
            "musicbrainz.org",
            "developer.apple.com",
            "acoustid.org",
            "taglib.org",
            "learn.microsoft.com",
            "www.rfc-editor.org",
        ]
        for entry in entries {
            XCTAssertFalse(entry.purpose.isEmpty, entry.id)
            if entry.key != nil { XCTAssertNotNil(entry.schema, entry.id) }
            XCTAssertEqual(Set(entry.sourceIDs).count, entry.sourceIDs.count, entry.id)
            XCTAssertEqual(entry.resolvedSources.count, entry.sourceIDs.count, entry.id)
            for sourceID in entry.sourceIDs {
                let source = sources[sourceID]
                XCTAssertNotNil(source, "\(entry.id): \(sourceID)")
                XCTAssertEqual(source?.url.scheme, "https", "\(entry.id): \(sourceID)")
                XCTAssertTrue(officialHosts.contains(source?.url.host ?? ""), "\(entry.id): \(sourceID)")
            }
        }
    }

    @MainActor
    func testReferenceLinksMatchThePrivacyDisclosure() {
        let domains = Set(MetadataFieldGuide.sources.compactMap { $0.url.host })
        let disclosure = NetworkServiceDisclosure.allDisclosures.first { $0.id == .metadataHelpReferences }
        XCTAssertEqual(domains, Set(disclosure?.domains ?? []))
    }

    @MainActor
    func testSearchFindsDisplayNamesNativeKeysAndIndependentDates() throws {
        func matches(_ query: String) -> Set<MetadataFieldKey> {
            Set(MetadataFieldGuide.entries.filter { $0.matches(query) }.compactMap(\.key))
        }
        XCTAssertTrue(matches("©day").contains(.year))
        XCTAssertTrue(matches("STANDALONEDATE").contains(.standaloneDate))
        XCTAssertTrue(matches("TDRL").contains(.releaseDate))
        XCTAssertTrue(matches(" Total   Tracks ").contains(.trackTotal))
        XCTAssertTrue(matches("MusicBrainz recording").contains(.musicBrainzTrackID))
        XCTAssertTrue(matches("Choose Date").isSuperset(of: [.year, .standaloneDate, .releaseDate, .originalReleaseDate, .itunesPurchaseDate]))
        XCTAssertTrue(matches("Tag Value Preview").isSuperset(of: [.year, .standaloneDate, .releaseDate, .originalReleaseDate, .itunesPurchaseDate]))
        XCTAssertTrue(matches("RFC 3339").isSuperset(of: [.year, .standaloneDate, .releaseDate, .originalReleaseDate, .itunesPurchaseDate]))
        XCTAssertTrue(matches("purd").contains(.itunesPurchaseDate))
        XCTAssertTrue(matches("WM/Year").contains(.year))
        XCTAssertEqual(matches("an-impossible-field-query"), [])
        XCTAssertEqual(matches(" ").count, MetadataFieldKey.allCases.count)
        let date = try XCTUnwrap(MetadataFieldGuide.entries.first { $0.key == .standaloneDate })
        XCTAssertTrue(date.purpose.contains("never fills"))
        let trackID = try XCTUnwrap(MetadataFieldGuide.entries.first { $0.key == .musicBrainzTrackID })
        XCTAssertTrue(trackID.purpose.contains("recording"))
    }

    @MainActor
    func testDateTimeEntriesProvideDetailedGuidanceWhileKeepingAddFieldPurposesConcise() throws {
        let dateKeys: Set<MetadataFieldKey> = [
            .year,
            .standaloneDate,
            .releaseDate,
            .originalReleaseDate,
            .itunesPurchaseDate,
        ]

        let guidedKeys = Set(MetadataFieldGuide.entries.filter { $0.valueGuidance != nil }.compactMap(\.key))
        XCTAssertEqual(guidedKeys, dateKeys)

        for key in dateKeys {
            let entry = try XCTUnwrap(MetadataFieldGuide.entries.first { $0.key == key })
            let guidance = try XCTUnwrap(entry.valueGuidance, key.rawValue)
            XCTAssertFalse(guidance.examples.isEmpty, key.rawValue)
            XCTAssertFalse(guidance.formatNote.isEmpty, key.rawValue)
            XCTAssertFalse(guidance.editingSummary.isEmpty, key.rawValue)
            XCTAssertFalse(guidance.pickerAvailabilityNote.isEmpty, key.rawValue)
            XCTAssertTrue(guidance.sharedEditingNote.contains("Tag Value Preview"), key.rawValue)
            XCTAssertTrue(guidance.sharedEditingNote.contains("Year & Month"), key.rawValue)
            XCTAssertTrue(guidance.sharedEditingNote.contains("Full Date"), key.rawValue)
            XCTAssertTrue(guidance.sharedEditingNote.contains("Apply"), key.rawValue)

            // Reused Add Field suggestions stay concise and separate from detail guidance.
            let suggestion = try XCTUnwrap(MetadataFieldSuggestion.allSupported.first {
                $0.displayName == entry.title
            })
            XCTAssertEqual(suggestion.detailText, entry.purpose)
            XCTAssertFalse(suggestion.detailText.contains("Tag Value Preview"), key.rawValue)
            XCTAssertFalse(suggestion.detailText.contains("Choose Date"), key.rawValue)
        }

        // iTunes Purchase Date must not imply an Inspector row or an MP4 purd picker.
        let purchaseEntry = try XCTUnwrap(MetadataFieldGuide.entries.first { $0.key == .itunesPurchaseDate })
        let purchaseGuidance = try XCTUnwrap(purchaseEntry.valueGuidance)
        XCTAssertTrue(purchaseGuidance.editingSummary.contains("not an Inspector row"))
        XCTAssertTrue(purchaseGuidance.pickerAvailabilityNote.contains("does not appear for MP4/M4A"))
        XCTAssertTrue(purchaseGuidance.pickerAvailabilityNote.contains("purd"))
        XCTAssertFalse(purchaseGuidance.pickerAvailabilityNote.contains("calendar button"))
    }
}
