import XCTest
import TagLibAudioMetadata
@testable import AudioMator

/// Presentation/state coverage for the four independent date intents.
@MainActor
final class IndependentDateIntentTests: XCTestCase {
    private func makeFile(
        id: UUID = UUID(),
        year: String = "",
        date: String = "",
        releaseDate: String = "",
        originalReleaseDate: String = ""
    ) -> AudioFile {
        AudioFileTestFactory.make(
            id: id,
            year: year,
            date: date,
            releaseDate: releaseDate,
            originalReleaseDate: originalReleaseDate
        )
    }

    func testSingleEditPayloadTracksUnchangedSetAndRemoveIndependently() {
        let file = makeFile(
            year: "2004",
            date: "2008-03-04",
            releaseDate: "2017-06-09",
            originalReleaseDate: "1999-11-12"
        )

        var edit = SingleFileEditModel(from: file)
        XCTAssertTrue(MetadataEditPayload(edit, comparedTo: file).changedFields.isEmpty)

        edit.date = "2008-03-05"
        var payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.changedFields, [.standaloneDate])
        XCTAssertEqual(
            TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields,
            [.standaloneDate: .text("2008-03-05")]
        )
        XCTAssertEqual(payload.year, "2004")
        XCTAssertEqual(payload.releaseDate, "2017-06-09")
        XCTAssertEqual(payload.originalReleaseDate, "1999-11-12")

        edit = SingleFileEditModel(from: file)
        edit.date = ""
        payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.changedFields, [.standaloneDate])
        XCTAssertEqual(
            TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields,
            [.standaloneDate: .remove]
        )

        edit = SingleFileEditModel(from: file)
        edit.year = "2005"
        payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.changedFields, [.year])
        XCTAssertEqual(
            TagLibAudioMetadataPipeline.metadataPatchForWrite(from: payload).fields,
            [.year: .text("2005")]
        )

        edit = SingleFileEditModel(from: file)
        edit.releaseDate = "2018-01-01"
        payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.changedFields, [.releaseDate])

        edit = SingleFileEditModel(from: file)
        edit.originalReleaseDate = "2000"
        payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.changedFields, [.originalReleaseDate])
    }

    func testMultiEditTracksMixedStateAndAppliesOnlyTheEditedDate() {
        let first = makeFile(year: "2004", date: "2008-03-04", releaseDate: "2017-06-09")
        let second = makeFile(year: "2005", date: "2008-03-04", releaseDate: "2019-04-03")

        var multi = MultiFileEditModel(files: [first, second])
        XCTAssertTrue(multi.mixedTextFields.contains(.year))
        XCTAssertFalse(multi.mixedTextFields.contains(.date))
        XCTAssertTrue(multi.mixedTextFields.contains(.releaseDate))
        XCTAssertNil(multi.placeholder(for: .date))
        XCTAssertNotNil(multi.placeholder(for: .year))

        multi.setText("2009-01-02", for: .date)
        let applied = multi.applyingChanges(to: first)
        XCTAssertEqual(applied.date, "2009-01-02")
        XCTAssertEqual(applied.year, "2004")
        XCTAssertEqual(applied.releaseDate, "2017-06-09")
        XCTAssertEqual(applied.originalReleaseDate, "")

        let payload = MetadataEditPayload(applied, comparedTo: first)
        XCTAssertEqual(payload.changedFields, [.standaloneDate])
        XCTAssertEqual(payload.date, "2009-01-02")
    }

    func testProviderReleaseDateApplyLeavesYearDateAndOriginalUntouched() {
        let file = makeFile(
            year: "2004",
            date: "2008-03-04",
            releaseDate: "2017-06-09",
            originalReleaseDate: "1999-11-12"
        )

        var iTunesEdit = SingleFileEditModel(from: file)
        iTunesTagWriteField.releaseDate.apply("2020-02-03", to: &iTunesEdit)
        let iTunesPayload = MetadataEditPayload(iTunesEdit, comparedTo: file)
        XCTAssertEqual(iTunesPayload.changedFields, [.releaseDate])
        XCTAssertEqual(iTunesPayload.releaseDate, "2020-02-03")
        XCTAssertEqual(iTunesPayload.year, "2004")
        XCTAssertEqual(iTunesPayload.date, "2008-03-04")
        XCTAssertEqual(iTunesPayload.originalReleaseDate, "1999-11-12")

        var musicBrainzEdit = SingleFileEditModel(from: file)
        MusicBrainzTagWriteField.releaseDate.apply("2021-05-06", to: &musicBrainzEdit)
        let musicBrainzPayload = MetadataEditPayload(musicBrainzEdit, comparedTo: file)
        XCTAssertEqual(musicBrainzPayload.changedFields, [.releaseDate])
        XCTAssertEqual(musicBrainzPayload.year, "2004")
        XCTAssertEqual(musicBrainzPayload.date, "2008-03-04")
        XCTAssertEqual(musicBrainzPayload.originalReleaseDate, "1999-11-12")
    }

    func testMultiEditContainerValueIsTrackedAndApplied() {
        let mp4 = URL(fileURLWithPath: "/tmp/multi-container.m4a")
        let first = AudioFileTestFactory.make(url: mp4)
        let second = AudioFileTestFactory.make(url: mp4)
        var multi = MultiFileEditModel(files: [first, second])
        XCTAssertFalse(multi.hasUnsavedChanges)

        multi.setContainerValue(.integer(0), for: .tvSeason)
        XCTAssertTrue(multi.hasUnsavedChanges)
        XCTAssertTrue(multi.hasPendingChanges(excluding: nil))

        let applied = multi.applyingChanges(to: first)
        XCTAssertEqual(applied.containerValues[.tvSeason], .integer(0))
        XCTAssertNil(applied.containerValues[.itunesGapless])
    }

    func testContainerFieldPresenceRoundTripsTypedValues() {
        let file = makeFile().withUpdatedURL(
            URL(fileURLWithPath: "/tmp/container.m4a"),
            fileFingerprint: nil,
            metadataFileVersion: nil
        )
        var edit = SingleFileEditModel(from: file)
        edit.containerValues[.tvSeason] = .integer(0)
        edit.containerValues[.itunesGapless] = .boolean(false)
        edit.containerValues[.itunesMediaType] = .integer(4)
        edit.containerValues[.director] = .text("Someone")

        let payload = MetadataEditPayload(edit, comparedTo: file)
        XCTAssertEqual(payload.containerFields[.tvSeason], .integer(0))
        XCTAssertEqual(payload.containerFields[.itunesGapless], .boolean(false))
        XCTAssertEqual(payload.containerFields[.itunesMediaType], .integer(4))
        XCTAssertEqual(payload.containerFields[.director], .text("Someone"))
        XCTAssertEqual(Set(payload.changedFields), [.tvSeason, .itunesGapless, .itunesMediaType, .director])

        // Selecting a read-only RATE value is display-only and must not create
        // a write intent.
        var rateEdit = SingleFileEditModel(from: file)
        rateEdit.containerValues[.rate] = .integer(5)
        XCTAssertTrue(MetadataEditPayload(rateEdit, comparedTo: file).changedFields.isEmpty)
    }
}
