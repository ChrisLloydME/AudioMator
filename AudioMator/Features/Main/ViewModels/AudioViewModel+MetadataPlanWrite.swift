import Foundation

extension AudioViewModel {
    @discardableResult
    func applyFilenameMetadataPlan(
        _ entries: [FilenameMetadataWriteEntry],
        skippedIssues: [BatchMetadataWriteIssue] = []
    ) async -> BatchMetadataWriteSummary? {
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
        let targetURLs = entries.compactMap { entry in
            let matchingFiles = filesByID[entry.fileID]
            return matchingFiles?.count == 1 ? matchingFiles?.first?.url : nil
        }
        guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return nil }
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count + skippedIssues.count)

        beginMetadataSaveProgress(
            title: String(localized: "Writing Filename Metadata"),
            subtitle: String(localized: "Preparing \(entries.count) files..."),
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            guard let matchingFiles = filesByID[entry.fileID], matchingFiles.count == 1,
                  let file = matchingFiles.first else {
                return (entry.fileName, .failure(metadataPlanFileLookupFailureMessage(matchingFiles: filesByID[entry.fileID])))
            }

            guard entry.values.allSatisfy({ field, value in
                field.supportsFilenameToMetadataWriting && field.acceptsExtractedValue(value)
            }) else {
                return (entry.fileName, .failure(String(localized: "Some values in this filename preview can’t be applied. Close and reopen this tool, then check the template and preview.")))
            }

            guard let expectedFileFingerprint = entry.expectedFileFingerprint else {
                return (entry.fileName, .failure(String(localized: "The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before continuing.")))
            }

            var edit = SingleFileEditModel(from: file)
            for field in FileRenameMetadataField.allCases {
                guard let value = entry.values[field] else { continue }
                field.applyExtractedValue(value, to: &edit)
            }

            let result = await self.persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: expectedFileFingerprint
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

        summary.skippedIssues.append(contentsOf: skippedIssues)

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
    func applyMetadataExchangeWriteEntries(
        _ entries: [MetadataExchangeWriteEntry],
        skippedIssues: [BatchMetadataWriteIssue] = [],
        progressTitle: String = String(localized: "Importing Metadata")
    ) async -> BatchMetadataWriteSummary? {
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
        let targetURLs = entries.compactMap { entry in
            let matchingFiles = filesByID[entry.fileID]
            return matchingFiles?.count == 1 ? matchingFiles?.first?.url : nil
        }
        guard prepareMetadataMutationDirectoryAccess(for: targetURLs) else { return nil }
        var summary = BatchMetadataWriteSummary(totalTargets: entries.count + skippedIssues.count)

        beginMetadataSaveProgress(
            title: progressTitle,
            subtitle: String(localized: "Preparing \(entries.count) files..."),
            totalUnitCount: entries.count
        )
        defer { endMetadataSaveProgress() }

        let outcomes = await executeBoundedMetadataPlan(fileNames: entries.map(\.fileName)) { index in
            let entry = entries[index]
            guard let matchingFiles = filesByID[entry.fileID], matchingFiles.count == 1,
                  let file = matchingFiles.first else {
                return (entry.fileName, .failure(metadataPlanFileLookupFailureMessage(matchingFiles: filesByID[entry.fileID])))
            }

            guard entry.values.allSatisfy({ field, value in
                field.isWritableMetadataField && (
                    value == MetadataExchangeProfile.removalSentinel ||
                    (entry.preservingNumberPairComponents
                        ? field.fieldTransferValidationMessage(value)
                        : field.importedValueValidationMessage(value)) == nil
                )
            }) else {
                return (entry.fileName, .failure(String(localized: "Some values in this import preview can’t be applied. Close and reopen this tool, then check the template and imported values.")))
            }

            guard let expectedFileFingerprint = entry.expectedFileFingerprint else {
                return (entry.fileName, .failure(String(localized: "The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before continuing.")))
            }

            var edit = SingleFileEditModel(from: file)
            for field in MetadataExchangeField.allCases {
                guard let value = entry.values[field] else { continue }
                field.applyImportedValue(
                    value,
                    to: &edit,
                    preservingNumberPairComponents: entry.preservingNumberPairComponents
                )
            }

            let result = await self.persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: expectedFileFingerprint
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

        summary.skippedIssues.append(contentsOf: skippedIssues)

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
            title: String(localized: "Changes Couldn’t Be Applied"),
            subtitle: String(localized: "The same file is included more than once in this preview. Close and reopen this tool before applying changes.")
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
        return String(localized: "This file is no longer loaded in AudioMator. Import it again before applying changes.")
    }

    return String(localized: "These loaded files couldn’t be uniquely identified. Remove them from AudioMator and import them again.")
}
