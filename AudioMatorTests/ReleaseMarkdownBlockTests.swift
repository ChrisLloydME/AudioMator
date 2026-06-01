import XCTest
@testable import AudioMator

final class ReleaseMarkdownBlockTests: XCTestCase {
    func testParseEmptyMarkdownPreservesExistingSpacerBlockBehavior() {
        XCTAssertEqual(
            ReleaseMarkdownBlock.parse(""),
            [.spacer]
        )
    }

    func testParseHeadingsBulletsIndentedParagraphsAndCollapsedSpacers() {
        let blocks = ReleaseMarkdownBlock.parse(
            """
            # Version 1.2


            - Added search
              * Nested item
              Details line
            ###### Small Heading
            ####### Not a heading
            """
        )

        XCTAssertEqual(
            blocks,
            [
                .heading(level: 1, text: "Version 1.2"),
                .spacer,
                .bullet(indentLevel: 0, text: "Added search"),
                .bullet(indentLevel: 1, text: "Nested item"),
                .paragraph(indentLevel: 1, text: "Details line"),
                .heading(level: 6, text: "Small Heading"),
                .paragraph(indentLevel: 0, text: "####### Not a heading")
            ]
        )
    }

    func testParseNormalizesWindowsLineEndings() {
        XCTAssertEqual(
            ReleaseMarkdownBlock.parse("Title\r\n\r\n+ Fixed\rSubsection"),
            [
                .paragraph(indentLevel: 0, text: "Title"),
                .spacer,
                .bullet(indentLevel: 0, text: "Fixed"),
                .paragraph(indentLevel: 0, text: "Subsection")
            ]
        )
    }
}
