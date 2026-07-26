import Foundation

extension AudioViewModel {
    func applyLRCLIBSyncedLyrics(_ syncedLyrics: String, to fileID: AudioFile.ID) async -> Bool {
        guard metadataSaveProgress == nil else { return false }
        let normalizedLyrics = syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLyrics.isEmpty else { return false }
        guard canStartExternalFileMutation() else { return false }

        guard let file = files.first(where: { $0.id == fileID }) else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Apply Lyrics Failed",
                subtitle: "The file is no longer loaded in AudioMator."
            )
            return false
        }

        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Apply Lyrics Failed",
                subtitle: "This format does not support metadata writing yet."
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
            var propertyMap = try metadataPipeline.rawMetadataPropertyMap(for: url)
            propertyMap["LYRICS"] = normalizedLyrics
            return try metadataPipeline.writeRawMetadataPropertyMap(propertyMap, to: url)
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
                    subtitle: file.url.lastPathComponent
                )
            } else {
                presentMetadataWriteWarning(
                    title: "Lyrics Applied with Issues",
                    subtitle: ([file.url.lastPathComponent] + success.warnings).joined(separator: "\n")
                )
            }

            return true

        case .failure(let reason):
            updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            endMetadataSaveProgress()
            saveIssueLogStore.recordSingleIssue(
                title: "Apply Lyrics Failed",
                subtitle: [file.url.lastPathComponent, reason]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                fileName: file.url.lastPathComponent,
                messages: [reason],
                severity: .failure
            )
            presentMetadataWriteHUD(
                style: .failure,
                title: "Apply Lyrics Failed",
                subtitle: [file.url.lastPathComponent, reason]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            )
            return false
        }
    }

    func applyLRCLIBSyncedLyricsAutoMatches(_ matches: [LRCLIBSyncedLyricsAutoMatch]) async -> Set<AudioFile.ID> {
        guard metadataSaveProgress == nil else { return [] }
        guard !matches.isEmpty else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "No Synced Lyrics Found",
                subtitle: "LRCLIB did not return synced lyrics for the selected files."
            )
            return []
        }
        guard canStartExternalFileMutation() else { return [] }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let targetURLs = matches.compactMap { filesByID[$0.fileID]?.url }
        guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return [] }
        var summary = BatchMetadataWriteSummary(totalTargets: matches.count)
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
                        messages: ["LRCLIB returned empty synced lyrics."]
                    )
                )
                continue
            }

            guard let file = filesByID[match.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: match.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            guard isTagWriteSupportedExtension(file.url.pathExtension) else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: ["This format does not support metadata writing yet."]
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
                var propertyMap = try metadataPipeline.rawMetadataPropertyMap(for: url)
                propertyMap["LYRICS"] = normalizedLyrics
                return try metadataPipeline.writeRawMetadataPropertyMap(propertyMap, to: url)
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

        presentBatchMetadataWriteSummary(summary)
        return appliedFileIDs
    }
}
