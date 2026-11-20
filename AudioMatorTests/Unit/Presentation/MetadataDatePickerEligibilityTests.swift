import XCTest
import TagLibAudioMetadata
@testable import AudioMator

nonisolated final class MetadataDatePickerEligibilityTests: XCTestCase {
    @MainActor
    private func makeFile(
        path: String,
        id3v2MajorVersion: Int? = nil,
        year: String = "",
        date: String = "",
        releaseDate: String = "",
        originalReleaseDate: String = ""
    ) -> AudioFile {
        let id = UUID()
        let url = URL(fileURLWithPath: path)
        let baseline: MetadataConflictBaseline?
        if let id3v2MajorVersion {
            baseline = MetadataConflictBaseline(
                structured: StructuredMetadata(id3v2MajorVersion: id3v2MajorVersion)
            )
        } else {
            baseline = AudioFileTestFactory.fixtureConflictBaseline
        }

        let observation: AudioFile.Observation?
        if let baseline, let version = AudioFileTestFactory.fixtureFileVersion {
            observation = AudioFile.Observation(
                fileID: id,
                url: url,
                fingerprint: AudioFileTestFactory.fingerprint(for: url),
                version: version,
                conflictBaseline: baseline
            )
        } else {
            observation = nil
        }

        return AudioFile(
            id: id,
            url: url,
            title: "Track",
            artist: "",
            album: "",
            composer: "",
            genre: "",
            comment: "",
            track: 0,
            trackTotal: 0,
            disc: 0,
            discTotal: 0,
            trackNumberText: "",
            discNumberText: "",
            year: year,
            albumArtist: "",
            releaseDate: releaseDate,
            isrc: "",
            barcode: "",
            itunesAlbumID: "",
            itunesArtistID: "",
            itunesCatalogID: "",
            musicBrainzArtistID: "",
            musicBrainzAlbumID: "",
            musicBrainzTrackID: "",
            musicBrainzReleaseGroupID: "",
            publisher: "",
            copyright: "",
            credits: "",
            lyricist: "",
            remixer: "",
            producer: "",
            engineer: "",
            language: "",
            mediaType: "",
            releaseType: "",
            catalogNumber: "",
            releaseCountry: "",
            contentAdvisory: nil,
            duration: 180,
            bitrate: 320,
            sampleRate: 44_100,
            channels: 2,
            format: "",
            artworkData: nil,
            date: date,
            originalReleaseDate: originalReleaseDate,
            observation: observation
        )
    }

    @MainActor
    func testInspectorEligibilityRespectsExactFieldScopeAndTimestampSupport() {
        let mp3v24 = makeFile(path: "/tmp/track.mp3", id3v2MajorVersion: 4)
        let mp3v23 = makeFile(path: "/tmp/legacy.mp3", id3v2MajorVersion: 3)
        let m4a = makeFile(path: "/tmp/track.m4a")
        let flac = makeFile(path: "/tmp/track.flac")
        let ogg = makeFile(path: "/tmp/track.ogg")
        let wma = makeFile(path: "/tmp/track.wma")
        let xm = makeFile(path: "/tmp/module.xm")
        let mkv = makeFile(path: "/tmp/video.mkv")

        // ID3v2.4 MP3: Year (TDRC), Release Date (TDRL), Original Release Date (TDOR) support timestamps;
        // Date (TXXX(DATE)) is date-only.
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .year, files: [mp3v24])?.destinationFormat,
            .id3v24Timestamp
        )
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .releaseDate, files: [mp3v24])?.destinationFormat,
            .id3v24Timestamp
        )
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .originalReleaseDate, files: [mp3v24])?.destinationFormat,
            .id3v24Timestamp
        )
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .date, files: [mp3v24])?.destinationFormat,
            .isoDateOnly
        )

        // ID3v2.3 MP3: date writes are read-only/unverified -> no picker for any date field.
        for field in [InspectorMetadataField.year, .date, .releaseDate, .originalReleaseDate] {
            XCTAssertNil(
                MetadataDatePickerEligibilityResolver.inspectorEligibility(for: field, files: [mp3v23]),
                "ID3v2.3 \(field) must stay text-only"
            )
        }

        // MP4, FLAC, OGG: Year is NOT a timestamp target -> text-only; Date/Release/Original are date-only.
        for file in [m4a, flac, ogg] {
            XCTAssertNil(MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .year, files: [file]), file.url.pathExtension)
            XCTAssertEqual(
                MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .date, files: [file])?.destinationFormat,
                .isoDateOnly,
                file.url.pathExtension
            )
            XCTAssertEqual(
                MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .releaseDate, files: [file])?.destinationFormat,
                .isoDateOnly,
                file.url.pathExtension
            )
            XCTAssertEqual(
                MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .originalReleaseDate, files: [file])?.destinationFormat,
                .isoDateOnly,
                file.url.pathExtension
            )
        }

        // WMA/ASF: Original Release Date is year-only (WM/OriginalReleaseYear); Release Date unsupported; Year text-only.
        XCTAssertNil(MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .year, files: [wma]))
        XCTAssertNil(MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .releaseDate, files: [wma]))
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .originalReleaseDate, files: [wma])?.destinationFormat,
            .yearOnly
        )

        // Read-only / unsupported containers never get a picker.
        for unsupported in [xm, mkv] {
            for field in InspectorMetadataField.allCases {
                XCTAssertNil(
                    MetadataDatePickerEligibilityResolver.inspectorEligibility(for: field, files: [unsupported]),
                    "\(unsupported.url.pathExtension) \(field)"
                )
            }
        }

        // Non-date Inspector fields (including Copyright, Credits, Title, etc.) never get a picker.
        let nonDateFields = InspectorMetadataField.allCases.filter {
            ![.year, .date, .releaseDate, .originalReleaseDate].contains($0)
        }
        for field in nonDateFields {
            XCTAssertNil(
                MetadataDatePickerEligibilityResolver.inspectorEligibility(for: field, files: [mp3v24]),
                "Non-date field \(field) must keep existing control"
            )
            XCTAssertNil(
                MetadataDatePickerEligibilityResolver.inspectorEligibility(for: field, files: [m4a]),
                "Non-date field \(field) must keep existing control"
            )
        }
    }

    @MainActor
    func testMetadataEditorEligibilityHandlesAliasesCustomKeysReadOnlyAndPurchaseDate() {
        let mp3v24 = MetadataEditorTarget(file: makeFile(path: "/tmp/track.mp3", id3v2MajorVersion: 4))
        let mp3v23 = MetadataEditorTarget(file: makeFile(path: "/tmp/legacy.mp3", id3v2MajorVersion: 3))
        let m4a = MetadataEditorTarget(file: makeFile(path: "/tmp/track.m4a"))
        let flac = MetadataEditorTarget(file: makeFile(path: "/tmp/track.flac"))
        let ogg = MetadataEditorTarget(file: makeFile(path: "/tmp/track.ogg"))
        let xm = MetadataEditorTarget(file: makeFile(path: "/tmp/module.xm"))

        // Raw DATE key: literal `.standaloneDate` on Vorbis/APE; Year-slot / ambiguous on MP4 & ID3.
        let flacDate = MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: [flac])
        XCTAssertEqual(flacDate?.fieldKey, .standaloneDate)
        XCTAssertEqual(flacDate?.destinationFormat, .isoDateOnly)
        XCTAssertEqual(flacDate?.effectiveRawKey, "DATE")

        let oggDate = MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: [ogg])
        XCTAssertEqual(oggDate?.fieldKey, .standaloneDate)
        XCTAssertEqual(oggDate?.destinationFormat, .isoDateOnly)

        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: [m4a]))
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: [mp3v24]))
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: [mp3v23]))
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: [flac, mp3v24]))
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: [flac, m4a]))

        // Ambiguous aliases, custom keys, Copyright, durations, and other fields stay text-only.
        for rejectedKey in [
            "YEAR",
            "STANDALONEDATE",
            "ITUNESPURCHASEDATE",
            "PURCHASEDATE",
            "PURD",
            "RELEASETIME",
            "ORIGINAL YEAR",
            "CUSTOM_DATE",
            "MY_RELEASE_DATE",
            "DATE:CUSTOM",
            "COPYRIGHT",
            "DURATION",
            "TITLE",
            "COMMENT",
            "FILE_MODIFIED",
        ] {
            XCTAssertNil(
                MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: rejectedKey, targets: [mp3v24]),
                "Key \(rejectedKey) must remain text-only on MP3"
            )
            XCTAssertNil(
                MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: rejectedKey, targets: [m4a]),
                "Key \(rejectedKey) must remain text-only on M4A"
            )
            XCTAssertNil(
                MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: rejectedKey, targets: [flac]),
                "Key \(rejectedKey) must remain text-only on FLAC"
            )
        }

        // Release Date & Original Release Date in Metadata Editor.
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "RELEASEDATE", targets: [mp3v24])?.destinationFormat,
            .id3v24Timestamp
        )
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "RELEASEDATE", targets: [m4a])?.destinationFormat,
            .isoDateOnly
        )
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "ORIGINALDATE", targets: [mp3v24])?.destinationFormat,
            .id3v24Timestamp
        )
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "ORIGINALDATE", targets: [flac])?.destinationFormat,
            .isoDateOnly
        )
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "RELEASEDATE", targets: [mp3v23]))
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "RELEASEDATE", targets: [xm]))
    }

    @MainActor
    func testMixedSelectionIntersectsCapabilitiesToRepresentableSubset() {
        let mp3v24 = makeFile(path: "/tmp/a.mp3", id3v2MajorVersion: 4)
        let mp3v23 = makeFile(path: "/tmp/b.mp3", id3v2MajorVersion: 3)
        let flac = makeFile(path: "/tmp/c.flac")
        let m4a = makeFile(path: "/tmp/d.m4a")
        let wma = makeFile(path: "/tmp/e.wma")

        // MP3 (TDRL timestamp) + FLAC (RELEASEDATE date-only) -> date-only picker, no Add Time.
        let mixedRelease = MetadataDatePickerEligibilityResolver.inspectorEligibility(
            for: .releaseDate,
            files: [mp3v24, flac]
        )
        XCTAssertEqual(mixedRelease?.destinationFormat, .isoDateOnly)
        XCTAssertEqual(mixedRelease?.destinationFormat.supportsTime, false)

        // MP3 (TDOR timestamp) + WMA (WM/OriginalReleaseYear year-only) -> year-only picker.
        let mixedOriginal = MetadataDatePickerEligibilityResolver.inspectorEligibility(
            for: .originalReleaseDate,
            files: [mp3v24, wma]
        )
        XCTAssertEqual(mixedOriginal?.destinationFormat, .yearOnly)

        // MP3 (TDRC) + M4A (©day) for Year -> M4A not eligible -> no picker.
        XCTAssertNil(MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .year, files: [mp3v24, m4a]))

        // Writable ID3v2.4 + read-only ID3v2.3 -> no picker.
        XCTAssertNil(MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .releaseDate, files: [mp3v24, mp3v23]))

        // A mixed raw selection only gets precision every native destination supports.
        XCTAssertEqual(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(
                rawKey: "RELEASEDATE",
                targets: [MetadataEditorTarget(file: mp3v24), MetadataEditorTarget(file: m4a)]
            )?.destinationFormat,
            .isoDateOnly
        )
    }

    @MainActor
    func testInspectorVisibilitySettingsRemainUnchanged() {
        XCTAssertFalse(InspectorMetadataField.configurableFields.contains { $0.metadataFieldKey == .itunesPurchaseDate })
        XCTAssertTrue(InspectorMetadataField.defaultVisibleFields.contains(.year))
        XCTAssertTrue(InspectorMetadataField.defaultVisibleFields.contains(.releaseDate))
        XCTAssertFalse(InspectorMetadataField.defaultVisibleFields.contains(.date))
        XCTAssertFalse(InspectorMetadataField.defaultVisibleFields.contains(.originalReleaseDate))
        XCTAssertTrue(InspectorMetadataField.configurableFields.contains(.date))
        XCTAssertTrue(InspectorMetadataField.configurableFields.contains(.originalReleaseDate))
    }

    @MainActor
    func testWriterRejectionIdentifiesFileAndFieldAndRetainsInspectorAndEditorEdits() async throws {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(
            bundle.url(forResource: "testAudioFile.flac", withExtension: nil, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: "testAudioFile.flac", withExtension: nil)
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let failingURL = root.appendingPathComponent("rejected-date.flac")
        try FileManager.default.copyItem(at: source, to: failingURL)

        let realPipeline = TagLibAudioMetadataPipeline()
        let initial = try await realPipeline.loadAudioFile(at: failingURL, id: UUID())
        var seed = SingleFileEditModel(from: initial)
        seed.releaseDate = "2020-01-01"
        _ = try realPipeline.writeMetadata(
            MetadataEditPayload(seed, comparedTo: initial),
            to: failingURL,
            expectedVersion: initial.metadataFileVersion
        )
        let file = try await realPipeline.loadAudioFile(at: failingURL, id: initial.id)

        let pipeline = RejectingDateWriterPipeline(errorMessage: "Tag writer rejected value.")
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        viewModel.setSelectedAudioIDs([file.id])
        viewModel.updateEditForSelection()

        // User enters arbitrary date text directly; AudioMator must pass it to the writer.
        viewModel.edit?.releaseDate = "Unusual Custom Date"
        viewModel.saveInspectorEdits()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while viewModel.metadataSaveProgress != nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(pipeline.recordedReleaseDates, ["Unusual Custom Date"])
        XCTAssertEqual(viewModel.edit?.releaseDate, "Unusual Custom Date", "Failed write must retain draft for correction")
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
        let hud = try XCTUnwrap(viewModel.metadataWriteHUD)
        XCTAssertEqual(hud.style, .failure)
        XCTAssertTrue(hud.summary.contains("rejected-date.flac"))
        XCTAssertTrue(hud.details.contains("Release Date"), "Failure details must identify affected field: \(hud.details)")

        // Metadata Editor rejection also identifies affected file & field and retains the draft.
        viewModel.cancelEditing()
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [file])
        while store.isLoading {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(store.loadErrorMessage)
        store.upsertField(key: "RELEASEDATE", value: "Custom Raw Date")
        let request = try XCTUnwrap(store.startApply())
        let outcome = await viewModel.applyRawMetadataApplyRequest(request)
        let completion = store.completeApply(outcome)

        XCTAssertEqual(completion, .remainReady)
        XCTAssertFalse(outcome.didApplyAllChanges)
        XCTAssertEqual(store.draftPropertyMaps[file.id]?["RELEASEDATE"], ["Custom Raw Date"])
        XCTAssertEqual(store.pendingTargets.map(\.id), [file.id])
        let latestIssue = try XCTUnwrap(viewModel.saveIssueLogStore.entries.first?.issues.first)
        XCTAssertEqual(latestIssue.fileName, "rejected-date.flac")
        XCTAssertTrue(
            latestIssue.messages.joined(separator: " ").contains("Release Date"),
            "Raw writer failure must identify affected field: \(latestIssue.messages)"
        )
    }

    @MainActor
    func testMultiSelectionPreservesMixedValuesUntilExplicitApplyAndKeepsDateFieldsIndependent() {
        let first = makeFile(
            path: "/tmp/one.mp3",
            id3v2MajorVersion: 4,
            year: "2020",
            date: "2020-05-01",
            releaseDate: "2020-06-01",
            originalReleaseDate: "1999"
        )
        let second = makeFile(
            path: "/tmp/two.flac",
            year: "2021",
            date: "2021-07-02",
            releaseDate: "2021-08-03",
            originalReleaseDate: "2001"
        )

        var multiEdit = MultiFileEditModel(files: [first, second])
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.year))
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.date))
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.releaseDate))
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.originalReleaseDate))
        XCTAssertFalse(multiEdit.hasUnsavedChanges)

        // Opening the picker for a mixed Release Date selection uses the representable subset (.isoDateOnly)
        // and does not overwrite the mixed state unless the user explicitly applies.
        let eligibility = MetadataDatePickerEligibilityResolver.inspectorEligibility(
            for: .releaseDate,
            files: [first, second]
        )
        XCTAssertEqual(eligibility?.destinationFormat, .isoDateOnly)

        var session = MetadataDateTimePickerSession(
            initialText: nil,
            isMixed: true,
            destinationFormat: eligibility!.destinationFormat,
            systemTimeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 1_717_286_400)
        )
        // Dismissing/cancelling without Apply leaves all fields mixed and untouched.
        XCTAssertFalse(multiEdit.hasUnsavedChanges)
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.releaseDate))
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.year))
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.date))
        XCTAssertTrue(multiEdit.mixedTextFields.contains(.originalReleaseDate))

        // Applying a picker choice replaces only Release Date and keeps Year, Date, Original Release Date independent.
        session.setDatePrecision(.yearMonth)
        session.setYear(2024)
        session.setMonth(11)
        let applied = session.formattedValue
        XCTAssertEqual(applied, "2024-11")
        multiEdit.setText(applied!, for: .releaseDate)

        let firstPayload = multiEdit.applyingChanges(to: first)
        let secondPayload = multiEdit.applyingChanges(to: second)
        XCTAssertEqual(firstPayload.releaseDate, "2024-11")
        XCTAssertEqual(secondPayload.releaseDate, "2024-11")
        XCTAssertEqual(firstPayload.year, "2020")
        XCTAssertEqual(secondPayload.year, "2021")
        XCTAssertEqual(firstPayload.date, "2020-05-01")
        XCTAssertEqual(secondPayload.date, "2021-07-02")
        XCTAssertEqual(firstPayload.originalReleaseDate, "1999")
        XCTAssertEqual(secondPayload.originalReleaseDate, "2001")
    }

    @MainActor
    func testMetadataEditorFieldDraftPreservesMultiValueOrderEmbeddedNewlinesAndMixedNoOp() throws {
        let flac = makeFile(path: "/tmp/multi-value.flac")
        let target = MetadataEditorTarget(file: flac)
        let presentationID = MetadataEditorPresentationID()

        // Uniform multi-value field with embedded newline in element 2.
        let context = MetadataFieldEditorContext(
            mode: .edit,
            key: "DATE",
            values: ["2020-01-01", "Line 1\nLine 2", "2020-01-01"],
            targetIDs: [flac.id],
            beforeValuesByTarget: [flac.id: ["2020-01-01", "Line 1\nLine 2", "2020-01-01"]],
            selectedValueIndex: 0,
            isMixed: false,
            presentationID: presentationID,
            draftGeneration: 1,
            displayName: "Date",
            targets: [target]
        )
        let eligibility = try XCTUnwrap(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: context.targets)
        )
        XCTAssertEqual(eligibility.destinationFormat, .isoDateOnly)

        var draft = MetadataFieldValueDraft(context: context)
        let selectedID = try XCTUnwrap(draft.selectedElementID)
        var session = MetadataDateTimePickerSession(
            initialText: draft.text(for: selectedID),
            destinationFormat: eligibility.destinationFormat,
            systemTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        session.setDate(year: 2024, month: 6, day: 2)
        // Applying updates only the selected element, keeping elements 2 and 3 verbatim in order.
        draft.setText(try XCTUnwrap(session.formattedValue), for: selectedID)
        XCTAssertEqual(draft.values, ["2024-06-02", "Line 1\nLine 2", "2020-01-01"])

        // Mixed selection starts with no elements; opening & dismissing the picker without Apply leaves it untouched.
        let mixedContext = MetadataFieldEditorContext(
            mode: .edit,
            key: "RELEASEDATE",
            values: [],
            targetIDs: [flac.id],
            beforeValuesByTarget: [flac.id: ["2020-01-01"]],
            selectedValueIndex: nil,
            isMixed: true,
            presentationID: presentationID,
            draftGeneration: 1,
            displayName: "Release Date",
            emptyStartReason: .mixedSelection,
            targets: [target]
        )
        var mixedDraft = MetadataFieldValueDraft(context: mixedContext)
        XCTAssertTrue(mixedDraft.elements.isEmpty)
        XCTAssertFalse(mixedDraft.canCommit)

        // Explicitly applying adds the replacement value.
        mixedDraft.addValue(text: "2024-11")
        XCTAssertEqual(mixedDraft.values, ["2024-11"])
        XCTAssertTrue(mixedDraft.canCommit)
    }
}

nonisolated private final class RejectingDateWriterPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private enum WriterError: LocalizedError {
        case rejected(String)
        var errorDescription: String? {
            switch self {
            case .rejected(let message): return message
            }
        }
    }

    private let lock = NSLock()
    private let base = TagLibAudioMetadataPipeline()
    private let errorMessage: String
    private var capturedReleaseDates: [String] = []

    init(errorMessage: String) {
        self.errorMessage = errorMessage
    }

    var recordedReleaseDates: [String] {
        lock.withLock { capturedReleaseDates }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        try await base.loadAudioFile(at: url, id: id)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try base.metadataFileVersion(at: url)
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        try base.conflictSnapshot(for: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        base.rawMetadataDumpText(for: url)
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        try base.rawMetadataValueMap(for: url)
    }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try base.projectMetadataWrite(intent, fileExtension: fileExtension)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        if case .text(let releaseDate) = try TagLibAudioMetadataPipeline.metadataPatchForWrite(from: edit).fields[.releaseDate] {
            lock.withLock { capturedReleaseDates.append(releaseDate) }
        }
        throw WriterError.rejected(errorMessage)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        throw WriterError.rejected(errorMessage)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
