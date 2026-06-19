import Foundation

extension AudioViewModel {
    func applyRawMetadataPropertyMaps(
        _ propertyMaps: [AudioFile.ID: [String: String]],
        to targets: [MetadataEditorTarget]
    ) async {
        guard !targets.isEmpty else { return }

        var summary = BatchMetadataWriteSummary(totalTargets: targets.count)

        for target in targets {
            guard isTagWriteSupportedExtension(target.url.pathExtension) else {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: ["This format does not support metadata writing yet."]
                    )
                )
                continue
            }

            do {
                let writeResult = try await writeRawMetadataPropertyMapOffMainActor(
                    propertyMaps[target.id] ?? [:],
                    to: target.url
                )

                summary.succeeded += 1
                var warningMessages = writeResult.warnings

                let refreshWarning = await reloadEditedFile(
                    at: target.url,
                    id: target.id,
                    syncInspectorAfterReload: false
                )

                if let refreshWarning {
                    warningMessages.append(refreshWarning)
                    summary.allSuccessfulFilesRefreshed = false
                }

                if !warningMessages.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: target.fileName,
                            messages: warningMessages
                        )
                    )
                }
            } catch {
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: [(error as NSError).localizedDescription]
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
