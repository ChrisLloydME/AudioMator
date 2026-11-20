import Foundation

extension AudioViewModel {
    func createMuseAmpIDs(for targetFiles: [AudioFile]) {
        guard metadataSaveProgress == nil else { return }

        let targetFiles = targetFiles
        guard !targetFiles.isEmpty else { return }
        guard canStartExternalFileMutation() else { return }

        let assignments = MuseAmpCommentIDGenerator.assignments(
            for: targetFiles.map { file in
                MuseAmpTrackIdentity(
                    album: file.album,
                    albumArtist: file.albumArtist,
                    trackKey: file.url.path
                )
            }
        )

        // Freeze one reviewed write per target before any asynchronous execution.
        // The comment payload is part of the frozen intent, so grouping and
        // uniqueness are decided from the reviewed snapshots only.
        let plannedWrites: [PlannedMuseAmpWrite] = zip(targetFiles, assignments).map { file, assignment in
            var edit = SingleFileEditModel(from: file)
            edit.comment = assignment.commentText
            return PlannedMuseAmpWrite(
                fileName: file.url.lastPathComponent,
                write: ReviewedMetadataWriteFactory.semanticWrite(edit: edit, comparedTo: file)
            )
        }
        guard let progressToken = tryBeginMetadataSaveProgress(
            title: "Creating MuseAmp IDs",
            subtitle: "Preparing \(plannedWrites.count) files...",
            totalUnitCount: plannedWrites.count
        ) else { return }

        guard prepareMetadataMutationDirectoryAccess(for: plannedWrites.compactMap { $0.write }) else {
            endMetadataSaveProgress(token: progressToken)
            return
        }

        Task(priority: .userInitiated) {
            var summary = BatchMetadataOperationSummary(totalTargets: plannedWrites.count)

            for (index, planned) in plannedWrites.enumerated() {
                self.updateMetadataSaveProgress(
                    token: progressToken,
                    subtitle: planned.fileName,
                    completedUnitCount: index
                )

                guard let write = planned.write else {
                    summary.failureIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: planned.fileName,
                            messages: [Self.unreviewedMuseAmpEntryFailureMessage]
                        )
                    )
                    continue
                }

                let result = await self.executeReviewedMetadataWrite(write, publication: .batched)
                switch result {
                case .success(let success):
                    summary.succeeded += 1
                    summary.allSuccessfulFilesRefreshed = summary.allSuccessfulFilesRefreshed && success.didRefreshFileModel

                    if !success.warnings.isEmpty {
                        summary.warningIssues.append(
                            BatchMetadataWriteIssue(
                                fileName: planned.fileName,
                                messages: success.warnings
                            )
                        )
                    }
                case .failure(let reason):
                    summary.failureIssues.append(
                        BatchMetadataWriteIssue(
                            fileName: planned.fileName,
                            messages: [reason]
                        )
                    )
                case .cancelled:
                    summary.recordCancelledFiles([planned.fileName])
                }
            }

            self.updateMetadataSaveProgress(
                token: progressToken,
                subtitle: "Finishing...",
                completedUnitCount: plannedWrites.count
            )
            self.endMetadataSaveProgress(token: progressToken)

            if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
                self.refreshInspectorDraftAfterAcceptedPublication()
            }

            self.presentBatchMetadataOperationSummary(summary)
        }
    }

    private static var unreviewedMuseAmpEntryFailureMessage: String {
        String(localized: "This file doesn’t have a reviewed revision to write. Reload it, then try again.")
    }
}

/// One frozen MuseAmp write captured before asynchronous execution.
private struct PlannedMuseAmpWrite: Sendable {
    let fileName: String
    let write: ReviewedMetadataWrite?
}
