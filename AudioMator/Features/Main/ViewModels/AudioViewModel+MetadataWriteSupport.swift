import Foundation
import TagLibAudioMetadata
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
}

func fileCountLabel(_ count: Int) -> String {
    count == 1 ? "1 file" : "\(count) files"
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
            return String(localized: "Independent date editing is read-only for selected ID3v2.3 tags. No date conversion will be performed.")
        }
        let unsupportedCount = files.filter { !Self.canWrite(key, to: $0) }.count
        guard unsupportedCount > 0 else { return nil }
        if unsupportedCount == files.count {
            return String(localized: "This format cannot write") + " \(field.displayName)."
        }
        return String(localized: "Some selected formats cannot write") + " \(field.displayName)."
    }

    func containerFieldUnsupportedReason(
        _ key: MetadataFieldKey,
        in files: [AudioFile]
    ) -> String? {
        guard !files.isEmpty else { return nil }
        let unsupportedCount = files.filter { !Self.canWrite(key, to: $0) }.count
        guard unsupportedCount > 0 else { return nil }
        let name = ContainerMetadataFieldCatalog.displayName(for: key)
        if unsupportedCount == files.count {
            return String(localized: "This format cannot write") + " \(name)."
        }
        return String(localized: "Some selected formats cannot write") + " \(name)."
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
        failureTitle: String = String(localized: "Folder Access Needed")
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
                if didApplyReloadedFile, syncInspectorAfterReload, selectedAudioIDs.contains(id) {
                    updateEditForSelection()
                }
            }

            var warnings = success.writeResult.warnings
            if case .durabilityUncertain(let detail) = success.writeResult.commitStatus {
                warnings.append(
                    "Saved to disk, but macOS could not confirm directory durability. Do not retry this save as though it failed. \(detail)"
                )
            }
            if let reloadErrorDescription = success.reloadErrorDescription {
                warnings.append(
                    "Saved to disk, but the inspector could not refresh: \(reloadErrorDescription)"
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
            return .failure(String(localized: "The metadata operation was cancelled before it started."))
        }
    }

}
