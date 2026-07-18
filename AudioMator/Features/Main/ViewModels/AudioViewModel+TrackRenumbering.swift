import Foundation

extension AudioViewModel {
    // MARK: - Batch Track Renumbering by List Order

    /// Batch-rewrites Track Number (`TRCK`) using the current ordering of the middle list.
    ///
    /// - Parameters:
    ///   - orderedIDs: Source list order, usually `SharedState.customOrder`; use `files.map(\.id)` when empty.
    ///   - selectedIDs: Current selection. When non-empty, only selected items are rewritten in `orderedIDs` order.
    ///   - options: Rewrite options including direction, start value, and zero padding.
    ///
    /// - Returns: A summary result suitable for UI presentation.
    func renumberTrackNumbers(
        orderedIDs: [UUID],
        selectedIDs: Set<UUID>,
        options: TrackRenumberOptions
    ) async -> TrackRenumberResult {
        let targetsInOrder: [UUID] = {
            let base = orderedIDs
            if selectedIDs.isEmpty { return base }
            return base.filter { selectedIDs.contains($0) }
        }()

        guard !targetsInOrder.isEmpty else {
            return .empty
        }

        let filesByID: [UUID: AudioFile] = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let targetFiles: [AudioFile] = targetsInOrder.compactMap { filesByID[$0] }
        let writeTargets: [(id: UUID, url: URL, expectedFileFingerprint: AudioFileFingerprint?)] =
            targetFiles.map { ($0.id, $0.url, $0.fileFingerprint) }

        guard !writeTargets.isEmpty else {
            return .empty
        }

        let count = writeTargets.count
        let start = max(0, options.startNumber)

        let numbers: [Int] = {
            switch options.direction {
            case .ascending:
                return (0..<count).map { start + $0 }
            case .descending:
                return (0..<count).map { start + (count - 1 - $0) }
            }
        }()

        let maxNumber = numbers.max() ?? start
        let padWidth = trackRenumberPadWidth(maxNumber: maxNumber, padWithZeros: options.padWithZeros)
        let writableExtensions = AudioFormatSupport.metadataWritableExtensions
        let metadataPipeline = self.metadataPipeline
        let fileMutationCoordinator = self.fileMutationCoordinator

        let writeOutcome = await Task.detached(
            priority: .userInitiated
        ) { [writeTargets, numbers, padWidth, writableExtensions, metadataPipeline] in
            var result = TrackRenumberResult(
                totalTargets: writeTargets.count,
                succeeded: 0,
                skippedUnsupported: 0,
                failed: 0,
                failures: [],
                warnings: []
            )
            var reloadedFiles: [AudioFile] = []

            for (idx, target) in writeTargets.enumerated() {
                let newNumber = numbers[idx]

                let ext = target.url.pathExtension.lowercased()
                guard writableExtensions.contains(ext) else {
                    result.skippedUnsupported += 1
                    continue
                }

                do {
                    let formattedTrackNumber =
                        padWidth > 0
                        ? String(format: "%0*d", padWidth, newNumber)
                        : String(newNumber)

                    let targetOutcome: (
                        writeResult: AudioMetadataWriteResult,
                        reloadedFile: AudioFile?,
                        refreshWarning: String?
                    ) = try await fileMutationCoordinator.withExclusiveAccess(to: [target.url]) {
                        try await Task.detached(priority: .userInitiated) {
                            try validateExpectedFileFingerprint(target.expectedFileFingerprint, at: target.url)
                            let writeResult = try metadataPipeline.writeTrackNumberText(
                                formattedTrackNumber,
                                discNumberText: nil,
                                to: target.url,
                                verifyAfterWrite: true
                            )

                            do {
                                let reloadedFile = try await metadataPipeline.loadAudioFile(
                                    at: target.url,
                                    id: target.id
                                )
                                return (writeResult, reloadedFile, nil)
                            } catch {
                                let warning = "Saved to disk, but the file could not be refreshed: "
                                    + (error as NSError).localizedDescription
                                return (writeResult, nil, warning)
                            }
                        }.value
                    }
                    result.succeeded += 1
                    if let reloadedFile = targetOutcome.reloadedFile {
                        reloadedFiles.append(reloadedFile)
                    }

                    var warningMessages = targetOutcome.writeResult.warnings
                    if let refreshWarning = targetOutcome.refreshWarning {
                        warningMessages.append(refreshWarning)
                    }
                    if !warningMessages.isEmpty {
                        result.warnings.append(
                            TrackRenumberWarning(
                                fileName: target.url.lastPathComponent,
                                messages: warningMessages
                            )
                        )
                    }
                } catch {
                    result.failed += 1
                    let reason = (error as NSError).localizedDescription
                    result.failures.append(TrackRenumberFailure(fileName: target.url.lastPathComponent, reason: reason))
                }
            }

            return (result, reloadedFiles)
        }.value

        if !writeOutcome.1.isEmpty {
            replaceLoadedFiles(writeOutcome.1)
            updateEditForSelection()
        }

        return writeOutcome.0
    }
}
