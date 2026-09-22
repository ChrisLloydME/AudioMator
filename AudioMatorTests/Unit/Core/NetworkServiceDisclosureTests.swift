import XCTest
@testable import AudioMator

final class NetworkServiceDisclosureTests: XCTestCase {
    func testEveryProductionNetworkServiceHasOneCompleteDisclosure() {
        let disclosures = NetworkServiceDisclosure.allDisclosures

        XCTAssertEqual(Set(disclosures.map(\.id)), Set(NetworkServiceDisclosure.Entry.ID.allCases))
        XCTAssertEqual(disclosures.count, NetworkServiceDisclosure.Entry.ID.allCases.count)
        for disclosure in disclosures {
            XCTAssertFalse(disclosure.title.isEmpty, disclosure.id.rawValue)
            XCTAssertFalse(disclosure.domains.isEmpty, disclosure.id.rawValue)
            XCTAssertTrue(disclosure.domains.allSatisfy { !$0.isEmpty }, disclosure.id.rawValue)
            XCTAssertFalse(disclosure.sentDataSummary.isEmpty, disclosure.id.rawValue)
            XCTAssertFalse(disclosure.purpose.isEmpty, disclosure.id.rawValue)
        }
    }

    func testRegistryCoversEveryHostUsedByNetworkClients() {
        let disclosedHosts = Set(NetworkServiceDisclosure.allDisclosures.flatMap(\.domains))
        let productionHosts = Set(
            NetworkServiceDisclosure.iTunesArtwork.domains
                + NetworkServiceDisclosure.MusicBrainz.domains
                + NetworkServiceDisclosure.LRCLIB.domains
                + [NetworkServiceDisclosure.ReleaseNotes.host]
                + NetworkServiceDisclosure.SoftwareUpdates.domains
        )

        XCTAssertEqual(disclosedHosts, productionHosts)
        XCTAssertTrue(NetworkServiceDisclosure.allDisclosures.contains { $0.id == .lrclib })
    }
}
