import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class InspectorAndMetadataEditorWorkflowTests: XCTestCase {
    func testExplicitInspectorSelectionOrderMatchesInspectorControl() {
        XCTAssertEqual(
            ExplicitInspectorSelection.inspectorSelectionOrder.map(\.displayName),
            ["Unset", "Explicit", "Clean", "Not Explicit"]
        )
    }

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
        let viewModel = AudioViewModel(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles(files)

        for file in files {
            viewModel.selectedAudioIDs = [file.id]
            viewModel.updateEditForSelection()

            XCTAssertEqual(viewModel.editSourceFileID, file.id)
            XCTAssertEqual(viewModel.edit?.contentAdvisory, file.contentAdvisory)
            XCTAssertEqual(
                ExplicitInspectorSelection(contentAdvisory: viewModel.edit?.contentAdvisory).displayName,
                file.contentAdvisory?.displayName ?? "Unset"
            )
        }
    }

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
        let viewModel = AudioViewModel(metadataPipeline: RecordingMetadataPipeline())
        viewModel.mergeQuickImportFiles([first, second])

        viewModel.selectedAudioIDs = [firstID]
        viewModel.updateEditForSelection()

        XCTAssertEqual(viewModel.edit?.title, "First")
        XCTAssertEqual(viewModel.editSourceFileID, firstID)
        XCTAssertNil(viewModel.multiEdit)
        XCTAssertFalse(viewModel.hasUnsavedInspectorChanges)

        viewModel.edit?.title = "First Draft"
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)

        viewModel.selectedAudioIDs = [firstID, secondID]
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

    func testSaveInspectorEditsIgnoresStaleSingleFileEditSnapshot() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "First", contentAdvisory: .explicit)
        let second = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Second", contentAdvisory: .notExplicit)
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])

        viewModel.selectedAudioIDs = [firstID]
        viewModel.updateEditForSelection()
        XCTAssertEqual(viewModel.edit?.contentAdvisory, .explicit)
        XCTAssertEqual(viewModel.editSourceFileID, firstID)

        viewModel.selectedAudioIDs = [secondID]
        viewModel.saveInspectorEdits()

        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.edit?.contentAdvisory, .notExplicit)
        XCTAssertEqual(viewModel.editSourceFileID, secondID)
    }

    func testSaveInspectorEditsWritesSingleSelectionAndRefreshesEditModel() async throws {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/01.mp3")
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Original",
            includeDefaultFileFingerprint: false
        )
        let reloaded = AudioFileTestFactory.make(id: id, url: url, title: "Reloaded")
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.selectedAudioIDs = [id]
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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        viewModel.selectedAudioIDs = [id]
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
        XCTAssertTrue(viewModel.metadataWriteHUD?.subtitle.contains("changed after the preview") == true)
    }

    func testSaveInspectorEditsAppliesOnlyModifiedMultiFileFieldsToEachFile() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            album: "Old One",
            includeDefaultFileFingerprint: false
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            album: "Old Two",
            includeDefaultFileFingerprint: false
        )
        let firstReloaded = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "First", album: "Batch Album")
        let secondReloaded = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Second", album: "Batch Album")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ]
        )
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.selectedAudioIDs = [firstID, secondID]
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

    func testMetadataEditorRawMapApplyWritesEachTargetAndRefreshesLoadedFiles() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            includeDefaultFileFingerprint: false
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            includeDefaultFileFingerprint: false
        )
        let firstReloaded = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "Raw First")
        let secondReloaded = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Raw Second")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ]
        )
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.selectedAudioIDs = [firstID]
        viewModel.updateEditForSelection()

        await viewModel.applyRawMetadataPropertyMaps(
            [
                firstID: ["TITLE": "Raw First", "CUSTOM": "One"],
                secondID: ["TITLE": "Raw Second"]
            ],
            to: [
                MetadataEditorTarget(file: first),
                MetadataEditorTarget(file: second)
            ]
        )

        XCTAssertEqual(pipeline.rawMapWrites[firstURL], ["TITLE": "Raw First", "CUSTOM": "One"])
        XCTAssertEqual(pipeline.rawMapWrites[secondURL], ["TITLE": "Raw Second"])
        XCTAssertEqual(viewModel.files.map(\.title), ["Raw First", "Raw Second"])
        XCTAssertEqual(viewModel.edit?.title, "Raw First")
    }

    func testMetadataEditorRawMapApplyRejectsFileChangedSinceEditorOpened() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRawEditorFingerprintTests-\(UUID().uuidString)", isDirectory: true)
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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)

        try Data(repeating: 0x42, count: 32).write(to: fileURL, options: .atomic)
        await viewModel.applyRawMetadataPropertyMaps(
            [file.id: ["TITLE": "Stale Draft"]],
            to: [MetadataEditorTarget(file: file)]
        )

        XCTAssertTrue(
            pipeline.rawMapWrites.isEmpty,
            "Raw metadata writes must fail closed when the file changed after the editor opened."
        )
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertTrue(viewModel.metadataWriteHUD?.subtitle.contains("changed after the preview") == true)
    }

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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)

        try Data(repeating: 0x42, count: 32).write(to: fileURL, options: .atomic)
        let result = await viewModel.persistMetadataErase(file, syncInspectorAfterReload: false)

        guard case .failure(let reason) = result else {
            return XCTFail("Expected metadata erase to reject the stale file.")
        }
        XCTAssertTrue(reason.contains("changed after the preview"))
        XCTAssertEqual(
            pipeline.eraseCount,
            0,
            "Metadata erase must fail closed when the file changed after it was loaded."
        )
    }

    func testCreateMuseAmpIDsWritesDeterministicCommentPayloadsAndRefreshesLoadedFiles() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "First",
            album: "Shared Album",
            comment: "Old First",
            albumArtist: "Shared Artist",
            includeDefaultFileFingerprint: false
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Second",
            album: "Shared Album",
            comment: "Old Second",
            albumArtist: "Shared Artist",
            includeDefaultFileFingerprint: false
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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.selectedAudioIDs = [firstID]
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

    func testImportMetadataFieldValuesWritesChosenFieldInTargetOrderAndRefreshesLoadedFiles() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = URL(fileURLWithPath: "/tmp/01.mp3")
        let secondURL = URL(fileURLWithPath: "/tmp/02.mp3")
        let first = AudioFileTestFactory.make(
            id: firstID,
            url: firstURL,
            title: "Old First",
            album: "Keep Album",
            includeDefaultFileFingerprint: false
        )
        let second = AudioFileTestFactory.make(
            id: secondID,
            url: secondURL,
            title: "Old Second",
            album: "Keep Album",
            includeDefaultFileFingerprint: false
        )
        let firstReloaded = AudioFileTestFactory.make(id: firstID, url: firstURL, title: "Imported First", album: "Keep Album")
        let secondReloaded = AudioFileTestFactory.make(id: secondID, url: secondURL, title: "Imported Second", album: "Keep Album")
        let pipeline = RecordingMetadataPipeline(
            reloadedFilesByURL: [
                firstURL: firstReloaded,
                secondURL: secondReloaded
            ]
        )
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([first, second])
        viewModel.selectedAudioIDs = [firstID]
        viewModel.updateEditForSelection()

        await viewModel.importMetadataFieldValues(
            ["Imported First", "Imported Second"],
            to: .title,
            for: [first, second]
        )

        let writesByURL = Dictionary(uniqueKeysWithValues: pipeline.metadataWrites.map { ($0.url, $0.payload) })
        XCTAssertEqual(writesByURL[firstURL]?.title, "Imported First")
        XCTAssertEqual(writesByURL[firstURL]?.album, "Keep Album")
        XCTAssertEqual(writesByURL[secondURL]?.title, "Imported Second")
        XCTAssertEqual(writesByURL[secondURL]?.album, "Keep Album")
        XCTAssertEqual(viewModel.files.map(\.title), ["Imported First", "Imported Second"])
        XCTAssertEqual(viewModel.edit?.title, "Imported First")
    }

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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.selectedAudioIDs = [id]
        viewModel.updateEditForSelection()

        let summary = await viewModel.applyFilenameMetadataPlan([
            FilenameMetadataWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [
                    .title: "Parsed Title",
                    .artist: "Parsed Artist",
                    .trackNumberText: "07"
                ],
                expectedFileFingerprint: fingerprint
            )
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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.selectedAudioIDs = [id]
        viewModel.updateEditForSelection()

        let summary = await viewModel.applyMetadataExchangeWriteEntries([
            MetadataExchangeWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [
                    .title: "Imported Title",
                    .comment: "Imported Comment",
                    .discNumber: "2/2"
                ],
                expectedFileFingerprint: fingerprint
            )
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

    func testMetadataPlanWritesRejectDuplicateFileEntries() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/duplicate-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let filenameEntry = FilenameMetadataWriteEntry(
            fileID: id,
            fileName: url.lastPathComponent,
            values: [.title: "Filename Import"]
        )
        let filenameSummary = await viewModel.applyFilenameMetadataPlan([filenameEntry, filenameEntry])

        let exchangeEntry = MetadataExchangeWriteEntry(
            fileID: id,
            fileName: url.lastPathComponent,
            values: [.title: "Exchange Import"]
        )
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([exchangeEntry, exchangeEntry])

        XCTAssertNil(filenameSummary)
        XCTAssertNil(exchangeSummary)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Write Failed")
    }

    func testMetadataPlanWritesRejectInvalidFieldsAndValuesAtExecutionTime() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/invalid-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            FilenameMetadataWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.trackNumberText: "not-a-track"]
            )
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            MetadataExchangeWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.fileName: "not-writable"]
            )
        ])

        XCTAssertEqual(filenameSummary?.failureIssues.count, 1)
        XCTAssertEqual(exchangeSummary?.failureIssues.count, 1)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    func testMetadataPlanWritesRejectMissingFileFingerprintsAtExecutionTime() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/unverified-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            FilenameMetadataWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.title: "Filename Import"]
            )
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            MetadataExchangeWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.title: "Exchange Import"]
            )
        ])

        XCTAssertEqual(filenameSummary?.failureIssues.count, 1)
        XCTAssertEqual(exchangeSummary?.failureIssues.count, 1)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    func testMetadataPlanWritesRespectGlobalSaveProgressExclusion() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/busy-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.beginMetadataSaveProgress(
            title: "Existing Save",
            subtitle: "Busy",
            totalUnitCount: 3
        )
        let existingProgress = viewModel.metadataSaveProgress

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            FilenameMetadataWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.title: "Filename Import"]
            )
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            MetadataExchangeWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.title: "Exchange Import"]
            )
        ])

        XCTAssertNil(filenameSummary)
        XCTAssertNil(exchangeSummary)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.metadataSaveProgress, existingProgress)
        viewModel.endMetadataSaveProgress()
    }

    func testMetadataPlanWritesDoNotDiscardUnsavedInspectorEdits() async {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/unsaved-plan.flac")
        let original = AudioFileTestFactory.make(id: id, url: url, title: "Original")
        let pipeline = RecordingMetadataPipeline()
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.selectedAudioIDs = [id]
        viewModel.updateEditForSelection()
        viewModel.edit?.title = "Pending Inspector Edit"

        let filenameSummary = await viewModel.applyFilenameMetadataPlan([
            FilenameMetadataWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.title: "Filename Import"]
            )
        ])
        let exchangeSummary = await viewModel.applyMetadataExchangeWriteEntries([
            MetadataExchangeWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [.title: "Exchange Import"]
            )
        ])

        XCTAssertNil(filenameSummary)
        XCTAssertNil(exchangeSummary)
        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertEqual(viewModel.edit?.title, "Pending Inspector Edit")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        XCTAssertEqual(viewModel.metadataWriteHUD?.title, "Unsaved Changes")
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])

        await viewModel.applyFilenameMetadataPlan([
            FilenameMetadataWriteEntry(
                fileID: id,
                fileName: fileURL.lastPathComponent,
                values: [.title: "Stale Filename Import"],
                expectedFileFingerprint: previewFingerprint
            )
        ])
        await viewModel.applyMetadataExchangeWriteEntries([
            MetadataExchangeWriteEntry(
                fileID: id,
                fileName: fileURL.lastPathComponent,
                values: [.title: "Stale Exchange Import"],
                expectedFileFingerprint: previewFingerprint
            )
        ])

        XCTAssertTrue(pipeline.metadataWrites.isEmpty)
        XCTAssertNil(viewModel.metadataSaveProgress)
    }

    func testApplyMusicBrainzTaggingPlanPreservesFieldOrderAndRefreshesSelection() async throws {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/musicbrainz.flac")
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Old Title",
            album: "Keep Album",
            trackNumberText: "1/9",
            discNumberText: "1/1"
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
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.selectedAudioIDs = [id]
        viewModel.updateEditForSelection()

        await viewModel.applyMusicBrainzTaggingPlan([
            MusicBrainzTaggingWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
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

    func testApplyiTunesTaggingPlanWritesProviderFieldsAndRefreshesSelection() async throws {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/itunes.m4a")
        let original = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "Old Title",
            album: "Keep Album",
            trackNumberText: "1/9"
        )
        let reloaded = AudioFileTestFactory.make(
            id: id,
            url: url,
            title: "iTunes Title",
            album: "Keep Album",
            trackNumberText: "7/12"
        )
        let pipeline = RecordingMetadataPipeline(reloadedFilesByURL: [url: reloaded])
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([original])
        viewModel.selectedAudioIDs = [id]
        viewModel.updateEditForSelection()

        await viewModel.applyiTunesTaggingPlan([
            iTunesTaggingWriteEntry(
                fileID: id,
                fileName: url.lastPathComponent,
                values: [
                    .title: "iTunes Title",
                    .trackNumber: "7",
                    .trackTotal: "12",
                    .itunesAlbumID: "album-id",
                    .itunesArtistID: "artist-id",
                    .itunesCatalogID: "track-id",
                    .isExplicit: ContentAdvisory.explicit.displayName
                ]
            )
        ])

        let payload = try XCTUnwrap(pipeline.metadataWrites.first?.payload)
        XCTAssertEqual(pipeline.metadataWrites.map(\.url), [url])
        XCTAssertEqual(payload.title, "iTunes Title")
        XCTAssertEqual(payload.album, "Keep Album")
        XCTAssertEqual(payload.trackNumberText, "7/12")
        XCTAssertEqual(payload.itunesAlbumID, "album-id")
        XCTAssertEqual(payload.itunesArtistID, "artist-id")
        XCTAssertEqual(payload.itunesCatalogID, "track-id")
        XCTAssertEqual(payload.contentAdvisory, .explicit)
        XCTAssertNil(viewModel.metadataSaveProgress)
        XCTAssertEqual(viewModel.files.first?.title, "iTunes Title")
        XCTAssertEqual(viewModel.edit?.title, "iTunes Title")
    }

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
}

private final class RecordingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct MetadataWrite: Sendable {
        let payload: MetadataEditPayload
        let url: URL
    }

    private let lock = NSLock()
    private let reloadedFilesByURL: [URL: AudioFile]
    private(set) var metadataWrites: [MetadataWrite] = []
    private(set) var rawMapWrites: [URL: [String: String]] = [:]
    private var recordedEraseCount = 0

    init(reloadedFilesByURL: [URL: AudioFile] = [:]) {
        self.reloadedFilesByURL = reloadedFilesByURL
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

    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] {
        [:]
    }

    nonisolated func writeMetadata(_ edit: MetadataEditPayload, to url: URL) throws -> AudioMetadataWriteResult {
        lock.withLock {
            metadataWrites.append(MetadataWrite(payload: edit, url: url))
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(_ propertyMap: [String: String], to url: URL) throws -> AudioMetadataWriteResult {
        lock.withLock {
            rawMapWrites[url] = propertyMap
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        lock.withLock {
            recordedEraseCount += 1
        }
        return AudioMetadataWriteResult(warnings: [])
    }

    var eraseCount: Int {
        lock.withLock { recordedEraseCount }
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
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
#endif
