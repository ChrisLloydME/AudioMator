import XCTest
@testable import AudioMatorCoreLogic

final class AudioMatorCoreLogicTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")

    func testAudioTagNumberTextParsesPaddedNumberAndOptionalTotal() {
        let components = AudioTagNumberText.components(from: " 003 / 012 ")

        XCTAssertEqual(components.number, "003")
        XCTAssertEqual(components.total, "012")
        let parsedPair = AudioTagNumberText.parsedPair(from: " 003 / 012 ")
        XCTAssertEqual(parsedPair.number, 3)
        XCTAssertEqual(parsedPair.total, 12)
        XCTAssertEqual(AudioTagNumberText.positiveIndex(from: "003/012"), 3)
        XCTAssertNil(AudioTagNumberText.positiveIndex(from: "000/012"))
    }

    func testAudioTagNumberPairPreservesUserFacingRawTextUntilCleared() {
        let pair = AudioTagNumberPair(rawText: " 04 / 11 ", number: 4, total: 11)

        XCTAssertEqual(pair.displayedNumberText, "04")
        XCTAssertEqual(pair.displayedTotalText, "11")
        XCTAssertEqual(pair.canonicalRawText, "04 / 11")
        XCTAssertEqual(pair.replacingNumberText("").canonicalRawText, "")
    }

    func testTextEditPipelineAppliesDeterministicOrderedTransforms() {
        let pipeline = TextEditPipeline(steps: [
            .trimEdges(.whitespacesAndNewlines),
            .replaceText(TextFindReplacement(findText: "demo", replacementText: "live")),
            .transformCase(.lowercase),
            .transformCase(.capitalizeFirstLetter),
            .insertText(" (2026)", position: .suffix)
        ])

        XCTAssertEqual(
            pipeline.applying(
                to: " DEMO QUIET STORM ",
                context: TextEditPipelineContext(locale: locale)
            ),
            "Live quiet storm (2026)"
        )
    }

    func testFindReplacementCanRespectWholeTextAndCaseSensitivity() {
        let wholeText = TextFindReplacement(
            findText: "mix",
            replacementText: "version",
            options: TextFindReplacementOptions(matchesCase: true, matchesWholeText: true)
        )

        XCTAssertEqual(wholeText.applied(to: "mix", locale: locale), "version")
        XCTAssertEqual(wholeText.applied(to: "Mix", locale: locale), "Mix")
        XCTAssertEqual(wholeText.applied(to: "radio mix", locale: locale), "radio mix")
    }

    func testRenameTemplateParserPreservesUnknownPlaceholdersAsLiteralText() {
        let document = FileRenameTemplateDocument(rawValue: "{{trackNumber}} - {{unknown}} - {{title}}")

        XCTAssertEqual(
            document.segments,
            [
                .field(.trackNumberText),
                .literal(" - {{unknown}} - "),
                .field(.title)
            ]
        )
        XCTAssertTrue(document.containsFieldSegments)
    }

    func testRenameSanitizerReplacesPathUnsafeAndControlCharacters() {
        let sanitizer = FileRenameSanitizer()

        XCTAssertEqual(sanitizer.sanitizeBaseName(" Track/Name: Mix\u{0007} "), "Track-Name- Mix")
        XCTAssertEqual(sanitizer.sanitizeBaseName(" /:\u{0000}\n "), "---")
        XCTAssertNil(sanitizer.sanitizeBaseName(" \u{0007}\n "))
    }

    func testFilenameMetadataMatcherExtractsGreedyLiteralSeparatedFields() throws {
        let matcher = FilenameMetadataTemplateMatcher(
            document: FileRenameTemplateDocument(rawValue: "{{artist}} - {{title}}"),
            replaceUnderscoresWithSpaces: false
        )

        let captures = try XCTUnwrap(matcher.match("Boards - Aquarius - Version"))

        XCTAssertEqual(captures[.artist], "Boards - Aquarius")
        XCTAssertEqual(captures[.title], "Version")
    }

    func testFilenameMetadataMatcherRejectsConflictingRepeatedCaptures() {
        let matcher = FilenameMetadataTemplateMatcher(
            document: FileRenameTemplateDocument(rawValue: "{{artist}} - {{artist}}"),
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertNotNil(matcher.match("Boards of Canada - Boards of Canada"))
        XCTAssertNil(matcher.match("Boards of Canada - Aphex Twin"))
    }

    func testFilenameMetadataMatcherNormalizesUnderscoresAndValidatesTypedFields() throws {
        let matcher = FilenameMetadataTemplateMatcher(
            document: FileRenameTemplateDocument(rawValue: "{{trackNumber}} - {{year}} - {{releaseDate}} - {{title}}"),
            replaceUnderscoresWithSpaces: true
        )

        let captures = try XCTUnwrap(matcher.match("03/12 - 2026 - 2026-06-02 - Quiet_Storm"))

        XCTAssertEqual(captures[.trackNumberText], "03/12")
        XCTAssertEqual(captures[.year], "2026")
        XCTAssertEqual(captures[.releaseDate], "2026-06-02")
        XCTAssertEqual(captures[.title], "Quiet Storm")
        XCTAssertNil(matcher.match("side-a - 2026 - 2026-06-02 - Quiet Storm"))
        XCTAssertNil(matcher.match("03 - 20X6 - 2026-06-02 - Quiet Storm"))
    }

    func testMetadataExchangeCSVParsesBOMQuotesEmbeddedNewlinesAndTrailingFields() throws {
        XCTAssertEqual(
            try MetadataExchangeCSV.parse("\u{FEFF}Title,Artist\r\n\"A, B\",\"C\"\"D\"\n\"Line\nBreak\",Tail\rLast,"),
            [
                ["Title", "Artist"],
                ["A, B", "C\"D"],
                ["Line\nBreak", "Tail"],
                ["Last", ""]
            ]
        )
    }

    func testMetadataExchangeCSVDetectsDelimiterOutsideQuotes() {
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}};{{title}};{{artist}}"), ";")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}}|{{title}}|{{artist}}"), "|")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}}\t{{title}}\t{{artist}}"), "\t")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{fileName}},\"{{title}}; live\" ,{{artist}}"), ",")
        XCTAssertEqual(MetadataExchangeCSV.detectDelimiter(in: "{{title}}"), ",")
    }

    func testMetadataExchangeCSVTrimsUnquotedImportsButPreservesQuotedBlanks() throws {
        let rows = try MetadataExchangeCSV.parseFields(" title ,\"  quoted  \",\"\",   ", delimiter: ",")

        XCTAssertEqual(rows[0].map(\.importedValue), ["title", "  quoted  ", "", ""])
        XCTAssertEqual(rows[0].map(\.hasImportContent), [true, true, false, false])
    }

    func testMetadataExchangeCSVRejectsMalformedCommaQuotesButCanAllowPlainDelimitedQuotes() throws {
        XCTAssertThrowsError(try MetadataExchangeCSV.parse("\"unterminated"))
        XCTAssertThrowsError(try MetadataExchangeCSV.parse("a\"b,c"))
        XCTAssertThrowsError(try MetadataExchangeCSV.parse("\"a\"b,c"))

        XCTAssertEqual(
            try MetadataExchangeCSV.parseFields(
                "song.flac|Room 404: \"Do Not Wake\"",
                delimiter: "|",
                allowsBareQuotesInUnquotedFields: true
            ).map { row in row.map(\.value) },
            [["song.flac", "Room 404: \"Do Not Wake\""]]
        )
    }

    func testMetadataExchangeCSVSerializeEscapesOnlyWhenNeeded() {
        XCTAssertEqual(
            MetadataExchangeCSV.serialize([["Plain", "A, B", "C\"D", "Line\nBreak"]]),
            "Plain,\"A, B\",\"C\"\"D\",\"Line\nBreak\""
        )
        XCTAssertEqual(
            MetadataExchangeCSV.serialize([["Plain", "A\tB"]], delimiter: "\t"),
            "Plain\t\"A\tB\""
        )
    }

    func testLRCLIBQueryTreatsWhitespaceOnlyInputAsEmpty() {
        let query = LRCLIBSearchQuery(
            trackName: " \n ",
            artistName: "\t",
            albumName: " ",
            durationSeconds: 240
        )

        XCTAssertTrue(query.isEmpty)
    }

    func testLRCLIBRequestBuilderUsesExpectedEndpointTrimmedQueryItemsAndHeaders() throws {
        let request = try LRCLIBRequestBuilder.makeSearchRequest(
            for: LRCLIBSearchQuery(
                trackName: " Sweeter Than Fiction ",
                artistName: " Taylor Swift ",
                albumName: " ",
                durationSeconds: 235
            ),
            userAgent: "AudioMator/dev (test)"
        )

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "lrclib.net")
        XCTAssertEqual(components.path, "/api/search")
        XCTAssertEqual(queryItems["track_name"], "Sweeter Than Fiction")
        XCTAssertEqual(queryItems["artist_name"], "Taylor Swift")
        XCTAssertNil(queryItems["album_name"])
        XCTAssertEqual(queryItems["duration"], "235")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "AudioMator/dev (test)")
    }

    func testLRCLIBRankerScoresExactSyncedDurationMatchHighest() {
        let query = LRCLIBSearchQuery(
            trackName: "Cafe del Mar",
            artistName: "Energy 52",
            albumName: "Classic Remixes",
            durationSeconds: 233
        )
        let ranked = LRCLIBCandidateRanker.rankedCandidates(
            [
                makeCandidate(id: 1, track: "Café del Mar", artist: "Energy 52", album: "Classic Remixes", duration: 233, syncedLyrics: "[00:01.00]Line"),
                makeCandidate(id: 2, track: "Cafe del Mar", artist: "Energy 52", album: "Classic Remixes", duration: 248, plainLyrics: "Line"),
                makeCandidate(id: 3, track: "Cafe", artist: "Other Artist", album: "Other", duration: 233, syncedLyrics: "[00:01.00]Line")
            ],
            for: query
        )

        XCTAssertEqual(ranked.map(\.id), [1, 2, 3])
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    func testLRCLIBRankerUsesSyncedLyricsAsTieBreaker() {
        let query = LRCLIBSearchQuery(
            trackName: "Track",
            artistName: "Artist",
            albumName: "Album",
            durationSeconds: 180
        )
        let ranked = LRCLIBCandidateRanker.rankedCandidates(
            [
                makeCandidate(id: 1, track: "Track", artist: "Artist", album: "Album", duration: 180, plainLyrics: "Line"),
                makeCandidate(id: 2, track: "Track", artist: "Artist", album: "Album", duration: 180, syncedLyrics: "[00:01.00]Line")
            ],
            for: query
        )

        XCTAssertEqual(ranked.map(\.id), [2, 1])
    }

    func testTrackRenumberPadWidthIsFastPurePolicy() {
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 9, padWithZeros: true), 2)
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 100, padWithZeros: true), 3)
        XCTAssertEqual(trackRenumberPadWidth(maxNumber: 100, padWithZeros: false), 0)
    }

    func testFuzzyStringSimilarityNormalizesProviderMetadataNoise() {
        XCTAssertEqual(FuzzyStringSimilarity.normalize("  Café / ＤＥＬ—Mar!  "), "cafe del mar")
        XCTAssertEqual(FuzzyStringSimilarity.score("Beyoncé / JAY-Z", "beyonce jay z"), 1)
        XCTAssertLessThan(FuzzyStringSimilarity.score("Roygbiv", "Telephasic Workshop"), 0.4)
    }

    func testMuseAmpAssignmentsShareAlbumIDsAndKeepTrackIDsUnique() {
        let assignments = MuseAmpCommentIDGenerator.assignments(for: [
            MuseAmpTrackIdentity(album: "Blue Hour", albumArtist: "The Band", trackKey: "disc1-track1"),
            MuseAmpTrackIdentity(album: "Blue Hour", albumArtist: "The Band", trackKey: "disc1-track2"),
            MuseAmpTrackIdentity(album: "Blue Hour", albumArtist: "Other Band", trackKey: "disc1-track1")
        ])

        XCTAssertEqual(assignments[0].albumID, assignments[1].albumID)
        XCTAssertNotEqual(assignments[0].albumID, assignments[2].albumID)
        XCTAssertEqual(Set(assignments.map(\.trackID)).count, 3)
        XCTAssertTrue(assignments.allSatisfy { $0.albumID.allSatisfy(\.isNumber) && $0.trackID.allSatisfy(\.isNumber) })
    }

    func testMuseAmpCommentTextMatchesEmbeddedPayloadFormat() {
        XCTAssertEqual(
            MuseAmpCommentIDGenerator.commentText(albumID: "13868407145376506873", trackID: "4906269179403622017"),
            "{\"albumID\":\"13868407145376506873\",\"trackID\":\"4906269179403622017\",\"v\":1}"
        )
    }
}

private func makeCandidate(
    id: Int,
    track: String,
    artist: String,
    album: String,
    duration: Double?,
    plainLyrics: String? = nil,
    syncedLyrics: String? = nil,
    instrumental: Bool = false
) -> LRCLIBLyricsCandidate {
    LRCLIBLyricsCandidate(
        id: id,
        name: track,
        trackName: track,
        artistName: artist,
        albumName: album,
        duration: duration,
        instrumental: instrumental,
        plainLyrics: plainLyrics,
        syncedLyrics: syncedLyrics
    )
}
