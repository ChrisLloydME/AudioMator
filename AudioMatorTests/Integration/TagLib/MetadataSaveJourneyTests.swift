import AVFoundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

/// Starts at the displayed workbench/editor state, uses the actual executor,
/// and checks disk plus reloaded models. No recording metadata pipeline.
nonisolated final class MetadataSaveJourneyTests: XCTestCase {
    @MainActor
    private var pipeline: TagLibAudioMetadataPipeline { TagLibAudioMetadataPipeline() }

    @MainActor
    func testiTunesEachCheckedFieldWritesAndUncheckedFieldsSurvive() async throws {
        let expected: Set<iTunesTagWriteField> = [.title, .artist, .albumArtist, .album, .genre,
            .trackNumber, .trackTotal, .discNumber, .discTotal, .releaseDate, .copyright,
            .itunesAlbumID, .itunesArtistID, .itunesCatalogID, .isExplicit]
        XCTAssertEqual(expected.union([.barcode]), Set(iTunesTagWriteField.allCases))
        for ext in ["m4a", "flac", "aiff"] {
            for field in expected {
                let file = try await fixture(ext)
                let store = itunes(file)
                store.deselectAllFields()
                store.setFieldSelected(true, for: field)
                let plan = store.plan
                let entry = try XCTUnwrap(plan.writeEntries.first, "\(ext) \(field)")
                XCTAssertEqual(Set(entry.values.keys), [field])
                XCTAssertEqual(entry.expectedFileFingerprint, file.fileFingerprint)
                let vm = viewModel([file])
                await vm.applyiTunesTaggingPlan(plan.writeEntries)
                let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                XCTAssertEqual(field.localValue(from: saved), entry.values[field], "\(ext) checked \(field)")
                for other in iTunesTagWriteField.allCases where other != field {
                    XCTAssertEqual(other.localValue(from: saved), other.localValue(from: file),
                                   "\(ext) unchecked \(other) while writing \(field)")
                }
                XCTAssertEqual(saved.year, "2004")
                XCTAssertEqual(vm.files.first?.itunesArtistID, saved.itunesArtistID)
            }
        }
    }

    @MainActor
    func testMusicBrainzEachCheckedReleaseFieldWritesAndUncheckedFieldsSurvive() async throws {
        let expected: Set<MusicBrainzTagWriteField> = [.title, .artist, .albumArtist, .album,
            .trackNumber, .trackTotal, .discNumber, .releaseDate, .musicBrainzAlbumID,
            .musicBrainzTrackID, .musicBrainzReleaseGroupID, .mediaType, .releaseType, .releaseCountry,
            .genre, .discTotal, .publisher, .isrc, .barcode, .language, .catalogNumber]
        XCTAssertEqual(expected.union([.composer, .lyricist, .producer, .engineer, .remixer, .copyright]),
                       Set(MusicBrainzTagWriteField.allCases))
        for ext in ["m4a", "flac", "aiff"] {
            for field in expected {
                let file = try await fixture(ext)
                let store = musicbrainz(file)
                store.deselectAllFields()
                store.setFieldSelected(true, for: field)
                let plan = store.plan
                let entry = try XCTUnwrap(plan.writeEntries.first, "\(ext) \(field)")
                XCTAssertEqual(Set(entry.values.keys), [field])
                let vm = viewModel([file])
                await vm.applyMusicBrainzTaggingPlan(plan.writeEntries)
                let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                XCTAssertEqual(field.localValue(from: saved), entry.values[field], "\(ext) checked \(field)")
                for other in MusicBrainzTagWriteField.allCases where other != field {
                    XCTAssertEqual(other.localValue(from: saved), other.localValue(from: file),
                                   "\(ext) unchecked \(other) while writing \(field)")
                }
                XCTAssertEqual(saved.year, "2004")
                XCTAssertEqual(vm.files.first?.title, saved.title)
            }
        }
    }

    @MainActor
    func testCapturedDisplayedPlansExecuteTheirSelectionAfterCheckboxesChange() async throws {
        for useITunes in [true, false] {
            let file = try await fixture("m4a")
            let vm = viewModel([file])
            if useITunes {
                let store = itunes(file)
                store.deselectAllFields()
                store.setFieldSelected(true, for: .title)
                let displayed = store.plan
                store.deselectAllFields()
                store.setFieldSelected(true, for: .album)
                await vm.applyiTunesTaggingPlan(displayed.writeEntries)
            } else {
                let store = musicbrainz(file)
                store.deselectAllFields()
                store.setFieldSelected(true, for: .title)
                let displayed = store.plan
                store.deselectAllFields()
                store.setFieldSelected(true, for: .album)
                await vm.applyMusicBrainzTaggingPlan(displayed.writeEntries)
            }
            let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
            XCTAssertEqual(saved.title, "Remote")
            XCTAssertEqual(saved.album, file.album)
        }
    }

    @MainActor
    func testNoCheckedFieldsAndMissingRemoteValuesDoNotClearExistingTags() async throws {
        let file = try await fixture("flac")
        let before = try Data(contentsOf: file.url)
        let vm = viewModel([file])
        let apple = itunes(file)
        apple.deselectAllFields()
        apple.setFieldSelected(true, for: .barcode) // No remote barcode; must not invent or clear one.
        XCTAssertTrue(apple.plan.writeEntries.isEmpty)
        await vm.applyiTunesTaggingPlan(apple.plan.writeEntries)
        let mb = musicbrainz(file)
        mb.deselectAllFields()
        XCTAssertTrue(mb.plan.writeEntries.isEmpty)
        await vm.applyMusicBrainzTaggingPlan(mb.plan.writeEntries)
        mb.setFieldSelected(true, for: .composer) // No recording detail supplied.
        XCTAssertTrue(mb.plan.writeEntries.isEmpty)
        await vm.applyMusicBrainzTaggingPlan(mb.plan.writeEntries)
        XCTAssertEqual(try Data(contentsOf: file.url), before)
    }

    @MainActor
    func testBothProvidersRejectStaleDisplayedPlanAndContinueOtherBatchFiles() async throws {
        for useITunes in [true, false] {
            let stale = try await fixture("m4a")
            let valid = try await fixture("flac")
            let vm = viewModel([stale, valid])
            let appleEntries = [stale, valid].flatMap { file -> [iTunesTaggingWriteEntry] in
                let store = itunes(file); store.deselectAllFields(); store.setFieldSelected(true, for: .title)
                return store.plan.writeEntries
            }
            let mbEntries = [stale, valid].flatMap { file -> [MusicBrainzTaggingWriteEntry] in
                let store = musicbrainz(file); store.deselectAllFields(); store.setFieldSelected(true, for: .title)
                return store.plan.writeEntries
            }
            var external = SingleFileEditModel(from: stale)
            external.title = "External change"
            _ = try pipeline.writeMetadata(MetadataEditPayload(external, comparedTo: stale), to: stale.url,
                                           expectedVersion: stale.metadataFileVersion)
            let bytes = try Data(contentsOf: stale.url)
            if useITunes { await vm.applyiTunesTaggingPlan(appleEntries) }
            else { await vm.applyMusicBrainzTaggingPlan(mbEntries) }
            XCTAssertEqual(try Data(contentsOf: stale.url), bytes)
            let saved = try await pipeline.loadAudioFile(at: valid.url, id: valid.id)
            XCTAssertEqual(saved.title, "Remote")
            XCTAssertEqual(vm.files.first { $0.id == valid.id }?.title, "Remote")
        }
    }

    @MainActor
    func testMetadataEditorDraftAddReplaceDeletePersistsArraysAndRefreshes() async throws {
        let files = try await [fixture("m4a"), fixture("flac")]
        let vm = viewModel(files)
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: files)
        try await loaded(store)
        XCTAssertTrue(store.isEditable)
        store.upsertField(key: "TITLE", value: "Editor title")
        store.upsertField(key: "X-JOURNEY", value: "A; B\nduplicate\nduplicate\n  padded  ")
        store.deleteField(named: "COMMENT")
        let result = await vm.applyRawMetadataPropertyMaps(store.draftPropertyMaps, to: store.pendingTargets)
        XCTAssertTrue(result.didApplyAllChanges)
        XCTAssertEqual(result.succeededTargetIDs, Set(files.map(\.id)))
        store.recordAppliedTargets(result.succeededTargetIDs)
        XCTAssertFalse(store.hasUnsavedChanges)
        for file in files {
            let raw = try pipeline.rawMetadataValueMap(for: file.url)
            XCTAssertEqual(raw["TITLE"], ["Editor title"])
            XCTAssertEqual(raw["X-JOURNEY"], ["A; B", "duplicate", "duplicate", "  padded  "])
            XCTAssertNil(raw["COMMENT"])
            let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
            XCTAssertEqual(saved.itunesArtistID, file.itunesArtistID)
            XCTAssertEqual(vm.files.first { $0.id == file.id }?.title, "Editor title")
        }
    }

    @MainActor
    func testMetadataEditorKeepsFailedDraftAndRemovesOnlySuccessfulTargets() async throws {
        let stale = try await fixture("m4a")
        let valid = try await fixture("flac")
        let vm = viewModel([stale, valid])
        let store = MetadataEditorStore(metadataPipeline: pipeline)
        store.present(targetFiles: [stale, valid])
        try await loaded(store)
        store.upsertField(key: "TITLE", value: "Editor title")
        var edit = SingleFileEditModel(from: stale)
        edit.title = "External"
        _ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: stale), to: stale.url,
                                       expectedVersion: stale.metadataFileVersion)
        let bytes = try Data(contentsOf: stale.url)
        let result = await vm.applyRawMetadataPropertyMaps(store.draftPropertyMaps, to: store.pendingTargets)
        XCTAssertFalse(result.didApplyAllChanges)
        XCTAssertEqual(result.succeededTargetIDs, [valid.id])
        store.recordAppliedTargets(result.succeededTargetIDs)
        XCTAssertEqual(store.pendingTargets.map(\.id), [stale.id])
        XCTAssertEqual(store.draftPropertyMaps[stale.id]?["TITLE"], ["Editor title"])
        XCTAssertTrue(store.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: stale.url), bytes)
    }

    @MainActor
    func testMusicBrainzRecordingCreditsPreviewSelectionAndRealSave() async throws {
        let fields: [(MusicBrainzTagWriteField, String)] = [
            (.composer, "Remote composer"), (.lyricist, "Remote lyricist"),
            (.producer, "Remote producer"), (.engineer, "Remote engineer"),
            (.remixer, "Remote remixer"), (.copyright, "Remote copyright")
        ]
        for ext in ["m4a", "flac", "aiff"] {
            for (field, expected) in fields {
                let file = try await fixture(ext)
                let browser = MusicBrainzBrowserStore(client: OfflineJourneyMusicBrainzClient())
                _ = try await browser.recordingDetail(id: "offline-recording")
                let store = musicbrainz(file, browser: browser, recordingID: "offline-recording")
                store.deselectAllFields()
                store.setFieldSelected(true, for: field)
                let plan = store.plan
                XCTAssertEqual(plan.writeEntries.first?.values, [field: expected])
                let vm = viewModel([file])
                await vm.applyMusicBrainzTaggingPlan(plan.writeEntries)
                let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                XCTAssertEqual(field.localValue(from: saved), expected, "\(ext) \(field)")
                XCTAssertEqual(saved.title, file.title)
                XCTAssertEqual(saved.album, file.album)
                XCTAssertEqual(saved.itunesArtistID, file.itunesArtistID)
            }
        }
    }

    @MainActor
    func testInspectorRejectedSavePreservesDiskAndDirtyDraft() async throws {
        let file = try await fixture("aiff")
        let vm = viewModel([file])
        vm.edit?.title = "Keep unsaved draft"
        vm.edit?.itunesArtistID = "not-a-number"
        let before = try Data(contentsOf: file.url)
        vm.saveInspectorEdits()
        try await saveFinished(vm)
        XCTAssertEqual(try Data(contentsOf: file.url), before)
        XCTAssertEqual(vm.edit?.title, "Keep unsaved draft")
        XCTAssertEqual(vm.edit?.itunesArtistID, "not-a-number")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        XCTAssertEqual(vm.files.first?.title, file.title)
    }

    @MainActor
    func testInspectorBatchKeepsFailedDraftAndDoesNotRewriteSuccessfulFilesOnRetry() async throws {
        let stale = try await fixture("m4a")
        let valid = try await fixture("flac")
        let vm = viewModel([stale, valid])
        vm.multiEdit?.setText("Batch title", for: .title)
        var external = SingleFileEditModel(from: stale)
        external.title = "External title"
        _ = try pipeline.writeMetadata(MetadataEditPayload(external, comparedTo: stale), to: stale.url,
                                       expectedVersion: stale.metadataFileVersion)
        let before = try Data(contentsOf: stale.url)
        vm.saveInspectorEdits()
        try await saveFinished(vm)
        XCTAssertEqual(try Data(contentsOf: stale.url), before)
        let saved = try await pipeline.loadAudioFile(at: valid.url, id: valid.id)
        XCTAssertEqual(saved.title, "Batch title")
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        let successfulBytes = try Data(contentsOf: valid.url)
        let successfulVersion = try pipeline.metadataFileVersion(at: valid.url)
        vm.saveInspectorEdits()
        try await saveFinished(vm)
        XCTAssertEqual(try Data(contentsOf: valid.url), successfulBytes)
        XCTAssertEqual(try pipeline.metadataFileVersion(at: valid.url), successfulVersion)
        XCTAssertEqual(try Data(contentsOf: stale.url), before)
    }

    @MainActor
    func testInspectorIndependentDatesTypedIDsTotalsAndClears() async throws {
        let file = try await fixture("m4a")
        let vm = viewModel([file])
        vm.edit?.date = "2008-03-04"
        vm.edit?.originalReleaseDate = "1999-11-12"
        vm.edit?.itunesArtistID = "12345"
        vm.edit?.contentAdvisory = .clean
        vm.saveInspectorEdits()
        try await saveFinished(vm)
        vm.edit?.year = "2005"
        vm.edit?.releaseDate = "2020-02-03"
        vm.edit?.itunesArtistID = ""
        vm.edit?.setTrackTotalFieldText("")
        vm.edit?.contentAdvisory = nil
        vm.saveInspectorEdits()
        try await saveFinished(vm)
        let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
        XCTAssertEqual(saved.year, "2005")
        XCTAssertEqual(saved.date, "2008-03-04")
        XCTAssertEqual(saved.originalReleaseDate, "1999-11-12")
        XCTAssertEqual(saved.releaseDate, "2020-02-03")
        XCTAssertEqual(saved.itunesArtistID, "")
        XCTAssertEqual(saved.track, 7)
        XCTAssertEqual(saved.trackTotal, 0)
        XCTAssertNil(saved.contentAdvisory)
        XCTAssertEqual(vm.edit?.date, saved.date)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
    }

    @MainActor
    func testInspectorNoOpAndRevertedBatchNeverWriteDiskThenRealSaveBecomesClean() async throws {
        let files = try await [fixture("m4a"), fixture("flac")]
        let vm = viewModel(files)
        let bytes = try files.map { try Data(contentsOf: $0.url) }
        let versions = try files.map { try pipeline.metadataFileVersion(at: $0.url) }
        vm.multiEdit?.setText(files[0].album, for: .album)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.setText("Temporary", for: .album)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.setText(files[0].album, for: .album)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        // Exercise the direct entry point too: it must not enqueue no-op writes.
        vm.saveMultiFileEdits()
        XCTAssertNil(vm.metadataSaveProgress)
        for (index, file) in files.enumerated() {
            XCTAssertEqual(try Data(contentsOf: file.url), bytes[index])
            XCTAssertEqual(try pipeline.metadataFileVersion(at: file.url), versions[index])
        }
        vm.multiEdit?.setText("Actual edit", for: .album)
        vm.saveInspectorEdits()
        try await saveFinished(vm)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        await vm.refreshSelectedFilesAfterActivation()
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        for file in files {
            let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
            XCTAssertEqual(saved.album, "Actual edit")
        }
    }

    @MainActor
    func testBatchClearingUnknownAdvisoryRemainsAnActualEdit() async throws {
        let files = try await [fixture("m4a"), fixture("m4a")]
        var unknown: [AudioFile] = []
        for file in files {
            try TagLibMetadataManager.writeStructuredMetadataWithVerification(.init(mp4Atoms: [
                .init(key: "rtng", type: "uint", value: "4")
            ]), to: file.url)
            unknown.append(try await pipeline.loadAudioFile(at: file.url, id: file.id))
        }
        let vm = viewModel(unknown)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        vm.multiEdit?.explicitEditState = .set(nil)
        XCTAssertTrue(vm.hasUnsavedInspectorChanges)
        vm.saveInspectorEdits()
        try await saveFinished(vm)
        XCTAssertFalse(vm.hasUnsavedInspectorChanges)
        for file in unknown {
            let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
            XCTAssertNil(saved.advisoryRawValue)
        }
    }

    @MainActor
    func testAllDatePresenceStatesThroughDisplayedSaveJourneys() async throws {
        let keys: [MetadataFieldKey] = [.year, .standaloneDate, .releaseDate, .originalReleaseDate]
        let dates = ["2004", "2008-03-04", "2017-06-09", "1999-11-12"]
        var completed = 0
        for mask in 0..<16 {
            for journey in ["itunes", "musicbrainz", "inspector", "editor", "csv"] {
                let original = try await fixture("m4a")
                try TagLibMetadataManager.applyMetadataPatch(.init(fields: Dictionary(uniqueKeysWithValues:
                    keys.enumerated().map { index, key in
                        (key, mask & (1 << index) == 0 ? MetadataPatchValue.remove : .text(dates[index]))
                    })), to: original.url)
                let file = try await pipeline.loadAudioFile(at: original.url, id: original.id)
                let vm = viewModel([file])
                switch journey {
                case "itunes":
                    let store = itunes(file)
                    store.deselectAllFields(); store.setFieldSelected(true, for: .title)
                    XCTAssertEqual(Set(try XCTUnwrap(store.plan.writeEntries.first).values.keys), [.title])
                    await vm.applyiTunesTaggingPlan(store.plan.writeEntries)
                case "musicbrainz":
                    let store = musicbrainz(file)
                    store.deselectAllFields(); store.setFieldSelected(true, for: .title)
                    XCTAssertEqual(Set(try XCTUnwrap(store.plan.writeEntries.first).values.keys), [.title])
                    await vm.applyMusicBrainzTaggingPlan(store.plan.writeEntries)
                case "inspector":
                    vm.edit?.comment = "Sparse Inspector"
                    XCTAssertTrue(vm.hasUnsavedInspectorChanges)
                    vm.saveInspectorEdits()
                    try await saveFinished(vm)
                    XCTAssertFalse(vm.hasUnsavedInspectorChanges)
                case "csv":
                    let plan = MetadataExchangePlanner.makeCSVImportPlan(template: "{{comment}}",
                        sourceText: "comment\nSparse CSV", firstRowIsHeader: true,
                        targetFiles: [file], clearBlankImportedValues: false)
                    XCTAssertEqual(plan.writeEntries.count, 1)
                    _ = await vm.applyMetadataExchangeWriteEntries(plan.writeEntries)
                default:
                    let store = MetadataEditorStore(metadataPipeline: pipeline)
                    store.present(targetFiles: [file]); try await loaded(store)
                    store.upsertField(key: "COMMENT", value: "Sparse Editor")
                    let result = await vm.applyRawMetadataPropertyMaps(store.draftPropertyMaps, to: store.pendingTargets)
                    XCTAssertTrue(result.didApplyAllChanges)
                    store.recordAppliedTargets(result.succeededTargetIDs)
                    XCTAssertFalse(store.hasUnsavedChanges)
                }
                let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                if journey == "itunes" || journey == "musicbrainz" { XCTAssertEqual(saved.title, "Remote") }
                else { XCTAssertEqual(saved.comment, journey == "inspector" ? "Sparse Inspector" : journey == "csv" ? "Sparse CSV" : "Sparse Editor") }
                XCTAssertEqual([saved.year, saved.date, saved.releaseDate, saved.originalReleaseDate],
                    dates.enumerated().map { mask & (1 << $0.offset) == 0 ? "" : $0.element },
                    "\(journey), mask=\(mask)")
                completed += 1
            }
        }
        XCTAssertEqual(completed, 80)
    }

    @MainActor
    func testEveryProviderSelectionAcrossAllDatePresenceStates() async throws {
        let keys: [MetadataFieldKey] = [.year, .standaloneDate, .releaseDate, .originalReleaseDate]
        let dates = ["2004", "2008-03-04", "2017-06-09", "1999-11-12"]
        let browser = MusicBrainzBrowserStore(client: OfflineJourneyMusicBrainzClient())
        _ = try await browser.recordingDetail(id: "offline-recording")
        var completed = 0
        for mask in 0..<16 {
            for provider in 0..<2 {
                let count = provider == 0 ? iTunesTagWriteField.allCases.count : MusicBrainzTagWriteField.allCases.count
                for index in 0..<count {
                    let original = try await fixture("m4a")
                    try TagLibMetadataManager.applyMetadataPatch(.init(fields: Dictionary(uniqueKeysWithValues:
                        keys.enumerated().map { offset, key in
                            (key, mask & (1 << offset) == 0 ? MetadataPatchValue.remove : .text(dates[offset]))
                        })), to: original.url)
                    let file = try await pipeline.loadAudioFile(at: original.url, id: original.id)
                    let vm = viewModel([file])
                    var expectedDates = dates.enumerated().map { mask & (1 << $0.offset) == 0 ? "" : $0.element }
                    if provider == 0 {
                        let field = iTunesTagWriteField.allCases[index]
                        let store = itunes(file)
                        store.deselectAllFields(); store.setFieldSelected(true, for: field)
                        let plan = store.plan
                        if field == .barcode {
                            let before = try Data(contentsOf: file.url)
                            XCTAssertTrue(plan.writeEntries.isEmpty)
                            await vm.applyiTunesTaggingPlan(plan.writeEntries)
                            XCTAssertEqual(try Data(contentsOf: file.url), before)
                        } else {
                            let entry = try XCTUnwrap(plan.writeEntries.first)
                            XCTAssertEqual(Set(entry.values.keys), [field])
                            await vm.applyiTunesTaggingPlan(plan.writeEntries)
                            let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                            XCTAssertEqual(field.localValue(from: saved), entry.values[field], "mask=\(mask), iTunes \(field)")
                            for other in iTunesTagWriteField.allCases where other != field {
                                XCTAssertEqual(other.localValue(from: saved), other.localValue(from: file))
                            }
                            if field == .releaseDate { expectedDates[2] = try XCTUnwrap(entry.values[field]) }
                        }
                    } else {
                        let field = MusicBrainzTagWriteField.allCases[index]
                        let store = musicbrainz(file, browser: browser, recordingID: "offline-recording")
                        store.deselectAllFields(); store.setFieldSelected(true, for: field)
                        let plan = store.plan
                        let entry = try XCTUnwrap(plan.writeEntries.first)
                        XCTAssertEqual(Set(entry.values.keys), [field])
                        await vm.applyMusicBrainzTaggingPlan(plan.writeEntries)
                        let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                        XCTAssertEqual(field.localValue(from: saved), entry.values[field], "mask=\(mask), MusicBrainz \(field)")
                        for other in MusicBrainzTagWriteField.allCases where other != field {
                            XCTAssertEqual(other.localValue(from: saved), other.localValue(from: file))
                        }
                        if field == .releaseDate { expectedDates[2] = try XCTUnwrap(entry.values[field]) }
                    }
                    let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                    XCTAssertEqual([saved.year, saved.date, saved.releaseDate, saved.originalReleaseDate], expectedDates)
                    completed += 1
                }
            }
        }
        XCTAssertEqual(iTunesTagWriteField.allCases.count, 16)
        XCTAssertEqual(MusicBrainzTagWriteField.allCases.count, 27)
        XCTAssertEqual(completed, 688)
    }

    @MainActor
    private func saveFinished(_ vm: AudioViewModel) async throws {
        XCTAssertNotNil(vm.metadataSaveProgress)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while vm.metadataSaveProgress != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(vm.metadataSaveProgress, "Save timed out")
    }

    @MainActor
    func testAllAvailableCheckedFieldsSaveTogetherThroughDisplayedPlans() async throws {
        for ext in ["m4a", "flac", "aiff"] {
            for useITunes in [true, false] {
                let file = try await fixture(ext)
                let vm = viewModel([file])
                if useITunes {
                    let store = itunes(file)
                    store.selectAllAvailableFields()
                    let plan = store.plan
                    let expected = try XCTUnwrap(plan.writeEntries.first?.values)
                    XCTAssertGreaterThan(expected.count, 10)
                    await vm.applyiTunesTaggingPlan(plan.writeEntries)
                    let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                    for (field, value) in expected {
                        XCTAssertEqual(field.localValue(from: saved), value, "\(ext) combined iTunes \(field)")
                    }
                    // Explicit independent checks for the original failing IDs.
                    XCTAssertEqual(saved.itunesAlbumID, "100")
                    XCTAssertEqual(saved.itunesArtistID, "200")
                    XCTAssertEqual(saved.itunesCatalogID, "300")
                    XCTAssertEqual(saved.year, "2004")
                } else {
                    let browser = MusicBrainzBrowserStore(client: OfflineJourneyMusicBrainzClient())
                    _ = try await browser.recordingDetail(id: "offline-recording")
                    let store = musicbrainz(file, browser: browser, recordingID: "offline-recording")
                    store.selectAllAvailableFields()
                    let plan = store.plan
                    let expected = try XCTUnwrap(plan.writeEntries.first?.values)
                    XCTAssertGreaterThan(expected.count, 15)
                    await vm.applyMusicBrainzTaggingPlan(plan.writeEntries)
                    let saved = try await pipeline.loadAudioFile(at: file.url, id: file.id)
                    for (field, value) in expected {
                        XCTAssertEqual(field.localValue(from: saved), value, "\(ext) combined MusicBrainz \(field)")
                    }
                    XCTAssertEqual(saved.itunesArtistID, "888")
                    XCTAssertEqual(saved.year, "2004")
                }
            }
        }
    }

    @MainActor
    private func viewModel(_ files: [AudioFile]) -> AudioViewModel {
        let vm = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        vm.mergeQuickImportFiles(files)
        vm.setSelectedAudioIDs(Set(files.map(\.id)))
        return vm
    }

    @MainActor
    private func loaded(_ store: MetadataEditorStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.isLoading, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.loadErrorMessage)
    }

    @MainActor
    private func itunes(_ file: AudioFile) -> iTunesTaggingWorkbenchStore {
        let track = makeiTunesTrack(title: "Remote")
        let preview = iTunesAlbumMatchPreview(totalSelectedFiles: 1, matchedAssignments: [
            .init(id: file.id.uuidString, file: makeiTunesInput(id: file.id.uuidString), track: track, score: 1, reason: "test")
        ], unmatchedFiles: [], unassignedTracks: [], overallScore: 1)
        return iTunesTaggingWorkbenchStore(detail: makeiTunesDetail(track: track), preview: preview, loadedFiles: [file])
    }

    @MainActor
    private func musicbrainz(_ file: AudioFile, browser: MusicBrainzBrowserStore? = nil, recordingID: String = "") -> MusicBrainzTaggingWorkbenchStore {
        let track = MusicBrainzReleaseMatchTrack(id: "track-id", mediumTitle: "", mediumFormat: "Digital Media",
            mediumPosition: 1, mediumTrackCount: 1, releaseMediumCount: 2, number: "1", title: "Remote",
            artistCredit: "Artist", durationMilliseconds: nil, recordingID: recordingID, isrcs: ["USABC0400001"])
        let preview = MusicBrainzReleaseMatchPreview(totalSelectedFiles: 1, matchedAssignments: [
            .init(id: file.id.uuidString, file: makeMusicBrainzInput(id: file.id.uuidString), track: track, score: 1, reason: "test")
        ], unmatchedFiles: [], unassignedTracks: [], averageTrackScore: 1, overallScore: 1, selectionLooksMixed: false)
        return MusicBrainzTaggingWorkbenchStore(release: makeMusicBrainzRelease(recordingID: recordingID), preview: preview,
            loadedFiles: [file], browserStore: browser ?? MusicBrainzBrowserStore())
    }

    @MainActor
    private func fixture(_ ext: String) async throws -> AudioFile {
        let url: URL
        if ext == "aiff" {
            url = try aiff()
        } else {
            let bundle = Bundle(for: Self.self)
            let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile", withExtension: ext, subdirectory: "Fixtures/Audio")
                ?? bundle.url(forResource: "testAudioFile", withExtension: ext))
            url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: source, to: url)
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        }
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: file)
        edit.title = "Local title"; edit.artist = "Local artist"; edit.album = "Local album"
        edit.albumArtist = "Local album artist"; edit.genre = "Local genre"; edit.comment = "Keep comment"
        edit.year = "2004"; edit.releaseDate = "2017-06-09"; edit.copyright = "Local copyright"
        edit.setTrackNumberText("7/12"); edit.setDiscNumberText("3/5")
        edit.itunesAlbumID = "777"; edit.itunesArtistID = "888"; edit.itunesCatalogID = "999"
        edit.contentAdvisory = .explicit
        _ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file), to: url, expectedVersion: file.metadataFileVersion)
        return try await pipeline.loadAudioFile(at: url, id: file.id)
    }

    @MainActor
    private func aiff() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("aiff")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true
            ])
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4410))
            buffer.frameLength = 4410
            if let samples = buffer.floatChannelData { samples[0].update(repeating: 0, count: 4410) }
            try file.write(from: buffer)
        }
        return url
    }

    @MainActor
    private func makeiTunesInput(id: String) -> iTunesFileSearchInput {
        iTunesFileSearchInput(
            id: id,
            displayTitle: "Local",
            title: "Local",
            artist: "",
            albumArtist: "",
            album: "",
            trackNumber: "",
            discNumber: "",
            trackTotal: 0,
            durationMilliseconds: nil,
            releaseDate: "",
            barcode: "",
            itunesAlbumID: "",
            itunesArtistID: "",
            itunesCatalogID: ""
        )
    }

    @MainActor
    private func makeMusicBrainzInput(id: String) -> MusicBrainzFileSearchInput {
        MusicBrainzFileSearchInput(
            id: id,
            displayTitle: "Local",
            title: "Local",
            artist: "",
            albumArtist: "",
            album: "",
            trackNumber: ""
        )
    }

    @MainActor
    private func makeiTunesTrack(
        title: String,
        trackExplicitness: String = "notExplicit",
        collectionExplicitness: String = "notExplicit"
    ) -> iTunesTrackResult {
        iTunesTrackResult(
            trackID: 300,
            collectionID: 100,
            artistID: 200,
            collectionArtistID: 201,
            trackName: title,
            artistName: "Artist",
            collectionArtistName: "Artist",
            collectionName: "Album",
            trackNumber: 1,
            trackCount: 1,
            discNumber: 1,
            discCount: 2,
            durationMilliseconds: nil,
            releaseDate: "2024-01-01",
            primaryGenreName: "Genre",
            country: "USA",
            copyright: "Remote copyright",
            contentAdvisoryRating: "",
            kind: "song",
            wrapperType: "track",
            trackExplicitness: trackExplicitness,
            collectionExplicitness: collectionExplicitness,
            trackViewURL: nil,
            collectionViewURL: nil,
            artistViewURL: nil
        )
    }

    @MainActor
    private func makeiTunesDetail(
        track: iTunesTrackResult,
        collectionExplicitness: String = "notExplicit"
    ) -> iTunesAlbumDetail {
        iTunesAlbumDetail(
            album: iTunesAlbumResult(
                collectionID: 100,
                artistID: 200,
                collectionArtistID: 201,
                collectionName: "Album",
                artistName: "Artist",
                collectionArtistName: "Artist",
                trackCount: 1,
                releaseDate: "2024-01-01",
                primaryGenreName: "Genre",
                country: "USA",
                copyright: "Remote copyright",
                contentAdvisoryRating: "",
                collectionExplicitness: collectionExplicitness,
                collectionViewURL: nil,
                artistViewURL: nil,
                selectionMatchPreview: nil,
                selectionMatchScore: nil
            ),
            tracks: [track],
            selectionMatchPreview: nil
        )
    }

    @MainActor
    private func makeMusicBrainzRelease(
        id: String = "release-id",
        title: String = "Album",
        date: String = "2024-01-01",
        trackID: String = "track-id",
        trackNumber: String = "1",
        recordingID: String = ""
    ) -> MusicBrainzReleaseDetail {
        MusicBrainzReleaseDetail(
            id: id,
            title: title,
            artistCredit: "Artist",
            date: date,
            country: "US",
            status: "Official",
            barcode: "0012345678905",
            packaging: "",
            asin: "",
            quality: "",
            language: "eng",
            script: "",
            annotation: "",
            genres: [.init(name: "Rock", count: 1)],
            tags: [],
            releaseGroupTitle: "Album",
            releaseGroupID: "release-group-id",
            releaseGroupPrimaryType: "Album",
            releaseGroupSecondaryTypes: [],
            labels: [.init(id: "label", labelName: "Publisher", catalogNumber: "CAT-001")],
            media: [
                MusicBrainzReleaseDetail.Medium(
                    id: "medium-id",
                    title: "",
                    format: "Digital Media",
                    trackCount: 1,
                    discIDs: [],
                    tracks: [
                        MusicBrainzReleaseDetail.Medium.Track(
                            id: trackID,
                            number: trackNumber,
                            title: "Remote",
                            artistCredit: "Artist",
                            durationMilliseconds: nil,
                            recordingID: recordingID,
                            isrcs: ["USABC0400001"]
                        )
                    ]
                ),
                .init(id: "medium-2", title: "", format: "Digital Media", trackCount: 0, discIDs: [], tracks: [])
            ],
            selectionMatchPreview: nil
        )
    }

}

/// Only provider transport is stubbed; planning and every disk write remain real.
private actor OfflineJourneyMusicBrainzClient: MusicBrainzBrowserClient {
    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        throw CancellationError() // A save test must never search.
    }
    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail { throw CancellationError() }
    func recordingDetail(id: String, fallbackReleases: [MusicBrainzRecordingResult.Release]) async throws -> MusicBrainzRecordingDetail {
        .init(id: id, title: "Recording", artistCredit: "Artist", disambiguation: "", firstReleaseDate: "",
              durationMilliseconds: nil, annotation: "", isrcs: [], genres: [], tags: [], rating: nil,
              releases: [], relationshipGroups: [
                .init(title: "composer", values: ["Remote composer"]),
                .init(title: "lyricist", values: ["Remote lyricist"]),
                .init(title: "producer", values: ["Remote producer"]),
                .init(title: "engineer", values: ["Remote engineer"]),
                .init(title: "remixer", values: ["Remote remixer"]),
                .init(title: "phonographic copyright (℗) by", values: ["Remote copyright"])
              ])
    }
}
