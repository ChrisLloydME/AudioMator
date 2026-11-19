import XCTest
@testable import AudioMator

final class TextEditPipelineTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")

    func testUppercaseTransformsAllLetters() {
        XCTAssertEqual(
            TextCaseTransformation.uppercase.applied(to: "quiet storm 02", locale: locale),
            "QUIET STORM 02"
        )
    }

    func testLowercaseTransformsAllLetters() {
        XCTAssertEqual(
            TextCaseTransformation.lowercase.applied(to: "QUIET Storm 02", locale: locale),
            "quiet storm 02"
        )
    }

    func testTitleCaseCapitalizesEachWord() {
        XCTAssertEqual(
            TextCaseTransformation.titleCase.applied(to: "quiet storm: late night mix", locale: locale),
            "Quiet Storm: Late Night Mix"
        )
    }

    func testCapitalizeFirstLetterPreservesExistingRemainder() {
        XCTAssertEqual(
            TextCaseTransformation.capitalizeFirstLetter.applied(to: "  (live) quiet STORM", locale: locale),
            "  (Live) quiet STORM"
        )
    }

    func testSentenceCaseLowercasesRemainder() {
        XCTAssertEqual(
            TextCaseTransformation.sentenceCase.applied(to: "  (LIVE) QUIET STORM", locale: locale),
            "  (Live) quiet storm"
        )
    }

    func testTransformationSupportsLocaleSpecificCasing() {
        let turkishLocale = Locale(identifier: "tr_TR")

        XCTAssertEqual(
            TextCaseTransformation.uppercase.applied(to: "istanbul", locale: turkishLocale),
            "İSTANBUL"
        )
    }

    func testFindReplacementReplacesAllLiteralMatches() {
        let replacement = TextFindReplacement(findText: "mix", replacementText: "version")

        XCTAssertEqual(
            replacement.applied(to: "radio mix / club mix", locale: locale),
            "radio version / club version"
        )
    }

    func testFindReplacementCanMatchCase() {
        let replacement = TextFindReplacement(
            findText: "mix",
            replacementText: "version",
            options: TextFindReplacementOptions(matchesCase: true)
        )

        XCTAssertEqual(
            replacement.applied(to: "radio mix / club Mix", locale: locale),
            "radio version / club Mix"
        )
    }

    func testFindReplacementCanMatchWholeText() {
        let replacement = TextFindReplacement(
            findText: "mix",
            replacementText: "version",
            options: TextFindReplacementOptions(matchesWholeText: true)
        )

        XCTAssertEqual(replacement.applied(to: "mix", locale: locale), "version")
        XCTAssertEqual(replacement.applied(to: "radio mix", locale: locale), "radio mix")
    }

    func testFindReplacementWithEmptyFindTextIsNoOp() {
        let replacement = TextFindReplacement(findText: "", replacementText: "version")

        XCTAssertEqual(replacement.applied(to: "radio mix", locale: locale), "radio mix")
    }

    func testTrimEdgesRemovesLeadingAndTrailingWhitespace() {
        XCTAssertEqual(
            TextEditPipelineStep.trimEdges(.whitespacesAndNewlines)
                .applied(to: " \n Test \t", context: TextEditPipelineContext(locale: locale)),
            "Test"
        )
    }

    func testInsertTextCanPrependAndAppend() {
        XCTAssertEqual(
            TextEditPipelineStep.insertText("[Demo] ", position: .prefix)
                .applied(to: "Track", context: TextEditPipelineContext(locale: locale)),
            "[Demo] Track"
        )
        XCTAssertEqual(
            TextEditPipelineStep.insertText(" (Live)", position: .suffix)
                .applied(to: "Track", context: TextEditPipelineContext(locale: locale)),
            "Track (Live)"
        )
    }

    func testArrayTransformMapsEveryValueIndependentlyAndPreservesOrder() {
        let pipeline = TextEditPipeline(steps: [.insertText("P-", position: .prefix)])

        XCTAssertEqual(
            pipeline.applying(
                to: ["Alpha", "", "line one\nline two"],
                context: TextEditPipelineContext(locale: locale)
            ),
            ["P-Alpha", "P-", "P-line one\nline two"]
        )
    }

    func testArrayTransformKeepsDuplicatesAndEmptyInput() {
        let pipeline = TextEditPipeline(steps: [.transformCase(.uppercase)])

        XCTAssertEqual(
            pipeline.applying(to: ["dup", "dup"], context: TextEditPipelineContext(locale: locale)),
            ["DUP", "DUP"]
        )
        XCTAssertEqual(
            pipeline.applying(to: [], context: TextEditPipelineContext(locale: locale)),
            []
        )
    }

    func testArrayWholeValueMatchAppliesPerElement() {
        let pipeline = TextEditPipeline(steps: [
            .replaceText(TextFindReplacement(
                findText: "Alpha",
                replacementText: "Changed",
                options: TextFindReplacementOptions(matchesCase: false, matchesWholeText: true)
            ))
        ])

        XCTAssertEqual(
            pipeline.applying(
                to: ["Alpha", "Beta"],
                context: TextEditPipelineContext(locale: locale)
            ),
            ["Changed", "Beta"]
        )
    }

    func testPipelineAppliesStepsInOrder() {
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
}
