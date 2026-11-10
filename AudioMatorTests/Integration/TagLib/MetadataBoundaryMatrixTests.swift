import XCTest
import TagLibAudioMetadata
@testable import AudioMator

/// Independent expectations: never derive sample values, keys or expected patch
/// kinds from the production registry. Enumerations are used only for coverage.
nonisolated final class MetadataBoundaryMatrixTests: XCTestCase {
    nonisolated private struct FieldCase {
        let key: MetadataFieldKey
        let path: WritableKeyPath<SingleFileEditModel, String>
        let first: String
        let second: String
        let integer: Bool
        init(_ key: MetadataFieldKey, _ path: WritableKeyPath<SingleFileEditModel, String>,
             _ first: String, _ second: String, integer: Bool = false) {
            self.key = key; self.path = path; self.first = first; self.second = second; self.integer = integer
        }
        func patch(_ value: String) -> MetadataPatchValue {
            value.isEmpty ? .remove : integer ? .integer(Int(value)!) : .text(value)
        }
    }
    @MainActor
    private var cases: [FieldCase] { [
        .init(.title, \.title, "First title", "Second title"),
        .init(.artist, \.artist, "First artist", "Second artist"),
        .init(.album, \.album, "First album", "Second album"),
        .init(.composer, \.composer, "First composer", "Second composer"),
        .init(.genre, \.genre, "First genre", "Second genre"),
        .init(.comment, \.comment, "First comment", "Second comment"),
        .init(.year, \.year, "2004", "2005"),
        .init(.standaloneDate, \.date, "2008-03-04", "2009-04-05"),
        .init(.releaseDate, \.releaseDate, "2017-06-09", "2018-07-10"),
        .init(.originalReleaseDate, \.originalReleaseDate, "1999-11-12", "2000-12-13"),
        .init(.contentGroup, \.contentGroup, "First contentGroup", "Second contentGroup"),
        .init(.grouping, \.grouping, "First grouping", "Second grouping"),
        .init(.work, \.work, "First work", "Second work"),
        .init(.albumArtist, \.albumArtist, "First albumArtist", "Second albumArtist"),
        .init(.publisher, \.publisher, "First publisher", "Second publisher"),
        .init(.isrc, \.isrc, "USABC0400001", "USABC0400002"),
        .init(.barcode, \.barcode, "0012345678905", "0012345678912"),
        .init(.itunesAlbumID, \.itunesAlbumID, "12345", "67890", integer: true),
        .init(.itunesArtistID, \.itunesArtistID, "12345", "67890", integer: true),
        .init(.itunesCatalogID, \.itunesCatalogID, "12345", "67890", integer: true),
        .init(.musicBrainzAlbumID, \.musicBrainzAlbumID, "First musicBrainzAlbumID", "Second musicBrainzAlbumID"),
        .init(.musicBrainzTrackID, \.musicBrainzTrackID, "First musicBrainzTrackID", "Second musicBrainzTrackID"),
        .init(.musicBrainzReleaseGroupID, \.musicBrainzReleaseGroupID, "First musicBrainzReleaseGroupID", "Second musicBrainzReleaseGroupID"),
        .init(.lyricist, \.lyricist, "First lyricist", "Second lyricist"),
        .init(.remixer, \.remixer, "First remixer", "Second remixer"),
        .init(.producer, \.producer, "First producer", "Second producer"),
        .init(.engineer, \.engineer, "First engineer", "Second engineer"),
        .init(.language, \.language, "eng", "fra"),
        .init(.mediaType, \.mediaType, "First mediaType", "Second mediaType"),
        .init(.releaseType, \.releaseType, "First releaseType", "Second releaseType"),
        .init(.catalogNumber, \.catalogNumber, "First catalogNumber", "Second catalogNumber"),
        .init(.releaseCountry, \.releaseCountry, "US", "GB"),
        .init(.copyright, \.copyright, "First copyright", "Second copyright"),
    ] }

    @MainActor
    func testEveryDedicatedStringHasIndependentPatchAndRemovalContract() {
        // Reflection catches new string controls without a corresponding case.
        let actual = Set(Mirror(reflecting: SingleFileEditModel()).children.compactMap {
            $0.value is String ? $0.label : nil
        }).subtracting(["trackNumberText", "discNumberText"])
        let covered = Set(cases.map { String(describing: $0.path).split(separator: ".").last.map(String.init)! })
        XCTAssertEqual(actual, covered, "Update the independent manifest for every dedicated string field")
        XCTAssertEqual(Set(cases.map(\.key)).count, cases.count)
        let file = AudioFileTestFactory.make()
        for item in cases {
            var edit = SingleFileEditModel(from: file)
            edit[keyPath: item.path] = item.first
            let payload = MetadataEditPayload(edit, comparedTo: file)
            XCTAssertEqual(TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields,
                           [item.key: item.patch(item.first)], "set \(item.key)")
            // Use a new baseline so removals must be explicit, never omissions.
            var empty = edit
            empty[keyPath: item.path] = ""
            var removal = MetadataEditPayload(empty)
            removal.changedFields = [item.key]
            removal.trackNumberTextChanged = false
            removal.discNumberTextChanged = false
            XCTAssertEqual(TagLibAudioMetadataPipeline.metadataPatchForWrite(from: removal).fields,
                           [item.key: .remove], "remove \(item.key)")
        }
    }

    @MainActor
    func testAllDedicatedStringsPersistReplaceAndRemoveOnMP4() async throws {
        let url = try fixture("m4a")
        let pipeline = TagLibAudioMetadataPipeline()
        for item in cases {
            for value in [item.first, item.second, ""] {
                let file = try await pipeline.loadAudioFile(at: url, id: UUID())
                var edit = SingleFileEditModel(from: file)
                edit[keyPath: item.path] = value
                let payload = MetadataEditPayload(edit, comparedTo: file)
                let before = try Data(contentsOf: url)
                do {
                    _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: file.metadataFileVersion)
                } catch {
                    XCTAssertEqual(try Data(contentsOf: url), before, "Rejected write changed bytes")
                    XCTFail("m4a \(item.key) value=\(value): \(error)")
                    break
                }
                let reloaded = try await pipeline.loadAudioFile(at: url, id: file.id)
                XCTAssertEqual(SingleFileEditModel(from: reloaded)[keyPath: item.path], value,
                               "m4a \(item.key) value=\(value)")
            }
        }
    }

    @MainActor
    func testCommonFieldsAcrossCommittedFormatFixtures() async throws {
        for ext in ["mp3", "m4a", "flac", "ogg", "aac", "wav"] {
            let url = try fixture(ext)
            let pipeline = TagLibAudioMetadataPipeline()
            for item in cases.filter({ [.title, .artist, .album, .comment, .itunesAlbumID,
                                        .itunesArtistID, .itunesCatalogID].contains($0.key) }) {
                for value in [item.first, item.second, ""] {
                    let file = try await pipeline.loadAudioFile(at: url, id: UUID())
                    var edit = SingleFileEditModel(from: file)
                    edit[keyPath: item.path] = value
                    _ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file),
                                                   to: url, expectedVersion: file.metadataFileVersion)
                    let reloaded = try await pipeline.loadAudioFile(at: url, id: file.id)
                    XCTAssertEqual(SingleFileEditModel(from: reloaded)[keyPath: item.path], value,
                                   "\(ext) \(item.key) value=\(value)")
                }
            }
        }
    }

    // Explicit mappings keep coverage failures separate from value assertions.
    @MainActor
    private var exchangeCases: [MetadataExchangeField: (MetadataFieldKey, String)] {
        [
            .title: (.title, cases.first { $0.key == .title }!.first),
            .artist: (.artist, cases.first { $0.key == .artist }!.first),
            .album: (.album, cases.first { $0.key == .album }!.first),
            .albumArtist: (.albumArtist, cases.first { $0.key == .albumArtist }!.first),
            .composer: (.composer, cases.first { $0.key == .composer }!.first),
            .lyricist: (.lyricist, cases.first { $0.key == .lyricist }!.first),
            .producer: (.producer, cases.first { $0.key == .producer }!.first),
            .engineer: (.engineer, cases.first { $0.key == .engineer }!.first),
            .remixer: (.remixer, cases.first { $0.key == .remixer }!.first),
            .genre: (.genre, cases.first { $0.key == .genre }!.first),
            .year: (.year, cases.first { $0.key == .year }!.first),
            .date: (.standaloneDate, cases.first { $0.key == .standaloneDate }!.first),
            .originalReleaseDate: (.originalReleaseDate, cases.first { $0.key == .originalReleaseDate }!.first),
            .trackNumber: (.track, "3"),
            .trackTotal: (.trackTotal, "12"),
            .discNumber: (.disc, "2"),
            .discTotal: (.discTotal, "4"),
            .comment: (.comment, cases.first { $0.key == .comment }!.first),
            .releaseDate: (.releaseDate, cases.first { $0.key == .releaseDate }!.first),
            .publisher: (.publisher, cases.first { $0.key == .publisher }!.first),
            .copyright: (.copyright, cases.first { $0.key == .copyright }!.first),
            .isrc: (.isrc, cases.first { $0.key == .isrc }!.first),
            .barcode: (.barcode, cases.first { $0.key == .barcode }!.first),
            .language: (.language, cases.first { $0.key == .language }!.first),
            .mediaType: (.mediaType, cases.first { $0.key == .mediaType }!.first),
            .releaseType: (.releaseType, cases.first { $0.key == .releaseType }!.first),
            .catalogNumber: (.catalogNumber, cases.first { $0.key == .catalogNumber }!.first),
            .releaseCountry: (.releaseCountry, cases.first { $0.key == .releaseCountry }!.first),
            .itunesAlbumID: (.itunesAlbumID, cases.first { $0.key == .itunesAlbumID }!.first),
            .itunesArtistID: (.itunesArtistID, cases.first { $0.key == .itunesArtistID }!.first),
            .itunesCatalogID: (.itunesCatalogID, cases.first { $0.key == .itunesCatalogID }!.first),
            .musicBrainzAlbumID: (.musicBrainzAlbumID, cases.first { $0.key == .musicBrainzAlbumID }!.first),
            .musicBrainzTrackID: (.musicBrainzTrackID, cases.first { $0.key == .musicBrainzTrackID }!.first),
            .musicBrainzReleaseGroupID: (.musicBrainzReleaseGroupID, cases.first { $0.key == .musicBrainzReleaseGroupID }!.first),
            .contentAdvisory: (.explicitContent, "1"),
        ]
    }

    @MainActor
    func testExchangeAndProviderFieldInventoriesCannotGrowWithoutCases() {
        XCTAssertEqual(Set(exchangeCases.keys), Set(MetadataExchangeField.allCases.filter(\.isWritableMetadataField)))
        let names = Set(exchangeCases.keys.map(\.placeholderName)).union(["isExplicit"])
        for field in iTunesTagWriteField.allCases { XCTAssertTrue(names.contains(field.rawValue), field.rawValue) }
        for field in MusicBrainzTagWriteField.allCases { XCTAssertTrue(names.contains(field.rawValue), field.rawValue) }
    }

    @MainActor
    func testEveryCSVFieldPlansWritesAndReloadsThroughRealAdapter() async throws {
        let url = try fixture("m4a")
        let pipeline = TagLibAudioMetadataPipeline()
        for (field, sample) in exchangeCases {
            let file = try await pipeline.loadAudioFile(at: url, id: UUID())
            let plan = MetadataExchangePlanner.makeCSVImportPlan(template: "{{\(field.placeholderName)}}",
                sourceText: "\(field.placeholderName)\n\(sample.1)", firstRowIsHeader: true,
                targetFiles: [file], clearBlankImportedValues: false)
            let entry = try XCTUnwrap(plan.writeEntries.first, "CSV \(field) \(plan.rows)")
            var edit = SingleFileEditModel(from: file)
            for (key, value) in entry.values {
                key.applyImportedValue(value, to: &edit, preservingNumberPairComponents: true)
            }
            let payload = MetadataEditPayload(edit, comparedTo: file)
            XCTAssertTrue(payload.requestedFields.contains(sample.0), "CSV \(field)")
            _ = try pipeline.writeMetadata(payload, to: url, expectedVersion: file.metadataFileVersion)
            let reloaded = try await pipeline.loadAudioFile(at: url, id: file.id)
            XCTAssertEqual(field.value(from: reloaded, index: 0, relativeBasePath: nil), sample.1, "CSV \(field)")
        }
    }

    @MainActor
    func testProviderBatchExecutesWithRealPipelineAndReloadsEveryFile() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        var files: [AudioFile] = []
        for ext in ["m4a", "flac"] {
            files.append(try await pipeline.loadAudioFile(at: fixture(ext), id: UUID()))
        }
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(files)
        viewModel.setSelectedAudioIDs(Set(files.map(\.id)))
        await viewModel.applyiTunesTaggingPlan(files.map {
            iTunesTaggingWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                values: [.title: "Provider title", .itunesAlbumID: "12345", .itunesArtistID: "67890",
                         .itunesCatalogID: "54321", .releaseDate: "2017-06-09"])
        })
        for original in files {
            let reloaded = try await pipeline.loadAudioFile(at: original.url, id: original.id)
            XCTAssertEqual(reloaded.title, "Provider title")
            XCTAssertEqual(reloaded.itunesAlbumID, "12345")
            XCTAssertEqual(reloaded.itunesArtistID, "67890")
            XCTAssertEqual(reloaded.itunesCatalogID, "54321")
            XCTAssertEqual(viewModel.files.first { $0.id == original.id }?.itunesArtistID, "67890")
        }
        await viewModel.applyMusicBrainzTaggingPlan(files.map {
            MusicBrainzTaggingWriteEntry(fileID: $0.id, fileName: $0.url.lastPathComponent,
                values: [.title: "MusicBrainz title", .musicBrainzAlbumID: "00000000-0000-0000-0000-000000000001"])
        })
        for original in files {
            let reloaded = try await pipeline.loadAudioFile(at: original.url, id: original.id)
            XCTAssertEqual(reloaded.title, "MusicBrainz title")
            XCTAssertEqual(reloaded.musicBrainzAlbumID, "00000000-0000-0000-0000-000000000001")
            XCTAssertEqual(reloaded.itunesArtistID, "67890", "Other provider IDs must survive")
        }
    }

    @MainActor
    private var containerCases: [MetadataFieldKey: ContainerFieldValue] {
        [
            .director: .text("Director"),
            .itunesAccount: .text("test@example.invalid"),
            .itunesComposerID: .integer(123),
            .itunesCountryID: .integer(143441),
            .itunesGapless: .boolean(false),
            .itunesHDVideo: .boolean(true),
            .itunesOwner: .text("Owner"),
            .showMovement: .boolean(false),
            .storeDescription: .text("Description"),
            .tvEpisode: .integer(3),
            .tvEpisodeID: .text("S01E03"),
            .tvNetwork: .text("Network"),
            .tvSeason: .integer(1),
            .tvShow: .text("Show"),
            .tvShowSort: .text("Sorted show"),
            .itunesGenreID: .integer(1),
            .itunesMediaType: .integer(1),
            .itunesPurchaseDate: .text("2017-06-09T10:00:00Z"),
        ]
    }

    @MainActor
    func testAllEditableContainerFieldsHaveIndependentTypedCases() {
        XCTAssertEqual(Set(containerCases.keys), Set(ContainerMetadataFieldCatalog.editableKeys))
        for (key, value) in containerCases {
            let file = AudioFileTestFactory.make()
            var edit = SingleFileEditModel(from: file)
            edit.containerValues[key] = value
            let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: MetadataEditPayload(edit, comparedTo: file))
            XCTAssertEqual(patch.fields, [key: value.patchValue], "\(key)")
        }
    }

    @MainActor
    func testContainerValuesPersistIncludingFalseAndRemove() async throws {
        let url = try fixture("m4a")
        let pipeline = TagLibAudioMetadataPipeline()
        for (key, value) in containerCases {
            for requested in [value, nil] {
                let file = try await pipeline.loadAudioFile(at: url, id: UUID())
                var edit = SingleFileEditModel(from: file)
                edit.containerValues[key] = requested
                _ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file), to: url,
                                               expectedVersion: file.metadataFileVersion)
                let reloaded = try await pipeline.loadAudioFile(at: url, id: file.id)
                XCTAssertEqual(reloaded.containerValues[key], requested, "MP4 \(key)")
            }
        }
    }

    @MainActor
    func testStoreIDsUseNativeMP4AtomsAndPreserveUnrelatedRawValues() async throws {
        let url = try fixture("m4a")
        let pipeline = TagLibAudioMetadataPipeline()
        let sentinel = ["A; B", "duplicate", "duplicate", "  padded  "]
        _ = try pipeline.writeRawMetadataPatch(.init(valuesToSet: ["X-MATRIX-PRESERVE": sentinel]),
                                               to: url, expectedVersion: nil)
        let file = try await pipeline.loadAudioFile(at: url, id: UUID())
        var edit = SingleFileEditModel(from: file)
        edit.itunesAlbumID = "12345"
        edit.itunesArtistID = "67890"
        edit.itunesCatalogID = "54321"
        _ = try pipeline.writeMetadata(MetadataEditPayload(edit, comparedTo: file), to: url,
                                       expectedVersion: file.metadataFileVersion)
        let snapshot = try TagLibMetadataManager.readSnapshot(from: url, includingAudioContent: true)
        for (atom, expected) in [("plID", 12345), ("atID", 67890), ("cnID", 54321)] {
            let value = snapshot.structured.mp4Atoms.first { $0.key == atom }
            XCTAssertEqual(value.flatMap { $0.first ?? Int($0.value) }, expected, atom)
        }
        XCTAssertEqual(try pipeline.rawMetadataValueMap(for: url)["X-MATRIX-PRESERVE"], sentinel)
    }

    @MainActor
    func testInspectorSingleAndMultiSaveReachDiskAndRefreshSelection() async throws {
        let pipeline = TagLibAudioMetadataPipeline()
        var files: [AudioFile] = []
        for ext in ["m4a", "flac"] {
            files.append(try await pipeline.loadAudioFile(at: fixture(ext), id: UUID()))
        }
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles(files)
        viewModel.setSelectedAudioIDs([files[0].id])
        viewModel.edit?.title = "Inspector single"
        viewModel.edit?.itunesArtistID = "67890"
        viewModel.saveInspectorEdits()
        try await waitForSave(viewModel)
        let single = try await pipeline.loadAudioFile(at: files[0].url, id: files[0].id)
        XCTAssertEqual(single.title, "Inspector single")
        XCTAssertEqual(single.itunesArtistID, "67890")
        XCTAssertEqual(viewModel.edit?.itunesArtistID, "67890")
        viewModel.setSelectedAudioIDs(Set(files.map(\.id)))
        viewModel.multiEdit?.setText("Inspector batch", for: .title)
        viewModel.saveInspectorEdits()
        try await waitForSave(viewModel)
        for file in files {
            let reloaded = try await pipeline.loadAudioFile(at: file.url, id: file.id)
            XCTAssertEqual(reloaded.title, "Inspector batch")
            XCTAssertEqual(viewModel.files.first { $0.id == file.id }?.title, "Inspector batch")
        }
        let preserved = try await pipeline.loadAudioFile(at: files[0].url, id: files[0].id)
        XCTAssertEqual(preserved.itunesArtistID, "67890")
    }

    @MainActor
    private func waitForSave(_ viewModel: AudioViewModel) async throws {
        // Save starts synchronously; never pass just because no task started.
        XCTAssertNotNil(viewModel.metadataSaveProgress)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while viewModel.metadataSaveProgress != nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(viewModel.metadataSaveProgress, "Save did not finish within five seconds")
    }

    @MainActor
    private func fixture(_ ext: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        let source = try XCTUnwrap(bundle.url(forResource: "testAudioFile", withExtension: ext, subdirectory: "Fixtures/Audio")
            ?? bundle.url(forResource: "testAudioFile", withExtension: ext))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: source, to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
