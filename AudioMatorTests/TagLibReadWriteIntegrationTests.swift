import XCTest
import TagLibAudioMetadata
@testable import AudioMator

final class TagLibReadWriteIntegrationTests: XCTestCase {
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
        "testAudioFile.flac": ("07", "2", true),
        "testAudioFile.aac": ("07", "2", true),
        "testAudioFile.ogg": ("07", "2", true),
        "testAudioFile.wav": ("07", "2", true)
    ]

    func testAudioFixturesAreReadableByTagLib() throws {
        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            XCTAssertTrue(
                TagLibMetadataManager.isReadableFormat(fixtureURL.pathExtension),
                "\(fixtureName) should be reported as readable."
            )

            let metadata = try TagLibMetadataManager.readMetadataResult(from: fixtureURL)
            XCTAssertGreaterThan(metadata.duration, 0, "\(fixtureName) should expose duration.")
            XCTAssertGreaterThan(metadata.sampleRate, 0, "\(fixtureName) should expose sample rate.")
            XCTAssertGreaterThan(metadata.channels, 0, "\(fixtureName) should expose channel count.")
        }
    }

    func testCoreMetadataRoundTripsForWritableAudioFixtures() throws {
        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }

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
                failurePolicy: .warn
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
    }

    func testTrackAndDiscTextWritesRoundTripNumericValuesAcrossWritableAudioFixtures() throws {
        let pipeline = TagLibAudioMetadataPipeline()

        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }

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
    }

    func testEraseAllMetadataClearsCommonFieldsAcrossWritableAudioFixtures() throws {
        let pipeline = TagLibAudioMetadataPipeline()

        for fixtureName in Self.audioFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }

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
            XCTAssertEqual(erased.track, 0, fixtureName)
            XCTAssertEqual(erased.trackTotal, 0, fixtureName)
            XCTAssertEqual(erased.disc, 0, fixtureName)
            XCTAssertEqual(erased.discTotal, 0, fixtureName)

            let rawMap = try pipeline.rawMetadataPropertyMap(for: workingURL)
            for key in ["TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "TRACKNUMBER", "TRACKTOTAL", "DISCNUMBER", "DISCTOTAL"] {
                XCTAssertNil(rawMap[key], "\(fixtureName) should clear \(key)")
            }
        }
    }

    func testArtworkCanBeWrittenAndClearedForPrimaryFormats() throws {
        let artworkData = try Data(contentsOf: bundledArtworkFixtureURL(named: "testCover.jpg"))
        XCTAssertGreaterThan(artworkData.count, 0)

        for fixtureName in Self.artworkFixtureNames {
            let fixtureURL = try bundledAudioFixtureURL(named: fixtureName)
            guard TagLibMetadataManager.isWritableFormat(fixtureURL.pathExtension) else {
                continue
            }

            let workingURL = try makeWritableCopy(of: fixtureURL)
            defer { removeTemporaryFixtureDirectory(containing: workingURL) }

            let metadata = TagLibAudioMetadata()
            metadata.title = "Artwork Round Trip"
            metadata.artworkData = artworkData
            metadata.artworkMimeType = "image/jpeg"

            try TagLibMetadataManager.writeTagMetadata(
                metadata,
                to: workingURL,
                verification: .init(
                    expectedTrackNumber: nil,
                    expectedTrackTotal: nil,
                    expectedTrackNumberText: nil,
                    expectedDiscNumber: nil,
                    expectedDiscTotal: nil,
                    expectedDiscNumberText: nil,
                    expectedExplicitContent: nil,
                    artworkExpectation: .present,
                    customFieldKeys: []
                ),
                failurePolicy: .warn
            )

            let withArtwork = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertNotNil(withArtwork.artworkData, "\(fixtureName) should contain artwork after write.")

            let remover = TagLibAudioMetadata()
            remover.removeArtwork = true
            try TagLibMetadataManager.writeTagMetadata(
                remover,
                to: workingURL,
                verification: .init(
                    expectedTrackNumber: nil,
                    expectedTrackTotal: nil,
                    expectedTrackNumberText: nil,
                    expectedDiscNumber: nil,
                    expectedDiscTotal: nil,
                    expectedDiscNumberText: nil,
                    expectedExplicitContent: nil,
                    artworkExpectation: .absent,
                    customFieldKeys: []
                ),
                failurePolicy: .warn
            )

            let withoutArtwork = try TagLibMetadataManager.readMetadataResult(from: workingURL)
            XCTAssertNil(withoutArtwork.artworkData, "\(fixtureName) should not contain artwork after removal.")
        }
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
