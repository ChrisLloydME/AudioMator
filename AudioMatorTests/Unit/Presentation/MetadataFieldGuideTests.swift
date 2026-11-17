import XCTest
import TagLibAudioMetadata
@testable import AudioMator

@MainActor
final class MetadataFieldGuideTests: XCTestCase {
    func testEveryPackageFieldHasOneExplanationAndAnOfficialSource() {
        let entries = MetadataFieldGuide.entries
        XCTAssertEqual(entries.count, MetadataFieldKey.allCases.count + 6)
        XCTAssertEqual(Set(entries.compactMap(\.key)), Set(MetadataFieldKey.allCases))
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        XCTAssertEqual(Set(entries.filter { $0.key == nil }.map(\.id)), ["credits", "duration", "bitrate", "sampleRate", "channels", "format"])
        XCTAssertEqual(Set(entries.filter { $0.key == nil }.map(\.title)).count, 6)
        let sources = Dictionary(uniqueKeysWithValues: MetadataFieldGuide.sources.map { ($0.id, $0) })
        let officialHosts: Set<String> = ["id3.org", "www.xiph.org", "picard-docs.musicbrainz.org", "musicbrainz.org", "developer.apple.com", "acoustid.org", "taglib.org"]
        for entry in entries {
            XCTAssertFalse(entry.purpose.isEmpty, entry.id)
            if entry.key != nil { XCTAssertNotNil(entry.schema, entry.id) }
            let source = sources[entry.sourceID]
            XCTAssertNotNil(source, entry.id)
            XCTAssertEqual(source?.url.scheme, "https")
            XCTAssertTrue(officialHosts.contains(source?.url.host ?? ""), entry.id)
        }
    }

    func testReferenceLinksMatchThePrivacyDisclosure() {
        let domains = Set(MetadataFieldGuide.sources.compactMap { $0.url.host })
        let disclosure = NetworkServiceDisclosure.allDisclosures.first { $0.id == .metadataHelpReferences }
        XCTAssertEqual(domains, Set(disclosure?.domains ?? []))
    }

    func testSearchFindsDisplayNamesNativeKeysAndIndependentDates() throws {
        func matches(_ query: String) -> Set<MetadataFieldKey> {
            Set(MetadataFieldGuide.entries.filter { $0.matches(query) }.compactMap(\.key))
        }
        XCTAssertTrue(matches("©day").contains(.year))
        XCTAssertTrue(matches("STANDALONEDATE").contains(.standaloneDate))
        XCTAssertTrue(matches("TDRL").contains(.releaseDate))
        XCTAssertTrue(matches(" Total   Tracks ").contains(.trackTotal))
        XCTAssertTrue(matches("MusicBrainz recording").contains(.musicBrainzTrackID))
        XCTAssertEqual(matches("an-impossible-field-query"), [])
        XCTAssertEqual(matches(" ").count, MetadataFieldKey.allCases.count)
        let date = try XCTUnwrap(MetadataFieldGuide.entries.first { $0.key == .standaloneDate })
        XCTAssertTrue(date.purpose.contains("never fills"))
        let trackID = try XCTUnwrap(MetadataFieldGuide.entries.first { $0.key == .musicBrainzTrackID })
        XCTAssertTrue(trackID.purpose.contains("recording"))
    }
}
