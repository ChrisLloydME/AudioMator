import AVFoundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

final class TagLibReadWriteIntegrationTests: XCTestCase {
    func testCreditsOptimizationPreservesAVFoundationValuesAcrossFixtures() async throws {
        for fixtureName in Self.audioFixtureNames {
            let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: fixtureName))
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }
            for lyricist in [nil, "Credits writer"] as [String?] {
                if let lyricist {
                    _ = try TagLibMetadataManager.applyMetadataPatch(
                        MetadataPatch(fields: [.lyricist: .text(lyricist)]), to: workingURL
                    )
                }
                let metadata = (try? await AVURLAsset(url: workingURL).load(.metadata)) ?? []
                let creditsItems = AVMetadataItem.metadataItems(
                    from: metadata, withKey: "TEXT" as (NSCopying & NSSecureCoding), keySpace: .id3
                )
                var expectedCredits = ""
                for item in creditsItems {
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        expectedCredits = value
                        break
                    }
                }
                let snapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
                let file = try await TagLibAudioMetadataPipeline().loadAudioFile(at: workingURL, id: UUID())
                XCTAssertEqual(file.credits, expectedCredits, "\(fixtureName), lyricist=\(String(describing: lyricist))")
                if workingURL.pathExtension == "mp3" || workingURL.pathExtension == "wav" {
                    XCTAssertEqual(
                        AudioFile.needsAVFoundationCreditsRead(fileExtension: workingURL.pathExtension, rawMetadata: snapshot.raw),
                        snapshot.raw.id3v2Frames.contains { $0.frameID == "TEXT" }
                    )
                }
                if ["m4a", "ogg"].contains(workingURL.pathExtension) {
                    XCTAssertFalse(AudioFile.needsAVFoundationCreditsRead(
                        fileExtension: workingURL.pathExtension, rawMetadata: snapshot.raw
                    ))
                }
                if ["flac", "aac"].contains(workingURL.pathExtension) {
                    XCTAssertTrue(AudioFile.needsAVFoundationCreditsRead(
                        fileExtension: workingURL.pathExtension, rawMetadata: snapshot.raw
                    ))
                }
            }
        }
    }

    private static let audioFixtureNames = [
        "testAudioFile.mp3",
        "testAudioFile.m4a",
        "testAudioFile.flac",
        "testAudioFile.aac",
        "testAudioFile.ogg",
        "testAudioFile.wav"
    ]

    private static let artworkFixtureNames = [
        "testAudioFile.mp3",
        "testAudioFile.m4a",
        "testAudioFile.flac"
    ]

    private static let expectedNumberTextAfterTrackTextWrite = [
        "testAudioFile.mp3": ("07/12", "2/3", false),
        "testAudioFile.m4a": ("07/12", "2/3", false),
        "testAudioFile.flac": ("07", "2", false),
        "testAudioFile.aac": ("07", "2", false),
        "testAudioFile.ogg": ("07", "2", false),
        "testAudioFile.wav": ("07/12", "2/3", false)
    ]

    func testFieldTransferBlocksTotalOnlyPairsWithoutChangingFile() async throws {
        for fixtureName in Self.audioFixtureNames {
            let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: fixtureName))
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }
            _ = try TagLibMetadataManager.applyMetadataPatch(
                MetadataPatch(numberText: MetadataNumberTextPatch(trackNumberText: "07/12", discNumberText: "02/03")),
                to: workingURL
            )
            let pipeline = TagLibAudioMetadataPipeline()
            for source in [MetadataExchangeField.trackNumber, .discNumber] {
                let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
                let before = try Data(contentsOf: workingURL)
                let plan = MetadataFieldTransferPlanner.makePlan(
                    source: source, destination: .comment, operation: .cut, targetFiles: [baseline]
                )
                XCTAssertFalse(plan.canApply, fixtureName)
                XCTAssertTrue(plan.writeEntries.isEmpty, fixtureName)
                XCTAssertEqual(plan.rows.first?.status, .parseError, fixtureName)
                XCTAssertEqual(try Data(contentsOf: workingURL), before, fixtureName)
                let readBack = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
                XCTAssertEqual(readBack.comment, baseline.comment, fixtureName)
                XCTAssertEqual(readBack.trackTotal, 12, fixtureName)
                XCTAssertEqual(readBack.discTotal, 3, fixtureName)
                XCTAssertEqual(readBack.track, 7, fixtureName)
                XCTAssertEqual(readBack.disc, 2, fixtureName)
            }
        }
    }

    func testFieldTransferTextMatchesPreviewOnDisk() async throws {
        for fixtureName in Self.audioFixtureNames {
            let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: fixtureName))
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }
            let pipeline = TagLibAudioMetadataPipeline()
            for sourceValue in ["曲名\nFirst", "Artist; Another Artist"] {
                for operation in MetadataFieldTransferOperation.allCases {
                    _ = try TagLibMetadataManager.applyMetadataPatch(
                        MetadataPatch(fields: [.title: .text(sourceValue), .comment: .text("Old destination")]),
                        to: workingURL
                    )
                    let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
                    XCTAssertEqual(baseline.title, sourceValue, fixtureName)
                    let payload = try fieldTransferPayload(from: baseline, source: .title, destination: .comment, operation: operation)
                    _ = try pipeline.writeMetadata(payload, to: workingURL, expectedVersion: baseline.metadataFileVersion)
                    let readBack = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
                    XCTAssertEqual(readBack.comment, sourceValue, fixtureName)
                    XCTAssertEqual(readBack.title, operation == .copy ? sourceValue : "", fixtureName)
                }
            }
        }
    }

    func testFieldTransferCutNumberWithoutTotalRoundTripsOrPreservesFileOnFailure() async throws {
        for fixtureName in Self.audioFixtureNames {
            let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: fixtureName))
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }
            let pipeline = TagLibAudioMetadataPipeline()
            for source in [MetadataExchangeField.trackNumber, .discNumber] {
                _ = try TagLibMetadataManager.applyMetadataPatch(
                    MetadataPatch(numberText: MetadataNumberTextPatch(trackNumberText: "7/0", discNumberText: "2/0")),
                    to: workingURL
                )
                let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
                let sourceValue = source.value(from: baseline, index: 0, relativeBasePath: nil)
                let payload = try fieldTransferPayload(from: baseline, source: source, destination: .comment, operation: .cut)
                if fixtureName == "testAudioFile.mp3" && source == .discNumber {
                    // The same untouched-track normalization defect also affects
                    // explicit zero-total track text, not only padded numbers.
                    let before = try Data(contentsOf: workingURL)
                    XCTAssertThrowsError(try pipeline.writeMetadata(payload, to: workingURL, expectedVersion: baseline.metadataFileVersion)) { error in
                        XCTAssertTrue(String(describing: error).contains("Unedited PropertyMap field TRACKNUMBER changed"))
                    }
                    XCTAssertEqual(try Data(contentsOf: workingURL), before)
                    continue
                }
                _ = try pipeline.writeMetadata(payload, to: workingURL, expectedVersion: baseline.metadataFileVersion)
                let readBack = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
                XCTAssertEqual(readBack.comment, sourceValue, fixtureName)
                XCTAssertEqual(source.value(from: readBack, index: 0, relativeBasePath: nil), "", fixtureName)
                XCTAssertEqual(readBack.track, source == .trackNumber ? 0 : 7, fixtureName)
                XCTAssertEqual(readBack.disc, source == .discNumber ? 0 : 2, fixtureName)
                XCTAssertEqual(readBack.trackTotal, 0, fixtureName)
                XCTAssertEqual(readBack.discTotal, 0, fixtureName)
            }
        }
    }

    func testFieldTransferPaddedTextAndWhitespaceOnlySourceOnDisk() async throws {
        let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: "testAudioFile.flac"))
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }
        let pipeline = TagLibAudioMetadataPipeline()
        for sourceValue in ["  曲名\nFirst  ", " \n "] {
            for operation in MetadataFieldTransferOperation.allCases {
                _ = try TagLibMetadataManager.applyRawMetadataPatch(
                    RawMetadataPatch(valuesToSet: ["TITLE": [sourceValue], "COMMENT": ["Keep destination"]]),
                    to: workingURL
                )
                let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
                let before = try Data(contentsOf: workingURL)
                let plan = MetadataFieldTransferPlanner.makePlan(
                    source: .title, destination: .comment, operation: operation, targetFiles: [baseline]
                )
                if sourceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    XCTAssertFalse(plan.canApply)
                    XCTAssertTrue(plan.writeEntries.isEmpty)
                    XCTAssertEqual(try Data(contentsOf: workingURL), before)
                    continue
                }
                XCTAssertEqual(plan.rows.first?.changes.first?.importedValue, "曲名\nFirst")
                let payload = try fieldTransferPayload(from: baseline, source: .title, destination: .comment, operation: operation)
                _ = try pipeline.writeMetadata(payload, to: workingURL, expectedVersion: baseline.metadataFileVersion)
                let readBack = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
                XCTAssertEqual(readBack.comment, "曲名\nFirst")
                XCTAssertEqual(readBack.title, operation == .cut ? "" : baseline.title)
            }
        }
    }

    func testFieldTransferNumberCombinationsRoundTripOrFailWithoutChangingFile() async throws {
        let fields: [MetadataExchangeField] = [.trackNumber, .trackTotal, .discNumber, .discTotal]
        for fixtureName in Self.audioFixtureNames {
            let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: fixtureName))
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }
            let pipeline = TagLibAudioMetadataPipeline()
            for source in fields {
                for destination in fields where source != destination {
                    for operation in MetadataFieldTransferOperation.allCases {
                        let context = "\(fixtureName): \(operation) \(source) → \(destination)"
                        _ = try TagLibMetadataManager.applyMetadataPatch(
                            MetadataPatch(numberText: MetadataNumberTextPatch(trackNumberText: "07/12", discNumberText: "02/03")),
                            to: workingURL
                        )
                        let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
                        var expected: [MetadataExchangeField: Int] = [.trackNumber: 7, .trackTotal: 12, .discNumber: 2, .discTotal: 3]
                        expected[destination] = expected[source]
                        if operation == .cut { expected[source] = 0 }
                        if (expected[.trackNumber] == 0 && expected[.trackTotal] != 0) ||
                           (expected[.discNumber] == 0 && expected[.discTotal] != 0) {
                            let plan = MetadataFieldTransferPlanner.makePlan(
                                source: source, destination: destination, operation: operation, targetFiles: [baseline]
                            )
                            XCTAssertFalse(plan.canApply, context)
                            continue
                        }
                        let payload = try fieldTransferPayload(from: baseline, source: source, destination: destination, operation: operation)
                        let before = try Data(contentsOf: workingURL)
                        // Known external-package failures: disc-only ID3 writes
                        // normalize an untouched padded track; ADTS retains totals
                        // when clearing them with number-only text. Verify rollback.
                        let expectedFailure: String? = if fixtureName == "testAudioFile.mp3" &&
                            payload.discNumberTextChanged && !payload.trackNumberTextChanged {
                            "Unedited PropertyMap field TRACKNUMBER changed"
                        } else if fixtureName == "testAudioFile.aac" && operation == .cut &&
                            (source == .trackTotal || source == .discTotal) {
                            "differs after save (expected 0, got"
                        } else {
                            nil
                        }
                        do {
                            _ = try pipeline.writeMetadata(payload, to: workingURL, expectedVersion: baseline.metadataFileVersion)
                            if let expectedFailure {
                                XCTFail("Update the documented TagLib limitation after confirming the fix: \(context): \(expectedFailure)")
                            }
                        } catch {
                            guard let expectedFailure else {
                                XCTFail("\(context): \(error)")
                                continue
                            }
                            XCTAssertTrue(String(describing: error).contains(expectedFailure), "\(context): \(error)")
                            XCTAssertEqual(try Data(contentsOf: workingURL), before, context)
                            continue
                        }
                        let readBack = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
                        XCTAssertEqual(readBack.track, expected[.trackNumber], context)
                        XCTAssertEqual(readBack.trackTotal, expected[.trackTotal], context)
                        XCTAssertEqual(readBack.disc, expected[.discNumber], context)
                        XCTAssertEqual(readBack.discTotal, expected[.discTotal], context)
                    }
                }
            }
        }
    }

    private func fieldTransferPayload(
        from file: AudioFile,
        source: MetadataExchangeField,
        destination: MetadataExchangeField,
        operation: MetadataFieldTransferOperation
    ) throws -> MetadataEditPayload {
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: source, destination: destination, operation: operation, targetFiles: [file]
        )
        let entry = try XCTUnwrap(plan.writeEntries.first)
        var edit = SingleFileEditModel(from: file)
        for field in MetadataExchangeField.allCases {
            guard let value = entry.values[field] else { continue }
            field.applyImportedValue(value, to: &edit, preservingNumberPairComponents: entry.preservingNumberPairComponents)
        }
        return MetadataEditPayload(edit, comparedTo: file)
    }

    func testFieldTransferRejectedWritesLeaveSourceAndFileIntact() async throws {
        let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: "testAudioFile.m4a"))
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }
        let pipeline = TagLibAudioMetadataPipeline()
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.title: .text("2026"), .comment: .text("Original comment")]), to: workingURL
        )
        let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
        let unsupportedPayload = try fieldTransferPayload(from: baseline, source: .title, destination: .year, operation: .cut)
        let beforeUnsupportedWrite = try Data(contentsOf: workingURL)
        XCTAssertThrowsError(try pipeline.writeMetadata(unsupportedPayload, to: workingURL, expectedVersion: baseline.metadataFileVersion))
        XCTAssertEqual(try Data(contentsOf: workingURL), beforeUnsupportedWrite)

        let stalePayload = try fieldTransferPayload(from: baseline, source: .title, destination: .comment, operation: .cut)
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.comment: .text("External change")]), to: workingURL
        )
        let beforeStaleWrite = try Data(contentsOf: workingURL)
        XCTAssertThrowsError(try pipeline.writeMetadata(stalePayload, to: workingURL, expectedVersion: baseline.metadataFileVersion))
        XCTAssertEqual(try Data(contentsOf: workingURL), beforeStaleWrite)
        let readBack = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
        XCTAssertEqual(readBack.title, "2026")
        XCTAssertEqual(readBack.comment, "External change")
    }

    func testMetadataPatchConstructionContainsOnlyChangedIntent() {
        let file = AudioFileTestFactory.make(
            title: "Old Title",
            artist: "A; B",
            album: "Untouched Album",
            trackNumberText: "07/12",
            discNumberText: "2/3",
            contentAdvisory: .clean
        )
        var edit = SingleFileEditModel(from: file)
        edit.title = "New Title"
        let payload = MetadataEditPayload(edit, comparedTo: file)
        let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload)

        XCTAssertEqual(patch.fields, [.title: .text("New Title")])
        XCTAssertNil(patch.explicitAdvisory)
        XCTAssertNil(patch.numberText)
        XCTAssertEqual(patch.artwork, .unchanged)
    }

    func testDiscOnlyInspectorPatchLeavesTrackPairUnspecified() {
        let file = AudioFileTestFactory.make(trackNumberText: "07/12", discNumberText: "1/3")
        var edit = SingleFileEditModel(from: file)
        edit.setDiscNumberFieldText("2")
        let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: MetadataEditPayload(edit, comparedTo: file))
        XCTAssertNil(patch.numberText?.trackNumberText)
        XCTAssertEqual(patch.numberText?.discNumberText, "2/3")
    }

    func testTitleOnlyInspectorWritePreservesUntouchedRawValueStructure() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.flac")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let exactUntouchedValues: RawMetadataValueMap = [
            "ARTIST": ["A", "B"],
            "GENRE": ["Rock", "Alternative"],
            "X-AUDIOMATOR-PRESERVATION": ["duplicate", "duplicate", "  padded  ", "literal;semicolon"],
        ]
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: exactUntouchedValues),
            to: workingURL
        )

        let pipeline = TagLibAudioMetadataPipeline()
        let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
        let before = try pipeline.rawMetadataValueMap(for: workingURL)
        var edit = SingleFileEditModel(from: baseline)
        edit.title = "Intent Delta Title"
        let payload = MetadataEditPayload(edit, comparedTo: baseline)
        let patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload)

        XCTAssertEqual(patch.fields, [.title: .text("Intent Delta Title")])
        XCTAssertNil(patch.explicitAdvisory)
        XCTAssertNil(patch.numberText)
        XCTAssertEqual(patch.artwork, .unchanged)

        _ = try pipeline.writeMetadata(
            payload,
            to: workingURL,
            expectedVersion: baseline.metadataFileVersion
        )
        let after = try pipeline.rawMetadataValueMap(for: workingURL)

        XCTAssertEqual(after["TITLE"], ["Intent Delta Title"], "The edited title was not written")
        for (key, values) in exactUntouchedValues {
            XCTAssertEqual(before[key], values, "Fixture setup should preserve exact values for \(key)")
            XCTAssertEqual(after[key], before[key], "Title-only save changed untouched raw values for \(key)")
        }
    }

    func testInspectorYearAndReleaseDateEditsRemainIndependentOnFLAC() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.flac")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [
                .date: .text("2020"),
                .releaseDate: .text("2020-05-31"),
            ]),
            to: workingURL
        )

        let pipeline = TagLibAudioMetadataPipeline()
        var baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
        var edit = SingleFileEditModel(from: baseline)
        edit.year = "2021"
        var payload = MetadataEditPayload(edit, comparedTo: baseline)
        var patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload)
        XCTAssertEqual(patch.fields, [.date: .text("2021")])

        _ = try pipeline.writeMetadata(payload, to: workingURL, expectedVersion: baseline.metadataFileVersion)
        var snapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
        XCTAssertEqual(snapshot.raw.properties.first { $0.key == "DATE" }?.values, ["2021"])
        XCTAssertEqual(snapshot.raw.properties.first { $0.key == "RELEASEDATE" }?.values, ["2020-05-31"])

        baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
        edit = SingleFileEditModel(from: baseline)
        edit.releaseDate = ""
        payload = MetadataEditPayload(edit, comparedTo: baseline)
        patch = TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload)
        XCTAssertEqual(patch.fields, [.releaseDate: .remove])

        _ = try pipeline.writeMetadata(payload, to: workingURL, expectedVersion: baseline.metadataFileVersion)
        snapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
        XCTAssertEqual(snapshot.raw.properties.first { $0.key == "DATE" }?.values, ["2021"])
        XCTAssertNil(snapshot.raw.properties.first { $0.key == "RELEASEDATE" })
    }

    func testInspectorYearEditIsExplicitlyUnsupportedForMP4() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.releaseDate: .text("2020-05-31")]),
            to: workingURL
        )
        let pipeline = TagLibAudioMetadataPipeline()
        let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
        var edit = SingleFileEditModel(from: baseline)
        edit.year = "2021"
        let payload = MetadataEditPayload(edit, comparedTo: baseline)
        let before = try Data(contentsOf: workingURL)

        XCTAssertThrowsError(try pipeline.writeMetadata(
            payload,
            to: workingURL,
            expectedVersion: baseline.metadataFileVersion
        )) { error in
            XCTAssertEqual(
                error as? MetadataPatchValidationError,
                .unsupportedFieldForFormat(field: .date, format: "mp4")
            )
        }
        XCTAssertEqual(try Data(contentsOf: workingURL), before)
    }

    func testAudioFileLoadingRejectsMissingSourceFile() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-Missing-Load-\(UUID().uuidString).mp3")

        do {
            _ = try await TagLibAudioMetadataPipeline().loadAudioFile(
                at: missingURL,
                id: UUID()
            )
            XCTFail("A missing source must be reported as a load failure instead of an empty metadata snapshot.")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
        }
    }

    func testAudioFixturesAreReadableByTagLib() throws {
        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            let workingURL = try makeWritableCopy(of: fixtureURL)
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }

            XCTAssertTrue(
                TagLibMetadataManager.isReadableFormat(fixtureURL.pathExtension),
                "\(fixtureName) should be reported as readable."
            )

            // Published package version 0.5.1 treats status-only changes as read
            // conflicts. A private copy prevents test-bundle metadata activity
            // from making this fixture-readability assertion intermittent.
            let metadata = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertGreaterThan(metadata.duration, 0, "\(fixtureName) should expose duration.")
            XCTAssertGreaterThan(metadata.sampleRate, 0, "\(fixtureName) should expose sample rate.")
            XCTAssertGreaterThan(metadata.channels, 0, "\(fixtureName) should expose channel count.")
        }
    }

    func testConcurrentM4AReadsRemainStable() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMator-Concurrent-M4A-Reads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let fixtureURLs = try (0..<12).map { index in
            let copyURL = temporaryDirectory.appendingPathComponent("fixture-\(index).m4a")
            try FileManager.default.copyItem(at: fixtureURL, to: copyURL)
            return copyURL
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for fixtureURL in fixtureURLs {
                group.addTask {
                    for _ in 0..<25 {
                        let metadata = try TagLibMetadataManager.readMetadataResult(from: fixtureURL)
                        guard metadata.duration > 0 else {
                            throw ConcurrentM4AReadTestError.missingDuration(fixtureURL)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    func testRawMetadataInspectionLoadsAcrossAudioFixtures() throws {
        let pipeline = TagLibAudioMetadataPipeline()

        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            let rawText = try XCTUnwrap(
                pipeline.rawMetadataDumpText(for: fixtureURL),
                "\(fixtureName) should expose a raw metadata dump."
            )

            XCTAssertTrue(rawText.contains("File: \(fixtureName)"), fixtureName)
            XCTAssertTrue(rawText.contains("[TagLib Properties]"), fixtureName)

            let bridgeText = try XCTUnwrap(TagLibMetadataManager.bestEffortRawMetadataText(from: fixtureURL))
            for sectionHeader in Self.sectionHeaders(after: "TagLib Properties", in: bridgeText) {
                XCTAssertTrue(
                    rawText.contains("[\(sectionHeader)]"),
                    "\(fixtureName) dump should preserve bridge section [\(sectionHeader)]."
                )
            }

            let rawDump = try TagLibMetadataManager.rawMetadataResult(from: fixtureURL)
            for property in rawDump.properties {
                let values = property.values.isEmpty ? [property.value] : property.values
                let value = values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "; ")

                guard !value.isEmpty else { continue }
                XCTAssertTrue(
                    rawText.contains("\(property.key) = \(value)"),
                    "\(fixtureName) dump should include TagLib property \(property.key)."
                )
            }

            XCTAssertNoThrow(
                try pipeline.rawMetadataPropertyMap(for: fixtureURL),
                "\(fixtureName) should expose a normalized raw property map, even when it is empty."
            )
        }
    }

    private static func sectionHeaders(after precedingHeader: String, in text: String) -> [String] {
        var hasSeenPrecedingHeader = false
        var headers: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { continue }

            let header = String(trimmed.dropFirst().dropLast())
            if hasSeenPrecedingHeader {
                headers.append(header)
            } else if header == precedingHeader {
                hasSeenPrecedingHeader = true
            }
        }

        return headers
    }

    func testCoreMetadataRoundTripsForWritableAudioFixtures() throws {
        var executedFixtureCount = 0
        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }
            executedFixtureCount += 1

            let workingURL = try makeWritableCopy(of: fixtureURL)
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }

            var metadata = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            metadata.title = "AudioMator Integration Title"
            metadata.artist = "AudioMator Integration Artist"
            metadata.album = "AudioMator Integration Album"
            metadata.albumArtist = "AudioMator Integration Album Artist"
            metadata.genre = "Integration Test"
            metadata.comment = "Written by AudioMator XCTest"
            metadata.track = 7
            metadata.trackTotal = 12
            metadata.disc = 2
            metadata.discTotal = 3
            metadata.trackNumberText = "7/12"
            metadata.discNumberText = "2/3"
            metadata.year = "2026"
            metadata.releaseDate = "2026-05-13"

            try TagLibMetadataManager.writeMetadataWithVerification(
                metadata,
                to: workingURL,
                failurePolicy: .throw
            )

            let readBack = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertEqual(readBack.title, metadata.title, fixtureName)
            XCTAssertEqual(readBack.artist, metadata.artist, fixtureName)
            XCTAssertEqual(readBack.album, metadata.album, fixtureName)
            XCTAssertEqual(readBack.track, metadata.track, fixtureName)
            XCTAssertEqual(readBack.trackTotal, metadata.trackTotal, fixtureName)
            XCTAssertEqual(readBack.disc, metadata.disc, fixtureName)
            XCTAssertEqual(readBack.discTotal, metadata.discTotal, fixtureName)
        }
        XCTAssertGreaterThan(executedFixtureCount, 0, "No writable fixtures were exercised")
    }

    func testTrackAndDiscTextWritesRoundTripNumericValuesAcrossWritableAudioFixtures() throws {
        let pipeline = TagLibAudioMetadataPipeline()
        var executedFixtureCount = 0

        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }
            executedFixtureCount += 1

            let workingURL = try makeWritableCopy(of: fixtureURL)
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }

            let result = try pipeline.writeTrackNumberText(
                "07/12",
                discNumberText: "2/3",
                to: workingURL,
                verifyAfterWrite: true
            )

            XCTAssertFalse(
                result.warnings.contains { $0.contains("differs after save") },
                "\(fixtureName) should not report numeric write mismatches: \(result.warnings.joined(separator: "\n"))"
            )

            let readBack = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertEqual(readBack.track, 7, fixtureName)
            XCTAssertEqual(readBack.trackTotal, 12, fixtureName)
            XCTAssertEqual(readBack.disc, 2, fixtureName)
            XCTAssertEqual(readBack.discTotal, 3, fixtureName)

            let expected = try XCTUnwrap(Self.expectedNumberTextAfterTrackTextWrite[fixtureName])
            XCTAssertEqual(readBack.trackNumberText, expected.0, fixtureName)
            XCTAssertEqual(readBack.discNumberText, expected.1, fixtureName)
            XCTAssertEqual(
                AudioTagNumberPair(
                    rawText: readBack.trackNumberText,
                    number: readBack.track,
                    total: readBack.trackTotal
                ).displayedTotalText,
                "12",
                "\(fixtureName) should preserve the user-facing track total even when container text is normalized."
            )
            XCTAssertEqual(
                AudioTagNumberPair(
                    rawText: readBack.discNumberText,
                    number: readBack.disc,
                    total: readBack.discTotal
                ).displayedTotalText,
                "3",
                "\(fixtureName) should preserve the user-facing disc total even when container text is normalized."
            )

            let didNormalizeFormatting = result.warnings.contains {
                $0.contains("formatting was normalized by the container")
            }
            XCTAssertEqual(didNormalizeFormatting, expected.2, fixtureName)
        }
        XCTAssertGreaterThan(executedFixtureCount, 0, "No writable fixtures were exercised")
    }

    func testTrackNumberOnlyWriteDoesNotWarnWhenExistingTotalIsPreserved() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.mp3")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()

        _ = try pipeline.writeTrackNumberText(
            "01/12",
            discNumberText: nil,
            to: workingURL,
            verifyAfterWrite: true
        )

        let result = try pipeline.writeTrackNumberText(
            "07",
            discNumberText: nil,
            to: workingURL,
            verifyAfterWrite: true
        )

        XCTAssertFalse(
            result.warnings.contains { $0.contains("Track number") },
            result.warnings.joined(separator: "\n")
        )

        let readBack = try TagLibMetadataManager.readMetadataResult(from: workingURL)
        XCTAssertEqual(readBack.track, 7)
        XCTAssertEqual(readBack.trackTotal, 12)
    }

    func testEraseAllMetadataClearsCommonFieldsAcrossWritableAudioFixtures() throws {
        let pipeline = TagLibAudioMetadataPipeline()
        var executedFixtureCount = 0

        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }
            executedFixtureCount += 1

            let workingURL = try makeWritableCopy(of: fixtureURL)
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }

            var edit = SingleFileEditModel()
            edit.title = "Title To Erase"
            edit.artist = "Artist To Erase"
            edit.album = "Album To Erase"
            edit.albumArtist = "Album Artist To Erase"
            edit.composer = "Composer To Erase"
            edit.genre = "Genre To Erase"
            edit.comment = "Comment To Erase"
            edit.releaseDate = "2026-06-19"
            edit.publisher = "Label To Erase"
            edit.isrc = "USRC17607839"
            edit.barcode = "123456789012"
            edit.setTrackNumberFieldText("7")
            edit.setTrackTotalFieldText("12")
            edit.setDiscNumberFieldText("2")
            edit.setDiscTotalFieldText("3")

            _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)
            let written = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertEqual(written.title, "Title To Erase", fixtureName)
            XCTAssertEqual(written.artist, "Artist To Erase", fixtureName)
            XCTAssertEqual(written.album, "Album To Erase", fixtureName)
            XCTAssertEqual(written.albumArtist, "Album Artist To Erase", fixtureName)
            XCTAssertEqual(written.composer, "Composer To Erase", fixtureName)
            XCTAssertEqual(written.genre, "Genre To Erase", fixtureName)
            XCTAssertEqual(written.comment, "Comment To Erase", fixtureName)
            XCTAssertEqual(written.releaseDate, "2026-06-19", fixtureName)
            XCTAssertEqual(written.publisher, "Label To Erase", fixtureName)
            XCTAssertEqual(written.isrc, "USRC17607839", fixtureName)
            XCTAssertEqual(written.barcode, "123456789012", fixtureName)
            XCTAssertEqual(written.track, 7, fixtureName)
            XCTAssertEqual(written.trackTotal, 12, fixtureName)
            XCTAssertEqual(written.disc, 2, fixtureName)
            XCTAssertEqual(written.discTotal, 3, fixtureName)

            let eraseWarnings = try pipeline.eraseAllMetadata(at: workingURL).warnings
            XCTAssertFalse(
                eraseWarnings.contains { $0.contains("Title To Erase") || $0.contains("Track") },
                "\(fixtureName) should not report common-field erase mismatches: \(eraseWarnings.joined(separator: "\n"))"
            )

            let erased = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertTrue(erased.title.isEmpty, fixtureName)
            XCTAssertTrue(erased.artist.isEmpty, fixtureName)
            XCTAssertTrue(erased.album.isEmpty, fixtureName)
            XCTAssertTrue(erased.albumArtist.isEmpty, fixtureName)
            XCTAssertTrue(erased.genre.isEmpty, fixtureName)
            XCTAssertTrue(erased.comment.isEmpty, fixtureName)
            XCTAssertEqual(erased.composer, "", fixtureName)
            XCTAssertEqual(erased.releaseDate, "", fixtureName)
            XCTAssertEqual(erased.publisher, "", fixtureName)
            XCTAssertEqual(erased.isrc, "", fixtureName)
            XCTAssertEqual(erased.barcode, "", fixtureName)
            XCTAssertEqual(erased.track, 0, fixtureName)
            XCTAssertEqual(erased.trackTotal, 0, fixtureName)
            XCTAssertEqual(erased.disc, 0, fixtureName)
            XCTAssertEqual(erased.discTotal, 0, fixtureName)

            let rawMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
            for key in [
                "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "COMPOSER", "GENRE", "COMMENT",
                "RELEASEDATE", "LABEL", "PUBLISHER", "ISRC", "BARCODE", "UPC", "EAN",
                "TRACKNUMBER", "TRACKTOTAL", "DISCNUMBER", "DISCTOTAL"
            ] {
                XCTAssertNil(rawMap[key], "\(fixtureName) should clear \(key)")
            }
        }
        XCTAssertGreaterThan(executedFixtureCount, 0, "No writable fixtures were exercised")
    }

    func testInspectorArtworkIntentRoundTripsOnDisk() async throws {
        let artworkData = try Data(contentsOf: bundledArtworkFixtureURL(named: "testCover.jpg"))
        for fixtureName in Self.artworkFixtureNames {
            let workingURL = try makeWritableCopy(of: bundledAudioFixtureURL(named: fixtureName))
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }

            let pipeline = TagLibAudioMetadataPipeline()
            let baseline = try await pipeline.loadAudioFile(at: workingURL, id: UUID())
            var edit = SingleFileEditModel(from: baseline)
            edit.artworkEditAction = .replace(
                PendingArtwork(data: artworkData, mimeType: "image/jpeg")
            )
            _ = try pipeline.writeMetadata(
                MetadataEditPayload(edit, comparedTo: baseline),
                to: workingURL,
                expectedVersion: baseline.metadataFileVersion
            )

            let withArtwork = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
            XCTAssertNotNil(withArtwork.artworkData, fixtureName)
            XCTAssertEqual(withArtwork.artworkData, artworkData, "Artwork bytes should round-trip for \(fixtureName)")

            edit = SingleFileEditModel(from: withArtwork)
            edit.artworkEditAction = .remove
            _ = try pipeline.writeMetadata(
                MetadataEditPayload(edit, comparedTo: withArtwork),
                to: workingURL,
                expectedVersion: withArtwork.metadataFileVersion
            )
            let withoutArtwork = try await pipeline.loadAudioFile(at: workingURL, id: baseline.id)
            XCTAssertNil(withoutArtwork.artworkData, fixtureName)
        }
    }

    func testArtworkCanBeWrittenAndClearedForPrimaryFormats() throws {
        let artworkData = try Data(contentsOf: bundledArtworkFixtureURL(named: "testCover.jpg"))
        XCTAssertGreaterThan(artworkData.count, 0)

        var executedFixtureCount = 0
        for fixtureName in Self.artworkFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }
            executedFixtureCount += 1

            let workingURL = try makeWritableCopy(of: fixtureURL)
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }

            _ = try TagLibMetadataManager.applyMetadataPatch(
                MetadataPatch(
                    fields: [.title: .text("Artwork Round Trip")],
                    artwork: .replace([StructuredArtwork(mimeType: "image/jpeg", data: artworkData)])
                ),
                to: workingURL,
                failurePolicy: .throw
            )

            let withArtwork = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertNotNil(withArtwork.artworkData, "\(fixtureName) should contain artwork after write.")

            _ = try TagLibMetadataManager.applyMetadataPatch(
                MetadataPatch(artwork: .removeAll),
                to: workingURL,
                failurePolicy: .throw
            )

            let withoutArtwork = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertNil(withoutArtwork.artworkData, "\(fixtureName) should not contain artwork after removal.")
        }
        XCTAssertGreaterThan(executedFixtureCount, 0, "No writable artwork fixtures were exercised")
    }

    func testRawPropertyMapWriteRemovesDeletedMP4FreeformFields() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var propertyMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
        propertyMap["TITLE"] = "Raw Delete Regression"
        propertyMap["ITUNSMPB"] = "00000000 00000840 00000210 00000000003F5AB0 00000000 0003A5E0 00000000 00000000 00000000 00000000 00000000 00000000"

        let writeWarnings = try pipeline.writeRawMetadataPropertyMap(propertyMap, to: workingURL).warnings
        XCTAssertFalse(writeWarnings.contains { $0.contains("ITUNSMPB") }, writeWarnings.joined(separator: "\n"))
        XCTAssertEqual(try pipeline.rawMetadataPropertyMap(for: workingURL)["ITUNSMPB"], propertyMap["ITUNSMPB"])

        propertyMap.removeValue(forKey: "ITUNSMPB")

        let removalWarnings = try pipeline.writeRawMetadataPropertyMap(propertyMap, to: workingURL).warnings
        XCTAssertFalse(removalWarnings.contains { $0.contains("ITUNSMPB") }, removalWarnings.joined(separator: "\n"))
        XCTAssertNil(try pipeline.rawMetadataPropertyMap(for: workingURL)["ITUNSMPB"])
    }

    func testLosslessRawValueMapPreservesArraysDuplicatesWhitespaceAndLiteralSemicolons() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.flac")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let exactValues = ["A; B", "duplicate", "duplicate", "  spaced  "]
        _ = try TagLibMetadataManager.applyRawMetadataPatch(
            RawMetadataPatch(valuesToSet: ["X-AUDIOMATOR-ROUNDTRIP": exactValues]),
            to: workingURL
        )

        let pipeline = TagLibAudioMetadataPipeline()
        var valueMap = try pipeline.rawMetadataValueMap(for: workingURL)
        XCTAssertEqual(valueMap["X-AUDIOMATOR-ROUNDTRIP"], exactValues)

        let expectedVersion = try TagLibMetadataManager.readSnapshot(from: workingURL).fileVersion
        valueMap["LYRICS"] = ["[00:01.00] one; two"]
        _ = try pipeline.writeRawMetadataValueMap(
            valueMap,
            to: workingURL,
            expectedVersion: expectedVersion
        )

        let readBack = try pipeline.rawMetadataValueMap(for: workingURL)
        XCTAssertEqual(readBack["X-AUDIOMATOR-ROUNDTRIP"], exactValues)
        XCTAssertEqual(readBack["LYRICS"], ["[00:01.00] one; two"])
    }

    func testInspectorSaveRejectsSnapshotVersionThatPredatesExternalMetadataEdit() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.flac")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let staleSnapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
        _ = try TagLibMetadataManager.applyMetadataPatch(
            MetadataPatch(fields: [.title: .text("External Edit")]),
            to: workingURL
        )

        var edit = SingleFileEditModel()
        edit.title = "Stale Inspector Edit"
        XCTAssertThrowsError(
            try TagLibAudioMetadataPipeline().writeMetadata(
                MetadataEditPayload(edit),
                to: workingURL,
                expectedVersion: staleSnapshot.fileVersion
            )
        ) { error in
            guard case TagLibManagerError.fileChanged = error else {
                return XCTFail("Expected a package version conflict, got \(error)")
            }
        }
        XCTAssertEqual(try TagLibMetadataManager.readMetadataResult(from: workingURL).title, "External Edit")
    }

    func testRawPropertyMapWriteRemovesTrackTotalWithoutDroppingTrackNumber() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var propertyMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
        propertyMap["TRACKNUMBER"] = "7"
        propertyMap["TRACKTOTAL"] = "12"

        let writeWarnings = try pipeline.writeRawMetadataPropertyMap(propertyMap, to: workingURL).warnings
        XCTAssertFalse(writeWarnings.contains { $0.contains("TRACKTOTAL") || $0.contains("TOTALTRACKS") }, writeWarnings.joined(separator: "\n"))
        var readBack = try pipeline.rawMetadataPropertyMap(for: workingURL)
        XCTAssertEqual(readBack["TRACKNUMBER"], "7")
        XCTAssertEqual(readBack["TRACKTOTAL"], "12")

        propertyMap.removeValue(forKey: "TRACKTOTAL")

        let removalWarnings = try pipeline.writeRawMetadataPropertyMap(propertyMap, to: workingURL).warnings
        XCTAssertFalse(removalWarnings.contains { $0.contains("TRACKTOTAL") || $0.contains("TOTALTRACKS") }, removalWarnings.joined(separator: "\n"))
        readBack = try pipeline.rawMetadataPropertyMap(for: workingURL)
        XCTAssertEqual(readBack["TRACKNUMBER"], "7")
        XCTAssertNil(readBack["TRACKTOTAL"])
        XCTAssertNil(readBack["TOTALTRACKS"])
    }

    func testInspectorStyleMetadataWriteClearsTrackTotalWithoutDroppingTrackNumber() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var edit = SingleFileEditModel()
        edit.setTrackNumberFieldText("7")
        edit.setTrackTotalFieldText("12")

        _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)
        var readBack = try TagLibMetadataManager.readMetadataResult(from: workingURL)
        XCTAssertEqual(readBack.track, 7)
        XCTAssertEqual(readBack.trackTotal, 12)

        edit.setTrackTotalFieldText("")

        _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)
        readBack = try TagLibMetadataManager.readMetadataResult(from: workingURL)
        XCTAssertEqual(readBack.track, 7)
        XCTAssertEqual(readBack.trackTotal, 0)
        XCTAssertEqual(readBack.trackNumberText, "7")
    }

    func testInspectorStyleAdvisoryWriteDoesNotReplaceTheWholePropertyMap() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var edit = SingleFileEditModel()
        edit.title = "Advisory Regression Title"
        edit.artist = "Advisory Regression Artist"
        edit.album = "Advisory Regression Album"
        edit.albumArtist = "Advisory Regression Album Artist"
        edit.genre = "Regression"
        edit.comment = "Advisory should not erase sibling metadata"
        edit.contentAdvisory = .clean

        let warnings = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL).warnings
        XCTAssertFalse(warnings.contains { $0.contains("Could not write iTunes advisory") }, warnings.joined(separator: "\n"))

        let readBack = try TagLibMetadataManager.readMetadataResult(from: workingURL)
        XCTAssertEqual(readBack.title, edit.title)
        XCTAssertEqual(readBack.artist, edit.artist)
        XCTAssertEqual(readBack.album, edit.album)
        XCTAssertEqual(readBack.albumArtist, edit.albumArtist)
        XCTAssertEqual(readBack.genre, edit.genre)
        XCTAssertEqual(readBack.comment, edit.comment)

        let snapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
        XCTAssertEqual(snapshot.basic.explicitAdvisory, .clean)
        let rawMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
        XCTAssertEqual(rawMap["TITLE"], edit.title)
        XCTAssertEqual(rawMap["ARTIST"], edit.artist)
        XCTAssertEqual(rawMap["ALBUM"], edit.album)
    }

    func testInspectorStyleExplicitAdvisoryWritesiTunesExplicitValue() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var edit = SingleFileEditModel()
        edit.title = "Explicit Advisory Value"
        edit.contentAdvisory = .explicit

        _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)

        let snapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
        XCTAssertEqual(snapshot.basic.explicitAdvisory, .explicit)
    }

    func testInspectorStyleNotExplicitAdvisoryDoesNotBecomeExplicitAfterSave() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var edit = SingleFileEditModel()
        edit.title = "Not Explicit Advisory Value"
        edit.contentAdvisory = .notExplicit

        _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)

        let snapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
        XCTAssertEqual(snapshot.basic.explicitAdvisory, .notExplicit)

        let reloaded = try await AudioFile(url: workingURL)
        XCTAssertEqual(reloaded.contentAdvisory, .notExplicit)
        XCTAssertFalse(reloaded.isExplicit)
    }

    func testInspectorStyleUnsetAdvisoryClearsAnExistingAdvisory() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var edit = SingleFileEditModel()
        edit.title = "Advisory Clear Value"
        edit.contentAdvisory = .explicit

        _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)
        XCTAssertEqual(
            try TagLibMetadataManager.readSnapshot(from: workingURL).basic.explicitAdvisory,
            .explicit
        )

        edit.contentAdvisory = nil
        _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)

        let snapshot = try TagLibMetadataManager.readSnapshot(from: workingURL)
        XCTAssertEqual(snapshot.basic.explicitAdvisory, .unspecified)
        let rawMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
        XCTAssertNil(rawMap["ITUNESADVISORY"], "Clearing the advisory must remove the stored value")

        let reloaded = try await AudioFile(url: workingURL)
        XCTAssertNil(reloaded.contentAdvisory)
        XCTAssertFalse(reloaded.isExplicit)
    }

    func testAudioFileReadsiTunesExplicitAdvisoryValue() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        _ = try TagLibMetadataManager.writeRawMetadataPropertyMapWithVerification(
            ["ITUNESADVISORY": "1"],
            to: workingURL,
            mode: .merge,
            verifyAfterWrite: false
        )

        let file = try await AudioFile(url: workingURL)
        XCTAssertEqual(file.contentAdvisory, .explicit)
        XCTAssertTrue(file.isExplicit)

        let model = SingleFileEditModel(from: file)
        XCTAssertEqual(model.contentAdvisory, .explicit)
        XCTAssertTrue(model.isExplicit)

        XCTAssertEqual(try pipeline.rawMetadataPropertyMap(for: workingURL)["ITUNESADVISORY"], "1")
    }

    func testAudioFileIgnoresNonAdvisoryRawValuesWhenReadingContentAdvisory() async throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        _ = try TagLibMetadataManager.writeRawMetadataPropertyMapWithVerification(
            [
                "COMPILATION": "1",
                "DISCNUMBER": "1",
                "TRACKNUMBER": "4"
            ],
            to: workingURL,
            mode: .merge,
            verifyAfterWrite: false
        )

        let rawMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
        XCTAssertEqual(rawMap["COMPILATION"], "1")
        XCTAssertNil(rawMap["ITUNESADVISORY"])

        let file = try await AudioFile(url: workingURL)
        XCTAssertNil(file.contentAdvisory)
        XCTAssertFalse(file.isExplicit)
    }

    func testInspectorStyleMetadataWriteClearsEditableTextFields() throws {
        let fixtureURL = try bundledAudioFixtureURL(named: "testAudioFile.m4a")
        let workingURL = try makeWritableCopy(of: fixtureURL)
        defer { removeTemporaryFixtureDirectory(containing: workingURL) }

        let pipeline = TagLibAudioMetadataPipeline()
        var edit = SingleFileEditModel()
        edit.title = "Title To Clear"
        edit.artist = "Artist To Clear"
        edit.album = "Album To Clear"
        edit.composer = "Composer To Clear"
        edit.genre = "Genre To Clear"
        edit.comment = "Comment To Clear"
        edit.albumArtist = "Album Artist To Clear"
        edit.releaseDate = "2026-05-31"
        edit.publisher = "Label To Clear"
        edit.copyright = "Copyright To Clear"
        edit.isrc = "USRC17607839"
        edit.barcode = "123456789012"

        _ = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL)
        let written = try TagLibMetadataManager.readMetadataResult(from: workingURL)
        XCTAssertEqual(written.title, "Title To Clear")
        XCTAssertEqual(written.artist, "Artist To Clear")
        XCTAssertEqual(written.album, "Album To Clear")
        XCTAssertEqual(written.composer, "Composer To Clear")
        XCTAssertEqual(written.genre, "Genre To Clear")
        XCTAssertEqual(written.comment, "Comment To Clear")
        XCTAssertEqual(written.albumArtist, "Album Artist To Clear")
        XCTAssertEqual(written.releaseDate, "2026-05-31")
        XCTAssertEqual(written.publisher, "Label To Clear")
        XCTAssertEqual(written.copyright, "Copyright To Clear")
        XCTAssertEqual(written.isrc, "USRC17607839")
        XCTAssertEqual(written.barcode, "123456789012")
        var rawMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
        XCTAssertEqual(rawMap["TITLE"], "Title To Clear")
        XCTAssertEqual(rawMap["ARTIST"], "Artist To Clear")
        XCTAssertEqual(rawMap["ALBUM"], "Album To Clear")

        edit.title = ""
        edit.artist = ""
        edit.album = ""
        edit.composer = ""
        edit.genre = ""
        edit.comment = ""
        edit.albumArtist = ""
        edit.releaseDate = ""
        edit.publisher = ""
        edit.copyright = ""
        edit.isrc = ""
        edit.barcode = ""

        let warnings = try pipeline.writeMetadata(MetadataEditPayload(edit), to: workingURL).warnings
        XCTAssertFalse(warnings.contains { $0.contains("expected to be removed") }, warnings.joined(separator: "\n"))

        rawMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
        for key in [
            "TITLE", "ARTIST", "ARTISTS", "ALBUM", "COMPOSER", "GENRE", "COMMENT",
            "ALBUMARTIST", "ALBUM ARTIST", "RELEASEDATE", "DATE", "LABEL", "PUBLISHER",
            "COPYRIGHT", "ISRC", "BARCODE", "UPC", "EAN"
        ] {
            XCTAssertNil(rawMap[key], "\(key) should be cleared")
        }
    }

    private func bundledAudioFixtureURL(named fileName: String) throws -> URL {
        try bundledFixtureURL(named: fileName, preferredSubdirectory: "Fixtures/Audio")
    }

    private func bundledArtworkFixtureURL(named fileName: String) throws -> URL {
        try bundledFixtureURL(named: fileName, preferredSubdirectory: "Fixtures/Artwork")
    }

    private func bundledFixtureURL(named fileName: String, preferredSubdirectory: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        if let nestedURL = bundle.url(
            forResource: fileName,
            withExtension: nil,
            subdirectory: preferredSubdirectory
        ) {
            return nestedURL
        }

        return try XCTUnwrap(
            bundle.url(forResource: fileName, withExtension: nil),
            "Missing bundled fixture: \(fileName)"
        )
    }

    private func makeWritableCopy(of fixtureURL: URL) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorTagLibIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let workingURL = directoryURL.appendingPathComponent(fixtureURL.lastPathComponent, isDirectory: false)
        try FileManager.default.copyItem(at: fixtureURL, to: workingURL)
        return workingURL
    }

    private func removeTemporaryFixtureDirectory(containing workingURL: URL) {
        try? FileManager.default.removeItem(at: workingURL.deletingLastPathComponent())
    }
}

private enum ConcurrentM4AReadTestError: Error {
    case missingDuration(URL)
}
