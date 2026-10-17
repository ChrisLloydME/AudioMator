import XCTest
@testable import AudioMator

@MainActor
final class TestHostIsolationTests: XCTestCase {
    func testSchemeEnablesIsolatedHostAndFactoryHasNoRestoredState() {
        XCTAssertTrue(AudioMatorTestHost.isEnabled, "Run app-hosted tests using the AudioMator scheme's Test action")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: TagLibAudioMetadataPipeline())
        XCTAssertTrue(viewModel.watchedFolders.isEmpty)
        XCTAssertTrue(viewModel.fileAccessGrants.isEmpty)
        XCTAssertTrue(viewModel.saveIssueLogStore.entries.isEmpty)
        XCTAssertFalse(viewModel.conflictPolicyDefaults === UserDefaults.standard)
    }
}
