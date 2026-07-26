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
        guard prepareMetadataMutationDirectoryAccess(for: targets.map(\.url)) else {
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

            let result = await executeMetadataFileMutation(
                at: target.url,
                id: target.id,
                expectedFileFingerprint: target.expectedFileFingerprint,
                syncInspectorAfterReload: false
            ) { metadataPipeline, url in
                try metadataPipeline.writeRawMetadataPropertyMap(propertyMap, to: url)
            }

            switch result {
            case .success(let success):
                summary.succeeded += 1
                succeededTargetIDs.insert(target.id)
                if !success.didRefreshFileModel {
                    summary.allSuccessfulFilesRefreshed = false
                }

                if !success.warnings.isEmpty {
                    summary.warningIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: target.fileName,
                            messages: success.warnings
                        )
                    )
                }

            case .failure(let reason):
                failedTargetIDs.insert(target.id)
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: [reason]
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
