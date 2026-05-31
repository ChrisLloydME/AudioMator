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
