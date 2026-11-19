import Foundation

struct MetadataFileMutationSuccess: Sendable {
    let writeResult: AudioMetadataWriteResult
    let reloadedFile: AudioFile?
    let reloadErrorDescription: String?

}

enum MetadataFileMutationResult: Sendable {
    case success(MetadataFileMutationSuccess)
    case failure(String)
    case cancelled
}

/// How one file mutation obtains write authority and admission.
///
/// `reviewed` requires the captured coherent observation: the detached worker
/// verifies the captured fingerprint and the permit must still be pending before
/// the synchronous writer runs. `reviewedDraft` is the conflict-aware Inspector /
/// Raw Editor route: the permit gates admission but identity and revision policy
/// are validated inside `MetadataConflictResolver`, which owns rebasing.
/// `legacy` is the temporary migration path for not-yet-migrated callers.
nonisolated enum MetadataFileMutationAdmission: Sendable {
    case reviewed(ReviewedMetadataTarget, permit: MetadataCommitPermit)
    case reviewedDraft(ReviewedMetadataTarget, permit: MetadataCommitPermit)
    case legacy(expectedFileFingerprint: AudioFileFingerprint?)

    var permit: MetadataCommitPermit? {
        switch self {
        case .reviewed(_, let permit), .reviewedDraft(_, let permit):
            return permit
        case .legacy:
            return nil
        }
    }
}

/// Owns one file's persistence lifecycle from stale-file validation through reload.
///
/// Cancellation is honored while the operation is queued. After the reservation is
/// acquired, validation, admission, the synchronous commit, and observation of the
/// real commit outcome run to completion even if the caller is cancelled. A
/// successful commit then enters an independently bounded reload phase. A reload
/// timeout discards the late result and releases the reservation; it never changes
/// the commit outcome. `AudioViewModel` generations prevent an older completed
/// reload from replacing a newer file model if their MainActor handoffs arrive out
/// of order.
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
        admission: MetadataFileMutationAdmission,
        validateBeforeWrite: @escaping @Sendable () async throws -> Void = {},
        write: @escaping @Sendable (any AudioMetadataPipeline, URL) throws -> AudioMetadataWriteResult
    ) async -> MetadataFileMutationResult {
        let permit = admission.permit
        do {
            let pipeline = metadataPipeline
            let coordinator = fileMutationCoordinator
            let reloadTimeout = reloadTimeout
            return try await coordinator.withExclusiveAccess(to: [url]) {
                try await validateBeforeWrite()
                try Task.checkCancellation()

                // The caller-side cancellation handler exists before the detached
                // worker starts; cancellation synchronously revokes pending
                // admission. Once admitted, revocation is a no-op and the real
                // commit outcome is observed and reported.
                return await withTaskCancellationHandler {
                    await Task.detached(priority: .userInitiated) {
                        do {
                            switch admission {
                            case .reviewed(let target, let permit):
                                try validateExpectedFileFingerprint(target.fingerprint, at: url)
                                switch permit.admit() {
                                case .admitted:
                                    break
                                case .revoked(.cancelled):
                                    return .cancelled
                                case .revoked(.ineligible(let reason)):
                                    return .failure(reason)
                                }
                            case .reviewedDraft(_, let permit):
                                // Identity/revision validation belongs to the
                                // conflict resolver inside the writer.
                                switch permit.admit() {
                                case .admitted:
                                    break
                                case .revoked(.cancelled):
                                    return .cancelled
                                case .revoked(.ineligible(let reason)):
                                    return .failure(reason)
                                }
                            case .legacy(let expectedFileFingerprint):
                                try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)
                            }

                            let writeResult = try write(pipeline, url)

                            do {
                                let reloadedFile = try await withAsyncTimeout(
                                    reloadTimeout,
                                    operationName: String(localized: "Reloading the saved metadata"),
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
                } onCancel: {
                    permit?.revoke(reason: .cancelled)
                }
            }
        } catch is CancellationError {
            permit?.revoke(reason: .cancelled)
            return .cancelled
        } catch {
            return .failure((error as NSError).localizedDescription)
        }
    }

    /// Legacy forwarding for callers that still supply only a fingerprint. This
    /// path carries no permit and is removed after the final family migration.
    func execute(
        at url: URL,
        id: AudioFile.ID,
        expectedFileFingerprint: AudioFileFingerprint?,
        validateBeforeWrite: @escaping @Sendable () async throws -> Void = {},
        write: @escaping @Sendable (any AudioMetadataPipeline, URL) throws -> AudioMetadataWriteResult
    ) async -> MetadataFileMutationResult {
        await execute(
            at: url,
            id: id,
            admission: .legacy(expectedFileFingerprint: expectedFileFingerprint),
            validateBeforeWrite: validateBeforeWrite,
            write: write
        )
    }
}

nonisolated func validateExpectedFileFingerprint(
    _ expectedFileFingerprint: AudioFileFingerprint?,
    at url: URL
) throws {
    guard let expectedFileFingerprint else { return }
    try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)
}

/// Strict variant: the captured fingerprint is always verified inside the
/// reservation before the writer (and before admission).
nonisolated func validateExpectedFileFingerprint(
    _ expectedFileFingerprint: AudioFileFingerprint,
    at url: URL
) throws {
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
