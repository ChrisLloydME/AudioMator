#if os(macOS)
import AppKit
import Foundation

@MainActor
final class UpdateCheckPresenter {
    static let shared = UpdateCheckPresenter(updateChecker: UpdateChecker())

    private static let releasesPageURL = URL(string: "https://github.com/ChrisLloydME/AudioMator/releases")!

    private let updateChecker: UpdateChecker
    private var task: Task<Void, Never>?

    init(updateChecker: UpdateChecker) {
        self.updateChecker = updateChecker
    }

    func checkForUpdates() {
        guard task == nil else { return }

        task = Task { [weak self] in
            do {
                let result = try await self?.updateChecker.checkForUpdates()
                await MainActor.run {
                    self?.task = nil
                    if let result {
                        self?.present(result)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.task = nil
                    self?.presentFailure(error)
                }
            }
        }
    }

    private func present(_ result: UpdateCheckResult) {
        switch result {
        case .updateAvailable(let release, let currentVersion):
            let alert = NSAlert()
            alert.messageText = "AudioMator \(release.tagName) Is Available"
            alert.informativeText = "You are using AudioMator \(currentVersion). AudioMator can open GitHub Releases so you can download and install the update manually. AudioMator will not install updates silently."
            alert.addButton(withTitle: "Open GitHub Releases")
            alert.addButton(withTitle: "Not Now")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(Self.releasesPageURL)
            }

        case .upToDate(let currentVersion, _):
            let alert = NSAlert()
            alert.messageText = "AudioMator Is Up to Date"
            alert.informativeText = "You are using AudioMator \(currentVersion), which matches the latest published GitHub release."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Check for Updates"
        alert.informativeText = "\(error.localizedDescription)\n\nAudioMator could not retrieve release information from GitHub. You can still check GitHub Releases manually."
        alert.addButton(withTitle: "Open GitHub Releases")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }
}
#endif
