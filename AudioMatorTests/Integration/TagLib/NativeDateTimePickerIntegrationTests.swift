import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

nonisolated final class NativeDateTimePickerIntegrationTests: XCTestCase {
    @MainActor
    func testID3v24PickerGeneratedValuesRoundTripAtEveryPrecisionIncludingHalfHourZoneAndTimezoneSwitch() async throws {
        let mp3 = try writableFixture(named: "testAudioFile.mp3")
        let pipeline = TemporaryFixtureTagLibPipeline()
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))

        let precisions: [(label: String, configure: (inout MetadataDateTimePickerSession) -> Void, expected: String)] = [
            ("year-only", { s in
                s.setDatePrecision(.year)
                s.setYear(2024)
            }, "2024"),
            ("year-and-month", { s in
                s.setDatePrecision(.yearMonth)
                s.setYear(2024)
                s.setMonth(6)
            }, "2024-06"),
            ("full-date", { s in
                s.setDatePrecision(.date)
                s.setDate(year: 2024, month: 6, day: 2)
            }, "2024-06-02"),
            ("minute-utc", { s in
                s.setDate(year: 2024, month: 6, day: 2)
                s.setTimeEnabled(true)
                s.setTime(hour: 0, minute: 30)
            }, "2024-06-01T16:30"),
            ("second-utc", { s in
                s.setDate(year: 2024, month: 6, day: 2)
                s.setTimeEnabled(true)
                s.setSecondsEnabled(true)
                s.setTime(hour: 0, minute: 30, second: 45)
            }, "2024-06-01T16:30:45"),
        ]

        for item in precisions {
            let file = try await pipeline.loadAudioFile(at: mp3, id: UUID())
            let eligibility = try XCTUnwrap(
                MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .releaseDate, files: [file]),
                item.label
            )
            XCTAssertEqual(eligibility.destinationFormat, .id3v24Timestamp, item.label)

            var session = MetadataDateTimePickerSession(
                initialText: nil,
                destinationFormat: eligibility.destinationFormat,
                systemTimeZone: shanghai
            )
            item.configure(&session)
            let generated = try XCTUnwrap(session.formattedValue, item.label)
            XCTAssertEqual(generated, item.expected, item.label)

            var edit = SingleFileEditModel(from: file)
            edit.year = generated
            edit.releaseDate = generated
            edit.originalReleaseDate = generated
            _ = try pipeline.writeMetadata(
                MetadataEditPayload(edit, comparedTo: file),
                to: mp3,
                expectedVersion: file.metadataFileVersion
            )

            let reloaded = try await pipeline.loadAudioFile(at: mp3, id: file.id)
            XCTAssertEqual(reloaded.year, item.expected, "TDRC \(item.label)")
            XCTAssertEqual(reloaded.releaseDate, item.expected, "TDRL \(item.label)")
            XCTAssertEqual(reloaded.originalReleaseDate, item.expected, "TDOR \(item.label)")

            // Reopening restores precision and time; editing date alone preserves both;
            // switching display time zone to UTC preserves the stored instant.
            var reopened = MetadataDateTimePickerSession(
                initialText: reloaded.releaseDate,
                destinationFormat: eligibility.destinationFormat,
                systemTimeZone: shanghai
            )
            XCTAssertEqual(reopened.formattedValue, item.expected, "Reopen \(item.label)")
            if item.label == "minute-utc" {
                reopened.setTimeZone(identifier: "UTC")
                XCTAssertEqual(reopened.localComponents.hour, 16)
                XCTAssertEqual(reopened.localComponents.minute, 30)
                XCTAssertEqual(reopened.formattedValue, "2024-06-01T16:30")
            }
            if item.label == "second-utc" {
                reopened.setDate(year: 2024, month: 6, day: 5)
                XCTAssertEqual(reopened.timePrecision, .second)
                XCTAssertEqual(reopened.formattedValue, "2024-06-04T16:30:45")
            }
        }

        // Hour-precision ID3v2.4 timestamp reopened in Asia/Kolkata (+05:30) round-trips
        // without losing an hour and preserves UTC hour on date-only edit.
        let fileForHour = try await pipeline.loadAudioFile(at: mp3, id: UUID())
        var hourEdit = SingleFileEditModel(from: fileForHour)
        hourEdit.releaseDate = "2024-06-02T14"
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(hourEdit, comparedTo: fileForHour),
            to: mp3,
            expectedVersion: fileForHour.metadataFileVersion
        )
        let hourReloaded = try await pipeline.loadAudioFile(at: mp3, id: fileForHour.id)
        XCTAssertEqual(hourReloaded.releaseDate, "2024-06-02T14")

        var kolkataSession = MetadataDateTimePickerSession(
            initialText: hourReloaded.releaseDate,
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: kolkata
        )
        XCTAssertEqual(kolkataSession.localComponents.hour, 19)
        XCTAssertEqual(kolkataSession.localComponents.minute, 30)
        XCTAssertEqual(kolkataSession.formattedValue, "2024-06-02T14")

        kolkataSession.setDate(year: 2024, month: 6, day: 10)
        var dateOnlyHourEdit = SingleFileEditModel(from: hourReloaded)
        dateOnlyHourEdit.releaseDate = try XCTUnwrap(kolkataSession.formattedValue)
        _ = try pipeline.writeMetadata(
            MetadataEditPayload(dateOnlyHourEdit, comparedTo: hourReloaded),
            to: mp3,
            expectedVersion: hourReloaded.metadataFileVersion
        )
        let hourAfterDateOnly = try await pipeline.loadAudioFile(at: mp3, id: fileForHour.id)
        XCTAssertEqual(hourAfterDateOnly.releaseDate, "2024-06-10T14")
    }

    @MainActor
    func testDateOnlyTargetsRoundTripYearYearMonthAndFullDateAcrossFormats() async throws {
        let pipeline = TemporaryFixtureTagLibPipeline()
        for fixtureName in ["testAudioFile.flac", "testAudioFile.m4a", "testAudioFile.ogg"] {
            let url = try writableFixture(named: fixtureName)
            for (precision, expected) in [
                (MetadataDatePrecision.year, "2024"),
                (MetadataDatePrecision.yearMonth, "2024-06"),
                (MetadataDatePrecision.date, "2024-06-02"),
            ] {
                let file = try await pipeline.loadAudioFile(at: url, id: UUID())
                let eligibility = try XCTUnwrap(
                    MetadataDatePickerEligibilityResolver.inspectorEligibility(for: .releaseDate, files: [file]),
                    fixtureName
                )
                XCTAssertEqual(eligibility.destinationFormat, .isoDateOnly, fixtureName)
                XCTAssertFalse(eligibility.destinationFormat.supportsTime, fixtureName)

                var session = MetadataDateTimePickerSession(
                    initialText: nil,
                    destinationFormat: eligibility.destinationFormat,
                    systemTimeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
                )
                session.setDate(year: 2024, month: 6, day: 2)
                session.setDatePrecision(precision)
                let value = try XCTUnwrap(session.formattedValue)
                XCTAssertEqual(value, expected, fixtureName)

                var edit = SingleFileEditModel(from: file)
                edit.date = value
                edit.releaseDate = value
                edit.originalReleaseDate = value
                _ = try pipeline.writeMetadata(
                    MetadataEditPayload(edit, comparedTo: file),
                    to: url,
                    expectedVersion: file.metadataFileVersion
                )

                let reloaded = try await pipeline.loadAudioFile(at: url, id: file.id)
                XCTAssertEqual(reloaded.date, expected, fixtureName)
                XCTAssertEqual(reloaded.releaseDate, expected, fixtureName)
                XCTAssertEqual(reloaded.originalReleaseDate, expected, fixtureName)
            }
        }
    }

    @MainActor
    func testMetadataEditorRawKeysAndMultiValuesRoundTripThroughReviewedApply() async throws {
        let pipeline = TemporaryFixtureTagLibPipeline()
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        // 1. MP3 ID3v2.4 RELEASEDATE (TDRL) and ORIGINALDATE (TDOR) via Metadata Editor session apply.
        let mp3 = try writableFixture(named: "testAudioFile.mp3")
        let mp3File = try await pipeline.loadAudioFile(at: mp3, id: UUID())
        let mp3Target = MetadataEditorTarget(file: mp3File)
        let releaseElig = try XCTUnwrap(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "RELEASEDATE", targets: [mp3Target])
        )
        XCTAssertEqual(releaseElig.effectiveRawKey, "RELEASEDATE")
        XCTAssertEqual(releaseElig.destinationFormat, .id3v24Timestamp)

        var releaseSession = MetadataDateTimePickerSession(
            initialText: nil,
            destinationFormat: releaseElig.destinationFormat,
            systemTimeZone: shanghai
        )
        releaseSession.setDate(year: 2024, month: 6, day: 2)
        releaseSession.setTimeEnabled(true)
        releaseSession.setTime(hour: 0, minute: 30)
        let releaseTimestamp = try XCTUnwrap(releaseSession.formattedValue)
        XCTAssertEqual(releaseTimestamp, "2024-06-01T16:30")

        let mp3Store = MetadataEditorStore(metadataPipeline: pipeline)
        mp3Store.present(targetFiles: [mp3File])
        try await waitUntilLoaded(mp3Store)
        mp3Store.upsertField(key: "RELEASEDATE", value: releaseTimestamp)
        mp3Store.upsertField(key: "ORIGINALDATE", value: "1999-11")
        let mp3VM = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        mp3VM.mergeQuickImportFiles([mp3File])
        let mp3Request = try XCTUnwrap(mp3Store.startApply())
        let mp3Outcome = await mp3VM.applyRawMetadataApplyRequest(mp3Request)
        XCTAssertTrue(mp3Outcome.didApplyAllChanges, "MP3 HUD: \(String(describing: mp3VM.metadataWriteHUD))")
        XCTAssertEqual(mp3Store.completeApply(mp3Outcome), .dismiss)

        let mp3Reloaded = try await pipeline.loadAudioFile(at: mp3, id: mp3File.id)
        XCTAssertEqual(mp3Reloaded.releaseDate, "2024-06-01T16:30")
        XCTAssertEqual(mp3Reloaded.originalReleaseDate, "1999-11")

        let mp3Frames = try pipeline.conflictSnapshot(for: mp3).structured.id3v2Frames
        XCTAssertEqual(mp3Frames.filter { $0.frameID == "TDRL" }.map(\.value), [releaseTimestamp])
        XCTAssertEqual(mp3Frames.filter { $0.frameID == "TDOR" }.map(\.value), ["1999-11"])
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "YEAR", targets: [mp3Target]))
        XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "STANDALONEDATE", targets: [mp3Target]))

        // 2. FLAC raw DATE preserves exact key `"DATE"` AND multi-value array ordering & embedded newlines.
        let flac = try writableFixture(named: "testAudioFile.flac")
        let flacInitial = try await pipeline.loadAudioFile(at: flac, id: UUID())
        _ = try pipeline.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["DATE": ["2020-01-01", "Line 1\nLine 2"]]),
            to: flac,
            expectedVersion: flacInitial.metadataFileVersion
        )
        let flacFile = try await pipeline.loadAudioFile(at: flac, id: flacInitial.id)
        let flacStore = MetadataEditorStore(metadataPipeline: pipeline)
        flacStore.present(targetFiles: [flacFile])
        try await waitUntilLoaded(flacStore)
        flacStore.selectedFieldKey = "DATE"

        let editContext = try XCTUnwrap(flacStore.makeEditFieldContext())
        let flacDateElig = try XCTUnwrap(
            MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: "DATE", targets: editContext.targets)
        )
        XCTAssertEqual(flacDateElig.effectiveRawKey, "DATE")
        XCTAssertEqual(flacDateElig.destinationFormat, .isoDateOnly)

        var draft = MetadataFieldValueDraft(context: editContext)
        let firstElementID = try XCTUnwrap(draft.selectedElementID)
        draft.setText("2024-06-02", for: firstElementID)
        XCTAssertEqual(flacStore.commitFieldEntry(editContext, typedKey: "DATE", values: draft.values), .applied)

        let flacVM = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        flacVM.mergeQuickImportFiles([flacFile])
        let flacRequest = try XCTUnwrap(flacStore.startApply())
        let flacOutcome = await flacVM.applyRawMetadataApplyRequest(flacRequest)
        XCTAssertTrue(flacOutcome.didApplyAllChanges, "FLAC HUD: \(String(describing: flacVM.metadataWriteHUD))")
        XCTAssertEqual(flacStore.completeApply(flacOutcome), .dismiss)

        let flacReloaded = try await pipeline.loadAudioFile(at: flac, id: flacFile.id)
        XCTAssertEqual(flacReloaded.year, "")
        XCTAssertEqual(try pipeline.rawMetadataValueMap(for: flac)["DATE"], ["2024-06-02", "Line 1\nLine 2"])

        // 3. Confirm the actual MP4 atoms for allowed keys. The raw purchase
        // date key cannot address purd, and STANDALONEDATE is a projection key.
        let m4a = try writableFixture(named: "testAudioFile.m4a")
        let m4aFile = try await pipeline.loadAudioFile(at: m4a, id: UUID())
        let m4aTarget = MetadataEditorTarget(file: m4aFile)
        for key in ["ITUNESPURCHASEDATE", "PURCHASEDATE", "PURD", "STANDALONEDATE"] {
            XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: key, targets: [m4aTarget]))
        }
        let dateValues = ["RELEASEDATE": ["2024-06-02"], "ORIGINALDATE": ["1999-11"]]
        for key in dateValues.keys {
            let eligibility = MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: key, targets: [m4aTarget])
            XCTAssertEqual(eligibility?.destinationFormat, .isoDateOnly)
            XCTAssertEqual(eligibility?.effectiveRawKey, key)
        }
        _ = try pipeline.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: dateValues), to: m4a, expectedVersion: m4aFile.metadataFileVersion
        )
        let atoms = try pipeline.conflictSnapshot(for: m4a).structured.mp4Atoms
        for (key, values) in dateValues {
            let nativeKey = "----:com.apple.iTunes:\(key)"
            XCTAssertEqual(atoms.filter { $0.key == nativeKey }.flatMap(\.values), values)
        }
    }

    @MainActor
    func testRealID3v23FixtureIsIneligibleInBothInspectorAndMetadataEditor() async throws {
        let source = try bundledAudioFixtureURL(named: "testAudioFile.mp3")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("legacy-v23.mp3")
        try ID3v23FixtureBuilder.makeID3v23Copy(of: source).write(to: url)

        let pipeline = TemporaryFixtureTagLibPipeline()
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        let target = MetadataEditorTarget(file: file)

        for field in [InspectorMetadataField.year, .date, .releaseDate, .originalReleaseDate] {
            XCTAssertNil(MetadataDatePickerEligibilityResolver.inspectorEligibility(for: field, files: [file]))
        }
        for key in ["YEAR", "DATE", "STANDALONEDATE", "RELEASEDATE", "ORIGINALDATE", "ITUNESPURCHASEDATE"] {
            XCTAssertNil(MetadataDatePickerEligibilityResolver.metadataEditorEligibility(rawKey: key, targets: [target]))
        }
    }

    @MainActor
    func testDirectTypedCSVTextAndFilenameValuesReachWriterWithoutDateRewriting() async throws {
        let pipeline = TemporaryFixtureTagLibPipeline()
        let flac = try writableFixture(named: "testAudioFile.flac")
        let file = try await pipeline.loadAudioFile(at: flac, id: UUID())

        // 1. Direct Inspector typing/paste passes arbitrary text through without rewriting.
        var edit = SingleFileEditModel(from: file)
        edit.year = "circa 1998"
        edit.date = "Spring 2024"
        edit.releaseDate = "06/02/2024 00:30"
        edit.originalReleaseDate = "Late 1990s"
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        let writeResult = await viewModel.persistReviewedEditForTest(edit, to: file, comparedTo: file)
        if case .failure(let reason) = writeResult {
            return XCTFail("Expected direct user-entered date text to reach writer without AudioMator date rejection; got: \(reason)")
        }
        let reloaded = try await pipeline.loadAudioFile(at: flac, id: file.id)
        XCTAssertEqual(reloaded.year, "circa 1998")
        XCTAssertEqual(reloaded.date, "Spring 2024")
        XCTAssertEqual(reloaded.releaseDate, "06/02/2024 00:30")
        XCTAssertEqual(reloaded.originalReleaseDate, "Late 1990s")

        // Clear semantics still work cleanly.
        var clearEdit = SingleFileEditModel(from: reloaded)
        clearEdit.releaseDate = ""
        let clearResult = await viewModel.persistReviewedEditForTest(clearEdit, to: reloaded, comparedTo: reloaded)
        if case .failure(let reason) = clearResult {
            return XCTFail("Expected clearing releaseDate to succeed; got: \(reason)")
        }
        let afterClear = try await pipeline.loadAudioFile(at: flac, id: file.id)
        XCTAssertEqual(afterClear.releaseDate, "")
        XCTAssertEqual(afterClear.year, "circa 1998")

        // 2. CSV import passes non-ISO date values through without date-specific rejection.
        let csvPlan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{year}},{{date}},{{releaseDate}},{{originalReleaseDate}}",
            sourceText: "\(MetadataExchangeProfile.markerLine())\nYear,Date,Release Date,Original Release Date\nAutumn 2001,Q2 2002,06/02/2024,1990s",
            firstRowIsHeader: true,
            targetFiles: [afterClear],
            clearBlankImportedValues: false
        )
        XCTAssertNil(csvPlan.validationMessage)
        let csvEntry = try XCTUnwrap(csvPlan.writeEntries.first)
        XCTAssertEqual(csvEntry.previewValues[.year], "Autumn 2001")
        XCTAssertEqual(csvEntry.previewValues[.date], "Q2 2002")
        XCTAssertEqual(csvEntry.previewValues[.releaseDate], "06/02/2024")
        XCTAssertEqual(csvEntry.previewValues[.originalReleaseDate], "1990s")

        // 3. Text import passes non-ISO date values through without date-specific rejection.
        let textPlan = MetadataExchangePlanner.makeTextImportPlan(
            template: "{{year}} | {{releaseDate}}",
            sourceText: "circa 1979 | May 1980",
            targetFiles: [afterClear],
            clearBlankImportedValues: false
        )
        XCTAssertNil(textPlan.validationMessage)
        let textEntry = try XCTUnwrap(textPlan.writeEntries.first)
        XCTAssertEqual(textEntry.previewValues[.year], "circa 1979")
        XCTAssertEqual(textEntry.previewValues[.releaseDate], "May 1980")

        // 4. Filename extraction passes non-ISO date values through without date-specific rejection.
        let namedURL = flac.deletingLastPathComponent().appendingPathComponent("Spring 2024 - circa 1998.flac")
        try FileManager.default.moveItem(at: flac, to: namedURL)
        let namedFile = try await pipeline.loadAudioFile(at: namedURL, id: file.id)
        let filenamePlan = makeFilenameMetadataPlan(
            template: "{{releaseDate}} - {{originalReleaseDate}}",
            targetFiles: [namedFile],
            replaceUnderscoresWithSpaces: false
        )
        XCTAssertNil(filenamePlan.validationMessage)
        let filenameEntry = try XCTUnwrap(filenamePlan.writeEntries.first)
        XCTAssertEqual(filenameEntry.previewValues[.releaseDate], "Spring 2024")
        XCTAssertEqual(filenameEntry.previewValues[.originalReleaseDate], "circa 1998")
    }

    // MARK: - Helpers

    @MainActor
    private func waitUntilLoaded(_ store: MetadataEditorStore) async throws {
        let deadline = Date().addingTimeInterval(2)
        while store.isLoading && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(store.isLoading)
    }

    private func writableFixture(named fixtureName: String) throws -> URL {
        let source = try bundledAudioFixtureURL(named: fixtureName)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(fixtureName)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    private func bundledAudioFixtureURL(named name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: name, withExtension: nil)
        )
    }
}

/// Test-owned temporary files already have filesystem access. Skip only the production
/// folder permission UI; all reads and commits still use the real TagLib adapter.
private struct TemporaryFixtureTagLibPipeline: AudioMetadataPipeline {
    private let base = TagLibAudioMetadataPipeline()

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
        try base.writeMetadata(edit, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult {
        try base.writeMetadata(
            edit,
            to: url,
            expectedVersion: expectedVersion,
            expectedAudioContent: expectedAudioContent
        )
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion,
        expectedAudioContent: MetadataAudioContentIdentity
    ) throws -> AudioMetadataWriteResult {
        try base.writeRawMetadataPatch(
            patch,
            to: url,
            expectedVersion: expectedVersion,
            expectedAudioContent: expectedAudioContent
        )
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.eraseAllMetadata(at: url, expectedVersion: expectedVersion)
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
