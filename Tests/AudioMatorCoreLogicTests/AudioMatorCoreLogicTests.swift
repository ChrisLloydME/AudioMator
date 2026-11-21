import XCTest
@testable import AudioMatorCoreLogic

final class AudioMatorCoreLogicTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")

    func testFileSystemPathKeysRespectVolumeCaseSemantics() throws {
        XCTAssertNotEqual(
            FileSystemPathSemantics.comparisonKey(
                forCanonicalPath: "/Volumes/CaseSensitive/Album/Track.flac",
                isCaseSensitive: true
            ),
            FileSystemPathSemantics.comparisonKey(
                forCanonicalPath: "/Volumes/CaseSensitive/Album/track.flac",
                isCaseSensitive: true
            )
        )
        XCTAssertEqual(
            FileSystemPathSemantics.comparisonKey(
                forCanonicalPath: "/Volumes/CaseInsensitive/Album/Track.flac",
                isCaseSensitive: false
            ),
            FileSystemPathSemantics.comparisonKey(
                forCanonicalPath: "/Volumes/CaseInsensitive/Album/track.flac",
                isCaseSensitive: false
            )
        )

        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let volumeValues = try temporaryDirectoryURL.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        )
        let upperFutureURL = temporaryDirectoryURL.appendingPathComponent("AudioMator-Future.flac")
        let lowerFutureURL = temporaryDirectoryURL.appendingPathComponent("audiomator-future.flac")

        if volumeValues.volumeSupportsCaseSensitiveNames == true {
            XCTAssertNotEqual(
                FileSystemPathSemantics.key(for: upperFutureURL),
                FileSystemPathSemantics.key(for: lowerFutureURL)
            )
        } else {
            XCTAssertEqual(
                FileSystemPathSemantics.key(for: upperFutureURL),
                FileSystemPathSemantics.key(for: lowerFutureURL)
            )
        }
    }

    func testFileSystemPathKeysResolveStandardizedAndSymlinkAliases() throws {
        let testRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorPathSemantics-\(UUID().uuidString)", isDirectory: true)
        let realDirectoryURL = testRootURL.appendingPathComponent("real", isDirectory: true)
        let aliasDirectoryURL = testRootURL.appendingPathComponent("alias", isDirectory: true)
        let fileURL = realDirectoryURL.appendingPathComponent("track.flac")

        try FileManager.default.createDirectory(at: realDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRootURL) }
        try Data().write(to: fileURL)
        try FileManager.default.createSymbolicLink(at: aliasDirectoryURL, withDestinationURL: realDirectoryURL)

        let standardizedAliasURL = realDirectoryURL
            .appendingPathComponent("unused", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("track.flac")
        let symlinkAliasURL = aliasDirectoryURL.appendingPathComponent("track.flac")

        XCTAssertEqual(
            FileSystemPathSemantics.key(for: fileURL),
            FileSystemPathSemantics.key(for: standardizedAliasURL)
        )
        XCTAssertEqual(
            FileSystemPathSemantics.key(for: fileURL),
            FileSystemPathSemantics.key(for: symlinkAliasURL)
        )
        XCTAssertTrue(FileSystemPathSemantics.isSameOrDescendant(fileURL, of: aliasDirectoryURL))
        XCTAssertFalse(
            FileSystemPathSemantics.isSameOrDescendant(
                testRootURL.appendingPathComponent("real-copy/track.flac"),
                of: realDirectoryURL
            )
        )
    }

    func testMutationDirectoryAccessTreatsAuthorizedHomeAsCoveringDescendantFiles() {
        let homeURL = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let fileURLs = [
            homeURL.appendingPathComponent("Music/Album/01.aiff"),
            homeURL.appendingPathComponent("Downloads/02.aiff")
        ]

        XCTAssertTrue(
            FileMutationDirectoryAccessPlan.missingDirectories(
                for: fileURLs,
                activeDirectoryURLs: [homeURL]
            ).isEmpty
        )
    }

    func testMutationDirectoryAccessRequestsOnlyUncoveredUniqueParentFolders() {
        let homeURL = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let externalAlbumURL = URL(fileURLWithPath: "/Volumes/Library/Album", isDirectory: true)
        let fileURLs = [
            homeURL.appendingPathComponent("Music/covered.aiff"),
            externalAlbumURL.appendingPathComponent("01.aiff"),
            externalAlbumURL.appendingPathComponent("02.aiff"),
            URL(fileURLWithPath: "/Users/example-copy/not-covered.aiff")
        ]

        let missingDirectories = FileMutationDirectoryAccessPlan.missingDirectories(
            for: fileURLs,
            activeDirectoryURLs: [homeURL]
        )

        XCTAssertEqual(
            missingDirectories.map(\.path),
            ["/Users/example-copy", "/Volumes/Library/Album"]
        )
    }

    func testAudioNumericConversionRejectsInvalidAndOutOfRangeValues() {
        XCTAssertNil(AudioNumericConversion.roundedInt(.nan))
        XCTAssertNil(AudioNumericConversion.roundedInt(.infinity))
        XCTAssertNil(AudioNumericConversion.roundedInt(-.infinity))
        XCTAssertNil(AudioNumericConversion.roundedInt(.greatestFiniteMagnitude))
        XCTAssertNil(AudioNumericConversion.positiveDurationMilliseconds(.greatestFiniteMagnitude))
        XCTAssertNil(AudioNumericConversion.positiveDurationSeconds(0))
        XCTAssertNil(AudioNumericConversion.positiveDurationSeconds(-1))
    }

    func testAudioNumericConversionRoundsValidDurations() {
        XCTAssertEqual(AudioNumericConversion.positiveDurationMilliseconds(123.456), 123_456)
        XCTAssertEqual(AudioNumericConversion.positiveDurationSeconds(123.6), 124)
        XCTAssertEqual(AudioNumericConversion.roundedInt(123.9, rule: .down), 123)
    }

    func testAudioNumericConversionBoundsIntegerDistanceWithoutOverflow() {
        XCTAssertEqual(AudioNumericConversion.boundedDistance(10, 12, maximum: 2), 2)
        XCTAssertNil(AudioNumericConversion.boundedDistance(Int.max, Int.min, maximum: 30_000))
        XCTAssertNil(AudioNumericConversion.boundedDistance(0, Int.min, maximum: Int.max))
        XCTAssertNil(AudioNumericConversion.boundedDistance(10, 12, maximum: 1))
    }

    func testAudioNumericConversionSaturatesNonnegativeCounts() {
        XCTAssertEqual(AudioNumericConversion.saturatingNonnegativeSum(2, 3), 5)
        XCTAssertEqual(AudioNumericConversion.saturatingNonnegativeSum(-4, 3), 3)
        XCTAssertEqual(AudioNumericConversion.saturatingNonnegativeSum(Int.max, 1), Int.max)
    }

    func testAudioTagNumberTextParsesPaddedNumberAndOptionalTotal() {
        let components = AudioTagNumberText.components(from: " 003 / 012 ")

        XCTAssertEqual(components.number, "003")
        XCTAssertEqual(components.total, "012")
        XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: components.number), 3)
        XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: components.total ?? ""), 12)
        XCTAssertEqual(AudioTagNumberText.positiveIndex(from: "003/012"), 3)
        XCTAssertNil(AudioTagNumberText.positiveIndex(from: "000/012"))
    }

    func testAudioTagNumberPairPreservesUserFacingRawTextUntilCleared() {
        let pair = AudioTagNumberPair(rawText: " 04 / 11 ", number: 4, total: 11)

        XCTAssertEqual(pair.displayedNumberText, "04")
        XCTAssertEqual(pair.displayedTotalText, "11")
        XCTAssertEqual(pair.canonicalRawText, "04 / 11")
        XCTAssertEqual(pair.replacingNumberText("").canonicalRawText, "/11")
    }

    func testTextEditPipelineTransformsValueArraysPerElement() {
        let pipeline = TextEditPipeline(steps: [
            .trimEdges(.whitespacesAndNewlines),
            .transformCase(.uppercase)
        ])

        XCTAssertEqual(
            pipeline.applying(
                to: [" alpha ", "", "beta"],
                context: TextEditPipelineContext(locale: Locale(identifier: "en_US_POSIX"))
            ),
            ["ALPHA", "", "BETA"]
        )
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
        XCTAssertEqual(document.unknownPlaceholderNames, ["unknown"])
        XCTAssertFalse(document.hasUnterminatedPlaceholder)

        let unterminated = FileRenameTemplateDocument(rawValue: "{{trackNumber}} - {{title")
        XCTAssertTrue(unterminated.hasUnterminatedPlaceholder)
    }

    func testRenameSanitizerReplacesPathUnsafeAndControlCharacters() {
        let sanitizer = FileRenameSanitizer()

        XCTAssertEqual(sanitizer.sanitizeBaseName(" Track/Name: Mix\u{0007} "), "Track-Name- Mix")
        XCTAssertEqual(sanitizer.sanitizeBaseName(" /:\u{0000}\n "), "---")
        XCTAssertNil(sanitizer.sanitizeBaseName(" \u{0007}\n "))
    }

    func testFilenameMetadataMatcherRejectsAmbiguousLiteralSeparatedFields() {
        let matcher = FilenameMetadataTemplateMatcher(
            document: FileRenameTemplateDocument(rawValue: "{{artist}} - {{title}}"),
            replaceUnderscoresWithSpaces: false
        )

        XCTAssertNil(matcher.match("Boards - Aquarius - Version"))
    }

    func testFilenameMetadataMatcherKeepsUniqueTypedBacktrackingMatch() throws {
        let matcher = FilenameMetadataTemplateMatcher(
            document: FileRenameTemplateDocument(rawValue: "{{artist}} - {{trackNumber}} - {{title}}"),
            replaceUnderscoresWithSpaces: false
        )

        let captures = try XCTUnwrap(matcher.match("Boards - Aquarius - 07 - Version"))

        XCTAssertEqual(captures[.artist], "Boards - Aquarius")
        XCTAssertEqual(captures[.trackNumberText], "07")
        XCTAssertEqual(captures[.title], "Version")
    }

    func testFilenameMetadataMatcherFailsClosedWhenSearchBudgetIsExhausted() {
        let matcher = FilenameMetadataTemplateMatcher(
            document: FileRenameTemplateDocument(rawValue: "{{artist}} - {{title}}"),
            replaceUnderscoresWithSpaces: false,
            matchingStepLimit: 1
        )

        XCTAssertNil(matcher.match("Boards - Aquarius"))
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

        // User-entered/filename-extracted date values pass through without
        // date-specific format rejection or rewriting.
        let freeformDateCaptures = try XCTUnwrap(matcher.match("03 - Spring_2024 - circa_1998 - Quiet_Storm"))
        XCTAssertEqual(freeformDateCaptures[.trackNumberText], "03")
        XCTAssertEqual(freeformDateCaptures[.year], "Spring 2024")
        XCTAssertEqual(freeformDateCaptures[.releaseDate], "circa 1998")
        XCTAssertEqual(freeformDateCaptures[.title], "Quiet Storm")
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
        let codec = MetadataExchangeCSVCodec(profileVersion: nil)

        XCTAssertEqual(rows[0].map(codec.importedValue), ["title", "  quoted  ", "", ""])
        XCTAssertEqual(rows[0].map(codec.hasImportContent), [true, true, false, false])
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

    func testMetadataExchangeCSVSerializeEscapesOnlyWhenNeeded() throws {
        XCTAssertEqual(
            MetadataExchangeCSV.serialize([["Plain", "A, B", "C\"D", "Line\nBreak"]]),
            "Plain,\"A, B\",\"C\"\"D\",\"Line\nBreak\""
        )
        XCTAssertEqual(
            MetadataExchangeCSV.serialize([["Plain", "A\tB"]], delimiter: "\t"),
            "Plain\t\"A\tB\""
        )

        let roundTripRows = [["  Leading and trailing  ", "Line\r\nBreak"]]
        let serialized = MetadataExchangeCSV.serialize(roundTripRows)
        XCTAssertEqual(serialized, "\"  Leading and trailing  \",\"Line\r\nBreak\"")
        let codec = MetadataExchangeCSVCodec(profileVersion: 2)
        XCTAssertEqual(
            try MetadataExchangeCSV.parseFields(serialized).map { row in row.map(codec.importedValue) },
            roundTripRows
        )
    }

    func testMetadataExchangeCSVNeutralizesSpreadsheetFormulasReversibly() throws {
        let rows = [["=1+1", "+2", "-3", "@SUM(A1:A2)", "\t=4", "\u{00A0}=5", "'=literal", "plain"]]
        let serialized = MetadataExchangeCSV.serialize(rows)

        XCTAssertTrue(serialized.hasPrefix("'=1+1"))
        XCTAssertTrue(serialized.contains("''=literal"))
        // Lexical parsing keeps the export protection bytes...
        let lexical = try MetadataExchangeCSV.parse(serialized)
        XCTAssertEqual(lexical.count, 1)
        XCTAssertEqual(lexical[0].first, "'=1+1")
        XCTAssertEqual(lexical[0][1], "'+2")
        XCTAssertEqual(lexical[0].last, "plain")
        // ...and the marked profile codec is what reverses them.
        let codec = MetadataExchangeCSVCodec(profileVersion: 2)
        XCTAssertEqual(try MetadataExchangeCSV.parseFields(serialized).map { $0.map(codec.importedValue) }, rows)
    }

    func testFixedSeedCSVSerializationRoundTripsUnicodeEscapingAndFormulaPrefixes() throws {
        var generator = FixedSeedGenerator(seed: 0xA11D_10C5_C5A5_E001)
        let alphabet: [Character] = [
            "a", "Z", "0", " ", "\t", "\n", "\r", ",", ";", "|", "\"", "'", "=", "+", "-", "@",
            "é", "中", "🎵", "\u{00A0}"
        ]

        for delimiter in [Character(","), Character(";"), Character("|"), Character("\t")] {
            for _ in 0..<160 {
                let rowCount = generator.int(in: 1...4)
                let fieldCount = generator.int(in: 1...6)
                var rows: [[String]] = []
                for _ in 0..<rowCount {
                    var row: [String] = []
                    for _ in 0..<fieldCount {
                        let length = generator.int(in: 0...24)
                        let value = String((0..<length).map { _ in alphabet[generator.int(in: 0...(alphabet.count - 1))] })
                        row.append(value)
                    }
                    rows.append(row)
                }

                let serialized = MetadataExchangeCSV.serialize(rows, delimiter: delimiter)
                let codec = MetadataExchangeCSVCodec(profileVersion: 2)
                XCTAssertEqual(
                    try MetadataExchangeCSV.parseFields(serialized, delimiter: delimiter)
                        .map { row in row.map(codec.importedValue) },
                    rows,
                    "delimiter=\(delimiter)"
                )
            }
        }
    }

    func testMetadataExchangeCSVCodecKeepsUnmarkedExternalCellsLiteral() throws {
        let rows = try MetadataExchangeCSV.parseFields("'+44,\"'=literal\",\"''=A1\",\" '=B2\"")
        let literal = MetadataExchangeCSVCodec(profileVersion: nil)

        XCTAssertEqual(rows[0].map(\.value), ["'+44", "'=literal", "''=A1", " '=B2"])
        XCTAssertEqual(
            rows[0].map(literal.importedValue),
            ["'+44", "'=literal", "''=A1", " '=B2"]
        )

        // A recognized AudioMator profile still reverses its own protection.
        let profile = MetadataExchangeCSVCodec(profileVersion: 2)
        XCTAssertEqual(profile.importedValue(MetadataExchangeCSVField(value: "'+44", wasQuoted: false)), "+44")
        XCTAssertEqual(profile.importedValue(MetadataExchangeCSVField(value: "'=1+1", wasQuoted: false)), "=1+1")
        XCTAssertEqual(
            profile.importedValue(MetadataExchangeCSVField(value: "''=literal", wasQuoted: false)),
            "'=literal"
        )
    }

    func testMetadataExchangeCSVParsePreservesLeadingEmptyColumn() throws {
        // The audit's parser mutant dropped this leading empty cell and survived.
        XCTAssertEqual(try MetadataExchangeCSV.parse(",New Title"), [["", "New Title"]])
        XCTAssertEqual(try MetadataExchangeCSV.parse(","), [["", ""]])
    }

    func testMetadataExchangeCSVSoleEmptyCellRoundTrips() throws {
        let serialized = MetadataExchangeCSV.serialize([[""], ["Old B"]])
        XCTAssertEqual(serialized, "\"\"\r\nOld B")

        let fields = try MetadataExchangeCSV.parseFields(serialized)
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields[0].count, 1)
        XCTAssertEqual(fields[0][0].value, "")
        XCTAssertTrue(fields[0][0].wasQuoted)
        XCTAssertEqual(fields[1][0].value, "Old B")

        XCTAssertEqual(MetadataExchangeCSV.serialize([[""]]), "\"\"")
        XCTAssertEqual(
            try MetadataExchangeCSV.parseFields("\"\"").map { $0.map(\.value) },
            [[""]]
        )
    }

    func testMetadataExchangeTextFramingPreservesPhysicalSlots() {
        func frame(_ source: String) -> MetadataExchangeFraming {
            MetadataExchangeTextFramer.frame(source, extraction: MetadataExchangeProfile.extract(from: source))
        }

        XCTAssertEqual(frame("").records.map(\.rawText), [])
        XCTAssertEqual(frame("\n").records.map(\.rawText), ["", ""])
        XCTAssertEqual(frame("\n\nA\n").records.map(\.rawText), ["", "", "A", ""])
        XCTAssertEqual(frame("A\r\nB\rC").records.map(\.rawText), ["A", "B", "C"])
        XCTAssertTrue(frame("A\n").sourceEndedWithLineBreak)
        XCTAssertFalse(frame("A").sourceEndedWithLineBreak)
    }

    func testMetadataExchangeTextFramingHonorsMarkerAndBOMRules() {
        let marker = MetadataExchangeProfile.markerLine()
        let singleEmpty = MetadataExchangeTextFramer.frame(
            marker + "\n",
            extraction: MetadataExchangeProfile.extract(from: marker + "\n")
        )
        XCTAssertEqual(singleEmpty.records.map(\.rawText), [""])
        XCTAssertEqual(singleEmpty.profileVersion, 2)
        XCTAssertTrue(singleEmpty.hadMarker)
        XCTAssertTrue(singleEmpty.markerLineTerminated)

        let twoEmpty = MetadataExchangeTextFramer.frame(
            marker + "\n\n",
            extraction: MetadataExchangeProfile.extract(from: marker + "\n\n")
        )
        XCTAssertEqual(twoEmpty.records.map(\.rawText), ["", ""])

        let trailingEmptyKept = MetadataExchangeTextFramer.frame(
            marker + "\nA\n",
            extraction: MetadataExchangeProfile.extract(from: marker + "\nA\n")
        )
        XCTAssertEqual(trailingEmptyKept.records.map(\.rawText), ["A", ""])

        let bomSource = "\u{FEFF}" + marker + "\n\nA"
        let bom = MetadataExchangeTextFramer.frame(
            bomSource,
            extraction: MetadataExchangeProfile.extract(from: bomSource)
        )
        XCTAssertEqual(bom.records.map(\.rawText), ["", "A"])

        let incomplete = MetadataExchangeTextFramer.frame(
            marker,
            extraction: MetadataExchangeProfile.extract(from: marker)
        )
        XCTAssertNotNil(incomplete.validationMessage)
        XCTAssertTrue(incomplete.records.isEmpty)
    }

    func testMetadataExchangePositionalBindingUsesCountDrivenRules() {
        func framing(_ source: String) -> MetadataExchangeFraming {
            MetadataExchangeTextFramer.frame(source, extraction: MetadataExchangeProfile.extract(from: source))
        }
        let marker = MetadataExchangeProfile.markerLine()

        // Marked v2 is strict: no implicit terminator, no compaction.
        XCTAssertEqual(
            MetadataExchangePositionalBinder.bind(
                framing: framing(marker + "\n\nOld B"),
                targetCount: 2,
                clearBlankImportedValues: false
            ),
            .aligned([
                MetadataExchangeFramedRecord(sourceIndex: 0, rawText: ""),
                MetadataExchangeFramedRecord(sourceIndex: 1, rawText: "Old B")
            ])
        )
        XCTAssertEqual(
            MetadataExchangePositionalBinder.bind(
                framing: framing(marker + "\nA\n"),
                targetCount: 1,
                clearBlankImportedValues: false
            ),
            .countMismatch(records: 2, targets: 1)
        )

        // Legacy two-target terminator tolerance.
        XCTAssertEqual(
            MetadataExchangePositionalBinder.bind(
                framing: framing("A-tag\nB-tag\n"),
                targetCount: 2,
                clearBlankImportedValues: false
            ),
            .aligned([
                MetadataExchangeFramedRecord(sourceIndex: 0, rawText: "A-tag"),
                MetadataExchangeFramedRecord(sourceIndex: 1, rawText: "B-tag")
            ])
        )
        XCTAssertEqual(
            MetadataExchangePositionalBinder.bind(
                framing: framing("A-tag\n"),
                targetCount: 2,
                clearBlankImportedValues: false
            ),
            .aligned([
                MetadataExchangeFramedRecord(sourceIndex: 0, rawText: "A-tag"),
                MetadataExchangeFramedRecord(sourceIndex: 1, rawText: "")
            ])
        )
        XCTAssertEqual(
            MetadataExchangePositionalBinder.bind(
                framing: framing("A-tag\n\n\n"),
                targetCount: 2,
                clearBlankImportedValues: false
            ),
            .countMismatch(records: 4, targets: 2)
        )

        // Legacy one-file padding tolerance only with clearing disabled.
        XCTAssertEqual(
            MetadataExchangePositionalBinder.bind(
                framing: framing("\n  Quiet Storm  \n\n"),
                targetCount: 1,
                clearBlankImportedValues: false
            ),
            .legacyOneRecordPadding(targetIndex: 0, recordIndex: 1)
        )
        XCTAssertEqual(
            MetadataExchangePositionalBinder.bind(
                framing: framing("\n  Quiet Storm  \n\n"),
                targetCount: 1,
                clearBlankImportedValues: true
            ),
            .countMismatch(records: 4, targets: 1)
        )
    }

    func testMetadataExchangeNumberSpellingValidatesCompleteComponents() {
        typealias Spelling = MetadataExchangeNumberSpelling

        XCTAssertEqual(Spelling.parseComponent("3", maximum: 65535), .success(.value(text: "3", value: 3)))
        XCTAssertEqual(Spelling.parseComponent("007", maximum: 65535), .success(.value(text: "007", value: 7)))
        XCTAssertEqual(Spelling.parseComponent("+7", maximum: 65535), .success(.value(text: "+7", value: 7)))
        XCTAssertEqual(Spelling.parseComponent("0", maximum: 65535), .success(.removal))
        XCTAssertEqual(Spelling.parseComponent("00", maximum: 65535), .success(.removal))
        XCTAssertEqual(Spelling.parseComponent("+0", maximum: 65535), .success(.removal))
        XCTAssertEqual(Spelling.parseComponent("-1", maximum: 65535), .failure(.negativeMagnitude))
        XCTAssertEqual(Spelling.parseComponent("abc", maximum: 65535), .failure(.notAnInteger))
        XCTAssertEqual(Spelling.parseComponent("2147483648", maximum: Int(Int32.max)), .failure(.overflowsDeclaredMaximum))
        XCTAssertEqual(Spelling.parseComponent("65536", maximum: 65535), .failure(.overflowsDeclaredMaximum))
        XCTAssertEqual(Spelling.parseComponent("65535", maximum: 65535), .success(.value(text: "65535", value: 65535)))

        XCTAssertEqual(
            Spelling.parseNumberColumn("3/12", maximum: 65535),
            .success(.number(.value(text: "3", value: 3), embeddedTotal: .value(text: "12", value: 12)))
        )
        XCTAssertEqual(
            Spelling.parseNumberColumn("1/0", maximum: 65535),
            .success(.number(.value(text: "1", value: 1), embeddedTotal: .removal))
        )
        XCTAssertEqual(Spelling.parseNumberColumn("/12", maximum: 65535), .failure(.emptySlashComponent))
        XCTAssertEqual(Spelling.parseNumberColumn("3/", maximum: 65535), .failure(.emptySlashComponent))
        XCTAssertEqual(Spelling.parseNumberColumn("1/2/3", maximum: 65535), .failure(.multipleSlashes))
        XCTAssertEqual(Spelling.parseTotalColumn("3/12", maximum: 65535), .failure(.pairInTotalColumn))
    }

    func testFixedSeedTemplateSyntaxPreservesEveryGeneratedCodePoint() {
        var generator = FixedSeedGenerator(seed: 0x7E4D_91A7_E202_600D)
        let literalAlphabet: [Character] = ["a", " ", "-", "_", "}", "é", "中", "🎵", "\n"]
        let placeholderNames = ["title", "artist", "trackNumber", "未知", "", "a-b"]

        for _ in 0..<500 {
            var template = ""
            let segmentCount = generator.int(in: 1...12)
            for _ in 0..<segmentCount {
                if generator.bool() {
                    let length = generator.int(in: 0...12)
                    template += String((0..<length).map { _ in
                        literalAlphabet[generator.int(in: 0...(literalAlphabet.count - 1))]
                    })
                } else {
                    template += "{{\(placeholderNames[generator.int(in: 0...(placeholderNames.count - 1))])}}"
                }
            }

            let result = MetadataExchangeTemplateSyntaxParser.parse(template)
            let reconstructed = result.segments.map { segment in
                switch segment {
                case .literal(let literal):
                    return literal
                case .placeholder(let name):
                    return "{{\(name)}}"
                }
            }.joined()

            XCTAssertEqual(reconstructed, template)
            XCTAssertFalse(result.hasUnterminatedPlaceholder)
        }

        let unterminated = MetadataExchangeTemplateSyntaxParser.parse("前缀 {{title}} {{未完成")
        XCTAssertTrue(unterminated.hasUnterminatedPlaceholder)
        XCTAssertEqual(
            unterminated.segments.map { segment in
                switch segment {
                case .literal(let literal): return literal
                case .placeholder(let name): return "{{\(name)}}"
                }
            }.joined(),
            "前缀 {{title}} {{未完成"
        )
    }

    func testFixedSeedTrackDiscTextPreservesNumericIntent() {
        var generator = FixedSeedGenerator(seed: 0x7A4C_D15C_2026_0725)

        for _ in 0..<1_000 {
            let number = generator.int(in: 0...9_999)
            let total = generator.int(in: 0...9_999)
            let padding = generator.int(in: 1...5)
            let numberText = String(repeating: "0", count: max(0, padding - String(number).count)) + String(number)
            let totalText = String(repeating: "0", count: max(0, padding - String(total).count)) + String(total)
            let rawText = " \(numberText) / \(totalText) "
            let parsedComponents = AudioTagNumberText.components(from: rawText)

            XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: parsedComponents.number), number)
            XCTAssertEqual(AudioTagNumberText.clampedInteger(fromComponent: parsedComponents.total ?? ""), total)
            XCTAssertTrue(
                AudioTagNumberText.writeExpectationMatches(
                    expectedText: rawText,
                    actualNumber: number,
                    actualTotal: total
                )
            )
        }
    }

    func testFixedSeedRenameSanitizationKeepsUnicodeAndRemovesPathUnsafeScalars() {
        var generator = FixedSeedGenerator(seed: 0xF11E_1D3A_71A5_0001)
        let sanitizer = FileRenameSanitizer()
        let alphabet: [Character] = ["a", " ", "/", ":", "\n", "\t", "é", "中", "🎵", "-", "_"]

        for _ in 0..<500 {
            let length = generator.int(in: 1...40)
            let source = "track" + String((0..<length).map { _ in
                alphabet[generator.int(in: 0...(alphabet.count - 1))]
            })
            let sanitized = try? XCTUnwrap(sanitizer.sanitizeBaseName(source))

            XCTAssertNotNil(sanitized)
            XCTAssertFalse(sanitized?.contains("/") == true)
            XCTAssertFalse(sanitized?.contains(":") == true)
            XCTAssertFalse(sanitized?.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) == true)
        }
    }

    func testMetadataExchangeLocatorIndexUsesTheNarrowestAvailableKey() {
        let fields = ["name", "path"]
        let names = ["duplicate", "duplicate", "unique"]
        let paths = ["/a", "/b", "/c"]
        let index = MetadataExchangeLocatorCandidateIndex(
            itemCount: names.count,
            fields: fields
        ) { field, itemIndex in
            [field == "name" ? names[itemIndex] : paths[itemIndex]]
        }

        let candidates = index.candidateIndices(fields: fields) { field in
            field == "name" ? "duplicate" : "/b"
        }

        XCTAssertEqual(candidates, [1])
        XCTAssertTrue(index.candidateIndices(fields: fields) { _ in nil }.isEmpty)
    }

    func testMetadataExchangeExportBudgetCountsSeparatorsAndFailsClosed() {
        var budget = MetadataExchangeExportBudget(
            maximumUTF8ByteCount: 10,
            recordSeparatorUTF8ByteCount: 2
        )

        XCTAssertTrue(budget.append(recordUTF8ByteCount: 4))
        XCTAssertTrue(budget.append(recordUTF8ByteCount: 4))
        XCTAssertEqual(budget.usedUTF8ByteCount, 10)
        XCTAssertEqual(budget.recordCount, 2)
        XCTAssertFalse(budget.append(recordUTF8ByteCount: 0))
        XCTAssertFalse(budget.append(recordUTF8ByteCount: Int.max))
        XCTAssertEqual(budget.usedUTF8ByteCount, 10)
        XCTAssertEqual(budget.recordCount, 2)
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

    func testLRCLIBAutoMatchRejectsUnrelatedOrWeakCandidates() {
        let query = LRCLIBSearchQuery(
            trackName: "Correct Song",
            artistName: "Correct Artist",
            albumName: "Album",
            durationSeconds: 180
        )
        let exact = makeCandidate(
            id: 1, track: "Correct Song", artist: "Correct Artist", album: "Album",
            duration: 182, syncedLyrics: "[00:01.00]Line"
        )
        let unrelated = makeCandidate(
            id: 2, track: "Different Song", artist: "Different Artist", album: "Other",
            duration: 180, syncedLyrics: "[00:01.00]Line"
        )
        let partialArtist = makeCandidate(
            id: 3, track: "Correct Song", artist: "Correct", album: "Album",
            duration: 180, syncedLyrics: "[00:01.00]Line"
        )
        let wrongDuration = makeCandidate(
            id: 4, track: "Correct Song", artist: "Correct Artist", album: "Album",
            duration: 240, syncedLyrics: "[00:01.00]Line"
        )
        let plainOnly = makeCandidate(
            id: 5, track: "Correct Song", artist: "Correct Artist", album: "Album",
            duration: 180, plainLyrics: "Line"
        )

        XCTAssertTrue(LRCLIBCandidateRanker.isHighConfidenceAutoMatch(exact, for: query))
        XCTAssertFalse(LRCLIBCandidateRanker.isHighConfidenceAutoMatch(unrelated, for: query))
        XCTAssertFalse(LRCLIBCandidateRanker.isHighConfidenceAutoMatch(partialArtist, for: query))
        XCTAssertFalse(LRCLIBCandidateRanker.isHighConfidenceAutoMatch(wrongDuration, for: query))
        XCTAssertFalse(LRCLIBCandidateRanker.isHighConfidenceAutoMatch(plainOnly, for: query))
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

    func testTrackRenumberStartNumberPolicyIsFastPureState() {
        XCTAssertEqual(trackRenumberStartNumberInput("1"), .valid(1))
        XCTAssertEqual(trackRenumberStartNumberInput(" 007 "), .valid(7))
        XCTAssertEqual(trackRenumberStartNumberInput("9999"), .valid(9_999))
        XCTAssertEqual(trackRenumberStartNumberInput(""), .invalid(.blank))
        XCTAssertEqual(trackRenumberStartNumberInput("0"), .invalid(.outOfRange))
        XCTAssertEqual(trackRenumberStartNumberInput("10000"), .invalid(.outOfRange))
        XCTAssertEqual(trackRenumberStartNumberInput("999999999999999999999999"), .invalid(.outOfRange))
        XCTAssertEqual(trackRenumberStartNumberInput("-1"), .invalid(.malformed))
        XCTAssertEqual(trackRenumberStartNumberInput("+7"), .invalid(.malformed))
        XCTAssertEqual(trackRenumberStartNumberInput("1.5"), .invalid(.malformed))
        XCTAssertEqual(trackRenumberStartNumberInput("1/12"), .invalid(.malformed))
        XCTAssertEqual(trackRenumberStartNumberInput("７"), .invalid(.malformed))
        XCTAssertEqual(trackRenumberStartNumberInput("٠٧"), .invalid(.malformed))
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

    func testiTunesProviderCoreBuildsSearchLookupQueriesAndParsesLinks() throws {
        let query = iTunesProviderSearchQuery(
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

        XCTAssertEqual(try iTunesProviderLinkParser.parse("1440857781"), .album(1_440_857_781))
        XCTAssertEqual(try iTunesProviderLinkParser.parse("https://music.apple.com/us/album/demo/id1440857781?i=1440857783"), .track(1_440_857_783))
        XCTAssertEqual(try iTunesProviderLinkParser.parse("https://music.apple.com/us/album/demo/id1440857781"), .album(1_440_857_781))
    }

    func testiTunesArtworkCoreBuildsRequestsTransformsJSONAndOrdersDownloadURLs() throws {
        let requestURL = try iTunesArtworkCoreRequest(
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

        let results = try iTunesArtworkCore.transformResults(from: json, entity: .idAlbum)

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
                AudioFormatCapabilityCore(extensions: ["MP3", "mp3"], isWritable: true, canWriteArtwork: true, writableFieldKeys: ["title", "artist"]),
                AudioFormatCapabilityCore(extensions: ["WAV"], isWritable: true, canWriteArtwork: false, writableFieldKeys: ["title"]),
                AudioFormatCapabilityCore(extensions: ["FLAC"], isWritable: false, canWriteArtwork: true, writableFieldKeys: []),
                AudioFormatCapabilityCore(extensions: ["M4A"], isWritable: true, canWriteArtwork: true, writableFieldKeys: ["title", "artwork"])
            ]
        )

        XCTAssertEqual(snapshot.readableExtensions, ["mp3", "flac"])
        XCTAssertEqual(snapshot.metadataWritableExtensions, ["mp3", "m4a"])
        XCTAssertEqual(snapshot.artworkWritableExtensions, ["mp3", "m4a"])
        XCTAssertEqual(snapshot.orderedReadableExtensions, ["mp3", "flac", "mp3"])
        XCTAssertEqual(snapshot.writableFieldKeysByExtension["mp3"], ["title", "artist"])
        XCTAssertEqual(snapshot.writableFieldKeysByExtension["wav"], ["title"])
    }

    func testMetadataModelCoreMergedValueKeepsEqualValuesAndMarksMixedValues() {
        XCTAssertEqual(AudioMetadataMergeCore.mergedValue(["Same", "Same"], mixedPlaceholder: "mixed"), "Same")
        XCTAssertEqual(AudioMetadataMergeCore.mergedValue(["Same", "Other"], mixedPlaceholder: "mixed"), "mixed")
    }

    func testAudioFileFingerprintEqualityAndHashingTrackEveryRevisionField() {
        func makeFingerprint(
            path: String = "/Music/Album/Track.flac",
            size: UInt64 = 1_048_576,
            modificationDate: Date = Date(timeIntervalSinceReferenceDate: 800_000_000),
            fileSystemNumber: UInt64? = 16_777_219,
            fileNumber: UInt64? = 42
        ) -> AudioFileFingerprint {
            AudioFileFingerprint(
                normalizedPath: path,
                fileSize: size,
                contentModificationDate: modificationDate,
                fileSystemNumber: fileSystemNumber,
                fileNumber: fileNumber
            )
        }

        let reference = makeFingerprint()
        let sameRevision = makeFingerprint()

        XCTAssertEqual(reference, sameRevision)
        XCTAssertEqual(reference.hashValue, sameRevision.hashValue)
        XCTAssertEqual(Set([reference, sameRevision]).count, 1)

        let changedRevisions = [
            makeFingerprint(path: "/Music/Album/track.flac"),
            makeFingerprint(size: 1_048_577),
            makeFingerprint(modificationDate: Date(timeIntervalSinceReferenceDate: 800_000_001)),
            makeFingerprint(fileSystemNumber: 16_777_220),
            makeFingerprint(fileNumber: 43),
            makeFingerprint(fileSystemNumber: nil, fileNumber: nil)
        ]

        for changedRevision in changedRevisions {
            XCTAssertNotEqual(reference, changedRevision)
            XCTAssertEqual(Set([reference, changedRevision]).count, 2)
        }
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

private struct FixedSeedGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        precondition(range.lowerBound <= range.upperBound)
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    mutating func bool() -> Bool {
        next() & 1 == 0
    }
}

private func providerFile(_ id: String, title: String, track: String) -> ProviderFileFixture {
    ProviderFileFixture(id: id, title: title, trackNumber: track)
}

private func itunesFile(
    _ id: String,
    title: String,
    artist: String,
    album: String,
    trackNumber: String
) -> iTunesProviderFileInput {
    iTunesProviderFileInput(
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
