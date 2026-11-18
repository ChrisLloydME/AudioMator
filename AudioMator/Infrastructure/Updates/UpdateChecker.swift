import Foundation

struct UpdateReleaseMetadata: Equatable, Sendable {
    let version: ReleaseVersion
    let tagName: String
}

enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(UpdateReleaseMetadata, currentVersion: String)
    case upToDate(currentVersion: String, latestVersion: String)
    case aheadOfLatest(currentVersion: String, latestVersion: String)
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
            return String(localized: "The current app version couldn’t be determined, so updates can’t be checked.")
        case .missingReleaseVersion:
            return String(localized: "The latest GitHub release doesn't include a usable version number. Check GitHub Releases manually.")
        case .malformedReleaseResponse:
            return String(localized: "The version information from GitHub couldn’t be read. Check GitHub Releases manually.")
        case .rateLimited:
            return String(localized: "GitHub is limiting update checks. Wait a while before checking again.")
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

        if currentVersion > latestRelease.version {
            return .aheadOfLatest(
                currentVersion: currentVersionString,
                latestVersion: latestRelease.tagName
            )
        }

        return .upToDate(currentVersion: currentVersionString, latestVersion: latestRelease.tagName)
    }
}

private extension ReleaseVersion {
    var displayString: String {
        "\(marketingVersion.numbers.map(String.init).joined(separator: ".")) (\(buildNumber))"
    }
}
