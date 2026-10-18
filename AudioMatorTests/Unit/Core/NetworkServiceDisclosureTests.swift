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
        // Independent inventory, reviewed against request builders and page policy.
        let productionHosts: Set<String> = [
            "itunes.apple.com", "is5-ssl.mzstatic.com", "a5.mzstatic.com",
            "musicbrainz.org", "lrclib.net", "api.github.com", "apple.com"
        ]

        XCTAssertEqual(disclosedHosts, productionHosts)
        XCTAssertTrue(NetworkServiceDisclosure.allDisclosures.contains { $0.id == .lrclib })
    }
}
