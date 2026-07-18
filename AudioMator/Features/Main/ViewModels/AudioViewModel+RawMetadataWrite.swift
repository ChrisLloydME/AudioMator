import Foundation

struct RawMetadataApplyResult {
    let succeededTargetIDs: Set<AudioFile.ID>
    let failedTargetIDs: Set<AudioFile.ID>

    var didApplyAllChanges: Bool {
        failedTargetIDs.isEmpty
    }
}

extension AudioViewModel {
    @discardableResult
    func applyRawMetadataPropertyMaps(
        _ propertyMaps: [AudioFile.ID: [String: String]],
        to targets: [MetadataEditorTarget]
    ) async -> RawMetadataApplyResult {
        guard !targets.isEmpty else {
            return RawMetadataApplyResult(succeededTargetIDs: [], failedTargetIDs: [])
        }
        guard canStartExternalFileMutation() else {
            return RawMetadataApplyResult(
                succeededTargetIDs: [],
                failedTargetIDs: Set(targets.map(\.id))
            )
        }

        var summary = BatchMetadataWriteSummary(totalTargets: targets.count)
        var succeededTargetIDs = Set<AudioFile.ID>()
        var failedTargetIDs = Set<AudioFile.ID>()

        for target in targets {
            guard let propertyMap = propertyMaps[target.id] else {
                failedTargetIDs.insert(target.id)
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: [L10n.string("The metadata was not loaded for this file, so no changes were written.")]
                    )
                )
                continue
            }

            guard isTagWriteSupportedExtension(target.url.pathExtension) else {
                failedTargetIDs.insert(target.id)
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
                    propertyMap,
                    to: target.url,
                    expectedFileFingerprint: target.expectedFileFingerprint
                )

                summary.succeeded += 1
                succeededTargetIDs.insert(target.id)
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
                failedTargetIDs.insert(target.id)
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
        return RawMetadataApplyResult(
            succeededTargetIDs: succeededTargetIDs,
            failedTargetIDs: failedTargetIDs
        )
    }
}
