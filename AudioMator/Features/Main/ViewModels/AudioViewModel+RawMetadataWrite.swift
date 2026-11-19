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
        _ propertyMaps: [AudioFile.ID: RawMetadataValueMap],
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

        var summary = BatchMetadataOperationSummary(totalTargets: targets.count)
        var succeededTargetIDs = Set<AudioFile.ID>()
        var failedTargetIDs = Set<AudioFile.ID>()

        for (index, target) in targets.enumerated() {
            if Task.isCancelled {
                let unprocessed = targets.dropFirst(index)
                failedTargetIDs.formUnion(unprocessed.map(\.id))
                summary.recordCancelledFiles(unprocessed.map(\.fileName))
                break
            }
            guard !target.requiresMetadataRefresh else {
                failedTargetIDs.insert(target.id)
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: [L10n.string("The file couldn’t be checked after it moved. Close the Metadata Editor and choose Reload from Disk from the file’s context menu, then reopen the editor.")]
                    )
                )
                continue
            }

            guard let propertyMap = propertyMaps[target.id] else {
                failedTargetIDs.insert(target.id)
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: [L10n.string("Metadata wasn’t loaded for this file. Close and reopen the Metadata Editor. No changes were saved.")]
                    )
                )
                continue
            }

            guard isTagWriteSupportedExtension(target.url.pathExtension) else {
                failedTargetIDs.insert(target.id)
                summary.failureIssues.append(
                    BatchMetadataWriteIssue(
                        fileName: target.fileName,
                        messages: [String(localized: "AudioMator doesn't support saving metadata to this file format.")]
                    )
                )
                continue
            }

            let policy = MetadataConflictPolicy.load(from: conflictPolicyDefaults)
            let canResolve = target.metadataConflictBaseline != nil
                && target.expectedFileFingerprint != nil && target.expectedMetadataVersion != nil
            let result = await executeMetadataFileMutation(
                at: target.url,
                id: target.id,
                expectedFileFingerprint: canResolve ? nil : target.expectedFileFingerprint,
                syncInspectorAfterReload: false
            ) { metadataPipeline, url in
                if canResolve, let baseline = target.metadataConflictBaseline,
                   let fingerprint = target.expectedFileFingerprint, let version = target.expectedMetadataVersion {
                    return try MetadataConflictResolver.writeRawMetadata(
                        propertyMap,
                        original: baseline,
                        originalFingerprint: fingerprint,
                        originalVersion: version,
                        policy: policy,
                        pipeline: metadataPipeline,
                        url: url
                    )
                }
                return try metadataPipeline.writeRawMetadataValueMap(
                    propertyMap,
                    to: url,
                    expectedVersion: target.expectedMetadataVersion
                )
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
            case .cancelled:
                failedTargetIDs.insert(target.id)
                summary.recordCancelledFiles([target.fileName])
            }
        }

        if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
            updateEditForSelection()
        }

        presentBatchMetadataOperationSummary(summary)
        return RawMetadataApplyResult(
            succeededTargetIDs: succeededTargetIDs,
            failedTargetIDs: failedTargetIDs
        )
    }
}
