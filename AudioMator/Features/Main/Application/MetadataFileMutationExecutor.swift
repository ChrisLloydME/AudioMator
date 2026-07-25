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

/// Owns one file's persistence boundary from stale-file validation through reload.
///
/// The path reservation intentionally remains held while the persisted snapshot is
/// reloaded. A rename or second write therefore cannot interleave between the
/// successful write and the snapshot that represents it.
struct MetadataFileMutationExecutor: Sendable {
    let metadataPipeline: any AudioMetadataPipeline
    let fileMutationCoordinator: FileMutationCoordinator

    func execute(
        at url: URL,
        id: AudioFile.ID,
        expectedFileFingerprint: AudioFileFingerprint?,
        write: @escaping @Sendable (any AudioMetadataPipeline, URL) throws -> AudioMetadataWriteResult
    ) async -> MetadataFileMutationResult {
        do {
            return try await fileMutationCoordinator.withExclusiveAccess(to: [url]) {
                await Task.detached(priority: .userInitiated) {
                    do {
                        try validateExpectedFileFingerprint(expectedFileFingerprint, at: url)
                        let writeResult = try write(metadataPipeline, url)

                        do {
                            let reloadedFile = try await metadataPipeline.loadAudioFile(at: url, id: id)
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
