import Foundation

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
        if forceReload {
            beginMetadataSaveProgress(
                title: String(localized: "Reloading Files"),
                subtitle: String(localized: "Reading from disk…"),
                totalUnitCount: targets.count
            )
        }
        defer {
            isReloadingSelectedFiles = false
            if forceReload { endMetadataSaveProgress() }
        }

        let pipeline = metadataPipeline
        var failures: [String] = []
        for (index, target) in targets.enumerated() {
            guard !Task.isCancelled else { break }
            if forceReload {
                updateMetadataSaveProgress(subtitle: target.url.lastPathComponent, completedUnitCount: index)
            }
            do {
                try await fileMutationCoordinator.withExclusiveAccess(to: [target.url]) {
                    let refreshed = try await withAsyncTimeout(
                        .seconds(60), operationName: "File reload", priority: .utility
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
                    guard let refreshed else { return }
                    // Apply while still reserved, and reject a late read if the
                    // source was removed, moved or independently refreshed.
                    await MainActor.run {
                        guard let current = self.files.first(where: { $0.id == target.id }),
                              current.url == target.url,
                              current.snapshotID == target.snapshotID else { return }
                        self.replaceLoadedFile(
                            refreshed, refreshGeneration: self.makeFileModelRefreshGeneration()
                        )
                    }
                }
            } catch is CancellationError {
                break
            } catch {
                failures.append("\(target.url.lastPathComponent): \((error as NSError).localizedDescription)")
            }
        }

        if forceReload, !failures.isEmpty {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "Reload Failed"),
                subtitle: failures.joined(separator: "\n")
            )
        }
    }
}
