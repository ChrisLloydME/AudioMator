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

    func testFileRenameCollisionPolicyFlagsDuplicateTargetsAndExistingFileBlockers() {
        let duplicateStatuses = FileRenameCollisionPolicy.finalizedStatuses(for: [
            FileRenameCoreDraft(id: "a", sourceKey: "/music/a.flac", destinationKey: "/music/target.flac", destinationExists: false, initialStatus: .ready),
            FileRenameCoreDraft(id: "b", sourceKey: "/music/b.flac", destinationKey: "/music/target.flac", destinationExists: false, initialStatus: .ready),
            FileRenameCoreDraft(id: "c", sourceKey: "/music/c.flac", destinationKey: "/music/c.flac", destinationExists: true, initialStatus: .unchanged)
        ])

        XCTAssertEqual(duplicateStatuses["a"], .duplicateTarget)
        XCTAssertEqual(duplicateStatuses["b"], .duplicateTarget)
        XCTAssertEqual(duplicateStatuses["c"], .unchanged)

        let existingStatuses = FileRenameCollisionPolicy.finalizedStatuses(for: [
            FileRenameCoreDraft(id: "blocked", sourceKey: "/music/a.flac", destinationKey: "/music/existing.flac", destinationExists: true, initialStatus: .ready),
            FileRenameCoreDraft(id: "ready", sourceKey: "/music/b.flac", destinationKey: "/music/c.flac", destinationExists: false, initialStatus: .ready)
        ])

        XCTAssertEqual(existingStatuses["blocked"], .existingFile)
        XCTAssertEqual(existingStatuses["ready"], .ready)
    }

    func testFileRenameCollisionPolicyAllowsRenameCyclesWhenSourcesWillMove() {
        let statuses = FileRenameCollisionPolicy.finalizedStatuses(for: [
            FileRenameCoreDraft(id: "a", sourceKey: "/music/a.flac", destinationKey: "/music/b.flac", destinationExists: true, initialStatus: .ready),
            FileRenameCoreDraft(id: "b", sourceKey: "/music/b.flac", destinationKey: "/music/a.flac", destinationExists: true, initialStatus: .ready)
        ])

        XCTAssertEqual(statuses["a"], .ready)
        XCTAssertEqual(statuses["b"], .ready)
    }

    func testMetadataExchangeCoreValidatesCSVColumnTemplatesAndConflicts() {
        let valid = CoreMetadataExchange.parseCSVColumnTemplate("{{fileName}},{{title}},{{_ignore}},{{artist}}")
        XCTAssertNil(valid.validationMessage)
        XCTAssertEqual(valid.columns, [.fileName, .title, .ignore, .artist])

        let duplicate = CoreMetadataExchange.parseCSVColumnTemplate("{{fileName}},{{title}},{{title}}")
        XCTAssertNotNil(duplicate.validationMessage)

        let conflictingLocator = CoreMetadataExchange.parseCSVColumnTemplate("{{fileName}},{{baseName}},{{title}}")
        XCTAssertNotNil(conflictingLocator.validationMessage)
    }

    func testMetadataExchangeCoreExportsRelativePathsAndSelectionIndexes() {
        let files = [
            coreMetadataFile(id: "1", path: "/Volumes/Library/Album/01.flac", values: [.title: "One"]),
            coreMetadataFile(id: "2", path: "/Volumes/Library/Album/02.flac", values: [.title: "Two"])
        ]

        let rows = CoreMetadataExchange.textExportRows(
            fields: [.index, .relativePath, .title],
            files: files,
            separator: "|"
        )

        XCTAssertEqual(rows, ["1|01.flac|One", "2|02.flac|Two"])
        XCTAssertEqual(CoreMetadataExchange.relativePath(path: "/a/b/c.flac", basePath: "/a"), "b/c.flac")
        XCTAssertNil(CoreMetadataExchange.relativePath(path: "/x/b/c.flac", basePath: "/a"))
    }

    func testMetadataExchangeCoreCSVImportHandlesMatchingMissingExtraAndBlankClearing() {
        let files = [
            coreMetadataFile(id: "1", fileName: "A.flac", values: [.title: "Old A", .artist: "Artist"]),
            coreMetadataFile(id: "2", fileName: "B.flac", values: [.title: "Old B", .artist: "Artist"])
        ]
        let rows = CoreMetadataExchange.csvImportRows(
            columns: [.fileName, .title, .artist],
            sourceText: "file,title,artist\nA.flac,New A,\nC.flac,New C,Someone",
            firstRowIsHeader: true,
            targetFiles: files,
            clearBlankImportedValues: true
        )

        XCTAssertEqual(rows.map(\.status), [.ready, .noMatch, .missingExternalRecord])
        XCTAssertEqual(rows[0].writeValues[.title], "New A")
        XCTAssertEqual(rows[0].writeValues[.artist], "")
    }

    func testMetadataExchangeCoreSelectionOrderReportsExtraAndMissingRows() {
        let files = [
            coreMetadataFile(id: "1", fileName: "A.flac", values: [.title: "Old A"])
        ]
        let rows = CoreMetadataExchange.csvImportRows(
            columns: [.title],
            sourceText: "New A\nNew B",
            firstRowIsHeader: false,
            targetFiles: files,
            clearBlankImportedValues: false
        )

        XCTAssertEqual(rows.map(\.status), [.ready, .extraExternalRecord])
    }

    func testOnlineMetadataSelectionCoreComputesMajoritiesMixedStateAndRepresentatives() {
        let summary = OnlineMetadataSelectionCore.summary(
            albums: [" Album ", "Album", "Other"],
            albumArtists: ["Artist", "Artist", "Other"],
            primaryArtists: ["Singer", "Singer", "Guest"],
            trackTotals: [10, 10, 0],
            releaseDates: ["2026-06-02", "2026", "2025"],
            barcodes: ["123", "123", ""],
            providerAlbumIDs: ["abc", "abc", ""]
        )

        XCTAssertEqual(summary.albumCandidate, "Album")
        XCTAssertEqual(summary.trackCountCandidate, 10)
        XCTAssertEqual(summary.releaseYearCandidate, "2026")
        XCTAssertTrue(summary.selectionLooksMixed)

        let representatives = OnlineMetadataSelectionCore.representativeFiles(
            [
                providerFile("4", title: "Four", track: "04"),
                providerFile("1", title: "One", track: "01"),
                providerFile("2", title: "Two", track: "02"),
                providerFile("3", title: "Three", track: "03"),
                providerFile("5", title: "Five", track: "05")
            ],
            title: \.title,
            discNumber: { _ in 1 },
            trackNumber: { OnlineMetadataSelectionCore.normalizedPositiveIndex($0.trackNumber) }
        )

        XCTAssertEqual(representatives.map(\.id), ["1", "3", "5"])
    }

    func testITunesProviderCoreBuildsSearchLookupQueriesAndParsesLinks() throws {
        let query = ITunesProviderSearchQuery(
            mode: .file,
            fileInputs: [
                itunesFile("1", title: "Track One", artist: "Artist", album: "Album", trackNumber: "01/10"),
                itunesFile("2", title: "Track Two", artist: "Artist", album: "Album", trackNumber: "02/10")
            ]
        )

        XCTAssertEqual(query.searchTerm, "Album Artist")
        let searchURL = try query.searchURL(entity: "album", limit: 500)
        let searchComponents = try XCTUnwrap(URLComponents(url: searchURL, resolvingAgainstBaseURL: false))
        let searchItems = Dictionary(uniqueKeysWithValues: (searchComponents.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })

        XCTAssertEqual(searchComponents.host, "itunes.apple.com")
        XCTAssertEqual(searchComponents.path, "/search")
        XCTAssertEqual(searchItems["entity"], "album")
        XCTAssertEqual(searchItems["limit"], "200")
        XCTAssertEqual(searchItems["country"], "us")

        let lookupURL = try query.lookupURL(idName: "upc", idValue: "123456", country: " GB ", includeSongs: true)
        let lookupItems = Dictionary(uniqueKeysWithValues: (URLComponents(url: lookupURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
        XCTAssertEqual(lookupItems["upc"], "123456")
        XCTAssertEqual(lookupItems["country"], "gb")
        XCTAssertEqual(lookupItems["entity"], "song")

        XCTAssertEqual(try ITunesProviderLinkParser.parse("1440857781"), .album(1_440_857_781))
        XCTAssertEqual(try ITunesProviderLinkParser.parse("https://music.apple.com/us/album/demo/id1440857781?i=1440857783"), .track(1_440_857_783))
        XCTAssertEqual(try ITunesProviderLinkParser.parse("https://music.apple.com/us/album/demo/id1440857781"), .album(1_440_857_781))
    }

    func testITunesArtworkCoreBuildsRequestsTransformsJSONAndOrdersDownloadURLs() throws {
        let requestURL = try ITunesArtworkCoreRequest(
            query: "  Vespertine ",
            entity: .album,
            country: " US ",
            limit: 24
        ).searchURL()
        let requestItems = Dictionary(uniqueKeysWithValues: (URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })

        XCTAssertEqual(requestURL.host, "itunes.apple.com")
        XCTAssertEqual(requestURL.path, "/search")
        XCTAssertEqual(requestItems["term"], "Vespertine")
        XCTAssertEqual(requestItems["country"], "us")

        let json = """
        {
          "results": [
            {"collectionType":"Album","collectionName":"Vespertine","artistName":"Bjork","primaryGenreName":"Electronic","artworkUrl100":"https://is5-ssl.mzstatic.com/image/thumb/Music115/v4/aa/bb/cc/source/100x100bb.jpg"},
            {"collectionType":"Song","collectionName":"Hidden Place","artistName":"Bjork","artworkUrl100":"https://is5-ssl.mzstatic.com/image/thumb/Music115/v4/dd/ee/ff/source/100x100bb.jpg"},
            {"collectionType":"Album","collectionName":"Vespertine","artistName":"Bjork","artworkUrl100":"https://is5-ssl.mzstatic.com/image/thumb/Music115/v4/aa/bb/cc/source/100x100bb.jpg"}
          ]
        }
        """.data(using: .utf8)!

        let results = try ITunesArtworkCore.transformResults(from: json, entity: .idAlbum)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Vespertine • Bjork")
        XCTAssertEqual(results[0].pixelWidth, 3000)
        XCTAssertEqual(results[0].preferredDownloadURLs.first?.host, "a5.mzstatic.com")
        XCTAssertEqual(results[0].preferredPreviewURLs.first?.host, "is5-ssl.mzstatic.com")
    }

    func testMusicBrainzProviderCoreNormalizesFiltersQueriesLinksAndRepresentatives() throws {
        let filters = MusicBrainzProviderReleaseFilters(
            mediaFormats: [.digitalMedia],
            releaseYear: "released 2026-06-02",
            countries: [" us ", "ZZZ"],
            statuses: [.official]
        )

        XCTAssertTrue(filters.matches(date: "2026-01-01", country: "US", status: "official", candidateMediaFormats: ["Digital-Media"]))
        XCTAssertFalse(filters.matches(date: "2025-01-01", country: "US", status: "official", candidateMediaFormats: ["Digital Media"]))
        XCTAssertFalse(filters.matches(date: "2026-01-01", country: "GB", status: "official", candidateMediaFormats: ["Digital Media"]))

        let query = MusicBrainzProviderSearchQuery(
            mode: .file,
            title: "  Track  ",
            artist: "Artist",
            albumArtist: "Artist",
            album: "Album",
            trackNumber: "03/10",
            trackTotal: 10,
            durationMilliseconds: 5_100,
            releaseDate: "2026-06-02",
            isrc: "US-ABC-26-00001",
            barcode: "123",
            albumID: "550e8400-e29b-41d4-a716-446655440000",
            trackID: "",
            releaseFilters: filters
        )

        XCTAssertEqual(query.normalizedTrackNumber, 3)
        XCTAssertEqual(query.quantizedDuration, 2)
        XCTAssertEqual(query.selectionReleaseQuery.album, "Album")
        XCTAssertEqual(query.selectionReleaseQuery.artist, "Artist")
        XCTAssertEqual(query.selectionReleaseQuery.trackTotal, 10)
        XCTAssertEqual(query.artistCandidates, ["Artist"])

        XCTAssertEqual(
            try MusicBrainzProviderLinkParser.parse("musicbrainz.org/release/550e8400-e29b-41d4-a716-446655440000"),
            .release("550e8400-e29b-41d4-a716-446655440000")
        )
        XCTAssertThrowsError(try MusicBrainzProviderLinkParser.parse("musicbrainz.org/artist/550e8400-e29b-41d4-a716-446655440000"))

        let representatives = MusicBrainzProviderCore.representativeFilesForReleaseLookup(from: [
            mbFile("5", title: "Five", track: "05"),
            mbFile("1", title: "One", track: "01"),
            mbFile("3", title: "Three", track: "03"),
            mbFile("2", title: "Two", track: "02"),
            mbFile("4", title: "Four", track: "04")
        ])
        XCTAssertEqual(representatives.map(\.id), ["1", "3", "5"])
    }

    func testMusicBrainzProviderLuceneQueriesEscapeReservedCharactersAndLimitPreferredClauses() {
        let query = MusicBrainzProviderSearchQuery(
            mode: .track,
            title: "A+B",
            artist: "C:D",
            album: "The (Album)",
            trackNumber: "03/10",
            trackTotal: 10
        )

        let queries = MusicBrainzProviderLuceneQueryBuilder.recordingSearchQueries(from: query)
        let joinedQueries = queries.joined(separator: "\n")

        XCTAssertTrue(joinedQueries.contains("recording:\"A\\+B\""))
        XCTAssertTrue(joinedQueries.contains("artist:\"C\\:D\""))
        XCTAssertTrue(joinedQueries.contains("release:\"The \\(Album\\)\""))
        XCTAssertTrue(joinedQueries.contains("tnum:3"))
        XCTAssertLessThanOrEqual(queries.count, 6)
    }

    func testMusicBrainzProviderLuceneQueriesApplyReleaseFiltersToEveryPreferredClause() {
        let query = MusicBrainzProviderSearchQuery(
            mode: .album,
            artist: "Artist",
            album: "Album",
            releaseFilters: MusicBrainzProviderReleaseFilters(
                mediaFormats: [.digitalMedia, .cd],
                releaseYear: "2024-01-01",
                countries: ["us", "GB", "ignored"],
                statuses: [.official]
            )
        )

        let queries = MusicBrainzProviderLuceneQueryBuilder.releaseSearchQueries(from: query)

        XCTAssertFalse(queries.isEmpty)
        for query in queries {
            XCTAssertTrue(query.contains("date:\"2024\""))
            XCTAssertTrue(query.contains("(country:\"gb\" OR country:\"us\")"))
            XCTAssertTrue(query.contains("status:\"official\""))
            XCTAssertTrue(query.contains("format:\"CD\""))
            XCTAssertTrue(query.contains("format:\"Digital Media\""))
        }
    }

    func testMusicBrainzProviderLuceneQueriesDeduplicateAndLimitPreferredClauses() {
        let query = MusicBrainzProviderSearchQuery(
            mode: .album,
            title: "Shared",
            artist: "Shared",
            album: "Shared"
        )

        let queries = MusicBrainzProviderLuceneQueryBuilder.releaseSearchQueries(from: query)

        XCTAssertEqual(queries, Array(NSOrderedSet(array: queries)) as? [String])
        XCTAssertLessThanOrEqual(queries.count, 6)
    }

    func testAudioFormatSupportCoreNormalizesWritableAndArtworkExtensions() {
        let snapshot = AudioFormatSupportCore.snapshot(
            readableExtensions: ["MP3", "Flac", "MP3"],
            writableExtensions: ["MP3", "M4A"],
            capabilities: [
                AudioFormatCapabilityCore(extensions: ["MP3", "mp3"], isWritable: true, canWriteArtwork: true),
                AudioFormatCapabilityCore(extensions: ["WAV"], isWritable: true, canWriteArtwork: false),
                AudioFormatCapabilityCore(extensions: ["FLAC"], isWritable: false, canWriteArtwork: true),
                AudioFormatCapabilityCore(extensions: ["M4A"], isWritable: true, canWriteArtwork: true)
            ]
        )

        XCTAssertEqual(snapshot.readableExtensions, ["mp3", "flac"])
        XCTAssertEqual(snapshot.metadataWritableExtensions, ["mp3", "m4a"])
        XCTAssertEqual(snapshot.artworkWritableExtensions, ["mp3", "m4a"])
        XCTAssertEqual(snapshot.orderedReadableExtensions, ["mp3", "flac", "mp3"])
    }

    func testMetadataModelCoreMergesDuplicatesAndArtworkDecisions() {
        XCTAssertEqual(AudioMetadataMergeCore.mergedValue(["Same", "Same"], mixedPlaceholder: "mixed"), "Same")
        XCTAssertEqual(AudioMetadataMergeCore.mergedValue(["Same", "Other"], mixedPlaceholder: "mixed"), "mixed")
        XCTAssertEqual(
            AudioMetadataMergeCore.duplicateKeys(in: ["A.flac", "a.FLAC", "B.flac"]) { $0 },
            ["a.flac"]
        )

        XCTAssertEqual(ArtworkReplacementCore.decision(hasExistingArtwork: true, requestedReplacementDataIsEmpty: false, shouldRemove: false), .replace)
        XCTAssertEqual(ArtworkReplacementCore.decision(hasExistingArtwork: true, requestedReplacementDataIsEmpty: true, shouldRemove: true), .remove)
        XCTAssertEqual(ArtworkReplacementCore.decision(hasExistingArtwork: false, requestedReplacementDataIsEmpty: true, shouldRemove: true), .removeNoop)
        XCTAssertEqual(ArtworkReplacementCore.decision(hasExistingArtwork: true, requestedReplacementDataIsEmpty: true, shouldRemove: false), .keepExisting)
    }

    func testFileCollectionCoreSortsMergesGroupsAndDetectsDuplicatePaths() {
        let sorted = FileCollectionCore.sortedImportURLs([
            URL(fileURLWithPath: "/tmp/10.flac"),
            URL(fileURLWithPath: "/tmp/2.flac"),
            URL(fileURLWithPath: "/tmp/1.flac")
        ])
        XCTAssertEqual(sorted.map(\.lastPathComponent), ["1.flac", "2.flac", "10.flac"])

        let existing = [CoreAudioFileReference(id: "1", path: "/Music/A.flac", displayName: "A")]
        let merged = FileCollectionCore.mergePreservingExistingOrder(
            existing: existing,
            incoming: [
                CoreAudioFileReference(id: "2", path: "/music/a.flac", displayName: "A copy"),
                CoreAudioFileReference(id: "3", path: "/Music/B.flac", displayName: "B")
            ]
        )
        XCTAssertEqual(merged.map(\.id), ["1", "3"])

        let grouped = FileCollectionCore.groupedByAlbum(
            files: merged,
            album: { $0.id == "1" ? "Album" : "Album" },
            albumArtist: { $0.id == "1" ? "Artist" : "" },
            compilationKey: { _ in "Compilation" }
        )

        XCTAssertEqual(grouped["Album|Artist"]?.map { $0.id }, ["1"])
        XCTAssertEqual(grouped["Album|Compilation"]?.map { $0.id }, ["3"])
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

private struct ProviderFileFixture: Equatable, Hashable {
    let id: String
    let title: String
    let trackNumber: String
}

private func providerFile(_ id: String, title: String, track: String) -> ProviderFileFixture {
    ProviderFileFixture(id: id, title: title, trackNumber: track)
}

private func coreMetadataFile(
    id: String,
    fileName: String? = nil,
    path: String = "",
    values: [CoreMetadataExchangeField: String]
) -> CoreMetadataExchangeFile {
    let resolvedPath = path.isEmpty ? "/tmp/\(fileName ?? "\(id).flac")" : path
    let url = URL(fileURLWithPath: resolvedPath)
    let resolvedFileName = fileName ?? url.lastPathComponent
    return CoreMetadataExchangeFile(
        id: id,
        fileName: resolvedFileName,
        baseName: URL(fileURLWithPath: resolvedFileName).deletingPathExtension().lastPathComponent,
        path: resolvedPath,
        values: values
    )
}

private func itunesFile(
    _ id: String,
    title: String,
    artist: String,
    album: String,
    trackNumber: String
) -> ITunesProviderFileInput {
    ITunesProviderFileInput(
        id: id,
        displayTitle: title,
        title: title,
        artist: artist,
        albumArtist: "",
        album: album,
        trackNumber: trackNumber,
        discNumber: "1",
        trackTotal: 10,
        durationMilliseconds: nil,
        releaseDate: "2026-06-02",
        barcode: "",
        albumID: ""
    )
}

private func mbFile(_ id: String, title: String, track: String) -> MusicBrainzProviderFileInput {
    MusicBrainzProviderFileInput(
        id: id,
        displayTitle: title,
        title: title,
        artist: "Artist",
        albumArtist: "Artist",
        album: "Album",
        trackNumber: track,
        discNumber: "1",
        trackTotal: 5,
        durationMilliseconds: nil,
        releaseDate: "2026",
        isrc: "",
        barcode: "",
        albumID: "",
        trackID: ""
    )
}
