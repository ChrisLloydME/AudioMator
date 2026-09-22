import XCTest
@testable import AudioMator

final class MetadataExchangeFixtureTests: XCTestCase {
    private static let textImportFixtureSubdirectory = "Fixtures/MetadataExchange/TextImport"
    private static let audioFixtureSubdirectory = "Fixtures/MetadataExchange/Audio"

    func testPipeDelimitedFixtureParsesToExpectedMetadata() throws {
        let expected = try loadExpectedRecords()
        let actual = try parseCSVFixture(
            named: "txt2metadata_pipe.txt",
            delimiter: "|",
            expectedRecords: expected
        )

        XCTAssertEqual(actual, expected)
    }

    func testTabDelimitedFixtureParsesToExpectedMetadata() throws {
        let expected = try loadExpectedRecords()
        let actual = try parseCSVFixture(
            named: "txt2metadata_tab.txt",
            delimiter: "\t",
            expectedRecords: expected
        )

        XCTAssertEqual(actual, expected)
    }

    func testCommaCSVFixtureParsesToExpectedMetadataIncludingEscapedQuotes() throws {
        let expected = try loadExpectedRecords()
        let actual = try parseCSVFixture(
            named: "txt2metadata_csv_comma.csv",
            delimiter: ",",
            expectedRecords: expected
        )

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.last?.title, "Room 404: \"Do Not Wake\"")
    }

    func testSemicolonCSVFixtureParsesToExpectedMetadataWithEmbeddedCommasAndSemicolons() throws {
        let expected = try loadExpectedRecords()
        let actual = try parseCSVFixture(
            named: "txt2metadata_csv_semicolon.csv",
            delimiter: ";",
            expectedRecords: expected
        )

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.first?.title, "Glass Garden (Live at North Pier, 2024)")
        XCTAssertEqual(actual.first?.comment, "Live performance; crowd noise retained.")
        XCTAssertEqual(actual[5].title, "Velvet, Thunder; Rain")
    }

    func testAllTextImportFixturesProduceSameNormalizedMetadata() throws {
        let expected = try loadExpectedRecords()
        let fixtures: [(name: String, delimiter: Character)] = [
            ("txt2metadata_pipe.txt", "|"),
            ("txt2metadata_tab.txt", "\t"),
            ("txt2metadata_csv_comma.csv", ","),
            ("txt2metadata_csv_semicolon.csv", ";")
        ]

        for fixture in fixtures {
            let actual = try parseCSVFixture(
                named: fixture.name,
                delimiter: fixture.delimiter,
                expectedRecords: expected
            )
            XCTAssertEqual(actual, expected, fixture.name)
        }
    }

    func testCSVImportTrimsUnquotedFieldsButPreservesQuotedFieldWhitespace() throws {
        let file = AudioFileTestFactory.make(url: URL(fileURLWithPath: "/tmp/spaces.flac"))

        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: "{{fileName}},{{title}},{{artist}}",
            sourceText: " spaces.flac ,\"  Keep Surrounding Spaces  \",  Trim Me  ",
            firstRowIsHeader: false,
            targetFiles: [file],
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.rows.first?.status, .ready)
        let values = try XCTUnwrap(plan.rows.first?.writeEntry?.values)
        XCTAssertEqual(values[.title], "  Keep Surrounding Spaces  ")
        XCTAssertEqual(values[.artist], "Trim Me")
    }

    func testMetadataExchangeAudioFixturesExistForExpectedRows() throws {
        let bundle = Bundle(for: Self.self)

        for record in try loadExpectedRecords() {
            let url = try bundledFixtureURL(
                named: record.filename,
                preferredSubdirectory: Self.audioFixtureSubdirectory,
                bundle: bundle
            )
            let size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            XCTAssertGreaterThan(size, 0, record.filename)
        }
    }

    private func parseCSVFixture(
        named fixtureName: String,
        delimiter: Character,
        expectedRecords: [NormalizedMetadataRecord]
    ) throws -> [NormalizedMetadataRecord] {
        let sourceText = try loadTextFixture(named: fixtureName)
        let plan = MetadataExchangePlanner.makeCSVImportPlan(
            template: importTemplate(delimiter: delimiter),
            sourceText: sourceText,
            firstRowIsHeader: true,
            targetFiles: makeTargetFiles(for: expectedRecords),
            clearBlankImportedValues: false
        )

        XCTAssertNil(plan.validationMessage, fixtureName)
        XCTAssertEqual(plan.rows.count, expectedRecords.count, fixtureName)
        XCTAssertEqual(plan.rows.map(\.status), Array(repeating: .ready, count: expectedRecords.count), fixtureName)
        XCTAssertEqual(plan.issueCount, 0, fixtureName)
        XCTAssertEqual(plan.writeEntries.count, expectedRecords.count, fixtureName)

        return try plan.writeEntries.map(normalizedRecord(from:))
    }

    private func normalizedRecord(from entry: MetadataExchangeWriteEntry) throws -> NormalizedMetadataRecord {
        NormalizedMetadataRecord(
            filename: entry.fileName,
            title: try XCTUnwrap(entry.values[.title], entry.fileName),
            artist: try XCTUnwrap(entry.values[.artist], entry.fileName),
            album: try XCTUnwrap(entry.values[.album], entry.fileName),
            composer: try XCTUnwrap(entry.values[.composer], entry.fileName),
            comment: try XCTUnwrap(entry.values[.comment], entry.fileName)
        )
    }

    private func makeTargetFiles(for records: [NormalizedMetadataRecord]) -> [AudioFile] {
        records.map { record in
            AudioFileTestFactory.make(
                url: URL(fileURLWithPath: "/tmp/\(record.filename)")
            )
        }
    }

    private func importTemplate(delimiter: Character) -> String {
        [
            MetadataExchangeField.fileName,
            .title,
            .artist,
            .album,
            .composer,
            .comment
        ]
        .map(\.token)
        .joined(separator: String(delimiter))
    }

    private func loadExpectedRecords() throws -> [NormalizedMetadataRecord] {
        let text = try loadTextFixture(named: "expected_metadata.txt")
        var records: [NormalizedMetadataRecord] = []
        var currentFilename: String?
        var currentFields: [String: String] = [:]

        func flushRecord() throws {
            guard let filename = currentFilename else { return }
            records.append(
                NormalizedMetadataRecord(
                    filename: filename,
                    title: try XCTUnwrap(currentFields["TITLE"], filename),
                    artist: try XCTUnwrap(currentFields["ARTIST"], filename),
                    album: try XCTUnwrap(currentFields["ALBUM"], filename),
                    composer: try XCTUnwrap(currentFields["COMPOSER"], filename),
                    comment: try XCTUnwrap(currentFields["COMMENT"], filename)
                )
            )
            currentFilename = nil
            currentFields = [:]
        }

        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for line in normalizedText.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try flushRecord()
                continue
            }

            if currentFilename == nil {
                currentFilename = line.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            XCTAssertEqual(parts.count, 2, "Malformed expected metadata line: \(line)")
            guard parts.count == 2 else { continue }
            currentFields[String(parts[0])] = String(parts[1])
        }

        try flushRecord()
        return records
    }

    private func loadTextFixture(named fileName: String) throws -> String {
        let url = try bundledFixtureURL(
            named: fileName,
            preferredSubdirectory: Self.textImportFixtureSubdirectory,
            bundle: Bundle(for: Self.self)
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func bundledFixtureURL(
        named fileName: String,
        preferredSubdirectory: String,
        bundle: Bundle
    ) throws -> URL {
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
}

private struct NormalizedMetadataRecord: Equatable, CustomStringConvertible {
    let filename: String
    let title: String
    let artist: String
    let album: String
    let composer: String
    let comment: String

    var description: String {
        [
            filename,
            "TITLE=\(title)",
            "ARTIST=\(artist)",
            "ALBUM=\(album)",
            "COMPOSER=\(composer)",
            "COMMENT=\(comment)"
        ].joined(separator: " | ")
    }
}
