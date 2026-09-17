import Foundation

struct MetadataFileMutationSuccess: Sendable {
    let writeResult: AudioMetadataWriteResult
    let reloadedFile: AudioFile?
    let reloadErrorDescription: String?

    var didReloadFile: Bool {
        reloadedFile != nil
    }
}

enum MetadataFileMutationResult: Sendable {
    case success(MetadataFileMutationSuccess)
    case failure(String)
    case cancelled
}

/// Owns one file's persistence lifecycle from stale-file validation through reload.
///
/// Cancellation is honored while the operation is queued. After the reservation is
/// acquired, validation, synchronous commit, and observation of the real commit
/// outcome run to completion even if the caller is cancelled. A successful commit
/// then enters an independently bounded reload phase. A reload timeout discards the
/// late result and releases the reservation; it never changes the commit outcome.
/// `AudioViewModel` generations prevent an older completed reload from replacing a
/// newer file model if their MainActor handoffs arrive out of order.
struct MetadataFileMutationExecutor: Sendable {
    let metadataPipeline: any AudioMetadataPipeline
    let fileMutationCoordinator: FileMutationCoordinator
    let reloadTimeout: Duration

    init(
        metadataPipeline: any AudioMetadataPipeline,
        fileMutationCoordinator: FileMutationCoordinator,
        mutationTimeout: Duration = .seconds(60)
    ) {
        self.metadataPipeline = metadataPipeline
        self.fileMutationCoordinator = fileMutationCoordinator
        self.reloadTimeout = mutationTimeout
    }

    func execute(
        at url: URL,
        id: AudioFile.ID,
        expectedFileFingerprint: AudioFileFingerprint?,
        write: @escaping @Sendable (any AudioMetadataPipeline, URL) throws -> AudioMetadataWriteResult
    ) async -> MetadataFileMutationResult {
        do {
            let pipeline = metadataPipeline
            let coordinator = fileMutationCoordinator
            let reloadTimeout = reloadTimeout
            return try await coordinator.withExclusiveAccess(to: [url]) {
                await Task.detached(priority: .userInitiated) {
                    do {
                        try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)
                        let writeResult = try write(pipeline, url)

                        do {
                            let reloadedFile = try await withAsyncTimeout(
                                reloadTimeout,
                                operationName: "Metadata reload",
                                priority: .userInitiated
                            ) {
                                try await pipeline.loadAudioFile(at: url, id: id)
                            }
                            return .success(
                                MetadataFileMutationSuccess(
                                    writeResult: writeResult,
                                    reloadedFile: reloadedFile,
                                    reloadErrorDescription: nil
                                )
                            )
                        } catch {
                            return .success(
                                MetadataFileMutationSuccess(
                                    writeResult: writeResult,
                                    reloadedFile: nil,
                                    reloadErrorDescription: (error as NSError).localizedDescription
                                )
                            )
                        }
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .failure((error as NSError).localizedDescription)
                    }
                }.value
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure((error as NSError).localizedDescription)
        }
    }
}

nonisolated func validateExpectedFileFingerprint(
    _ expectedFileFingerprint: AudioFileFingerprint?,
    at url: URL
) throws {
    guard let expectedFileFingerprint else { return }

    let currentFingerprint: AudioFileFingerprint
    do {
        currentFingerprint = try AudioFileFingerprint.capture(at: url)
    } catch {
        throw AudioFileFingerprintValidationError.unavailable(fileName: url.lastPathComponent)
    }

    guard currentFingerprint == expectedFileFingerprint else {
        throw AudioFileFingerprintValidationError.changedSincePreview(fileName: url.lastPathComponent)
    }
}
