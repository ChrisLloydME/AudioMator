import XCTest
import TagLibAudioMetadata
@testable import AudioMator

/// Real-adapter disk acceptance for E1 frozen reviewed writes.
///
/// Every mutation happens on disposable fixture copies. The view model applies
/// planner-produced `ReviewedMetadataWrite` entries through the production strict
/// executor; only the transactional-directory prompt is bypassed by a thin wrapper
/// that declares `requiresTransactionalDirectoryAccess == false` (the real adapter
/// still performs every load, projection and write).
nonisolated final class ExchangeReviewedWriteAcceptanceTests: XCTestCase {
    private let base = TagLibAudioMetadataPipeline()
    private let acceptancePipeline = AcceptancePipeline()

    // MARK: – AM-01

    @MainActor
    func testAM01LoneTrackRemovalPreservesFLACSiblingTotalAndAudioIdentity() async throws {
        let url = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let seeded = try await seed(url, trackText: "3/12", discText: "2/4")
        _ = try base.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["X-E1-KEEP": ["keep"]]),
            to: url,
            expectedVersion: seeded.metadataFileVersion
        )
        let file = try await load(url)
        let identityBefore = try base.conflictSnapshot(for: url).audioContentIdentity

        let plan = try makeCSVPlan(
            template: "{{trackNumber}}",
            source: removalCSV,
            targets: [file]
        )
        XCTAssertEqual(plan.writeEntries.count, 1)
        XCTAssertEqual(plan.writeEntries.first?.frozenPayload?.requestedFields, [.track])

        let summary = await applyExchange(plan, files: [file])
        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertEqual(summary?.failureIssues.count, 0)

        let persisted = try await load(url)
        XCTAssertEqual(persisted.track, 0, "A lone track removal clears the number component")
        XCTAssertEqual(persisted.trackTotal, 12, "A lone track removal keeps the sibling total")
        XCTAssertEqual(persisted.disc, 2, "The unrelated disc pair is untouched")
        XCTAssertEqual(persisted.discTotal, 4)
        XCTAssertEqual(try base.rawMetadataValueMap(for: url)["X-E1-KEEP"], ["keep"])
        let identityAfter = try base.conflictSnapshot(for: url).audioContentIdentity
        XCTAssertEqual(identityBefore, identityAfter, "Qualified audio identity is preserved")
    }

    @MainActor
    func testAM01LoneDiscRemovalPreservesFLACSiblingTotal() async throws {
        let url = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let file = try await seed(url, trackText: "3/12", discText: "2/4")

        let plan = try makeCSVPlan(template: "{{discNumber}}", source: removalCSV, targets: [file])
        let summary = await applyExchange(plan, files: [file])
        XCTAssertEqual(summary?.succeeded, 1)

        let persisted = try await load(url)
        XCTAssertEqual(persisted.disc, 0)
        XCTAssertEqual(persisted.discTotal, 4)
        XCTAssertEqual(persisted.track, 3)
        XCTAssertEqual(persisted.trackTotal, 12)
    }

    @MainActor
    func testAM01MP4LoneTrackRemovalPersistsOrRejectsWithUnchangedBytes() async throws {
        let url = try fixtureCopy("m4a")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let file = try await seed(url, trackText: "3/12")
        let bytesBefore = try Data(contentsOf: url)

        let plan = try makeCSVPlan(template: "{{trackNumber}}", source: removalCSV, targets: [file])
        if plan.writeEntries.isEmpty {
            // The concrete layout may not support a component-only removal. It must
            // reject explicitly and leave every byte unchanged.
            XCTAssertEqual(plan.rows.first?.status, .parseError)
            XCTAssertEqual(try Data(contentsOf: url), bytesBefore)
            return
        }

        let summary = await applyExchange(plan, files: [file])
        XCTAssertEqual(summary?.succeeded, 1)
        let persisted = try await load(url)
        XCTAssertEqual(persisted.track, 0)
        XCTAssertEqual(persisted.trackTotal, 12)
    }

    @MainActor
    func testAM01WholePairSetterControlWouldFailSiblingAssertion() async throws {
        let url = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let file = try await seed(url, trackText: "3/12")
        XCTAssertEqual(file.trackTotal, 12)

        // Negative control: the old production path cleared the whole pair. This
        // demonstrates the new sibling assertion genuinely detects the old defect.
        var legacyEdit = SingleFileEditModel(from: file)
        legacyEdit.setTrackNumberText("")
        let legacyPayload = MetadataEditPayload(legacyEdit, comparedTo: file)
        _ = try base.writeMetadata(
            legacyPayload,
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        let persisted = try await load(url)
        XCTAssertEqual(persisted.trackTotal, 0, "The old whole-pair setter removes the sibling total")
    }

    // MARK: – AM-02

    @MainActor
    func testAM02BlankLeadingRecordDoesNotShiftTwoRealTargets() async throws {
        let fileAURL = try fixtureCopy("flac")
        let fileBURL = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fileAURL) }
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fileBURL) }
        let fileA = try await seed(fileAURL, title: "")
        let fileB = try await seed(fileBURL, title: "Old B")

        let source = """
        \(MetadataExchangeProfile.markerLine())

        New B
        """
        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: source,
            targetFiles: [fileA, fileB],
            clearBlankImportedValues: false,
            projector: acceptancePipeline
        )
        XCTAssertNil(plan.validationMessage)
        XCTAssertNil(plan.blockingMessage)
        XCTAssertEqual(plan.rows.count, 2)
        XCTAssertEqual(plan.rows.map(\.fileID), [fileA.id, fileB.id])
        XCTAssertEqual(plan.rows.map(\.status), [.unchanged, .ready])
        XCTAssertEqual(plan.writeEntries.count, 1)
        XCTAssertEqual(plan.writeEntries.first?.fileID, fileB.id)

        let bytesABefore = try Data(contentsOf: fileAURL)
        let summary = await applyExchange(plan, files: [fileA, fileB])
        XCTAssertEqual(summary?.succeeded, 1)
        XCTAssertEqual(summary?.failureIssues.count, 0)

        let persistedA = try await load(fileAURL)
        let persistedB = try await load(fileBURL)
        XCTAssertEqual(persistedA.title, "", "The blank first record consumed file A's slot without shifting")
        XCTAssertEqual(persistedB.title, "New B")
        XCTAssertEqual(try Data(contentsOf: fileAURL), bytesABefore, "The ignored blank slot wrote nothing to file A")
    }

    @MainActor
    func testAM02PositionalCountMismatchBlocksWithUnchangedBytes() async throws {
        let fileAURL = try fixtureCopy("flac")
        let fileBURL = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fileAURL) }
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fileBURL) }
        let fileA = try await seed(fileAURL, title: "Old A")
        let fileB = try await seed(fileBURL, title: "Old B")
        let bytesA = try Data(contentsOf: fileAURL)
        let bytesB = try Data(contentsOf: fileBURL)

        let source = """
        \(MetadataExchangeProfile.markerLine())
        Only A
        """
        let plan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{title}}",
            sourceText: source,
            targetFiles: [fileA, fileB],
            clearBlankImportedValues: false,
            projector: acceptancePipeline
        )
        XCTAssertNotNil(plan.blockingMessage)
        XCTAssertFalse(plan.canApply)
        XCTAssertTrue(plan.writeEntries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileAURL), bytesA)
        XCTAssertEqual(try Data(contentsOf: fileBURL), bytesB)
    }

    // MARK: – AM-16

    @MainActor
    func testAM16ExternalLiteralApostrophePersistsInTitle() async throws {
        let url = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let file = try await load(url)

        let plan = try makeCSVPlan(template: "{{title}}", source: "'+44", targets: [file])
        XCTAssertEqual(plan.writeEntries.first?.previewValues[.title], "'+44")
        let summary = await applyExchange(plan, files: [file])
        XCTAssertEqual(summary?.succeeded, 1)

        let persisted = try await load(url)
        XCTAssertEqual(persisted.title, "'+44", "An unmarked external literal keeps its apostrophe")
    }

    // MARK: – Numeric rules

    @MainActor
    func testZeroSpellingsRemoveOnlyThatComponent() async throws {
        for literal in ["0", "00", "+0"] {
            let url = try fixtureCopy("flac")
            addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
            let file = try await seed(url, trackText: "3/12")
            let plan = try makeCSVPlan(template: "{{trackNumber}}", source: literal, targets: [file])
            let entry = try XCTUnwrap(plan.writeEntries.first, literal)
            XCTAssertEqual(entry.frozenPayload?.requestedFields, [.track], literal)
            let summary = await applyExchange(plan, files: [file])
            XCTAssertEqual(summary?.succeeded, 1, literal)
            let persisted = try await load(url)
            XCTAssertEqual(persisted.track, 0, literal)
            XCTAssertEqual(persisted.trackTotal, 12, literal)
        }
    }

    @MainActor
    func testInvalidNumberSpellingsRejectWithZeroByteChanges() async throws {
        let url = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let file = try await seed(url, trackText: "3/12")
        let bytesBefore = try Data(contentsOf: url)
        for source in ["-1", "/12", "3/", "1/2/3", "2147483648", "abc"] {
            let plan = try makeCSVPlan(template: "{{trackNumber}}", source: source, targets: [file])
            XCTAssertTrue(plan.writeEntries.isEmpty, source)
            XCTAssertEqual(plan.rows.first?.status, .parseError, source)
            XCTAssertEqual(try Data(contentsOf: url), bytesBefore, source)
        }

        let mp4URL = try fixtureCopy("m4a")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: mp4URL) }
        let mp4File = try await seed(mp4URL, trackText: "3/12")
        let mp4Bytes = try Data(contentsOf: mp4URL)
        let overflow = try makeCSVPlan(template: "{{trackNumber}}", source: "65536", targets: [mp4File])
        XCTAssertTrue(overflow.writeEntries.isEmpty)
        XCTAssertEqual(overflow.rows.first?.status, .parseError)
        XCTAssertEqual(try Data(contentsOf: mp4URL), mp4Bytes)
    }

    @MainActor
    func testExplicitTotalColumnWinsOverEmbeddedTotalOnDisk() async throws {
        let url = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let file = try await seed(url, trackText: "3/12")
        let plan = try makeCSVPlan(
            template: "{{trackNumber}},{{trackTotal}}",
            source: "4/9,12",
            targets: [file]
        )
        XCTAssertEqual(plan.writeEntries.first?.frozenPayload?.requestedFields, [.track])
        let summary = await applyExchange(plan, files: [file])
        XCTAssertEqual(summary?.succeeded, 1)
        let persisted = try await load(url)
        XCTAssertEqual(persisted.track, 4)
        XCTAssertEqual(persisted.trackTotal, 12, "The explicit total column overrides the embedded 9")
    }

    // MARK: – Copy/Cut

    @MainActor
    func testCopyCutNumericZeroAndIndependentComponentsOnDisk() async throws {
        let zeroURL = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: zeroURL) }
        let zeroFile = try await seed(zeroURL, trackText: "3/12", title: "0")
        let zeroBytes = try Data(contentsOf: zeroURL)
        for operation in MetadataFieldTransferOperation.allCases {
            let plan = MetadataFieldTransferPlanner.makePlan(
                source: .title,
                destination: .trackNumber,
                operation: operation,
                targetFiles: [zeroFile],
                projector: acceptancePipeline
            )
            XCTAssertTrue(plan.writeEntries.isEmpty, operation.title)
            XCTAssertEqual(try Data(contentsOf: zeroURL), zeroBytes)
        }

        let cutURL = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: cutURL) }
        let cutFile = try await seed(cutURL, trackText: "3/12")
        let cutPlan = MetadataFieldTransferPlanner.makePlan(
            source: .trackNumber,
            destination: .comment,
            operation: .cut,
            targetFiles: [cutFile],
            projector: acceptancePipeline
        )
        let summary = await applyExchange(cutPlan, files: [cutFile])
        XCTAssertEqual(summary?.succeeded, 1)
        let persisted = try await load(cutURL)
        XCTAssertEqual(persisted.track, 0, "Cut removes only the source component")
        XCTAssertEqual(persisted.trackTotal, 12, "Cut preserves the sibling total")
        XCTAssertEqual(persisted.comment, "3")
    }

    // MARK: – Filename extraction and revision guard

    @MainActor
    func testFilenameExtractionAppliesFrozenPayloadWithoutDraftFields() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("E1Filename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("07 - Song.flac")
        try FileManager.default.copyItem(at: try fixtureURL("flac"), to: url)

        let file = try await load(url)
        let plan = makeFilenameMetadataPlan(
            template: "{{trackNumber}} - {{title}}",
            targetFiles: [file],
            replaceUnderscoresWithSpaces: false,
            projector: acceptancePipeline
        )
        XCTAssertEqual(plan.writeEntries.count, 1)
        let summary = await applyFilename(plan, files: [file])
        XCTAssertEqual(summary?.succeeded, 1)
        let persisted = try await load(url)
        XCTAssertEqual(persisted.track, 7)
        XCTAssertEqual(persisted.title, "Song")
    }

    @MainActor
    func testApplyRejectsStaleCapturedRevisionWithoutWriting() async throws {
        let url = try fixtureCopy("flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: url) }
        let file = try await seed(url, title: "Old Title")
        let plan = try makeCSVPlan(template: "{{title}}", source: "New Title", targets: [file])
        XCTAssertFalse(plan.writeEntries.isEmpty)

        // External change after review: the captured revision must fail inside the
        // coordinator and the reviewed change must not be written.
        _ = try base.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["ARTIST": ["External Change"]]),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        let bytesAfterExternalWrite = try Data(contentsOf: url)
        let summary = await applyExchange(plan, files: [file])
        XCTAssertEqual(summary?.succeeded, 0)
        XCTAssertEqual(summary?.failureIssues.count, 1)
        XCTAssertEqual(try Data(contentsOf: url), bytesAfterExternalWrite, "No bytes changed after the stale rejection")
        let persisted = try await load(url)
        XCTAssertEqual(persisted.title, "Old Title", "The stale reviewed title was not applied")
    }

    // MARK: – Helpers

    private var removalCSV: String {
        """
        \(MetadataExchangeProfile.markerLine())
        <remove>
        """
    }

    @MainActor
    private func makeCSVPlan(
        template: String,
        source: String,
        targets: [AudioFile]
    ) throws -> MetadataExchangeImportPlan {
        MetadataExchangePlanner.makeCSVImportPlan(
            template: template,
            sourceText: source,
            firstRowIsHeader: false,
            targetFiles: targets,
            clearBlankImportedValues: false,
            projector: acceptancePipeline
        )
    }

    @MainActor
    private func applyExchange(
        _ plan: MetadataExchangeImportPlan,
        files: [AudioFile]
    ) async -> BatchMetadataOperationSummary? {
        guard !plan.writeEntries.isEmpty else { return nil }
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: acceptancePipeline)
        viewModel.mergeQuickImportFiles(files)
        return await viewModel.applyMetadataExchangeWriteEntries(plan.writeEntries)
    }

    @MainActor
    private func applyFilename(
        _ plan: FilenameMetadataPlan,
        files: [AudioFile]
    ) async -> BatchMetadataOperationSummary? {
        guard !plan.writeEntries.isEmpty else { return nil }
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: acceptancePipeline)
        viewModel.mergeQuickImportFiles(files)
        return await viewModel.applyFilenameMetadataPlan(plan.writeEntries)
    }

    @MainActor
    private func seed(
        _ url: URL,
        trackText: String? = nil,
        discText: String? = nil,
        title: String? = nil
    ) async throws -> AudioFile {
        let file = try await load(url)
        var edit = SingleFileEditModel(from: file)
        if let trackText { edit.setTrackNumberText(trackText) }
        if let discText { edit.setDiscNumberText(discText) }
        if let title { edit.title = title }
        _ = try base.writeMetadata(
            MetadataEditPayload(edit, comparedTo: file),
            to: url,
            expectedVersion: file.metadataFileVersion
        )
        return try await load(url)
    }

    @MainActor
    private func load(_ url: URL) async throws -> AudioFile {
        try await base.loadAudioFile(at: url, id: UUID())
    }

    private func fixtureURL(_ fileExtension: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(
                forResource: "testAudioFile",
                withExtension: fileExtension,
                subdirectory: "Fixtures/Audio"
            ) ?? bundle.url(forResource: "testAudioFile", withExtension: fileExtension)
        )
    }

    private func fixtureCopy(_ fileExtension: String) throws -> URL {
        try MetadataTestTokens.makeFixtureCopy(fileExtension: fileExtension)
    }
}

/// Real adapter wrapper that only disables the app's transactional-directory prompt
/// for tests. Every read, projection, strict write and erase is forwarded unchanged.
private final class AcceptancePipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let base = TagLibAudioMetadataPipeline()

    nonisolated var requiresTransactionalDirectoryAccess: Bool { false }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        try await base.loadAudioFile(at: url, id: id)
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        try base.conflictSnapshot(for: url)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try base.metadataFileVersion(at: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        base.rawMetadataDumpText(for: url)
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        try base.rawMetadataValueMap(for: url)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.writeMetadata(edit, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.eraseAllMetadata(at: url, expectedVersion: expectedVersion)
    }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try base.projectMetadataWrite(intent, fileExtension: fileExtension)
    }

    nonisolated func writeReviewedMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try base.writeReviewedMetadata(edit, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeReviewedRawPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try base.writeReviewedRawPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func eraseAllMetadataReviewed(
        at url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        try base.eraseAllMetadataReviewed(at: url, expectedVersion: expectedVersion)
    }
}
