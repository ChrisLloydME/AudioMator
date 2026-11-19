import Foundation
import TagLibAudioMetadata

private let supportedTagWriteExtensions = AudioFormatSupport.metadataWritableExtensions

private let supportedArtworkWriteExtensions = AudioFormatSupport.artworkWritableExtensions

func isTagWriteSupportedExtension(_ ext: String) -> Bool {
    supportedTagWriteExtensions.contains(ext.lowercased())
}

func isArtworkWriteSupportedExtension(_ ext: String) -> Bool {
    supportedArtworkWriteExtensions.contains(ext.lowercased())
}

struct MetadataWriteSuccessOutcome: Sendable {
    let warnings: [String]
    let didRefreshFileModel: Bool
}

enum MetadataWriteExecutionResult: Sendable {
    case success(MetadataWriteSuccessOutcome)
    case failure(String)
    /// Precommit cancellation only. A commit that crossed the admission boundary
    /// always reports `.success`/`.failure` with its real disk outcome.
    case cancelled
}

func fileCountLabel(_ count: Int) -> String {
    count == 1 ? String(localized: "1 file") : String(localized: "\(count) files")
}

extension AudioViewModel {
    /// Per-file capability reason for a semantic Inspector row. Capability is
    /// advisory until the package validates the concrete file, but unsupported
    /// destinations are shown and disabled before Save.
    func metadataFieldUnsupportedReason(
        _ field: InspectorMetadataField,
        in files: [AudioFile]
    ) -> String? {
        guard let key = field.metadataFieldKey, !files.isEmpty else { return nil }
        if [MetadataFieldKey.year, .standaloneDate, .releaseDate, .originalReleaseDate].contains(key),
           files.contains(where: { $0.hasUnverifiedIndependentDateProjection }) {
            return String(localized: "These ID3v2.3 tags don't allow these date fields to be edited separately. Their dates will stay as they are.")
        }
        let unsupportedCount = files.filter { !Self.canWrite(key, to: $0) }.count
        guard unsupportedCount > 0 else { return nil }
        if unsupportedCount == files.count {
            return String(localized: "This file format doesn’t support saving") + " \(field.displayName)."
        }
        return String(localized: "Some selected file formats don’t support saving") + " \(field.displayName)."
    }

    nonisolated static func canWrite(_ key: MetadataFieldKey, to file: AudioFile) -> Bool {
        if file.hasUnverifiedIndependentDateProjection,
           [MetadataFieldKey.year, .standaloneDate, .releaseDate, .originalReleaseDate].contains(key) {
            return false // The package exposes this unverified layout read-only.
        }
        guard let writable = AudioFormatSupport.writableMetadataFields(for: file.url.pathExtension) else {
            return false
        }
        return writable.contains(key)
    }
}

extension AudioViewModel {
    func prepareMetadataMutationDirectoryAccess(
        for urls: [URL],
        failureTitle: String = String(localized: "Allow Folder Access")
    ) -> Bool {
        guard let failure = ensureMetadataMutationDirectoryAccess(for: urls) else { return true }

        presentMetadataWriteHUD(
            style: .warning,
            title: failureTitle,
            subtitle: failure
        )
        return false
    }

    func canStartExternalFileMutation() -> Bool {
        guard hasUnsavedInspectorChanges else { return true }

        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Unsaved Changes"),
            subtitle: String(localized: "Save or discard the pending inspector edits before changing files from another tool.")
        )
        return false
    }

    func beginMetadataSaveProgress(
        title: String,
        subtitle: String,
        totalUnitCount: Int
    ) {
        flushPendingMetadataReloads()
        lastMetadataProgressPublication = .now
        metadataSaveProgress = MetadataSaveProgress(
            title: title,
            subtitle: subtitle,
            completedUnitCount: 0,
            totalUnitCount: max(totalUnitCount, 1)
        )
    }

    func updateMetadataSaveProgress(
        subtitle: String,
        completedUnitCount: Int
    ) {
        guard let current = metadataSaveProgress else { return }
        // Each progress publication invalidates the window. Bound that work for
        // fast batch writes while always publishing the final completed count.
        guard completedUnitCount >= current.totalUnitCount ||
            lastMetadataProgressPublication.duration(to: .now) >= .milliseconds(100) else { return }
        lastMetadataProgressPublication = .now
        metadataSaveProgress = MetadataSaveProgress(
            title: current.title,
            subtitle: subtitle,
            completedUnitCount: min(max(completedUnitCount, 0), current.totalUnitCount),
            totalUnitCount: current.totalUnitCount
        )
    }

    func endMetadataSaveProgress() {
        // Publish every accepted reload before reporting batch completion,
        // including partial failures and cancellation.
        flushPendingMetadataReloads()
        metadataSaveProgress = nil
    }

    func executeMetadataFileMutation(
        at url: URL,
        id: AudioFile.ID,
        expectedFileFingerprint: AudioFileFingerprint?,
        syncInspectorAfterReload: Bool,
        write: @escaping @Sendable (any AudioMetadataPipeline, URL) throws -> AudioMetadataWriteResult
    ) async -> MetadataWriteExecutionResult {
        do { try validateMetadataWriteRecovery(id: id, url: url) }
        catch { return .failure(error.localizedDescription) }
        if let accessFailure = ensureMetadataMutationDirectoryAccess(for: [url]) {
            return .failure(accessFailure)
        }

        let executor = MetadataFileMutationExecutor(
            metadataPipeline: metadataPipeline,
            fileMutationCoordinator: fileMutationCoordinator
        )
        let refreshGeneration = makeFileModelRefreshGeneration()
        let result = await executor.execute(
            at: url,
            id: id,
            expectedFileFingerprint: expectedFileFingerprint,
            validateBeforeWrite: { try await self.validateMetadataWriteRecovery(id: id, url: url) },
            write: write
        )

        switch result {
        case .success(let success):
            var didApplyReloadedFile = false
            if let reloadedFile = success.reloadedFile {
                didApplyReloadedFile = replaceLoadedFile(
                    reloadedFile,
                    refreshGeneration: refreshGeneration,
                    deferVisibleRefresh: metadataSaveProgress != nil && !syncInspectorAfterReload
                )
                if didApplyReloadedFile, syncInspectorAfterReload {
                    refreshInspectorDraftAfterAcceptedPublication()
                }
            }

            var warnings = success.writeResult.warnings
            if case .durabilityUncertain(let detail) = success.writeResult.commitStatus {
                warnings.append(
                    MetadataCommitWarning.durability(detail)
                )
            }
            if let reloadErrorDescription = success.reloadErrorDescription {
                warnings.append(
                    MetadataCommitWarning.reload(reloadErrorDescription)
                )
            }

            return .success(
                MetadataWriteSuccessOutcome(
                    warnings: warnings,
                    didRefreshFileModel: didApplyReloadedFile
                )
            )

        case .failure(let reason):
            return .failure(reason)

        case .cancelled:
            return .cancelled
        }
    }

}


extension AudioViewModel {
    /// Runs independent captured plan entries with the existing four-file
    /// bound. Results remain in plan order; nil means cancelled before entry.
    func executeBoundedMetadataPlan(
        fileNames: [String],
        operation: @escaping @MainActor @Sendable (Int) async -> (fileName: String, result: MetadataWriteExecutionResult)
    ) async -> [(fileName: String, result: MetadataWriteExecutionResult)?] {
        var results = Array<(fileName: String, result: MetadataWriteExecutionResult)?>(repeating: nil, count: fileNames.count)
        var completed = 0
        await MetadataBatchExecutor.execute(count: fileNames.count) { index -> (fileName: String, result: MetadataWriteExecutionResult)? in
            guard !Task.isCancelled else { return nil }
            return await operation(index)
        } onCompletion: { index, result in
            results[index] = result
            completed += 1
            self.updateMetadataSaveProgress(subtitle: fileNames[index], completedUnitCount: completed)
        }
        return results
    }
}

/// Shared post-commit warnings must never imply that a committed write failed.
enum MetadataCommitWarning {
    static func reload(_ detail: String) -> String {
        String(localized: "Your changes were saved, but the file couldn’t be reloaded. Close the Metadata Editor if it is open, then choose Reload from Disk from the file’s context menu to read the saved values.\nDetails: \(detail)")
    }

    static func durability(_ detail: String) -> String {
        String(localized: "Your changes were saved, but macOS couldn't confirm that the save will survive a crash or power loss. Don't repeat this save.\nDetails: \(detail)")
    }
}
