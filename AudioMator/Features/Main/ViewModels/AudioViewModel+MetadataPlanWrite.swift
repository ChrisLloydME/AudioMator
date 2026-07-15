import Foundation

extension AudioViewModel {
    @discardableResult
    func applyFilenameMetadataPlan(_ entries: [FilenameMetadataWriteEntry]) async -> BatchMetadataWriteSummary? {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return nil }

        guard !hasUnsavedInspectorChanges else {
            presentUnsavedMetadataPlanFailure()
            return nil
        }

        guard Set(entries.map(\.fileID)).count == entries.count else {
            presentDuplicateMetadataPlanFailure()
            return nil
        }

        let filesByID = Dictionary(grouping: files, by: \.id)
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: String(localized: "Writing Filename Metadata"),
            subtitle: String(localized: "Preparing \(entries.count) files..."),
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        for (index, entry) in entries.enumerated() {
            updateMetadataSaveProgress(
                subtitle: entry.fileName,
                completedUnitCount: index
            )

            guard let matchingFiles = filesByID[entry.fileID], matchingFiles.count == 1,
                  let file = matchingFiles.first else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: [metadataPlanFileLookupFailureMessage(matchingFiles: filesByID[entry.fileID])]
                    )
                )
                continue
            }

            guard entry.values.allSatisfy({ field, value in
                field.supportsFilenameToMetadataWriting && field.acceptsExtractedValue(value)
            }) else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: [String(localized: "The filename metadata plan contains an invalid field or value. Refresh the preview and try again.")]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for field in FileRenameMetadataField.allCases {
                guard let value = entry.values[field] else { continue }
                field.applyExtractedValue(value, to: &edit)
            }

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: entry.expectedFileFingerprint
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

        updateMetadataSaveProgress(
            subtitle: String(localized: "Finishing..."),
            completedUnitCount: entries.count
        )

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
        return summary
    }

    @discardableResult
    func applyMetadataExchangeWriteEntries(_ entries: [MetadataExchangeWriteEntry]) async -> BatchMetadataWriteSummary? {
        guard !entries.isEmpty, metadataSaveProgress == nil else { return nil }

        guard !hasUnsavedInspectorChanges else {
            presentUnsavedMetadataPlanFailure()
            return nil
        }

        guard Set(entries.map(\.fileID)).count == entries.count else {
            presentDuplicateMetadataPlanFailure()
            return nil
        }

        let filesByID = Dictionary(grouping: files, by: \.id)
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count)

        beginMetadataSaveProgress(
            title: String(localized: "Importing Metadata"),
            subtitle: String(localized: "Preparing \(entries.count) files..."),
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        for (index, entry) in entries.enumerated() {
            updateMetadataSaveProgress(
                subtitle: entry.fileName,
                completedUnitCount: index
            )

            guard let matchingFiles = filesByID[entry.fileID], matchingFiles.count == 1,
                  let file = matchingFiles.first else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: [metadataPlanFileLookupFailureMessage(matchingFiles: filesByID[entry.fileID])]
                    )
                )
                continue
            }

            guard entry.values.allSatisfy({ field, value in
                field.isWritableMetadataField && field.importedValueValidationMessage(value) == nil
            }) else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: entry.fileName,
                        messages: [String(localized: "The metadata exchange plan contains an invalid field or value. Refresh the preview and try again.")]
                    )
                )
                continue
            }

            var edit = SingleFileEditModel(from: file)
            for field in MetadataExchangeField.allCases {
                guard let value = entry.values[field] else { continue }
                field.applyImportedValue(value, to: &edit)
            }

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: entry.expectedFileFingerprint
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

        updateMetadataSaveProgress(
            subtitle: String(localized: "Finishing..."),
            completedUnitCount: entries.count
        )

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataWriteSummary(summary)
        return summary
    }

    private func presentDuplicateMetadataPlanFailure() {
        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Write Failed"),
            subtitle: String(localized: "The write plan contains more than one entry for the same file. Refresh the preview and try again.")
        )
    }

    private func presentUnsavedMetadataPlanFailure() {
        presentMetadataWriteHUD(
            style: .failure,
            title: String(localized: "Unsaved Changes"),
            subtitle: String(localized: "Save or discard the pending inspector edits before writing a metadata exchange plan.")
        )
    }
}

private func metadataPlanFileLookupFailureMessage(matchingFiles: [AudioFile]?) -> String {
    guard matchingFiles != nil else {
        return String(localized: "The file is no longer loaded in AudioMator.")
    }

    return String(localized: "More than one loaded file has the same identifier. Reload the files and try again.")
}
