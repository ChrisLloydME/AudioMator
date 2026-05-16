import XCTest
@testable import AudioMator

final class TextCaseTransformationTests: XCTestCase {
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

    func testPipelineAppliesStepsInOrder() {
        let pipeline = TextEditPipeline(steps: [
            .transformCase(.lowercase),
            .transformCase(.capitalizeFirstLetter)
        ])

        XCTAssertEqual(
            pipeline.applying(
                to: "QUIET STORM",
                context: TextEditPipelineContext(locale: locale)
            ),
            "Quiet storm"
        )
    }
}
