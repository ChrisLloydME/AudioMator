import Foundation

/// Enabled only by the scheme's Test action. Release builds always run normally.
nonisolated enum AudioMatorTestHost {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["AUDIOMATOR_TEST_HOST"] == "1"
        #else
        false
        #endif
    }
}
