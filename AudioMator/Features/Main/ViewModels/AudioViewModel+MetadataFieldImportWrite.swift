import Foundation

extension AudioViewModel {
    /// Imports one text field value per target file and writes the chosen metadata field in order.
    func importMetadataFieldValues(
        _ values: [String],
        to field: MultiFileEditableTextField,
        for targetFiles: [AudioFile]
    ) async {
        guard !targetFiles.isEmpty else { return }
        guard canStartExternalFileMutation() else { return }

        guard values.count == targetFiles.count else {
            presentMetadataWriteHUD(
                style: .failure,
                title: "Import Failed",
                subtitle: "Imported \(values.count) values for \(targetFiles.count) selected files."
            )
            return
        }
        guard prepareMetadataMutationDirectoryAccess(for: targetFiles.map(\.url)) else { return }

        var summary = BatchMetadataWriteSummary(totalTargets: targetFiles.count)

        for (file, value) in zip(targetFiles, values) {
            var edit = SingleFileEditModel(from: file)
            field.apply(value, to: &edit)

            let result = await persistMetadataEdit(
                edit,
                to: file,
                syncInspectorAfterReload: false,
                expectedFileFingerprint: file.fileFingerprint
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
