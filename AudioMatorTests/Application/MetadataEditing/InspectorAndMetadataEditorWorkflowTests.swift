import XCTest
import os
import TagLibAudioMetadata
@testable import AudioMator

// MARK: – Strict reviewed-write test entries

@MainActor
private func makeTestExchangeEntry(
    file: AudioFile,
    values: [MetadataExchangeField: String],
    projection: MetadataWriteProjection? = nil
) -> MetadataExchangeWriteEntry {
    var edit = SingleFileEditModel(from: file)
    for field in MetadataExchangeField.allCases {
        guard let value = values[field] else { continue }
        field.applyImportedValue(value, to: &edit, preservingNumberPairComponents: true)
    }
    let payload = MetadataEditPayload(edit, comparedTo: file)
    let target = ReviewedMetadataTarget(verified: file)!
    let resolvedProjection = projection ?? MetadataWriteProjection(
        requestedFields: payload.requestedFields,
        effectiveFields: payload.requestedFields,
        validation: .executable,
        isEncoderNoOp: false
    )
    return MetadataExchangeWriteEntry(
        fileName: file.url.lastPathComponent,
        write: ReviewedMetadataWrite(target: target, intent: .semantic(payload), projection: resolvedProjection),
        resolvedIntent: nil
    )
}

@MainActor
private func makeTestFilenameEntry(
    file: AudioFile,
    values: [FileRenameMetadataField: String],
    projection: MetadataWriteProjection? = nil
) -> FilenameMetadataWriteEntry {
    var edit = SingleFileEditModel(from: file)
    for field in FileRenameMetadataField.allCases {
        guard let value = values[field] else { continue }
        field.applyExtractedValue(value, to: &edit)
    }
    let payload = MetadataEditPayload(edit, comparedTo: file)
    let target = ReviewedMetadataTarget(verified: file)!
    let resolvedProjection = projection ?? MetadataWriteProjection(
        requestedFields: payload.requestedFields,
        effectiveFields: payload.requestedFields,
        validation: .executable,
        isEncoderNoOp: false
    )
    return FilenameMetadataWriteEntry(
        fileName: file.url.lastPathComponent,
        write: ReviewedMetadataWrite(target: target, intent: .semantic(payload), projection: resolvedProjection),
        previewValues: values
    )
}

private func rejectedTestProjection(_ message: String) -> MetadataWriteProjection {
    MetadataWriteProjection(validation: .rejected(message))
}

#if os(macOS)
nonisolated final class InspectorAndMetadataEditorWorkflowTests: XCTestCase {
    @MainActor
    func testVisibleFileRevisionAndSelectionLookupRefreshAfterSameIDReload() {
        let original = AudioFileTestFactory.make(title: "Original")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingMetadataPipeline())
        viewModel.files = [original]
        let revision = viewModel.filesRevision
        viewModel.setSelectedAudioIDs([original.id, UUID()])
        XCTAssertEqual(viewModel.selectedAudioIDs, [original.id])
        XCTAssertEqual(viewModel.filesRevision, revision)
        viewModel.edit?.title = "Draft"
        XCTAssertEqual(viewModel.filesRevision, revision)

        let reloaded = AudioFileTestFactory.make(id: original.id, url: original.url, title: "Reloaded")
        viewModel.files = [reloaded]
        XCTAssertNotEqual(viewModel.filesRevision, revision)
        XCTAssertEqual(viewModel.selectedFiles.first?.title, "Reloaded")
        viewModel.updateEditForSelection()
        XCTAssertEqual(viewModel.edit?.title, "Reloaded")
        viewModel.files = []
        viewModel.setSelectedAudioIDs([original.id])
        XCTAssertTrue(viewModel.selectedAudioIDs.isEmpty)
        XCTAssertTrue(viewModel.selectedFiles.isEmpty)
    }

    @MainActor
    func testArtworkPreviewTracksSingleMultiReplacementRemovalAndDraftEdits() {
        let file = AudioFileTestFactory.make(artworkData: Data([1]))
        let other = AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/other-artwork.mp3"), artworkData: Data([1])
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles([file, other])
        viewModel.setSelectedAudioIDs([file.id])
        XCTAssertEqual(viewModel.inspectorArtworkPreview.sourceID, file.snapshotID)
        viewModel.edit?.title = "Changed title"
        XCTAssertEqual(viewModel.inspectorArtworkPreview.sourceID, file.snapshotID)

        let pending = PendingArtwork(data: Data([2]), mimeType: "image/png")
        viewModel.edit?.artworkEditAction = .replace(pending)
        XCTAssertEqual(viewModel.inspectorArtworkPreview.sourceID, pending.id)
        viewModel.edit?.artworkEditAction = .remove
        XCTAssertNil(viewModel.inspectorArtworkPreview.sourceID)
        viewModel.cancelEditing()
        XCTAssertEqual(viewModel.inspectorArtworkPreview.sourceID, file.snapshotID)

        viewModel.setSelectedAudioIDs([file.id, other.id])
        XCTAssertNotNil(viewModel.inspectorArtworkPreview.sourceID)
        let sharedSourceID = viewModel.inspectorArtworkPreview.sourceID
        viewModel.multiEdit?.setText("Changed", for: .title)
        XCTAssertEqual(viewModel.inspectorArtworkPreview.sourceID, sharedSourceID)
        viewModel.multiEdit?.artworkEditAction = .replace(pending)
        XCTAssertEqual(viewModel.inspectorArtworkPreview.sourceID, pending.id)
        viewModel.setSelectedAudioIDs([])
        XCTAssertNil(viewModel.inspectorArtworkPreview.sourceID)
    }

    @MainActor
    func testToolbarAddWatchedFolderRequestsSidebarSelectionChange() {
        let notificationCenter = NotificationCenter()
        let expectedSelection = SidebarSelection.watchedLibrary
        let receivedSelection = OSAllocatedUnfairLock<SidebarSelection?>(initialState: nil)
        let observer = notificationCenter.addObserver(
            forName: .requestSidebarSelectionChange,
            object: nil,
            queue: nil
        ) { notification in
            let selection = notification.object as? SidebarSelection
            receivedSelection.withLock { $0 = selection }
        }
        defer { notificationCenter.removeObserver(observer) }

        ToolbarEditCommands.performAddWatchedFolders(
            using: { expectedSelection },
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(receivedSelection.withLock { $0 }, expectedSelection)
    }

    @MainActor
    func testSidebarSelectionRequestPreservesDraftUntilDiscardIsConfirmed() {
        var pendingConfirmation: (() -> Void)?
        var didDiscardDraft = false
        var didCommitSelection = false

        ContentView.performSidebarSelectionChange(
            hasUnsavedInspectorChanges: true,
            suppressesDiscardWarning: false,
            requestDiscardConfirmation: { pendingConfirmation = $0 },
            discardInspectorEdits: { didDiscardDraft = true },
            commitSelection: { didCommitSelection = true }
        )

        XCTAssertNotNil(pendingConfirmation)
        XCTAssertFalse(didDiscardDraft)
        XCTAssertFalse(didCommitSelection)

        pendingConfirmation?()

        XCTAssertTrue(didDiscardDraft)
        XCTAssertTrue(didCommitSelection)
    }

    @MainActor
    func testToolbarAddWatchedFolderDoesNotRequestSelectionWhenPickerIsCancelled() {
        let notificationCenter = NotificationCenter()
        let requestCount = OSAllocatedUnfairLock(initialState: 0)
        let observer = notificationCenter.addObserver(
            forName: .requestSidebarSelectionChange,
            object: nil,
            queue: nil
        ) { _ in
            requestCount.withLock { $0 += 1 }
        }
        defer { notificationCenter.removeObserver(observer) }

        ToolbarEditCommands.performAddWatchedFolders(
            using: { nil },
            notificationCenter: notificationCenter
        )

        XCTAssertEqual(requestCount.withLock { $0 }, 0)
    }

    @MainActor
    func testExplicitInspectorSelectionOrderMatchesInspectorControl() {
        XCTAssertEqual(
            ExplicitInspectorSelection.inspectorSelectionOrder.map(\.displayName),
            ["Unset", "Explicit", "Clean", "Not Explicit"]
        )
    }

    @MainActor
    func testExplicitInspectorSelectionRoundTripsAllFourStates() {
        let cases: [(ContentAdvisory?, String)] = [
            (nil, "Unset"),
            (.explicit, "Explicit"),
            (.clean, "Clean"),
            (.notExplicit, "Not Explicit")
        ]

        for (advisory, displayName) in cases {
            let selection = ExplicitInspectorSelection(contentAdvisory: advisory)
            XCTAssertEqual(selection.contentAdvisory, advisory)
            XCTAssertEqual(selection.displayName, displayName)
        }
    }

    @MainActor
    func testInspectorSelectionSyncPreservesAllExplicitStates() {
        let cases: [ContentAdvisory?] = [nil, .explicit, .clean, .notExplicit]
        let files = cases.enumerated().map { index, advisory in
            AudioFileTestFactory.make(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/\(index).m4a"),
                title: "\(index)",
                contentAdvisory: advisory
            )
        }
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles(files)

        for file in files {
            viewModel.setSelectedAudioIDs([file.id])
            viewModel.updateEditForSelection()

            XCTAssertEqual(viewModel.editSourceFileID, file.id)
            XCTAssertEqual(viewModel.edit?.contentAdvisory, file.contentAdvisory)
            XCTAssertEqual(
                ExplicitInspectorSelection(contentAdvisory: viewModel.edit?.contentAdvisory).displayName,
                file.contentAdvisory?.displayName ?? "Unset"
            )
        }
    }

    @MainActor
    func testInspectorSelectionSyncCreatesSingleAndMultiEditModels() {
        let firstID = UUID()
        let secondID = UUID()
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: URL(fileURLWithPath: "/tmp/01.mp3"),
            title: "First",
            album: "Shared Album"
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: URL(fileURLWithPath: "/tmp/02.mp3"),
            title: "Second",
            album: "Shared Album"
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles([first, second])

        viewModel.setSelectedAudioIDs([firstID])
        viewModel.updateEditForSelection()

        XCTAssertEqual(viewModel.edit?.title, "First")
        XCTAssertEqual(viewModel.editSourceFileID, firstID)
        XCTAssertNil(viewModel.multiEdit)
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)

        viewModel.edit?.title = "First Draft"
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        viewModel.setSelectedAudioIDs([firstID, secondID])
        viewModel.updateEditForSelection()

        XCTAssertNil(viewModel.edit)
        XCTAssertNil(viewModel.editSourceFileID)
        XCTAssertEqual(viewModel.multiEdit?.text(for: .album), "Shared Album")
        XCTAssertEqual(viewModel.multiEdit?.text(for: .title), "")
        XCTAssertEqual(viewModel.multiEdit?.placeholder(for: .title), "Multiple Values")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)

        viewModel.multiEdit?.setText("Batch Album", for: .album)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        viewModel.cancelEditing()
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(viewModel.multiEdit?.text(for: .album), "Shared Album")
    }

    @MainActor
    func testAudioViewModelOwnsSelectionDraftAndVisibleFilePruning() {
        let first = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/selection-owner-01.mp3"),
            title: "First"
        )
        let second = AudioFileTestFactory.make(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/selection-owner-02.mp3"),
            title: "Second"
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles([first, second])

        viewModel.setSelectedAudioIDs([first.id, UUID()])

        XCTAssertEqual(viewModel.selectedAudioIDs, [first.id])
        XCTAssertEqual(viewModel.editSourceFileID, first.id)
        XCTAssertEqual(viewModel.edit?.title, "First")
        XCTAssertNil(viewModel.multiEdit)

        viewModel.setSelectedAudioIDs([first.id, second.id])

        XCTAssertEqual(viewModel.selectedAudioIDs, [first.id, second.id])
        XCTAssertNil(viewModel.edit)
        XCTAssertNotNil(viewModel.multiEdit)

        viewModel.removeQuickImportFile(id: first.id)

        XCTAssertEqual(viewModel.selectedAudioIDs, [second.id])
        XCTAssertEqual(viewModel.editSourceFileID, second.id)
        XCTAssertEqual(viewModel.edit?.title, "Second")
        XCTAssertNil(viewModel.multiEdit)

        viewModel.clearList()

        XCTAssertTrue(viewModel.selectedAudioIDs.isEmpty)
        XCTAssertNil(viewModel.editSourceFileID)
        XCTAssertNil(viewModel.edit)
        XCTAssertNil(viewModel.multiEdit)
    }

    @MainActor
    func testSaveSingleEditsRejectsAnEditOwnedByAnotherFile() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "First", contentAdvisory: .explicit)
        let second = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Second", contentAdvisory: .notExplicit)
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])

        viewModel.setSelectedAudioIDs([firstID])
        var staleEdit = try XCTUnwrap(viewModel.edit)
        staleEdit.title = "Stale first file draft"
        viewModel.edit = staleEdit

        // Simulate a desynchronized inspector: the selection is the second
        // file but the draft still names the first. The guard must prevent the
        // first file's draft from being written to the second.
        viewModel.setSelectedAudioIDs([secondID])
        viewModel.edit = staleEdit
        viewModel.editSourceFileID = firstID
        viewModel.saveSingleEdits()

        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.editSourceFileID, secondID)
        XCTAssertEqual(viewModel.edit?.title, "Second")
    }

    @MainActor
    func testPersistMetadataEditRejectsUnsupportedFieldBeforeMutation() async {
        let id = UUID()
        let file = AudioFileTestFactory.make(
            id: id,
            url: URL(fileURLWithPath: "/tmp/restricted.xm"),
            title: "Allowed title",
            artist: "Original artist"
        )
        var edit = SingleFileEditModel(from: file)
        edit.artist = "Unsupported artist change"
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)

        let result = await viewModel.persistReviewedEditForTest(edit, to: file)

        guard case .failure(let reason) = result else {
            return XCTFail("Expected an unsupported-field failure")
        }
        XCTAssertTrue(reason.contains("can’t be saved in this file format"))
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
    }

    @MainActor
    func testSaveInspectorEditsWritesSingleSelectionAndRefreshesEditModel() async throws {
        let id = UUID()
        let url = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Original",
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        let reloaded = AudioFileTestFactory.make(id: id, url: url, title: "Reloaded")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [url: reloaded],
            fileVersionsByURL: [url: tokens.version]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()
        viewModel.edit?.title = "Draft Title"

        viewModel.saveInspectorEdits()

        try await pipeline.waitForMetadataWriteCount(1)
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [url])
        XCTAssertEqual(pipeline.metadataWrites.first?.payload.title, "Draft Title")
        XCTAssertEqual(viewModel.files.first?.title, "Reloaded")
        XCTAssertEqual(viewModel.edit?.title, "Reloaded")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testSaveInspectorEditsRejectsFileChangedSinceSelection() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorInspectorFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("changed.mp3")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try Data(repeating: 0x41, count: 16).write(to: fileURL)
        let loadedFingerprint = try AudioFileFingerprint.capture(at: fileURL)
        let id = UUID()
        let file = AudioFileTestFactory.make(
            id: id,
            url: fileURL,
            title: "Loaded Title",
            fileFingerprint: loadedFingerprint
        )
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()
        viewModel.edit?.title = "Inspector Draft"

        try Data(repeating: 0x42, count: 32).write(to: fileURL, options: .atomic)
        viewModel.saveInspectorEdits()
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        XCTAssertTrue(
            pipeline.metadataWrites.isEmpty,
            "Inspector writes must fail closed when the file changed after it was loaded."
        )
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertTrue(viewModel.metadataWriteHUD?.subtitle.contains("has changed since it was last checked") == true)
    }

    @MainActor
    func testReloadedSnapshotRefreshesAnUnmodifiedInspectorDraft() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/reloaded-clean-inspector.mp3")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let reloaded = AudioFileTestFactory.make(id: id, url: url, title: "Reloaded")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingMetadataPipeline())

        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.mergeQuickImportFiles([reloaded])

        XCTAssertEqual(viewModel.edit?.title, "Reloaded")
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testInspectorDeltaUsesOriginalDraftDespiteListRefresh() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        let original = AudioFileTestFactory.make(
            url: url,
            title: "Original",
            artist: "Original artist",
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        let pipeline = RecordingMetadataPipeline(
            fileVersionsByURL: [url: tokens.version]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([original.id])
        viewModel.edit?.title = "User title"
        viewModel.mergeQuickImportFiles([
            AudioFileTestFactory.make(
                id: original.id, url: original.url, title: "Original",
                artist: "External artist", includeDefaultFileFingerprint: false
            )
        ])

        viewModel.saveInspectorEdits()
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        let payload = try XCTUnwrap(pipeline.metadataWrites.first?.payload)
        XCTAssertEqual(payload.changedFields, [.title])
        XCTAssertEqual(payload.title, "User title")
    }

    @MainActor
    func testSavingCleanInspectorDoesNotAttemptAFileMutation() {
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        let file = AudioFileTestFactory.make(title: "Unedited")
        viewModel.mergeQuickImportFiles([file])
        viewModel.setSelectedAudioIDs([file.id])

        viewModel.saveInspectorEdits()

        XCTAssertNil(viewModel.metadataSaveProgress)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
    }

    @MainActor
    func testReloadedSnapshotKeepsTheOriginalFingerprintForDirtyInspectorSave() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorInspectorReloadConflict-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("changed.mp3")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try Data(repeating: 0x41, count: 16).write(to: fileURL)
        let original = AudioFileTestFactory.make(
            id: UUID(),
            url: fileURL,
            title: "Original",
            fileFingerprint: try AudioFileFingerprint.capture(at: fileURL)
        )
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([original.id])
        viewModel.edit?.title = "User Draft"

        try Data(repeating: 0x42, count: 32).write(to: fileURL, options: .atomic)
        let externalSnapshot = AudioFileTestFactory.make(
            id: original.id,
            url: fileURL,
            title: "External Change",
            fileFingerprint: try AudioFileFingerprint.capture(at: fileURL)
        )
        viewModel.mergeQuickImportFiles([externalSnapshot])
        viewModel.saveInspectorEdits()
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        XCTAssertEqual(viewModel.edit?.title, "User Draft")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertTrue(viewModel.metadataWriteHUD?.subtitle.contains("has changed since it was last checked") == true)
    }

    @MainActor
    func testSaveInspectorEditsAppliesOnlyModifiedMultiFileFieldsToEachFile() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = try MetadataTestTokens.makeFixtureCopy()
        let secondURL = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock {
            MetadataTestTokens.removeFixtureCopy(at: firstURL)
            MetadataTestTokens.removeFixtureCopy(at: secondURL)
        }
        let firstTokens = try MetadataTestTokens.mintedTokens(at: firstURL)
        let secondTokens = try MetadataTestTokens.mintedTokens(at: secondURL)
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            album: "Old One",
            fileFingerprint: firstTokens.fingerprint,
            metadataFileVersion: firstTokens.version
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            album: "Old Two",
            fileFingerprint: secondTokens.fingerprint,
            metadataFileVersion: secondTokens.version
        )
        let firstReloaded = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "First", album: "Batch Album")
        let secondReloaded = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Second", album: "Batch Album")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ],
            fileVersionsByURL: [
                firstURL: firstTokens.version,
                secondURL: secondTokens.version
            ]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.setSelectedAudioIDs([firstID, secondID])
        viewModel.updateEditForSelection()
        viewModel.multiEdit?.setText("Batch Album", for: .album)

        viewModel.saveInspectorEdits()

        try await pipeline.waitForMetadataWriteCount(2)
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        let writesByURL = Dictionary(uniqueKeysWithValues: pipeline.metadataWrites.map { ($0.url, $0.payload) })
        XCTAssertEqual(writesByURL[firstURL]?.title, "First")
        XCTAssertEqual(writesByURL[firstURL]?.album, "Batch Album")
        XCTAssertEqual(writesByURL[secondURL]?.title, "Second")
        XCTAssertEqual(writesByURL[secondURL]?.album, "Batch Album")
        XCTAssertEqual(viewModel.files.map(\.album), ["Batch Album", "Batch Album"])
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testMetadataEditorRawMapApplyWritesEachTargetAndRefreshesLoadedFiles() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = try MetadataTestTokens.makeFixtureCopy()
        let secondURL = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock {
            MetadataTestTokens.removeFixtureCopy(at: firstURL)
            MetadataTestTokens.removeFixtureCopy(at: secondURL)
        }
        let firstTokens = try MetadataTestTokens.mintedTokens(at: firstURL)
        let secondTokens = try MetadataTestTokens.mintedTokens(at: secondURL)
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            fileFingerprint: firstTokens.fingerprint,
            metadataFileVersion: firstTokens.version
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            fileFingerprint: secondTokens.fingerprint,
            metadataFileVersion: secondTokens.version
        )
        let firstReloaded = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "Raw First")
        let secondReloaded = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Raw Second")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ],
            fileVersionsByURL: [
                firstURL: firstTokens.version,
                secondURL: secondTokens.version
            ]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.setSelectedAudioIDs([firstID])
        viewModel.updateEditForSelection()

        let applyResult = await viewModel.applyRawMetadataPropertyMaps(
            [
                firstID: ["TITLE": ["Raw First"], "CUSTOM": ["One"]],
                secondID: ["TITLE": ["Raw Second"]]
            ],
            to: [
                MetadataEditorTarget(file: first),
                MetadataEditorTarget(file: second)
            ]
        )

        XCTAssertEqual(pipeline.rawMapWrites[firstURL], ["TITLE": "Raw First", "CUSTOM": "One"])
        XCTAssertEqual(pipeline.rawMapWrites[secondURL], ["TITLE": "Raw Second"])
        XCTAssertTrue(applyResult.didApplyAllChanges)
        XCTAssertEqual(applyResult.succeededTargetIDs, [firstID, secondID])
        XCTAssertEqual(viewModel.files.map(\.title), ["Raw First", "Raw Second"])
        XCTAssertEqual(viewModel.edit?.title, "Raw First")
    }

    @MainActor
    func testMetadataEditorRawMapApplyRejectsMissingTargetMap() async throws {
        let url = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        let file = AudioFileTestFactory.make(
            url: url,
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)

        let applyResult = await viewModel.applyRawMetadataPropertyMaps(
            [:],
            to: [MetadataEditorTarget(file: file)]
        )

        XCTAssertTrue(
            pipeline.rawMapWrites.isEmpty,
            "A missing editor map must not be converted into an empty metadata write."
        )
        XCTAssertFalse(applyResult.didApplyAllChanges)
        XCTAssertEqual(applyResult.failedTargetIDs, [file.id])
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertTrue(viewModel.metadataWriteHUD?.subtitle.contains("Metadata wasn’t loaded") == true)
    }

    @MainActor
    func testMetadataEditorRawMapApplyRejectsFileChangedSinceEditorOpened() async throws {
        let fileURL = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fileURL) }
        let tokens = try MetadataTestTokens.mintedTokens(at: fileURL)
        let file = AudioFileTestFactory.make(
            url: fileURL,
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        let pipeline = RecordingMetadataPipeline(
            fileVersionsByURL: [fileURL: tokens.version]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])

        try Data(repeating: 0x42, count: 32).write(to: fileURL, options: .atomic)
        await viewModel.applyRawMetadataPropertyMaps(
            [file.id: ["TITLE": ["Stale Draft"]]],
            to: [MetadataEditorTarget(file: file)]
        )

        XCTAssertTrue(
            pipeline.rawMapWrites.isEmpty,
            "Raw metadata writes must fail closed when the file changed after the editor opened."
        )
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertTrue(viewModel.metadataWriteHUD?.subtitle.contains("has changed since it was last checked") == true)
    }

    @MainActor
    func testEraseMetadataRejectsFileChangedSinceSelection() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorEraseFingerprintTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("changed.mp3")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try Data(repeating: 0x41, count: 16).write(to: fileURL)
        let file = AudioFileTestFactory.make(
            url: fileURL,
            fileFingerprint: try AudioFileFingerprint.capture(at: fileURL)
        )
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])

        try Data(repeating: 0x42, count: 32).write(to: fileURL, options: .atomic)
        let result = await viewModel.persistMetadataErase(file, syncInspectorAfterReload: false)

        guard case .failure(let reason) = result else {
            return XCTFail("Expected metadata erase to reject the stale file.")
        }
        XCTAssertTrue(reason.contains("has changed since it was last checked"))
        XCTAssertEqual(
            pipeline.eraseCount,
            0,
            "Metadata erase must fail closed when the file changed after it was loaded."
        )
    }

    @MainActor
    func testCreateMuseAmpIDsWritesDeterministicCommentPayloadsAndRefreshesLoadedFiles() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = try MetadataTestTokens.makeFixtureCopy()
        let secondURL = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock {
            MetadataTestTokens.removeFixtureCopy(at: firstURL)
            MetadataTestTokens.removeFixtureCopy(at: secondURL)
        }
        let firstTokens = try MetadataTestTokens.mintedTokens(at: firstURL)
        let secondTokens = try MetadataTestTokens.mintedTokens(at: secondURL)
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            album: "Shared Album",
            comment: "Old First",
            albumArtist: "Shared Artist",
            fileFingerprint: firstTokens.fingerprint,
            metadataFileVersion: firstTokens.version
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            album: "Shared Album",
            comment: "Old Second",
            albumArtist: "Shared Artist",
            fileFingerprint: secondTokens.fingerprint,
            metadataFileVersion: secondTokens.version
        )
        let expectedAssignments = MuseAmpCommentIDGenerator.assignments(for: [
            MuseAmpTrackIdentity(album: first.album, albumArtist: first.albumArtist, trackKey: firstURL.path),
            MuseAmpTrackIdentity(album: second.album, albumArtist: second.albumArtist, trackKey: secondURL.path)
        ])
        let firstReloaded = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            album: "Shared Album",
            comment: expectedAssignments[0].commentText,
            albumArtist: "Shared Artist"
        )
        let secondReloaded = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            album: "Shared Album",
            comment: expectedAssignments[1].commentText,
            albumArtist: "Shared Artist"
        )
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.setSelectedAudioIDs([firstID])
        viewModel.updateEditForSelection()

        viewModel.createMuseAmpIDs(for: [first, second])

        try await pipeline.waitForMetadataWriteCount(2)
        try await waitUntil(viewModel.metadataSaveProgress == nil)

        let writesByURL = Dictionary(uniqueKeysWithValues: pipeline.metadataWrites.map { ($0.url, $0.payload) })
        XCTAssertEqual(writesByURL[firstURL]?.comment, expectedAssignments[0].commentText)
        XCTAssertEqual(writesByURL[secondURL]?.comment, expectedAssignments[1].commentText)
        XCTAssertEqual(expectedAssignments[0].albumID, expectedAssignments[1].albumID)
        XCTAssertNotEqual(expectedAssignments[0].trackID, expectedAssignments[1].trackID)
        XCTAssertEqual(viewModel.files.map(\.comment), expectedAssignments.map(\.commentText))
        XCTAssertEqual(viewModel.edit?.comment, expectedAssignments[0].commentText)
    }

    @MainActor
    func testApplyFilenameMetadataPlanWritesExtractedFieldsAndRefreshesSelection() async throws {
        let id = UUID()
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFilenameMetadataWriteTests-\(UUID().uuidString)", isDirectory: true)
        let url = directoryURL.appendingPathComponent("07 - Old Artist - Old Title.mp3")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Old Title",
            artist: "Old Artist",
            album: "Keep Album",
            trackNumberText: "01",
            fileFingerprint: fingerprint
        )
        let reloaded = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Parsed Title",
            artist: "Parsed Artist",
            album: "Keep Album",
            trackNumberText: "07"
        )
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()

        let summary = await viewModel.applyFilenameMetadataPlan([
            makeTestFilenameEntry(file: original, values: [
                .title: "Parsed Title",
                .artist: "Parsed Artist",
                .trackNumberText: "07"
            ])
        ])

        let payload = try XCTUnwrap(pipeline.metadataWrites.first?.payload)
        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [url])
        XCTAssertEqual(payload.title, "Parsed Title")
        XCTAssertEqual(payload.artist, "Parsed Artist")
        XCTAssertEqual(payload.trackNumberText, "07")
        XCTAssertEqual(payload.album, "Keep Album")
        XCTAssertEqual(viewModel.files.first?.title, "Parsed Title")
        XCTAssertEqual(viewModel.edit?.title, "Parsed Title")
        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertTrue(summary?.failureIssues.isEmpty == true)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testApplyMetadataExchangeWriteEntriesWritesImportedFieldsAndRefreshesSelection() async throws {
        let id = UUID()
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorMetadataExchangeWriteTests-\(UUID().uuidString)", isDirectory: true)
        let url = directoryURL.appendingPathComponent("exchange.flac")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Old Title",
            album: "Keep Album",
            comment: "Old Comment",
            discNumberText: "1/2",
            fileFingerprint: fingerprint
        )
        let reloaded = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Imported Title",
            album: "Keep Album",
            comment: "Imported Comment",
            discNumberText: "2/2"
        )
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()

        let summary = await viewModel.applyMetadataExchangeWriteEntries([
            makeTestExchangeEntry(file: original, values: [
                .title: "Imported Title",
                .comment: "Imported Comment",
                .discNumber: "2/2"
            ])
        ])

        let payload = try XCTUnwrap(pipeline.metadataWrites.first?.payload)
        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [url])
        XCTAssertEqual(payload.title, "Imported Title")
        XCTAssertEqual(payload.comment, "Imported Comment")
        XCTAssertEqual(payload.discNumberText, "2/2")
        XCTAssertEqual(payload.album, "Keep Album")
        XCTAssertEqual(viewModel.files.first?.comment, "Imported Comment")
        XCTAssertEqual(viewModel.edit?.comment, "Imported Comment")
        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertTrue(summary?.failureIssues.isEmpty == true)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testFieldTransferCutWritesDestinationAndSourceClearInOnePayload() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFieldTransferTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let url = directoryURL.appendingPathComponent("transfer.flac")
        try Data("fixture".utf8).write(to: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let original = AudioFileTestFactory.make(
            url: url, title: "Keep Title", comment: "Replace Comment", track: 7, trackTotal: 12,
            trackNumberText: "007/012", fileFingerprint: fingerprint
        )
        let reloaded = AudioFileTestFactory.make(
            id: original.id, url: url, comment: "Keep Title", track: 7, trackTotal: 12
        )
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([original.id])
        viewModel.updateEditForSelection()
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .comment, operation: .cut, targetFiles: [original]
        )

        let summary = await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)

        XCTAssertEqual(pipeline.metadataWrites.count, 1)
        let payload = try XCTUnwrap(pipeline.metadataWrites.first?.payload)
        XCTAssertEqual(payload.comment, "Keep Title")
        XCTAssertEqual(payload.trackNumber, 7)
        XCTAssertEqual(payload.trackTotal, 12)
        XCTAssertEqual(payload.title, "")
        XCTAssertEqual(viewModel.edit?.comment, "Keep Title")
        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertTrue(summary?.failureIssues.isEmpty == true)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testFieldTransferBatchFailureKeepsSourceAndContinuesOtherFiles() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFieldTransferFailureTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let failedURL = directoryURL.appendingPathComponent("failed.flac")
        let successfulURL = directoryURL.appendingPathComponent("successful.flac")
        try Data("fixture".utf8).write(to: failedURL)
        try Data("fixture".utf8).write(to: successfulURL)
        let failed = AudioFileTestFactory.make(
            url: failedURL, title: "Keep source", comment: "Keep destination",
            fileFingerprint: try AudioFileFingerprint.capture(at: failedURL)
        )
        let successful = AudioFileTestFactory.make(
            url: successfulURL, title: "Move source",
            fileFingerprint: try AudioFileFingerprint.capture(at: successfulURL)
        )
        let reloaded = AudioFileTestFactory.make(id: successful.id, url: successfulURL, comment: "Move source")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [successfulURL: reloaded], failingMetadataWriteURLs: [failedURL]
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([failed, successful])
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .comment, operation: .cut, targetFiles: [failed, successful]
        )

        let summary = await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)

        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertEqual(summary?.failureIssues.count, 1)
        XCTAssertEqual(summary?.failureIssues.first?.fileName, failedURL.lastPathComponent)
        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [successfulURL])
        XCTAssertEqual(viewModel.files.first(where: { $0.id == failed.id })?.title, "Keep source")
        XCTAssertEqual(viewModel.files.first(where: { $0.id == failed.id })?.comment, "Keep destination")
        XCTAssertEqual(viewModel.files.first(where: { $0.id == successful.id })?.title, "")
        XCTAssertEqual(viewModel.files.first(where: { $0.id == successful.id })?.comment, "Move source")
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testFieldTransferExecutionAcceptsTotalOnlyPlan() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorFieldTransferSafetyTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let url = directoryURL.appendingPathComponent("unsafe.flac")
        let originalBytes = Data("fixture".utf8)
        try originalBytes.write(to: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let original = AudioFileTestFactory.make(url: url, track: 7, trackTotal: 12, fileFingerprint: fingerprint)
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let summary = await viewModel.applyMetadataExchangeWriteEntries([
            makeTestExchangeEntry(file: original, values: [.trackNumber: "", .comment: "7"])
        ])

        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertEqual(summary?.failureIssues.count, 0)
        XCTAssertEqual(pipeline.metadataWrites.count, 1)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        XCTAssertEqual(pipeline.metadataWrites.first?.payload.trackNumber, 0)
        XCTAssertEqual(pipeline.metadataWrites.first?.payload.trackTotal, 12)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testMetadataPlanSummaryAccountsForSkippedRows() async throws {
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorSkippedSummary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("skipped-summary.flac")
        try Data("fixture".utf8).write(to: url)
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Original",
            fileFingerprint: fingerprint
        )
        let reloaded = AudioFileTestFactory.make(id: id, url: url, title: "New")
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let summary = await viewModel.applyMetadataExchangeWriteEntries(
            [
                makeTestExchangeEntry(file: original, values: [.title: "New"])
            ],
            skippedIssues: [
                BatchMetadataWriteIssue(fileName: "bad-1.flac", messages: ["1 missing CSV column(s)."]),
                BatchMetadataWriteIssue(fileName: "bad-2.flac", messages: ["2 extra CSV column(s)."])
            ]
        )

        XCTAssertEqual(summary?.totalTargets, 3)
        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertEqual(summary?.skippedIssues.count, 2)
        XCTAssertTrue(summary?.warningIssues.isEmpty == true)
        XCTAssertTrue(summary?.hudSubtitle.contains("2 files were skipped") == true)
        XCTAssertFalse(summary?.hudSubtitle.contains("saved with issues") == true)
        XCTAssertEqual(viewModel.saveIssueLogStore.entries.first?.issues.map(\.fileName), ["bad-1.flac", "bad-2.flac"])
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .warning)
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Changes Saved with Warnings")
    }

    @MainActor
    func testMetadataPlanWritesRejectDuplicateFileEntries() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/duplicate-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let filenameEntry = makeTestFilenameEntry(file: original, values: [.title: "Filename Import"])
        let filenameSummary = await viewModel.applyFilenameMetadataPlan([filenameEntry, filenameEntry])

        let exchangeEntry = makeTestExchangeEntry(file: original, values: [.title: "Exchange Import"])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([exchangeEntry, exchangeEntry])

        XCTAssertNil(filenameSummary)
        XCTAssertNil(exchangeSummary)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Changes Couldn’t Be Applied")
    }

    @MainActor
    func testMetadataPlanWritesRejectInvalidFieldsAndValuesAtExecutionTime() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/invalid-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            makeTestFilenameEntry(
                file: original,
                values: [.trackNumberText: "not-a-track"],
                projection: rejectedTestProjection("This filename preview can’t be applied.")
            )
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            makeTestExchangeEntry(
                file: original,
                values: [.fileName: "not-writable"],
                projection: rejectedTestProjection("This import preview can’t be applied.")
            )
        ])

        XCTAssertEqual(filenameSummary?.failureIssues.count, 1)
        XCTAssertEqual(exchangeSummary?.failureIssues.count, 1)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testMetadataPlanWritesRejectMissingFileFingerprintsAtExecutionTime() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/unverified-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            makeTestFilenameEntry(file: original, values: [.title: "Filename Import"])
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            makeTestExchangeEntry(file: original, values: [.title: "Exchange Import"])
        ])

        XCTAssertEqual(filenameSummary?.failureIssues.count, 1)
        XCTAssertEqual(exchangeSummary?.failureIssues.count, 1)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testMetadataPlanWritesRespectGlobalSaveProgressExclusion() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/busy-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        let token = viewModel.beginMetadataSaveProgress(
            title: "Existing Save",
            subtitle: "Busy",
            totalUnitCount: 3
        )
        let existingProgress = viewModel.metadataSaveProgress

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            makeTestFilenameEntry(file: original, values: [.title: "Filename Import"])
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            makeTestExchangeEntry(file: original, values: [.title: "Exchange Import"])
        ])

        XCTAssertNil(filenameSummary)
        XCTAssertNil(exchangeSummary)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.metadataSaveProgress, existingProgress)
        viewModel.endMetadataSaveProgress(token: token)
    }

    @MainActor
    func testMetadataPlanWritesDoNotDiscardUnsavedInspectorEdits() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/unsaved-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()
        viewModel.edit?.title = "Pending Inspector Edit"

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            makeTestFilenameEntry(file: original, values: [.title: "Filename Import"])
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            makeTestExchangeEntry(file: original, values: [.title: "Exchange Import"])
        ])

        XCTAssertNil(filenameSummary)
        XCTAssertNil(exchangeSummary)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.edit?.title, "Pending Inspector Edit")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Unsaved Changes")
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testMetadataPlanWritesForwardExpectedFileFingerprint() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorMetadataPlanWriteTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("stale.flac")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try Data(repeating: 0x41, count: 16).write(to: fileURL)
        let previewFingerprint = try AudioFileFingerprint.capture(at: fileURL)
        try Data(repeating: 0x42, count: 32).write(to: fileURL)

        let id = UUID()
        let original = AudioFileTestFactory.make(id: id, url: fileURL, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let previewFile = AudioFileTestFactory.make(
            id: id,
            url: fileURL,
            title: "Original",
            fileFingerprint: previewFingerprint
        )
        await viewModel.applyFilenameMetadataPlan([
            makeTestFilenameEntry(file: previewFile, values: [.title: "Stale Filename Import"])
        ])
        await viewModel.applyMetadataExchangeWriteEntries([
            makeTestExchangeEntry(file: previewFile, values: [.title: "Stale Exchange Import"])
        ])

        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    @MainActor
    func testApplyMusicBrainzTaggingPlanPreservesFieldOrderAndRefreshesSelection() async throws {
        let id = UUID()
        let url = try MetadataTestTokens.makeFixtureCopy()
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Old Title",
            album: "Keep Album",
            trackNumberText: "1/9",
            discNumberText: "1/1",
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        let reloaded = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "MusicBrainz Title",
            album: "Keep Album",
            trackNumberText: "7/12",
            discNumberText: "2/3"
        )
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()

        await viewModel.applyMusicBrainzTaggingPlan([
            MusicBrainzTaggingWriteEntry(
                file: original,
                values: [
                    .title: "MusicBrainz Title",
                    .trackNumber: "7",
                    .trackTotal: "12",
                    .discNumber: "2",
                    .discTotal: "3",
                    .musicBrainzAlbumID: "release-id"
                ]
            )
        ])

        let payload = try XCTUnwrap(pipeline.metadataWrites.first?.payload)
        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [url])
        XCTAssertEqual(payload.title, "MusicBrainz Title")
        XCTAssertEqual(payload.album, "Keep Album")
        XCTAssertEqual(payload.trackNumberText, "7/12")
        XCTAssertEqual(payload.discNumberText, "2/3")
        XCTAssertEqual(payload.musicBrainzAlbumID, "release-id")
        XCTAssertNil(viewModel.metadataSaveProgress)
        XCTAssertEqual(viewModel.files.first?.title, "MusicBrainz Title")
        XCTAssertEqual(viewModel.edit?.title, "MusicBrainz Title")
    }

    @MainActor
    func testApplyiTunesTaggingPlanWritesProviderFieldsAndRefreshesSelection() async throws {
        let id = UUID()
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "m4a")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Old Title",
            album: "Keep Album",
            trackNumberText: "1/9",
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        let reloaded = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "iTunes Title",
            album: "Keep Album",
            trackNumberText: "7/12"
        )
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()

        await viewModel.applyiTunesTaggingPlan([
            iTunesTaggingWriteEntry(
                file: original,
                values: [
                    .title: "iTunes Title",
                    .trackNumber: "7",
                    .trackTotal: "12",
                    .itunesAlbumID: "12345",
                    .itunesArtistID: "67890",
                    .itunesCatalogID: "54321",
                    .isExplicit: ContentAdvisory.explicit.displayName
                ]
            )
        ])

        let payload = try XCTUnwrap(pipeline.metadataWrites.first?.payload)
        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [url])
        XCTAssertEqual(payload.title, "iTunes Title")
        XCTAssertEqual(payload.album, "Keep Album")
        XCTAssertEqual(payload.trackNumberText, "7/12")
        XCTAssertEqual(payload.itunesAlbumID, "12345")
        XCTAssertEqual(payload.itunesArtistID, "67890")
        XCTAssertEqual(payload.itunesCatalogID, "54321")
        XCTAssertEqual(payload.contentAdvisory, .explicit)
        XCTAssertNil(viewModel.metadataSaveProgress)
        XCTAssertEqual(viewModel.files.first?.title, "iTunes Title")
        XCTAssertEqual(viewModel.edit?.title, "iTunes Title")
    }

    @MainActor
    func testCancelledProviderApplyClearsProgressAfterCommittedReloadCompletes() async throws {
        let id = UUID()
        let url = try MetadataTestTokens.makeFixtureCopy(fileExtension: "m4a")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let tokens = try MetadataTestTokens.mintedTokens(at: url)
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Original",
            fileFingerprint: tokens.fingerprint,
            metadataFileVersion: tokens.version
        )
        let pipeline = ProviderApplyGatedPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let applyTask = Task {
            await viewModel.applyiTunesTaggingPlan([
                iTunesTaggingWriteEntry(
                    file: original,
                    values: [.title: "Remote"]
                )
            ])
        }
        await pipeline.reloadStarted.wait()
        XCTAssertNotNil(viewModel.metadataSaveProgress)

        applyTask.cancel()
        // Once committed, cancellation does not abandon the protected reload.
        // Release it before joining the task, otherwise this test deadlocks
        // against its own latch until the production reload deadline expires.
        XCTAssertNotNil(viewModel.metadataSaveProgress)
        await pipeline.allowReload.signal()
        await applyTask.value

        XCTAssertNil(
            viewModel.metadataSaveProgress,
            "A cancelled provider apply must clear progress when its committed reload completes."
        )
    }

    @MainActor
    func testExternalMetadataWriteDoesNotDiscardUnsavedInspectorDraft() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/itunes-unsaved.m4a")
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Original",
            includeDefaultFileFingerprint: false
        )
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.setSelectedAudioIDs([id])
        viewModel.updateEditForSelection()
        viewModel.edit?.title = "Pending Inspector Draft"

        await viewModel.applyiTunesTaggingPlan([
            iTunesTaggingWriteEntry(
                file: original,
                values: [.title: "Provider Title"]
            )
        ])

        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.edit?.title, "Pending Inspector Draft")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Unsaved Changes")
    }

    @MainActor
    private func waitUntil(
        _ condition: @autoclosure @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }

    @MainActor
    func testPassivePruneKeepsCapturedMultiDraftAndBlocksImplicitTransfer() {
        let firstID = UUID()
        let secondID = UUID()
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: URL(fileURLWithPath: "/tmp/f3b-prune-01.mp3"),
            title: "First"
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: URL(fileURLWithPath: "/tmp/f3b-prune-02.mp3"),
            title: "Second"
        )
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.setSelectedAudioIDs([firstID, secondID])
        viewModel.multiEdit?.setText("Batch Album", for: .album)

        viewModel.removeQuickImportFile(id: firstID)

        XCTAssertTrue(viewModel.hasInspectorPendingReview)
        XCTAssertEqual(viewModel.selectedAudioIDs, [secondID])
        XCTAssertEqual(viewModel.multiEdit?.text(for: .album), "Batch Album")
        XCTAssertFalse(viewModel.isInspectorPendingReviewResumable)

        viewModel.discardInspectorPendingReview()
        XCTAssertFalse(viewModel.hasInspectorPendingReview)
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)
    }

}

private nonisolated final class RecordingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct MetadataWrite: Sendable {
        let payload: MetadataEditPayload
        let url: URL
    }

    private let lock = NSLock()
    private let reloadedFilesByURL: [URL: AudioFile]
    private let failingMetadataWriteURLs: Set<URL>
    private let fileVersionsByURL: [URL: MetadataFileVersion]
    private(set) var metadataWrites: [MetadataWrite] = []
    private(set) var rawMapWrites: [URL: [String: String]] = [:]
    private var recordedEraseCount = 0

    init(
        reloadedFilesByURL: [URL: AudioFile] = [:],
        failingMetadataWriteURLs: Set<URL> = [],
        fileVersionsByURL: [URL: MetadataFileVersion] = [:]
    ) {
        self.reloadedFilesByURL = reloadedFilesByURL
        self.failingMetadataWriteURLs = failingMetadataWriteURLs
        self.fileVersionsByURL = fileVersionsByURL
    }

    /// The reviewed version the draft route compares before writing. Tests seed
    /// the token captured with their fixture-backed observation.
    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        guard let version = lock.withLock({ fileVersionsByURL[url] }) else {
            throw CocoaError(.featureUnsupported)
        }
        return version
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        if let file = reloadedFilesByURL[url] {
            return file
        }

        return await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url)
        }
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        nil
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        [:]
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        if failingMetadataWriteURLs.contains(url) {
            throw CocoaError(.fileWriteNoPermission)
        }
        lock.withLock {
            metadataWrites.append(MetadataWrite(payload: edit, url: url))
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            rawMapWrites[url] = patch.valuesToSet.mapValues { $0.joined(separator: "; ") }
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            recordedEraseCount += 1
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    // MARK: Reviewer-strict adapter route (S8)

    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        if failingMetadataWriteURLs.contains(url) {
            throw CocoaError(.fileWriteNoPermission)
        }
        lock.withLock {
            metadataWrites.append(MetadataWrite(payload: edit, url: url))
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeReviewedRawPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            rawMapWrites[url] = patch.valuesToSet.mapValues { $0.joined(separator: "; ") }
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadataReviewed(
        at url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            recordedEraseCount += 1
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    var eraseCount: Int {
        lock.withLock { recordedEraseCount }
    }

    func waitForMetadataWriteCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(2)

        while Date() < deadline {
            if lock.withLock({ metadataWrites.count >= expectedCount }) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for \(expectedCount) metadata writes", file: file, line: line)
    }
}

private actor ProviderApplyLatch {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !signaled else { return }
        signaled = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    func wait() async {
        guard !signaled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class ProviderApplyGatedPipeline: AudioMetadataPipeline, @unchecked Sendable {
    let reloadStarted = ProviderApplyLatch()
    let allowReload = ProviderApplyLatch()

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await reloadStarted.signal()
        await allowReload.wait()
        return await AudioFileTestFactory.make(id: id, url: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
#endif
