import Foundation
import TagLibAudioMetadata
@testable import AudioMator

/// Test-only migration seam for call sites that previously used the removed mixed
/// `persistMetadataEdit` helper.
///
/// It deliberately does **not** re-create optional production authority: the write
/// still goes through the explicit reviewed or conflict-aware draft routes with a
/// captured target and nonoptional package revision. Navigation and validation
/// stay in the test call sites; this helper only maps the old shape onto the new
/// routes so named test identities keep exercising the same behavior.
@MainActor
extension AudioViewModel {
    func persistReviewedEditForTest(
        _ edit: SingleFileEditModel,
        to file: AudioFile,
        comparedTo sourceFile: AudioFile? = nil,
        syncInspectorAfterReload: Bool = true,
        expectedFileFingerprint: AudioFileFingerprint? = nil,
        expectedMetadataVersion: MetadataFileVersion? = nil
    ) async -> MetadataWriteExecutionResult {
        guard !file.requiresMetadataRefreshBeforeWriting else {
            return .failure(
                String(localized: "The file couldn’t be checked after it moved. Before editing, choose Reload from Disk from the file’s context menu. Unsaved Inspector edits must be discarded to reload.")
            )
        }
        guard isTagWriteSupportedExtension(file.url.pathExtension) else {
            return .failure(String(localized: "AudioMator doesn't support saving metadata to this file format."))
        }

        let baselineFile = sourceFile ?? file
        let editPayload = MetadataEditPayload(edit, comparedTo: baselineFile)
        if let message = editPayload.numberPairValidationMessage {
            return .failure(message)
        }
        let unsupportedFields = unsupportedMetadataWriteFields(
            in: editPayload,
            forFileExtension: file.url.pathExtension
        )
        if !unsupportedFields.isEmpty {
            let labels = ListFormatter.localizedString(byJoining: unsupportedFields.map {
                MetadataFieldRegistry.schema(for: $0)?.displayName ?? String(localized: "Metadata field")
            }.sorted())
            return .failure(
                String(localized: "Changes to \(labels) can’t be saved in this file format. No changes were saved.")
            )
        }

        let fingerprint = expectedFileFingerprint
            ?? baselineFile.fileFingerprint
            ?? file.fileFingerprint
        let version = expectedMetadataVersion
            ?? baselineFile.metadataFileVersion
            ?? file.metadataFileVersion
        guard let fingerprint, let version else {
            return .failure(
                String(localized: "The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before continuing.")
            )
        }

        let target: ReviewedMetadataTarget
        if let sourceFile, let sourceTarget = ReviewedMetadataTarget(verified: sourceFile) {
            target = sourceTarget
        } else {
            target = ReviewedMetadataTarget(
                id: file.id,
                url: file.url,
                fingerprint: fingerprint,
                version: version
            )
        }

        guard let projection = try? TagLibAudioMetadataPipeline().projectMetadataWrite(
            .semantic(editPayload),
            fileExtension: file.url.pathExtension
        ) else {
            return .failure(
                String(localized: "The file couldn’t be checked for changes. Choose Reload from Disk from its context menu before continuing.")
            )
        }
        switch projection.validation {
        case .executable:
            break
        case .rejected(let message):
            return .failure(message)
        case .unsupported(let fields):
            let labels = ListFormatter.localizedString(byJoining: fields.map {
                MetadataFieldRegistry.schema(for: $0)?.displayName ?? String(localized: "Metadata field")
            }.sorted())
            return .failure(
                String(localized: "Changes to \(labels) can’t be saved in this file format. No changes were saved.")
            )
        }

        let write = ReviewedMetadataWrite(
            target: target,
            intent: .semantic(editPayload),
            projection: projection
        )
        let publication: MetadataPublicationPolicy = syncInspectorAfterReload ? .immediate : .batched
        let result: MetadataWriteExecutionResult
        if let sourceFile, let baseline = sourceFile.metadataConflictBaseline {
            result = await executeReviewedDraftMetadataWrite(
                ReviewedMetadataDraft(
                    write: write,
                    baseline: baseline,
                    policy: MetadataConflictPolicy.load(from: conflictPolicyDefaults)
                ),
                publication: publication
            )
        } else {
            result = await executeReviewedMetadataWrite(write, publication: publication)
        }

        if case .success(let success) = result, success.didRefreshFileModel, syncInspectorAfterReload {
            refreshInspectorDraftAfterAcceptedPublication()
        }
        return result
    }
}

/// One low-level executor admission for tests that exercise reservation, reload
/// and cancellation mechanics through the reviewed route.
@MainActor
struct ReviewedTestAdmission {
    let url: URL
    let id: UUID
    let admission: MetadataFileMutationAdmission
    let version: MetadataFileVersion
    private let directory: URL?

    init(name: String = "mutation.mp3", id: UUID = UUID()) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewedTestAdmission-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: 32).write(to: url)
        try self.init(existingURL: url, id: id, directory: directory)
    }

    init(existingURL: URL, id: UUID = UUID(), directory: URL? = nil) throws {
        guard let version = AudioFileTestFactory.fixtureFileVersion else {
            throw CocoaError(.fileReadUnknown)
        }
        let fingerprint = try AudioFileFingerprint.capture(at: existingURL)
        let target = ReviewedMetadataTarget(
            id: id,
            url: existingURL,
            fingerprint: fingerprint,
            version: version
        )
        self.url = existingURL
        self.id = id
        self.admission = .reviewed(target, permit: MetadataCommitPermit())
        self.version = version
        self.directory = directory
    }

    func removeDirectory() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
