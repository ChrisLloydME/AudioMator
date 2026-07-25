import Foundation

private let supportedTagWriteExtensions = AudioFormatSupport.metadataWritableExtensions

private let supportedArtworkWriteExtensions = AudioFormatSupport.artworkWritableExtensions

func isTagWriteSupportedExtension(_ ext: String) -> Bool {
    supportedTagWriteExtensions.contains(ext.lowercased())
}

func isArtworkWriteSupportedExtension(_ ext: String) -> Bool {
    supportedArtworkWriteExtensions.contains(ext.lowercased())
}

struct MetadataWriteSuccessOutcome {
    let warnings: [String]
    let didRefreshFileModel: Bool
}

enum MetadataWriteExecutionResult {
    case success(MetadataWriteSuccessOutcome)
    case failure(String)
}

func fileCountLabel(_ count: Int) -> String {
    count == 1 ? "1 file" : "\(count) files"
}

extension AudioViewModel {
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
        metadataSaveProgress = MetadataSaveProgress(
            title: current.title,
            subtitle: subtitle,
            completedUnitCount: min(max(completedUnitCount, 0), current.totalUnitCount),
            totalUnitCount: current.totalUnitCount
        )
    }

    func endMetadataSaveProgress() {
        metadataSaveProgress = nil
    }

    func executeMetadataFileMutation(
        at url: URL,
        id: AudioFile.ID,
        expectedFileFingerprint: AudioFileFingerprint?,
        syncInspectorAfterReload: Bool,
        write: @escaping @Sendable (any AudioMetadataPipeline, URL) throws -> AudioMetadataWriteResult
    ) async -> MetadataWriteExecutionResult {
        let executor = MetadataFileMutationExecutor(
            metadataPipeline: metadataPipeline,
            fileMutationCoordinator: fileMutationCoordinator
        )
        let result = await executor.execute(
            at: url,
            id: id,
            expectedFileFingerprint: expectedFileFingerprint,
            write: write
        )

        switch result {
        case .success(let success):
            if let reloadedFile = success.reloadedFile {
                replaceLoadedFile(reloadedFile)
                if syncInspectorAfterReload, selectedAudioIDs.contains(id) {
                    updateEditForSelection()
                }
            }

            var warnings = success.writeResult.warnings
            if let reloadErrorDescription = success.reloadErrorDescription {
                warnings.append(
                    "Saved to disk, but the inspector could not refresh: \(reloadErrorDescription)"
                )
            }

            return .success(
                MetadataWriteSuccessOutcome(
                    warnings: warnings,
                    didRefreshFileModel: success.didReloadFile
                )
            )

        case .failure(let reason):
            return .failure(reason)

        case .cancelled:
            return .failure(String(localized: "The metadata operation was cancelled before it started."))
        }
    }

}
