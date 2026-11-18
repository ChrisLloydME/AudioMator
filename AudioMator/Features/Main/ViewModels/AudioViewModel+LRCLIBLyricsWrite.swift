import Foundation
import TagLibAudioMetadata

extension AudioViewModel {
    func applyLRCLIBSyncedLyrics(_ syncedLyrics: String, to fileID: AudioFile.ID) async -> Bool {
        guard metadataSaveProgress == nil else { return false }
        let normalizedLyrics = syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLyrics.isEmpty else { return false }
        guard canStartExternalFileMutation() else { return false }

        guard let file = files.first(where: { $0.id == fileID }) else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: String(localized: "This file is no longer loaded in AudioMator. Import it again before applying changes.")
            )
            return false
        }

        guard !file.requiresMetadataRefreshBeforeWriting else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: String(localized: "The file couldn’t be checked after it moved. Choose Reload from Disk from its context menu before applying lyrics.")
            )
            return false
        }

        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: String(localized: "AudioMator doesn't support saving metadata to this file format.")
            )
            return false
        }
        guard unsupportedMetadataWriteFields(
            [.lyrics],
            forFileExtension: file.url.pathExtension
        ).isEmpty else {
            presentMetadataWriteHUD(
                style: .failure,
                title: String(localized: "Lyrics Couldn’t Be Applied"),
                subtitle: String(localized: "This file format doesn't support saving lyrics in AudioMator. No changes were saved.")
            )
            return false
        }

        beginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: file.url.lastPathComponent,
            totalUnitCount: 1
        )

        let result = await executeMetadataFileMutation(
            at: file.url,
            id: file.id,
            expectedFileFingerprint: file.fileFingerprint,
            syncInspectorAfterReload: true
        ) { metadataPipeline, url in
            try metadataPipeline.writeRawMetadataPatch(
                RawMetadataPatch(valuesToSet: ["LYRICS": [normalizedLyrics]]),
                to: url,
                expectedVersion: file.metadataFileVersion
            )
        }

        switch result {
        case .success(let success):
            updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            endMetadataSaveProgress()

            if success.warnings.isEmpty {
                presentMetadataWriteHUD(
                    style: .success,
                    title: "LRCLIB Lyrics Applied",
                    subtitle: file.url.lastPathComponent,
                    summary: file.url.lastPathComponent,
                    details: ""
                )
            } else {
                presentMetadataWriteWarning(
                    title: String(localized: "Lyrics Saved with Warnings"),
                    fileName: file.url.lastPathComponent,
                    warnings: success.warnings
                )
            }

            return true

        case .failure(let reason):
            updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            endMetadataSaveProgress()
            presentMetadataWriteFailure(
                for: file.url.lastPathComponent, reason: reason,
                title: String(localized: "Lyrics Couldn’t Be Applied")
            )
            return false
        }
    }

    func applyLRCLIBSyncedLyricsAutoMatches(_ matches: [LRCLIBSyncedLyricsAutoMatch]) async -> Set<AudioFile.ID> {
        guard metadataSaveProgress == nil else { return [] }
        guard !matches.isEmpty else {
            presentMetadataWriteHUD(
                style: .warning,
                title: String(localized: "No Synced Lyrics Available"),
                subtitle: String(localized: "LRCLIB didn't find synced lyrics for these files. Try different search details or choose another result.")
            )
            return []
        }
        guard canStartExternalFileMutation() else { return [] }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let targetURLs = matches.compactMap { filesByID[$0.fileID]?.url }
        guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return [] }
        var summary = BatchMetadataOperationSummary(totalTargets: matches.count)
        var appliedFileIDs = Set<AudioFile.ID>()

        beginMetadataSaveProgress(
            title: "Applying LRCLIB Lyrics",
            subtitle: "Preparing \(matches.count) files...",
            totalUnitCount: matches.count
        )

        for (index, match) in matches.enumerated() {
            updateMetadataSaveProgress(
                subtitle: match.fileName,
                completedUnitCount: index
            )

            let normalizedLyrics = match.syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedLyrics.isEmpty else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: match.fileName,
                        messages: [String(localized: "This lyrics result is empty. Choose another result.")]
                    )
                )
                continue
            }

            guard let file = filesByID[match.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: match.fileName,
                        messages: [String(localized: "This file is no longer loaded in AudioMator. Import it again before applying changes.")]
                    )
                )
                continue
            }

            guard !file.requiresMetadataRefreshBeforeWriting else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: [String(localized: "The file couldn’t be checked after it moved. Choose Reload from Disk from its context menu before applying lyrics.")]
                    )
                )
                continue
            }

            guard isTagWriteSupportedExtension(file.url.pathExtension) else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: [String(localized: "AudioMator doesn't support saving metadata to this file format.")]
                    )
                )
                continue
            }
            guard unsupportedMetadataWriteFields(
                [.lyrics],
                forFileExtension: file.url.pathExtension
            ).isEmpty else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: [String(localized: "This file format doesn't support saving lyrics in AudioMator. No changes were saved.")]
                    )
                )
                continue
            }

            let result = await executeMetadataFileMutation(
                at: file.url,
                id: file.id,
                expectedFileFingerprint: file.fileFingerprint,
                syncInspectorAfterReload: false
            ) { metadataPipeline, url in
                try metadataPipeline.writeRawMetadataPatch(
                    RawMetadataPatch(valuesToSet: ["LYRICS": [normalizedLyrics]]),
                    to: url,
                    expectedVersion: file.metadataFileVersion
                )
            }

            switch result {
            case .success(let success):
                if !success.didRefreshFileModel {
                    summary.allSuccessfulFilesRefreshed = false
                }

                summary.succeeded += 1
                appliedFileIDs.insert(file.id)

                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: file.url.lastPathComponent,
                            messages: success.warnings
                        )
                    )
                }

            case .failure(let reason):
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: [reason]
                    )
                )
            }
        }

        updateMetadataSaveProgress(
            subtitle: "Finishing...",
            completedUnitCount: matches.count
        )
        endMetadataSaveProgress()

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataOperationSummary(summary)
        return appliedFileIDs
    }
}
