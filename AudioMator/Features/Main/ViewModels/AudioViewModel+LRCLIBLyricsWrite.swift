import Foundation

extension AudioViewModel {
    func applyLRCLIBSyncedLyrics(_ syncedLyrics: String, to fileID: AudioFile.ID) async -> Bool {
        guard metadataSaveProgress == nil else { return false }
        let normalizedLyrics = syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLyrics.isEmpty else { return false }

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

        do {
            let writeResult = try await updateRawMetadataPropertyMapOffMainActor(
                at: file.url,
                expectedFileFingerprint: file.fileFingerprint
            ) {
                $0["LYRICS"] = normalizedLyrics
            }
            var warnings = writeResult.warnings
            let refreshWarning = await reloadEditedFile(file, syncInspectorAfterReload: true)
            if let refreshWarning {
                warnings.append(refreshWarning)
            }

            updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            endMetadataSaveProgress()

            if warnings.isEmpty {
                presentMetadataWriteHUD(
                    style: .success,
                    title: "LRCLIB Lyrics Applied",
                    subtitle: file.url.lastPathComponent
                )
            } else {
                presentMetadataWriteWarning(
                    title: "Lyrics Applied with Issues",
                    subtitle: ([file.url.lastPathComponent] + warnings).joined(separator: "\n")
                )
            }

            return true
        } catch {
            let reason = (error as NSError).localizedDescription
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

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
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

            do {
                let writeResult = try await updateRawMetadataPropertyMapOffMainActor(
                    at: file.url,
                    expectedFileFingerprint: file.fileFingerprint
                ) {
                    $0["LYRICS"] = normalizedLyrics
                }
                var warningMessages = writeResult.warnings
                let refreshWarning = await reloadEditedFile(file, syncInspectorAfterReload: false)

                if let refreshWarning {
                    warningMessages.append(refreshWarning)
                    summary.allSuccessfulFilesRefreshed = false
                }

                summary.succeeded += 1
                appliedFileIDs.insert(file.id)

                if !warningMessages.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: file.url.lastPathComponent,
                            messages: warningMessages
                        )
                    )
                }
            } catch {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: file.url.lastPathComponent,
                        messages: [(error as NSError).localizedDescription]
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
