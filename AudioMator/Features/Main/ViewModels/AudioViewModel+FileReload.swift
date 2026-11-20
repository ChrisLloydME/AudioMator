import Foundation
import TagLibAudioMetadata

struct SelectedFileReloadFailure: Equatable {
    let fileID: UUID
    let url: URL
    let reason: String
}

extension AudioViewModel {
    /// Explicit reload requires the UI to resolve an existing dirty draft first.
    func reloadSelectedFilesFromDisk() async {
        guard !hasUnsavedInspectorChanges else { return }
        await refreshSelectedFiles(forceReload: true)
    }

    /// Reconcile selected files when returning from another app. Clean drafts
    /// follow the disk; dirty drafts keep their original expected revision.
    func refreshSelectedFilesAfterActivation() async {
        await refreshSelectedFiles(forceReload: false)
    }

    private func refreshSelectedFiles(forceReload: Bool) async {
        guard !isReloadingSelectedFiles, metadataSaveProgress == nil else { return }
        let targets = selectedFiles
        guard !targets.isEmpty else { return }
        isReloadingSelectedFiles = true
        let progressToken: UUID? = forceReload
            ? beginMetadataSaveProgress(
                title: String(localized: "Reloading Files"),
                subtitle: String(localized: "Reading from disk…"),
                totalUnitCount: targets.count
            )
            : nil
        defer {
            isReloadingSelectedFiles = false
            if let progressToken { endMetadataSaveProgress(token: progressToken) }
        }

        let pipeline = metadataPipeline
        var failures: [String] = []
        var failureIdentities: [SelectedFileReloadFailure] = []
        var replacementReviews: [PendingReplacementFileReview] = []
        for (index, target) in targets.enumerated() {
            guard !Task.isCancelled else { break }
            if let progressToken {
                updateMetadataSaveProgress(
                    token: progressToken,
                    subtitle: target.url.lastPathComponent,
                    completedUnitCount: index
                )
            }
            do {
                let initialGeneration = fileModelRefreshGeneration(for: target.id)
                let pendingReview = try await fileMutationCoordinator.withExclusiveAccess(to: [target.url]) { () async throws -> PendingReplacementFileReview? in
                    let refreshed = try await withAsyncTimeout(
                        .seconds(60), operationName: String(localized: "Reloading the file"), priority: .utility
                    ) {
                        if !forceReload,
                           let fingerprint = target.fileFingerprint,
                           let version = target.metadataFileVersion,
                           fingerprint == (try AudioFileFingerprint.capture(at: target.url)),
                           version == (try pipeline.metadataFileVersion(at: target.url)) {
                            return nil as AudioFile?
                        }
                        return try await pipeline.loadAudioFile(at: target.url, id: target.id)
                    }
                    guard let refreshed else { return nil }
                    // Apply while still reserved, and reject a late read if the
                    // source was removed, moved or independently refreshed.
                    return await MainActor.run {
                        guard let current = self.committedFile(withID: target.id),
                              current.url == target.url,
                              self.fileModelRefreshGeneration(for: target.id) == initialGeneration else {
                            return nil
                        }
                        let accepted = self.replaceLoadedFile(
                            refreshed, refreshGeneration: self.makeFileModelRefreshGeneration(),
                            clearing: forceReload ? .explicitAuthorizedReload : nil
                        )
                        guard forceReload,
                              accepted,
                              let observation = refreshed.observation else {
                            return nil
                        }
                        return self.makePendingReplacementFileReviewIfNeeded(
                            for: refreshed,
                            observation: observation
                        )
                    }
                }
                if let pendingReview {
                    replacementReviews.append(pendingReview)
                }
            } catch is CancellationError {
                break
            } catch {
                failureIdentities.append(.init(fileID: target.id, url: target.url, reason: error.localizedDescription))
                failures.append(String(localized: "“\(target.url.lastPathComponent)” couldn’t be reloaded.\nDetails: \((error as NSError).localizedDescription)"))
            }
        }

        if forceReload, !Task.isCancelled, !replacementReviews.isEmpty {
            setPendingReplacementFileReviews(replacementReviews)
        }

        guard !Task.isCancelled, Set(targets.map(\.id)) == selectedAudioIDs else { return }
        let shouldReport = forceReload || failureIdentities != lastAutomaticReloadFailures
        lastAutomaticReloadFailures = failureIdentities
        if shouldReport, !failures.isEmpty {
            presentMetadataWriteHUD(
                style: forceReload && failures.count == targets.count ? .failure : .warning,
                title: forceReload ? String(localized: "Files Couldn’t Be Reloaded")
                    : String(localized: "Automatic Refresh Couldn’t Be Completed"),
                subtitle: failures.joined(separator: "\n"),
                summary: String(localized: "Files that couldn’t be reloaded: \(failures.count)."),
                details: failures.joined(separator: "\n\n")
            )
        }
    }

    /// Completes explicit user acceptance of replacement files surfaced by
    /// Reload from Disk. Each file is re-read under its path reservation and
    /// accepted only if its directory entry still matches the reviewed identity;
    /// `.journalPending` decisions are never cleared here.
    func acceptPendingReplacementFiles() async {
        guard !hasUnsavedInspectorChanges else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Unsaved Changes"),
                subtitle: String(localized: "Save or discard the pending inspector edits before accepting a replacement file.")
            )
            return
        }
        guard !isReloadingSelectedFiles, metadataSaveProgress == nil else { return }
        let reviews = pendingReplacementFileReviews
        guard !reviews.isEmpty else { return }
        dismissPendingReplacementFileReviews()

        isReloadingSelectedFiles = true
        let progressToken = beginMetadataSaveProgress(
            title: String(localized: "Accepting Replacement Files"),
            subtitle: String(localized: "Verifying on disk…"),
            totalUnitCount: reviews.count
        )
        defer {
            isReloadingSelectedFiles = false
            endMetadataSaveProgress(token: progressToken)
        }

        let pipeline = metadataPipeline
        var failures: [String] = []
        for (index, review) in reviews.enumerated() {
            guard !Task.isCancelled else { break }
            updateMetadataSaveProgress(
                token: progressToken,
                subtitle: review.fileName,
                completedUnitCount: index
            )
            guard let current = committedFile(withID: review.fileID),
                  FileSystemPathSemantics.key(for: current.url) == FileSystemPathSemantics.key(for: review.url) else {
                failures.append(String(localized: "“\(review.fileName)” is no longer at that location. Choose Reload from Disk and review it again."))
                continue
            }
            guard !hasJournalRecoveryDecision(for: review.fileID) else {
                failures.append(String(localized: "“\(review.fileName)” still requires Rename Recovery before it can be edited."))
                continue
            }
            do {
                let failureMessage = try await fileMutationCoordinator.withExclusiveAccess(to: [review.url]) { () async throws -> String? in
                    let fresh = try await withAsyncTimeout(
                        .seconds(60),
                        operationName: String(localized: "Verifying replacement file"),
                        priority: .utility
                    ) {
                        try await pipeline.loadAudioFile(at: review.url, id: review.fileID)
                    }
                    guard let observation = fresh.observation else {
                        return String(localized: "“\(review.fileName)” couldn’t be verified on disk. Editing remains paused.")
                    }
                    let liveIdentity = EntryIdentityKey(fingerprint: observation.fingerprint)
                    guard FileSystemPathSemantics.key(for: observation.url) == FileSystemPathSemantics.key(for: review.url),
                          review.observedIdentity.matches(liveIdentity) else {
                        return String(localized: "“\(review.fileName)” changed again before it was accepted. Choose Reload from Disk to review the current file.")
                    }
                    return await MainActor.run {
                        guard let committed = self.committedFile(withID: review.fileID),
                              FileSystemPathSemantics.key(for: committed.url) == FileSystemPathSemantics.key(for: review.url),
                              !self.hasJournalRecoveryDecision(for: review.fileID) else {
                            return String(localized: "“\(review.fileName)” couldn’t be accepted because its state changed. Choose Reload from Disk to review it again.")
                        }
                        self.replaceLoadedFile(
                            fresh,
                            refreshGeneration: self.makeFileModelRefreshGeneration(),
                            clearing: .explicitReplacementAcceptance(
                                url: review.url,
                                observedIdentity: review.observedIdentity
                            )
                        )
                        return nil
                    }
                }
                if let failureMessage {
                    failures.append(failureMessage)
                }
            } catch is CancellationError {
                break
            } catch {
                failures.append(String(localized: "“\(review.fileName)” couldn’t be verified.\nDetails: \((error as NSError).localizedDescription)"))
            }
        }

        if !Task.isCancelled, !failures.isEmpty {
            presentMetadataWriteHUD(
                style: failures.count == reviews.count ? .failure : .warning,
                title: String(localized: "Replacement File Couldn’t Be Accepted"),
                subtitle: failures.joined(separator: "\n"),
                summary: String(localized: "Files that couldn’t be accepted: \(failures.count)."),
                details: failures.joined(separator: "\n\n")
            )
        }
    }
}
