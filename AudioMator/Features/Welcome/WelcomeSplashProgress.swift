import Foundation

enum WelcomeSplashProgress {
    static let completionKey = "hasCompletedWelcomeSplash"
    static let completedVersionKey = "completedWelcomeSplashVersion"
    static let currentVersion = 3

    static func shouldPresent(hasCompleted: Bool, completedVersion: Int) -> Bool {
        !hasCompleted || completedVersion < currentVersion
    }
}
