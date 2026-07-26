import Foundation

extension AudioViewModel {
    func createMuseAmpIDs(for targetFiles: [AudioFile]) {
        guard metadataSaveProgress == nil else { return }

        let targetFiles = targetFiles
        guard !targetFiles.isEmpty else { return }
        guard canStartExternalFileMutation() else { return }
        guard prepareMetadataMutationDirectoryAccess(for: targetFiles.map(\.url)) else { return }

        let assignments = MuseAmpCommentIDGenerator.assignments(
            for: targetFiles.map { file in
                MuseAmpTrackIdentity(
                    album: file.album,
                    albumArtist: file.albumArtist,
                    trackKey: file.url.path
                )
            }
        )

        beginMetadataSaveProgress(
            title: "Creating MuseAmp IDs",
            subtitle: "Preparing \(targetFiles.count) files...",
            totalUnitCount: targetFiles.count
        )

        Task(priority: .userInitiated) {
            var summary = BatchMetadataWriteSummary(totalTargets: targetFiles.count)

            for (index, pair) in zip(targetFiles, assignments).enumerated() {
                let file = pair.0
                let museAmpID = pair.1

                self.updateMetadataSaveProgress(
                    subtitle: file.url.lastPathComponent,
                    completedUnitCount: index
                )

                var edit = SingleFileEditModel(from: file)
                edit.comment = museAmpID.commentText

                let result = await self.persistMetadataEdit(
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

            self.updateMetadataSaveProgress(
                subtitle: "Finishing...",
                completedUnitCount: targetFiles.count
            )
            self.endMetadataSaveProgress()

            if summary.failureIssues.isEmpty && summary.allSuccessfulFilesRefreshed {
                self.updateEditForSelection()
            }

            self.presentBatchMetadataWriteSummary(summary)
        }
    }
}
