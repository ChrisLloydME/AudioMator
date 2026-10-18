import Foundation
import TagLibAudioMetadata

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
        guard canStartExternalFileMutation() else { return .empty }

        let filesByID: [UUID: AudioFile] = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let targetFiles: [AudioFile] = targetsInOrder.compactMap { filesByID[$0] }
        let allTargets: [(id: UUID, url: URL, expectedFileFingerprint: AudioFileFingerprint?, expectedMetadataVersion: MetadataFileVersion?, requiresMetadataRefresh: Bool, refreshGeneration: UInt64)] =
            targetFiles.map {
                ($0.id, $0.url, $0.fileFingerprint, $0.metadataFileVersion, $0.requiresMetadataRefreshBeforeWriting, makeFileModelRefreshGeneration())
            }
        let writableExtensions = AudioFormatSupport.metadataWritableExtensions
        let supportedTargets = allTargets.filter { target in
            let ext = target.url.pathExtension.lowercased()
            return writableExtensions.contains(ext) &&
                unsupportedMetadataWriteFields([.track, .trackTotal], forFileExtension: ext).isEmpty
        }
        let skippedUnsupported = allTargets.count - supportedTargets.count
        let refreshFailures = supportedTargets.filter(\.requiresMetadataRefresh).map {
            TrackRenumberFailure(fileName: $0.url.lastPathComponent,
                reason: String(localized: "The file revision could not be verified after it moved. Reload the file before renumbering tracks."))
        }
        let writeTargets = supportedTargets.filter { !$0.requiresMetadataRefresh }

        guard !allTargets.isEmpty else { return .empty }
        guard !writeTargets.isEmpty else {
            return TrackRenumberResult(
                totalTargets: allTargets.count,
                succeeded: 0,
                skippedUnsupported: skippedUnsupported,
                failed: refreshFailures.count,
                failures: refreshFailures,
                warnings: []
            )
        }

        if let accessFailure = ensureMetadataMutationDirectoryAccess(for: writeTargets.map(\.url)) {
            return TrackRenumberResult(
                totalTargets: allTargets.count,
                succeeded: 0,
                skippedUnsupported: skippedUnsupported,
                failed: writeTargets.count + refreshFailures.count,
                failures: refreshFailures + writeTargets.map {
                    TrackRenumberFailure(fileName: $0.url.lastPathComponent, reason: accessFailure)
                },
                warnings: []
            )
        }

        let count = writeTargets.count
        let start = normalizedTrackRenumberStartNumber(options.startNumber)

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
        let metadataPipeline = self.metadataPipeline
        let mutationExecutor = MetadataFileMutationExecutor(
            metadataPipeline: metadataPipeline,
            fileMutationCoordinator: fileMutationCoordinator
        )

        let writeOutcome = await { () async -> (TrackRenumberResult, [(file: AudioFile, refreshGeneration: UInt64)]) in
            var result = TrackRenumberResult(
                totalTargets: allTargets.count,
                succeeded: 0,
                skippedUnsupported: skippedUnsupported,
                failed: refreshFailures.count,
                failures: refreshFailures,
                warnings: []
            )
            var reloadedFiles: [(file: AudioFile, refreshGeneration: UInt64)] = []

            for (idx, target) in writeTargets.enumerated() {
                if Task.isCancelled {
                    let unprocessed = writeTargets.dropFirst(idx)
                    result.failed += unprocessed.count
                    result.failures.append(contentsOf: unprocessed.map {
                        TrackRenumberFailure(fileName: $0.url.lastPathComponent,
                            reason: String(localized: "Cancelled before this file was processed. No changes were made."))
                    })
                    break
                }
                let newNumber = numbers[idx]

                let formattedTrackNumber =
                    padWidth > 0
                    ? String(format: "%0*d", padWidth, newNumber)
                    : String(newNumber)
                let targetOutcome = await mutationExecutor.execute(
                    at: target.url,
                    id: target.id,
                    expectedFileFingerprint: target.expectedFileFingerprint
                ) { metadataPipeline, url in
                    try metadataPipeline.writeTrackNumberText(
                        formattedTrackNumber,
                        discNumberText: nil,
                        to: url,
                        verifyAfterWrite: true,
                        expectedVersion: target.expectedMetadataVersion
                    )
                }

                switch targetOutcome {
                case .success(let success):
                    result.succeeded += 1
                    if let reloadedFile = success.reloadedFile {
                        reloadedFiles.append((reloadedFile, target.refreshGeneration))
                    }

                    var warningMessages = success.writeResult.warnings
                    if case .durabilityUncertain(let detail) = success.writeResult.commitStatus {
                        warningMessages.append(String(localized: "Saved to disk, but macOS could not confirm directory durability. Do not retry this save as though it failed.") + " " + detail)
                    }
                    if let reloadErrorDescription = success.reloadErrorDescription {
                        warningMessages.append(
                            "Saved to disk, but the file could not be refreshed: \(reloadErrorDescription)"
                        )
                    }
                    if !warningMessages.isEmpty {
                        result.warnings.append(
                            TrackRenumberWarning(
                                fileName: target.url.lastPathComponent,
                                messages: warningMessages
                            )
                        )
                    }

                case .failure(let reason):
                    result.failed += 1
                    result.failures.append(TrackRenumberFailure(fileName: target.url.lastPathComponent, reason: reason))

                case .cancelled:
                    result.failed += 1
                    result.failures.append(
                        TrackRenumberFailure(
                            fileName: target.url.lastPathComponent,
                            reason: "The track renumber operation was cancelled before it started."
                        )
                    )
                }
            }

            return (result, reloadedFiles)
        }()

        if !writeOutcome.1.isEmpty {
            var didApplyReloadedFile = false
            for reload in writeOutcome.1 {
                didApplyReloadedFile = replaceLoadedFile(
                    reload.file,
                    refreshGeneration: reload.refreshGeneration
                ) || didApplyReloadedFile
            }
            if didApplyReloadedFile {
                updateEditForSelection()
            }
        }

        return writeOutcome.0
    }
}
