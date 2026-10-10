import XCTest
@testable import AudioMator

final class MetadataFieldTransferTests: XCTestCase {
    func testCopyUsesEachFilesOwnValueAndDeduplicatesSelection() throws {
        let first = AudioFileTestFactory.make(title: "  曲名\nFirst  ", artist: "Old Artist")
        let second = AudioFileTestFactory.make(title: "Second", artist: "Another Artist")
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .artist, operation: .copy, targetFiles: [first, second, first]
        )

        XCTAssertNil(plan.validationMessage)
        XCTAssertEqual(plan.writeEntries.map(\.fileID), [first.id, second.id])
        XCTAssertEqual(plan.writeEntries.map(\.values), [[.artist: first.title], [.artist: second.title]])
        XCTAssertEqual(plan.writeEntries.first?.expectedFileFingerprint, first.fileFingerprint)
        XCTAssertEqual(plan.rows.first?.changes.first?.currentValue, "Old Artist")
        XCTAssertTrue(try XCTUnwrap(plan.writeEntries.first).preservingNumberPairComponents)
    }

    func testCutStillClearsSourceWhenDestinationAlreadyMatches() {
        let file = AudioFileTestFactory.make(title: "Same", artist: "Same")
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .artist, operation: .cut, targetFiles: [file]
        )

        XCTAssertTrue(plan.canApply)
        XCTAssertEqual(plan.writeEntries.first?.values, [.title: ""])
        XCTAssertEqual(plan.rows.first?.changes.map(\.willWrite), [false, true])
    }

    func testEmptySourcesAreSkippedAndEqualCopiesAreUnchanged() {
        let empty = AudioFileTestFactory.make(artist: "Keep Artist")
        let equal = AudioFileTestFactory.make(title: "Same", artist: "Same")
        for operation in MetadataFieldTransferOperation.allCases {
            let plan = MetadataFieldTransferPlanner.makePlan(
                source: .title, destination: .artist, operation: operation, targetFiles: [empty]
            )
            XCTAssertFalse(plan.canApply)
            XCTAssertEqual(plan.rows.first?.status, .unchanged)
            XCTAssertNotNil(plan.rows.first?.issueMessage)
            XCTAssertEqual(plan.issueCount, 0)
        }
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .artist, operation: .copy, targetFiles: [equal]
        )
        XCTAssertEqual(plan.rows.first?.status, .unchanged)
        XCTAssertFalse(plan.canApply)
    }

    func testSameAndNonMetadataFieldsCannotBeTransferred() {
        let file = AudioFileTestFactory.make(title: "Keep")
        let pairs: [(MetadataExchangeField, MetadataExchangeField)] = [
            (.title, .title), (.fileName, .title), (.title, .path)
        ]
        for (source, destination) in pairs {
            let plan = MetadataFieldTransferPlanner.makePlan(
                source: source, destination: destination, operation: .cut, targetFiles: [file]
            )
            XCTAssertNotNil(plan.validationMessage)
            XCTAssertFalse(plan.canApply)
            XCTAssertTrue(plan.rows.isEmpty)
        }
    }

    func testInvalidDestinationNeverProducesSourceClearAndValidFilesRemainReady() {
        for value in ["Not a number", "7/12", "-1", "2147483648", "Bad\0Text"] {
            let invalid = AudioFileTestFactory.make(title: value)
            let valid = AudioFileTestFactory.make(title: "007", track: 1, trackTotal: 12)
            let plan = MetadataFieldTransferPlanner.makePlan(
                source: .title, destination: .trackNumber, operation: .cut, targetFiles: [invalid, valid]
            )
            XCTAssertEqual(plan.rows.first?.status, .parseError, value)
            XCTAssertNil(plan.rows.first?.writeEntry, value)
            XCTAssertEqual(plan.writeEntries.map(\.fileID), [valid.id], value)
            XCTAssertEqual(plan.writeEntries.first?.values, [.title: "", .trackNumber: "007"], value)
            XCTAssertEqual(plan.issueCount, 1)
        }
    }

    func testUnavailableFileCannotBeCut() {
        let file = AudioFileTestFactory.make(title: "Keep", includeDefaultFileFingerprint: false)
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .artist, operation: .cut, targetFiles: [file]
        )
        XCTAssertEqual(plan.rows.first?.status, .sourceUnavailable)
        XCTAssertFalse(plan.canApply)
        XCTAssertNil(plan.rows.first?.writeEntry)
    }

    func testContentAdvisoryIsValidatedAndCanonicalized() {
        let file = AudioFileTestFactory.make(title: "Explicit")
        let plan = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .contentAdvisory, operation: .cut, targetFiles: [file]
        )
        XCTAssertEqual(plan.writeEntries.first?.values, [.title: "", .contentAdvisory: "1"])
        let invalid = MetadataFieldTransferPlanner.makePlan(
            source: .title, destination: .contentAdvisory, operation: .cut,
            targetFiles: [AudioFileTestFactory.make(title: "Unrecognized")]
        )
        XCTAssertFalse(invalid.canApply)
    }

    func testTrackAndDiscFieldsTransferIndependentlyAndPreserveTextIntent() throws {
        let file = AudioFileTestFactory.make(
            title: "004", track: 7, trackTotal: 12, disc: 2, discTotal: 3,
            trackNumberText: "007/012", discNumberText: "02/03"
        )
        let cases: [(MetadataExchangeField, MetadataExchangeField, String, String)] = [
            (.trackNumber, .comment, "/12", "02/03"),
            (.discNumber, .comment, "007/012", "/3"),
            (.title, .trackNumber, "004/012", "02/03"),
            (.trackTotal, .trackNumber, "012", "02/03"),
            (.trackNumber, .trackTotal, "/7", "02/03"),
            (.discTotal, .discNumber, "007/012", "03"),
            (.discNumber, .discTotal, "007/012", "/2")
        ]
        for (source, destination, expectedTrack, expectedDisc) in cases {
            let plan = MetadataFieldTransferPlanner.makePlan(
                source: source, destination: destination, operation: .cut, targetFiles: [file]
            )
            let entry = try XCTUnwrap(plan.writeEntries.first)
            var edit = SingleFileEditModel(from: file)
            for field in MetadataExchangeField.allCases {
                guard let value = entry.values[field] else { continue }
                field.applyImportedValue(value, to: &edit, preservingNumberPairComponents: entry.preservingNumberPairComponents)
            }
            XCTAssertEqual(edit.trackNumberFieldText + "/" + edit.trackTotalFieldText, expectedTrack.contains("/") ? expectedTrack : expectedTrack + "/")
            XCTAssertEqual(edit.discNumberFieldText + "/" + edit.discTotalFieldText, expectedDisc.contains("/") ? expectedDisc : expectedDisc + "/")
            if destination == .comment {
                XCTAssertEqual(edit.comment, source == .trackNumber ? "007" : "02")
            }
        }
    }
}
