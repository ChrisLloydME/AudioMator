import Foundation

extension AudioViewModel {
    func applyMusicBrainzTaggingPlan(_ entries: [MusicBrainzTaggingWriteEntry]) async {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return }
        guard canStartExternalFileMutation() else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let targetURLs = entries.compactMap { filesByID[$0.fileID]?.url }
        guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return }
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: "Applying MusicBrainz Tags",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        for (index, entry) in entries.enumerated() {
            guard !Task.isCancelled else { return }
            updateMetadataSaveProgress(
                subtitle: entry.fileName,
                completedUnitCount: index
            )

            guard let file = filesByID[entry.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values.sorted(by: { lhs, rhs in
                lhs.key.writeOrderIndex < rhs.key.writeOrderIndex
            }) {
                field.apply(value, to: &edit)
            }

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: entry.expectedFileFingerprint
            )
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let success):
                summary.succeeded += 1
                summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

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
            completedUnitCount: entries.count
        )

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
    }

    func applyiTunesTaggingPlan(_ entries: [iTunesTaggingWriteEntry]) async {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return }
        guard canStartExternalFileMutation() else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let targetURLs = entries.compactMap { filesByID[$0.fileID]?.url }
        guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return }
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: "Applying iTunes Tags",
            subtitle: "Preparing \(entries.count) files...",
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        for (index, entry) in entries.enumerated() {
            guard !Task.isCancelled else { return }
            updateMetadataSaveProgress(
                subtitle: entry.fileName,
                completedUnitCount: index
            )

            guard let file = filesByID[entry.fileID] else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: ["The file is no longer loaded in AudioMator."]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values.sorted(by: { lhs, rhs in
                lhs.key.writeOrderIndex < rhs.key.writeOrderIndex
            }) {
                field.apply(value, to: &edit)
            }

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: entry.expectedFileFingerprint
            )
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let success):
                summary.succeeded += 1
                summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

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
            completedUnitCount: entries.count
        )

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
    }
}
