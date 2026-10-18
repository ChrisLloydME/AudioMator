import XCTest
@testable import AudioMator

nonisolated final class TestHostIsolationTests: XCTestCase {
    func testHostFlagCannotEnableIsolationInReleaseAndCustomDebugRunnerIsRecognized() {
        XCTAssertFalse(AudioMatorTestHost.shouldEnable(environment: ["AUDIOMATOR_TEST_HOST": "1"], isDebugBuild: false))
        XCTAssertFalse(AudioMatorTestHost.shouldEnable(environment: ["XCTestConfigurationFilePath": "/tmp/test"], isDebugBuild: false))
        XCTAssertTrue(AudioMatorTestHost.shouldEnable(environment: ["XCTestConfigurationFilePath": "/tmp/test"], isDebugBuild: true))
        XCTAssertFalse(AudioMatorTestHost.shouldEnable(environment: [:], isDebugBuild: true))
    }

    @MainActor
    func testActualAppHostUsesIsolatedStoresAndPresentationPreferences() throws {
        let host = try XCTUnwrap(AudioMatorTestHost.launchedViewModel)
        XCTAssertNotNil(AudioMatorTestHost.launchedSharedState)
        XCTAssertTrue(host.watchedFolders.isEmpty)
        XCTAssertTrue(host.fileAccessGrants.isEmpty)
        XCTAssertTrue(host.saveIssueLogStore.entries.isEmpty)
        XCTAssertTrue(host.conflictPolicyDefaults === AudioMatorTestHost.preferences)
        XCTAssertFalse(host.conflictPolicyDefaults === UserDefaults.standard)
        let original = UserDefaults.standard.object(forKey: settingsSelectedTabDefaultsKey) as? String
        AudioMatorTestHost.preferences.set("test-isolated-value", forKey: settingsSelectedTabDefaultsKey)
        defer { AudioMatorTestHost.preferences.removeObject(forKey: settingsSelectedTabDefaultsKey) }
        XCTAssertEqual(UserDefaults.standard.object(forKey: settingsSelectedTabDefaultsKey) as? String, original)
    }

    @MainActor
    func testSchemeEnablesIsolatedHostAndFactoryHasNoRestoredState() {
        XCTAssertTrue(AudioMatorTestHost.isEnabled, "Run app-hosted tests using the AudioMator scheme's Test action")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: TagLibAudioMetadataPipeline())
        XCTAssertTrue(viewModel.watchedFolders.isEmpty)
        XCTAssertTrue(viewModel.fileAccessGrants.isEmpty)
        XCTAssertTrue(viewModel.saveIssueLogStore.entries.isEmpty)
        XCTAssertFalse(viewModel.conflictPolicyDefaults === UserDefaults.standard)
    }
}
