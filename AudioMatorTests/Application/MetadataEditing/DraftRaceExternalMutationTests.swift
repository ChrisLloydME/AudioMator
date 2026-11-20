import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

#if os(macOS)
/// AM-06 gap-closure: external mutations started while a live Inspector draft
/// exists (raw Metadata Editor commit, rename transaction, filename/exchange
/// plan writes) must never reset or replace that draft. Drafts are created
/// during the paused operation because the entry guards deliberately reject a
/// dirty draft at start.
nonisolated final class DraftRaceExternalMutationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var authorizedRoot: URL?

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - Raw Metadata Editor commit

    @MainActor
    func testRawCommitDoesNotDiscardDraftCreatedDuringOperation() async throws {
        let rawURL = try makeTemporaryCopy(of: "testAudioFile.flac")
        let otherURL = try makeTemporaryCopy(of: "testAudioFile.mp3")
        let realPipeline = TagLibAudioMetadataPipeline()
        let rawFile = try await realPipeline.loadAudioFile(at: rawURL, id: UUID())
        let otherFile = AudioFileTestFactory.makeDisplayOnly(
            id: UUID(),
            url: otherURL,
            title: "Other"
        )
        let gate = OperationGate(operation: .rawPatchWrite)
        let pipeline = GatedPipeline(inner: realPipeline, gate: gate)
        let viewModel = try makeAuthorizedViewModel(pipeline: pipeline)
        viewModel.mergeQuickImportFiles([rawFile, otherFile])

        let applyTask = Task {
            await viewModel.applyRawMetadataPropertyMaps(
                [rawFile.id: ["TITLE": ["Raw Title"]]],
                to: [MetadataEditorTarget(file: rawFile)]
            )
        }
        let reachedGate = await gate.waitUntilBlocked()
        XCTAssertTrue(reachedGate, "Raw apply never reached the gated writer")

        // The batch is mid-flight: create and edit a different file's draft.
        viewModel.setSelectedAudioIDs([otherFile.id])
        viewModel.edit?.title = "Draft Created During Raw Apply"
        let draftIdentity = viewModel.inspectorDraftIdentity
        let otherBaseline = viewModel.inspectorDraft?.baselinesByID[otherFile.id]?.snapshotID
        XCTAssertEqual(draftIdentity?.targetIDs, [otherFile.id])
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        gate.open()
        let result = await applyTask.value

        XCTAssertEqual(result.succeededTargetIDs, [rawFile.id], "HUD: \(viewModel.metadataWriteHUD?.subtitle ?? "nil")")
        XCTAssertEqual(result.failedTargetIDs, [])
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .success, "\(viewModel.metadataWriteHUD?.title ?? "") | \(viewModel.metadataWriteHUD?.subtitle ?? "")")
        XCTAssertEqual(viewModel.edit?.title, "Draft Created During Raw Apply")
        XCTAssertEqual(viewModel.editSourceFileID, otherFile.id)
        XCTAssertEqual(viewModel.inspectorDraftIdentity?.sessionID, draftIdentity?.sessionID)
        XCTAssertEqual(viewModel.inspectorDraft?.baselinesByID[otherFile.id]?.snapshotID, otherBaseline)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(viewModel.committedFile(withID: rawFile.id)?.title, "Raw Title")
    }

    // MARK: - Rename transaction

    @MainActor
    func testRenameDoesNotDiscardDraftCreatedDuringOperation() async throws {
        let renameURL = try makeTemporaryCopy(of: "testAudioFile.flac")
        let otherURL = try makeTemporaryCopy(of: "testAudioFile.mp3")
        let realPipeline = TagLibAudioMetadataPipeline()
        let renameFile = try await realPipeline.loadAudioFile(at: renameURL, id: UUID())
        let otherFile = AudioFileTestFactory.makeDisplayOnly(
            id: UUID(),
            url: otherURL,
            title: "Other"
        )
        let gate = OperationGate(operation: .load)
        let pipeline = GatedPipeline(inner: realPipeline, gate: gate)
        let viewModel = try makeAuthorizedViewModel(pipeline: pipeline)
        viewModel.mergeQuickImportFiles([renameFile, otherFile])
        viewModel.setSelectedAudioIDs([otherFile.id])
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)

        let plan = makeFileRenamePlan(template: "am06-renamed-file", targetFiles: [renameFile])
        XCTAssertEqual(plan.operations.count, 1, "Expected a single actionable rename operation")
        let renameTask = Task { await viewModel.renameFiles(using: plan) }
        let reachedGate = await gate.waitUntilBlocked()
        XCTAssertTrue(reachedGate, "Rename never reached the gated readback")

        // The transaction is mid-flight: edit the currently selected other file.
        viewModel.edit?.title = "Draft Created During Rename"
        let draftIdentity = viewModel.inspectorDraftIdentity
        let otherBaseline = viewModel.inspectorDraft?.baselinesByID[otherFile.id]?.snapshotID
        XCTAssertEqual(draftIdentity?.targetIDs, [otherFile.id])

        gate.open()
        let result = await renameTask.value

        XCTAssertNil(result.failureMessage)
        XCTAssertEqual(result.renamed, 1)
        XCTAssertEqual(result.recoveryItems.count, 0)
        XCTAssertNotNil(viewModel.metadataWriteHUD, "Rename must report its outcome")
        XCTAssertEqual(viewModel.edit?.title, "Draft Created During Rename")
        XCTAssertEqual(viewModel.editSourceFileID, otherFile.id)
        XCTAssertEqual(viewModel.inspectorDraftIdentity?.sessionID, draftIdentity?.sessionID)
        XCTAssertEqual(viewModel.inspectorDraft?.baselinesByID[otherFile.id]?.snapshotID, otherBaseline)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        let expectedDestination = plan.operations[0].destinationURL
        XCTAssertEqual(viewModel.committedFile(withID: renameFile.id)?.url, expectedDestination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDestination.path))
    }

    // MARK: - Filename / exchange plan writes

    @MainActor
    func testFilenamePlanCompletionDoesNotDiscardDifferentFileDraft() async throws {
        let planURL = try makeTemporaryCopy(of: "testAudioFile.flac")
        let otherURL = try makeTemporaryCopy(of: "testAudioFile.mp3")
        let realPipeline = TagLibAudioMetadataPipeline()
        let planFile = try await realPipeline.loadAudioFile(at: planURL, id: UUID())
        let otherFile = AudioFileTestFactory.makeDisplayOnly(id: UUID(), url: otherURL, title: "Other")
        let gate = OperationGate(operation: .metadataWrite)
        let pipeline = GatedPipeline(inner: realPipeline, gate: gate)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([planFile, otherFile])
        let entry = try makeFilenameEntry(for: planFile, title: "From Filename Plan")

        let applyTask = Task { await viewModel.applyFilenameMetadataPlan([entry]) }
        let reachedGate = await gate.waitUntilBlocked()
        XCTAssertTrue(reachedGate, "Filename plan never reached the gated writer")

        viewModel.setSelectedAudioIDs([otherFile.id])
        viewModel.edit?.title = "Draft Created During Plan Write"
        let sessionID = viewModel.inspectorDraftIdentity?.sessionID

        gate.open()
        let summary = await applyTask.value

        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertEqual(summary?.failureIssues.count, 0)
        XCTAssertEqual(viewModel.edit?.title, "Draft Created During Plan Write")
        XCTAssertEqual(viewModel.inspectorDraftIdentity?.sessionID, sessionID)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testExchangePlanCompletionDoesNotDiscardSameTargetDraftCreatedDuringOperation() async throws {
        let planURL = try makeTemporaryCopy(of: "testAudioFile.flac")
        let realPipeline = TagLibAudioMetadataPipeline()
        let planFile = try await realPipeline.loadAudioFile(at: planURL, id: UUID())
        let gate = OperationGate(operation: .metadataWrite)
        let pipeline = GatedPipeline(inner: realPipeline, gate: gate)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([planFile])
        let entry = try makeExchangeEntry(for: planFile, title: "From Exchange Plan")

        let applyTask = Task { await viewModel.applyMetadataExchangeWriteEntries([entry]) }
        let reachedGate = await gate.waitUntilBlocked()
        XCTAssertTrue(reachedGate, "Exchange plan never reached the gated writer")

        // Same target as the batch: the draft is created while the batch runs.
        viewModel.setSelectedAudioIDs([planFile.id])
        viewModel.edit?.title = "Draft Created During Exchange Plan"
        let sessionID = viewModel.inspectorDraftIdentity?.sessionID
        let baselineSnapshotID = viewModel.inspectorDraft?.baselinesByID[planFile.id]?.snapshotID

        gate.open()
        let summary = await applyTask.value

        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertEqual(summary?.failureIssues.count, 0)
        XCTAssertEqual(viewModel.edit?.title, "Draft Created During Exchange Plan")
        XCTAssertEqual(viewModel.inspectorDraftIdentity?.sessionID, sessionID)
        XCTAssertEqual(viewModel.inspectorDraft?.baselinesByID[planFile.id]?.snapshotID, baselineSnapshotID)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
    }

    // MARK: - Hidden Quick Import source rename publication

    @MainActor
    func testRenameWhileQuickImportHiddenPublishesHiddenRowAndBinding() async throws {
        let quickImportURL = try makeTemporaryCopy(of: "testAudioFile.flac")
        let watchedDirectory = try makeTemporaryDirectory()
        let suiteName = "AudioMatorDraftRace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folderStore = WatchedFolderStore(userDefaults: defaults)
        let folder = try folderStore.makeFolder(from: watchedDirectory)
        let authorizedFolder = try folderStore.makeFolder(from: authorizedRootDirectory())
        folderStore.saveFolders([folder, authorizedFolder])

        let realPipeline = TagLibAudioMetadataPipeline()
        let pipeline = GatedPipeline(inner: realPipeline, gate: nil)
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorDraftRace-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let journalStore = LocalRenameJournalStore(
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AudioMatorDraftRaceJournal-\(UUID().uuidString)", isDirectory: true)
        )
        let viewModel = AudioViewModel(
            watchedFolderStore: folderStore,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: logURL),
            conflictPolicyDefaults: defaults,
            renameJournalStore: journalStore,
            renameJournalAutoClassification: false
        )
        let quickImportFile = try await realPipeline.loadAudioFile(at: quickImportURL, id: UUID())
        viewModel.mergeQuickImportFiles([quickImportFile])

        // The watched-folder sidebar is the visible source; Quick Import is hidden.
        viewModel.setSidebarSelection(.watchedFolder(folder.id))
        XCTAssertTrue(viewModel.files.isEmpty)
        XCTAssertFalse(viewModel.files.contains { $0.id == quickImportFile.id })

        // Use the production verified-move publication/readback seam for this
        // hidden-source check so the test isolates F3 source-membership publication
        // from the F5-owned rename-journal identity comparison. The end-to-end
        // rename transaction and its report are covered by
        // testRenameDoesNotDiscardDraftCreatedDuringOperation.
        let destinationURL = quickImportURL.deletingLastPathComponent()
            .appendingPathComponent("am06-hidden-renamed-file.flac", isDirectory: false)
        try FileManager.default.moveItem(at: quickImportURL, to: destinationURL)
        let receipt = FileRenameMoveReceipt(
            moveID: FileMoveID(),
            fileID: quickImportFile.id,
            sourceURL: quickImportURL,
            destinationURL: destinationURL,
            entryIdentity: try FileEntryIdentityCapture.capture(at: destinationURL)
        )
        viewModel.publishMovePlaceholders([receipt])
        let readbackWarnings = await viewModel.readBackMovedFiles([receipt])
        XCTAssertTrue(
            readbackWarnings.isEmpty,
            "Move readback warnings: \(readbackWarnings.joined(separator: " | "))"
        )

        // Hidden-source publication by stable ID: membership, URL and observation.
        let hiddenPublishedFile = try XCTUnwrap(viewModel.committedFile(withID: quickImportFile.id))
        XCTAssertEqual(hiddenPublishedFile.url, destinationURL)
        XCTAssertEqual(hiddenPublishedFile.id, quickImportFile.id)
        XCTAssertNotNil(hiddenPublishedFile.observation)
        XCTAssertEqual(
            hiddenPublishedFile.fileFingerprint,
            try AudioFileFingerprint.capture(at: destinationURL)
        )
        XCTAssertEqual(
            hiddenPublishedFile.metadataFileVersion,
            try realPipeline.metadataFileVersion(at: destinationURL)
        )

        // Switching back to the previously hidden collection shows the renamed row
        // with its original identity and current observation, and it is selectable.
        viewModel.setSidebarSelection(.quickImport)
        let row = try XCTUnwrap(viewModel.files.first(where: { $0.id == quickImportFile.id }))
        XCTAssertEqual(row.url, destinationURL)
        let reloadedDestination = try await realPipeline.loadAudioFile(
            at: destinationURL,
            id: quickImportFile.id
        )
        XCTAssertEqual(row.title, reloadedDestination.title)
        XCTAssertNil(viewModel.files.first(where: { $0.url == quickImportURL }))

        viewModel.setSelectedAudioIDs([quickImportFile.id])
        XCTAssertEqual(viewModel.selectedAudioIDs, [quickImportFile.id])
        XCTAssertEqual(viewModel.editSourceFileID, quickImportFile.id)
        XCTAssertEqual(viewModel.edit?.title, row.title)
    }

    // MARK: - Helpers



    @MainActor
    private func authorizedRootDirectory() throws -> URL {
        if let authorizedRoot { return authorizedRoot }
        let root = try makeTemporaryDirectory()
        authorizedRoot = root
        return root
    }

    @MainActor
    private func makeAuthorizedViewModel(
        pipeline: any AudioMetadataPipeline
    ) throws -> AudioViewModel {
        let root = try authorizedRootDirectory()
        let suiteName = "AudioMatorDraftRace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let folderStore = WatchedFolderStore(userDefaults: defaults)
        let authorizedFolder = try folderStore.makeFolder(from: root)
        XCTAssertTrue(folderStore.saveFolders([authorizedFolder]))
        return AudioViewModel(
            watchedFolderStore: folderStore,
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: AudioViewModelTestFactory.makeIssueLogStore(),
            conflictPolicyDefaults: defaults,
            renameJournalStore: LocalRenameJournalStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("AudioMatorDraftRaceJournal-\(UUID().uuidString)", isDirectory: true)
            ),
            renameJournalAutoClassification: false
        )
    }

    @MainActor
    private func makeTemporaryDirectory() throws -> URL {
        // Resolve the /var -> /private/var alias so every test URL, the rename
        // journal and the loader observe the same lexical directory entry.
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("AudioMatorDraftRace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    @MainActor
    private func makeTemporaryCopy(of fixtureName: String) throws -> URL {
        let directory = try authorizedRootDirectory()
            .appendingPathComponent("copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let destination = directory.appendingPathComponent(fixtureName)
        let source = try XCTUnwrap(fixtureSourceURL(named: fixtureName))
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    @MainActor
    private func fixtureSourceURL(named name: String) -> URL? {
        let bundle = Bundle(for: DraftRaceExternalMutationTests.self)
        return bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: name, withExtension: nil)
    }

    @MainActor
    private func makeFilenameEntry(
        for file: AudioFile,
        title: String
    ) throws -> FilenameMetadataWriteEntry {
        var edit = SingleFileEditModel(from: file)
        edit.title = title
        let write = try XCTUnwrap(
            ReviewedMetadataWriteFactory.semanticWrite(edit: edit, comparedTo: file)
        )
        return FilenameMetadataWriteEntry(
            fileName: file.url.lastPathComponent,
            write: write,
            previewValues: [.title: title]
        )
    }

    @MainActor
    private func makeExchangeEntry(
        for file: AudioFile,
        title: String
    ) throws -> MetadataExchangeWriteEntry {
        var edit = SingleFileEditModel(from: file)
        edit.title = title
        let write = try XCTUnwrap(
            ReviewedMetadataWriteFactory.semanticWrite(edit: edit, comparedTo: file)
        )
        return MetadataExchangeWriteEntry(
            fileName: file.url.lastPathComponent,
            write: write,
            resolvedIntent: nil
        )
    }
}

// MARK: - Gated pipeline

/// Operations the gated test double can pause.
private nonisolated enum GatedPipelineOperation: Sendable, Equatable {
    case load
    case metadataWrite
    case rawPatchWrite
}

private nonisolated final class GatedPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let inner: any AudioMetadataPipeline
    private let gate: OperationGate?

    init(inner: any AudioMetadataPipeline, gate: OperationGate?) {
        self.inner = inner
        self.gate = gate
    }

    nonisolated var requiresTransactionalDirectoryAccess: Bool {
        // The test grants the temporary root explicitly; never open a folder
        // picker from the standalone test process.
        false
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if let gate {
            await gate.blockAsynchronouslyIfMatching(.load)
        }
        return try await inner.loadAudioFile(at: url, id: id)
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        try inner.conflictSnapshot(for: url)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try inner.metadataFileVersion(at: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        inner.rawMetadataDumpText(for: url)
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        try inner.rawMetadataValueMap(for: url)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        gate?.blockSynchronouslyIfMatching(.metadataWrite)
        return try inner.writeMetadata(edit, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        gate?.blockSynchronouslyIfMatching(.rawPatchWrite)
        return try inner.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try inner.eraseAllMetadata(at: url, expectedVersion: expectedVersion)
    }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try inner.projectMetadataWrite(intent, fileExtension: fileExtension)
    }
}

/// One-shot operation gate used to keep an external mutation paused while the
/// test creates an Inspector draft. It never blocks the main actor: synchronous
/// writer closures block their worker with short sleeps; async loads await short
/// sleeps; the test polls `waitUntilBlocked` asynchronously.


private nonisolated final class OperationGate: @unchecked Sendable {
    private let operation: GatedPipelineOperation
    private let lock = NSLock()
    private var hasStarted = false
    private var isOpen = false

    init(operation: GatedPipelineOperation) {
        self.operation = operation
    }

    func blockSynchronouslyIfMatching(_ candidate: GatedPipelineOperation) {
        guard candidate == operation else { return }
        markStarted()
        let deadline = Date().addingTimeInterval(30)
        while !isOpened, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    func blockAsynchronouslyIfMatching(_ candidate: GatedPipelineOperation) async {
        guard candidate == operation else { return }
        markStarted()
        let deadline = Date().addingTimeInterval(30)
        while !isOpened, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func waitUntilBlocked(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var iterations = 0
        while !hasStartedNow, Date() < deadline {
            iterations += 1
            if iterations % 100 == 0 {
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return hasStartedNow
    }

    func open() {
        lock.lock()
        isOpen = true
        lock.unlock()
    }

    private func markStarted() {
        lock.lock()
        hasStarted = true
        lock.unlock()
    }

    private var hasStartedNow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasStarted
    }

    private var isOpened: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOpen
    }
}
#endif
