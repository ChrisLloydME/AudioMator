import Foundation

enum WelcomeSplashProgress {
    static let completionKey = "hasCompletedWelcomeSplash"
    static let completedVersionKey = "completedWelcomeSplashVersion"
    static let currentVersion = 2

    static func shouldPresent(hasCompleted: Bool, completedVersion: Int) -> Bool {
        !hasCompleted || completedVersion < currentVersion
    }
}
