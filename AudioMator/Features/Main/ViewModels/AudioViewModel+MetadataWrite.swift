import Foundation
import TagLibAudioMetadata

nonisolated func unsupportedMetadataWriteFields(
    in editPayload: MetadataEditPayload,
    forFileExtension fileExtension: String
) -> Set<MetadataFieldKey> {
    var requestedFields = editPayload.changedFields
    if editPayload.contentAdvisoryChanged {
        requestedFields.insert(.explicitContent)
    }
    if editPayload.trackNumberTextChanged {
        requestedFields.formUnion([.track, .trackTotal])
    }
    if editPayload.discNumberTextChanged {
        requestedFields.formUnion([.disc, .discTotal])
    }
    switch editPayload.artwork {
    case .unchanged:
        break
    case .replace, .remove:
        requestedFields.insert(.artwork)
    }

    return unsupportedMetadataWriteFields(
        requestedFields,
        forFileExtension: fileExtension
    )
}

nonisolated func unsupportedMetadataWriteFields(
    _ requestedFields: Set<MetadataFieldKey>,
    forFileExtension fileExtension: String
) -> Set<MetadataFieldKey> {
    guard let writableFields = AudioFormatSupport.writableMetadataFields(for: fileExtension) else {
        return []
    }
    return requestedFields.subtracting(writableFields)
}

extension AudioViewModel {
    // MARK: - Inspector Writes (TagLib)

    func saveInspectorEdits() {
        guard metadataSaveProgress == nil else { return }
        guard hasUnsavedInspectorChanges else { return }

        if selectedAudioIDs.count > 1 {
            saveMultiFileEdits()
        } else {
            saveSingleEdits()
        }
    }

    /// Writes the current inspector edits back to the selected audio file through the TagLib bridge.
    func saveSingleEdits() {
        guard
            let edit = edit,
            let id = selectedAudioIDs.first,
            let file = files.first(where: { $0.id == id })
        else {
            return
        }

        guard editSourceFileID == id else {
            updateEditForSelection()
            return
        }

        beginMetadataSaveProgress(
            title: "Saving Metadata",
            subtitle: file.url.lastPathComponent,
            totalUnitCount: 1
        )
        let expectedFileFingerprint = inspectorEditSourceFilesByID[id]?.fileFingerprint
            ?? file.fileFingerprint
        let expectedMetadataVersion = inspectorEditSourceFilesByID[id]?.metadataFileVersion
            ?? file.metadataFileVersion
        let sourceFile = inspectorEditSourceFilesByID[id] ?? file

        Task(priority: .userInitiated) {
            let result = await self.persistMetadataEdit(
                edit,
                to: file,
                comparedTo: sourceFile,
                expectedFileFingerprint: expectedFileFingerprint,
                expectedMetadataVersion: expectedMetadataVersion
            )
            self.updateMetadataSaveProgress(
                subtitle: file.url.lastPathComponent,
                completedUnitCount: 1
            )
            self.endMetadataSaveProgress()

            switch result {
            case .success(let success):
                if success.warnings.isEmpty {
                    self.presentMetadataWriteSuccess(for: file.url.lastPathComponent)
                } else {
                    self.presentMetadataWriteWarning(
                        title: "Saved with Issues",
                        subtitle: ([file.url.lastPathComponent] + success.warnings).joined(separator: "\n")
                    )
                }
            case .failure(let reason):
                self.presentMetadataWriteFailure(
                    for: file.url.lastPathComponent,
                    reason: reason
                )
            }
        }
    }

    /// Applies only the modified multi-file fields to each selected file, then reuses the existing write path.
    func saveMultiFileEdits() {
        guard selectedAudioIDs.count > 1, let multiEdit else {
            return
        }

        guard multiEdit.hasUnsavedChanges else {
            return
        }

        let completedEdits = completedInspectorEditsByID
        let targetFiles = files.filter {
            selectedAudioIDs.contains($0.id) && multiEdit.hasPendingChanges(excluding: completedEdits[$0.id])
        }
        guard !targetFiles.isEmpty else { return }
        guard prepareMetadataMutationDirectoryAccess(for: targetFiles.map(\.url)) else { return }

        let editSnapshot = multiEdit
        let selectionSnapshot = selectedAudioIDs
        let expectedFileFingerprints = inspectorEditSourceFilesByID.mapValues(\.fileFingerprint)
        let expectedMetadataVersions = inspectorEditSourceFilesByID.compactMapValues(\.metadataFileVersion)
        let sourceFiles = inspectorEditSourceFilesByID

        beginMetadataSaveProgress(
            title: "Saving Metadata",
            subtitle: "Preparing \(targetFiles.count) files…",
            totalUnitCount: targetFiles.count
        )

        Task(priority: .userInitiated) {
            var summary = BatchMetadataWriteSummary(totalTargets: targetFiles.count)

            for (index, file) in targetFiles.enumerated() {
                self.updateMetadataSaveProgress(
                    subtitle: file.url.lastPathComponent,
                    completedUnitCount: index
                )

                let sourceFile = sourceFiles[file.id] ?? file
                let effectiveEdit = editSnapshot.applyingChanges(to: sourceFile, excluding: completedEdits[file.id])
                let result = await self.persistMetadataEdit(
                    effectiveEdit,
                    to: file,
                    comparedTo: sourceFile,
                    syncInspectorAfterReload: false,
                    expectedFileFingerprint: expectedFileFingerprints[file.id]
                        ?? file.fileFingerprint,
                    expectedMetadataVersion: expectedMetadataVersions[file.id]
                        ?? file.metadataFileVersion
                )

                switch result {
                case .success(let success):
                    // Keep the failed targets' baselines and drafts. A completed
                    // target starts any further edits from its actual readback.
                    if self.selectedAudioIDs.contains(file.id),
                       self.inspectorEditSourceFilesByID[file.id]?.snapshotID == sourceFile.snapshotID {
                        self.completedInspectorEditsByID[file.id] = editSnapshot
                        if success.didRefreshFileModel,
                           let refreshed = self.files.first(where: { $0.id == file.id && $0.url == file.url }) {
                            self.inspectorEditSourceFilesByID[file.id] = refreshed
                        }
                    }
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

            self.updateMetadataSaveProgress(
                subtitle: "Finishing…",
                completedUnitCount: targetFiles.count
            )
            self.endMetadataSaveProgress()

            if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed,
               self.selectedAudioIDs == selectionSnapshot, !self.hasUnsavedInspectorChanges {
                self.updateEditForSelection()
            }

            self.presentBatchMetadataWriteSummary(summary)
        }
    }

    func persistMetadataEdit(
        _ edit: SingleFileEditModel,
        to file: AudioFile,
        comparedTo sourceFile: AudioFile? = nil,
        syncInspectorAfterReload: Bool = true,
        expectedFileFingerprint: AudioFileFingerprint? = nil,
        expectedMetadataVersion: MetadataFileVersion? = nil
    ) async -> MetadataWriteExecutionResult {
        guard !file.requiresMetadataRefreshBeforeWriting else {
            return .failure(
                "The file revision could not be verified after it moved. Reload the file before editing metadata."
            )
        }
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            return .failure("This format does not support metadata writing yet.")
        }

        let editPayload = MetadataEditPayload(edit, comparedTo: sourceFile ?? file)
        let unsupportedFields = unsupportedMetadataWriteFields(
            in: editPayload,
            forFileExtension: file.url.pathExtension
        )
        if !unsupportedFields.isEmpty {
            let labels = unsupportedFields.map(\.rawValue).sorted().joined(separator: ", ")
            return .failure(
                "This format cannot write the requested metadata fields: \(labels). No changes were made."
            )
        }

        let policy = MetadataConflictPolicy.load(from: conflictPolicyDefaults)
        let baselineFile = sourceFile ?? file
        let canResolve = sourceFile != nil
            && baselineFile.metadataConflictBaseline != nil
            && baselineFile.fileFingerprint != nil
            && baselineFile.metadataFileVersion != nil
            && (expectedFileFingerprint == nil || expectedFileFingerprint == baselineFile.fileFingerprint)
            && (expectedMetadataVersion == nil || expectedMetadataVersion == baselineFile.metadataFileVersion)

        return await executeMetadataFileMutation(
            at: file.url,
            id: file.id,
            // The resolver performs a fresh read and identity validation inside
            // the same reservation; strict preview-based writes keep this guard.
            expectedFileFingerprint: canResolve ? nil : expectedFileFingerprint,
            syncInspectorAfterReload: syncInspectorAfterReload
        ) { metadataPipeline, url in
            if canResolve, let baseline = baselineFile.metadataConflictBaseline,
               let fingerprint = baselineFile.fileFingerprint,
               let version = baselineFile.metadataFileVersion {
                return try MetadataConflictResolver.writeMetadata(
                    editPayload,
                    original: baseline,
                    originalFingerprint: fingerprint,
                    originalVersion: version,
                    policy: policy,
                    pipeline: metadataPipeline,
                    url: url
                )
            }
            return try metadataPipeline.writeMetadata(
                editPayload,
                to: url,
                expectedVersion: expectedMetadataVersion ?? file.metadataFileVersion
            )
        }
    }

    func presentBatchMetadataWriteSummary(_ summary: BatchMetadataWriteSummary) {
        guard summary.totalTargets > 0 else { return }

        saveIssueLogStore.record(summary: summary)

        presentMetadataWriteHUD(
            style: summary.hudStyle,
            title: summary.hudTitle,
            subtitle: summary.hudSubtitle
        )
    }

}
