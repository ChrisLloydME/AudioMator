import XCTest
@testable import AudioMator

nonisolated final class NetworkServiceDisclosureTests: XCTestCase {
    @MainActor
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

    @MainActor
    func testRegistryMatchesExpectedClientAndProviderPageDomains() {
        let disclosures = NetworkServiceDisclosure.allDisclosures
        // MetadataFieldGuideTests verifies the reference entry against the guide's URLs.
        let disclosedHosts = Set(disclosures.filter { $0.id != .metadataHelpReferences }.flatMap(\.domains))
        // Independent inventory from request builders and provider page navigation policy.
        let expectedHosts: Set<String> = [
            "itunes.apple.com", "is5-ssl.mzstatic.com", "a5.mzstatic.com",
            "musicbrainz.org", "lrclib.net", "api.github.com", "apple.com",
        ]
        let differences = [
            "Missing hosts: \(expectedHosts.subtracting(disclosedHosts).sorted())",
            "Unexpected hosts: \(disclosedHosts.subtracting(expectedHosts).sorted())",
        ]
        XCTAssertEqual(disclosedHosts, expectedHosts, differences.joined(separator: "\n"))
    }
}
