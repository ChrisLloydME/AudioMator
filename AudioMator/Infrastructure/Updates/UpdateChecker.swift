import Foundation

struct UpdateReleaseMetadata: Equatable, Sendable {
    let version: ReleaseVersion
    let tagName: String
    let displayName: String
    let releaseURL: URL
}

enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(UpdateReleaseMetadata, currentVersion: String)
    case upToDate(currentVersion: String, latestVersion: String)
}

enum UpdateCheckError: LocalizedError, Equatable {
    case missingCurrentVersion
    case missingReleaseVersion
    case malformedReleaseResponse
    case rateLimited
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCurrentVersion:
            return "AudioMator could not read the current app version."
        case .missingReleaseVersion:
            return "GitHub did not return a usable release version."
        case .malformedReleaseResponse:
            return "GitHub returned release information AudioMator could not read."
        case .rateLimited:
            return "GitHub rate limited the update check. Please try again later."
        case .requestFailed(let message):
            return message
        }
    }
}

protocol UpdateReleaseProviding: Sendable {
    func fetchLatestRelease() async throws -> UpdateReleaseMetadata
}

struct UpdateChecker: Sendable {
    private let releaseProvider: any UpdateReleaseProviding
    private let currentVersionProvider: @Sendable () -> ReleaseVersion?

    init(
        releaseProvider: any UpdateReleaseProviding = GitHubUpdateReleaseClient(),
        currentVersionProvider: @escaping @Sendable () -> ReleaseVersion? = {
            guard let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            else {
                return nil
            }
            return ReleaseVersion(marketingVersion: marketingVersion, buildNumber: buildNumber)
        }
    ) {
        self.releaseProvider = releaseProvider
        self.currentVersionProvider = currentVersionProvider
    }

    func checkForUpdates() async throws -> UpdateCheckResult {
        guard let currentVersion = currentVersionProvider() else {
            throw UpdateCheckError.missingCurrentVersion
        }

        let currentVersionString = currentVersion.displayString

        let latestRelease = try await releaseProvider.fetchLatestRelease()

        if latestRelease.version > currentVersion {
            return .updateAvailable(latestRelease, currentVersion: currentVersionString)
        }

        return .upToDate(currentVersion: currentVersionString, latestVersion: latestRelease.tagName)
    }
}

private extension ReleaseVersion {
    var displayString: String {
        "\(marketingVersion.numbers.map(String.init).joined(separator: ".")) (\(buildNumber))"
    }
}
