import Foundation

/// Debug test hosts share isolated preferences across app state, views and commands.
/// Release builds always use production preferences, regardless of environment.
nonisolated enum AudioMatorTestHost {
    static func shouldEnable(environment: [String: String], isDebugBuild: Bool) -> Bool {
        isDebugBuild && (environment["AUDIOMATOR_TEST_HOST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil)
    }

    static var isEnabled: Bool {
        #if DEBUG
        shouldEnable(environment: ProcessInfo.processInfo.environment, isDebugBuild: true)
        #else
        false
        #endif
    }

    static let preferences: UserDefaults = isEnabled
        ? UserDefaults(suiteName: "AudioMatorTestHost.\(UUID().uuidString)")!
        : .standard

    // Weak diagnostics let XCTest inspect the actual app-owned objects, without
    // constructing a second app or retaining any production state globally.
    @MainActor static weak var launchedViewModel: AudioViewModel?
    @MainActor static weak var launchedSharedState: SharedState?
}
