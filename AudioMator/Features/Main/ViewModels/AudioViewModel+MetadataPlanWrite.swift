import Foundation

extension AudioViewModel {
    func applyFilenameMetadataPlan(_ entries: [FilenameMetadataWriteEntry]) async {
        guard !entries.isEmpty else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        for entry in entries {
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
            for (field, value) in entry.values {
                field.applyExtractedValue(value, to: &edit)
            }

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false
            )

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

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
    }

    func applyMetadataExchangeWriteEntries(_ entries: [MetadataExchangeWriteEntry]) async {
        guard !entries.isEmpty else { return }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        for entry in entries {
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
            for (field, value) in entry.values {
                field.applyImportedValue(value, to: &edit)
            }

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false
            )

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

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
    }
}
