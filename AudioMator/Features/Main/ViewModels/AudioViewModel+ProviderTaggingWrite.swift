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

        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            guard let file = filesByID[entry.fileID] else {
                return (entry.fileName, .failure("The file is no longer loaded in AudioMator."))
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values.sorted(by: { lhs, rhs in
                lhs.key.writeOrderIndex < rhs.key.writeOrderIndex
            }) {
                field.apply(value, to: &edit)
            }

            let result = await self.persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: entry.expectedFileFingerprint
            )
            return (file.url.lastPathComponent, result)
        }
        for (index, entry) in entries.enumerated() {
            guard let outcome = outcomes[index] else {
                summary.recordCancelledFiles([entry.fileName])
                continue
            }
            switch outcome.result {
            case .success(let success):
                summary.succeeded += 1
                summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: outcome.fileName,
                            messages: success.warnings
                        )
                    )
                }
            case .failure(let reason):
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: outcome.fileName,
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

        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            guard let file = filesByID[entry.fileID] else {
                return (entry.fileName, .failure("The file is no longer loaded in AudioMator."))
            }

            var edit = SingleFileEditModel(from: file)
            for (field, value) in entry.values.sorted(by: { lhs, rhs in
                lhs.key.writeOrderIndex < rhs.key.writeOrderIndex
            }) {
                field.apply(value, to: &edit)
            }

            let result = await self.persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: entry.expectedFileFingerprint
            )
            return (file.url.lastPathComponent, result)
        }
        for (index, entry) in entries.enumerated() {
            guard let outcome = outcomes[index] else {
                summary.recordCancelledFiles([entry.fileName])
                continue
            }
            switch outcome.result {
            case .success(let success):
                summary.succeeded += 1
                summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: outcome.fileName,
                            messages: success.warnings
                        )
                    )
                }
            case .failure(let reason):
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: outcome.fileName,
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
