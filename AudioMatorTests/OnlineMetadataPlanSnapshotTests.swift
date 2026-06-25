import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class OnlineMetadataPlanSnapshotTests: XCTestCase {
    func testWorkbenchViewsApplyTheDisplayedPlanInsteadOfReadingStorePlanAgain() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcePaths = [
            "AudioMator/Features/ITunesBrowser/Views/ITunesTaggingWorkbenchView.swift",
            "AudioMator/Features/MusicBrainzBrowser/Views/MusicBrainzTaggingWorkbenchView.swift"
        ]

        for sourcePath in sourcePaths {
            let source = try String(
                contentsOf: repositoryURL.appendingPathComponent(sourcePath),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains("applyTags(plan: plan)"), sourcePath)
            XCTAssertFalse(source.contains("let entries = store.plan.writeEntries"), sourcePath)
        }
    }

    func testITunesWorkbenchStoreKeepsCapturedPlanIndependentFromLaterSelections() throws {
        let fileID = UUID()
        let fingerprint = syntheticFingerprint(path: "/tmp/itunes-store.mp3")
        let file = AudioFileTestFactory.make(
            id: fileID,
            url: URL(fileURLWithPath: fingerprint.normalizedPath),
            title: "Local",
            fileFingerprint: fingerprint
        )
        let input = makeITunesInput(id: fileID.uuidString)
        let track = makeITunesTrack(title: "Remote")
        let detail = makeITunesDetail(track: track)
        let preview = ITunesAlbumMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [
                ITunesAlbumMatchAssignment(
                    id: "assignment",
                    file: input,
                    track: track,
                    score: 1,
                    reason: "test"
                )
            ],
            unmatchedFiles: [],
            unassignedTracks: [],
            overallScore: 1
        )
        let store = ITunesTaggingWorkbenchStore(
            detail: detail,
            preview: preview,
            loadedFiles: [file]
        )

        let displayedPlan = store.plan
        store.setFieldSelected(false, for: .title)

        XCTAssertEqual(displayedPlan.writeEntries.first?.values[.title], "Remote")
        XCTAssertEqual(displayedPlan.writeEntries.first?.expectedFileFingerprint, fingerprint)
        XCTAssertNil(store.plan.writeEntries.first?.values[.title])
    }

    func testMusicBrainzWorkbenchStoreKeepsCapturedPlanIndependentFromLaterSelections() throws {
        let fileID = UUID()
        let fingerprint = syntheticFingerprint(path: "/tmp/musicbrainz-store.flac")
        let file = AudioFileTestFactory.make(
            id: fileID,
            url: URL(fileURLWithPath: fingerprint.normalizedPath),
            title: "Local",
            fileFingerprint: fingerprint
        )
        let input = makeMusicBrainzInput(id: fileID.uuidString)
        let matchTrack = MusicBrainzReleaseMatchTrack(
            id: "track-id",
            mediumTitle: "",
            mediumFormat: "Digital Media",
            mediumPosition: 1,
            mediumTrackCount: 1,
            releaseMediumCount: 1,
            number: "1",
            title: "Remote",
            artistCredit: "Artist",
            durationMilliseconds: nil,
            recordingID: "",
            isrcs: []
        )
        let release = makeMusicBrainzRelease()
        let preview = MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [
                MusicBrainzReleaseMatchAssignment(
                    id: "assignment",
                    file: input,
                    track: matchTrack,
                    score: 1,
                    reason: "test"
                )
            ],
            unmatchedFiles: [],
            unassignedTracks: [],
            averageTrackScore: 1,
            overallScore: 1,
            selectionLooksMixed: false
        )
        let store = MusicBrainzTaggingWorkbenchStore(
            release: release,
            preview: preview,
            loadedFiles: [file],
            browserStore: MusicBrainzBrowserStore()
        )

        let displayedPlan = store.plan
        store.setFieldSelected(false, for: .title)

        XCTAssertEqual(displayedPlan.writeEntries.first?.values[.title], "Remote")
        XCTAssertEqual(displayedPlan.writeEntries.first?.expectedFileFingerprint, fingerprint)
        XCTAssertNil(store.plan.writeEntries.first?.values[.title])
    }

    func testProviderPlansCaptureDisplayedValuesAndFileFingerprint() throws {
        let fixture = try TemporaryFingerprintFixture()
        defer { fixture.remove() }

        let fileID = UUID()
        let file = AudioFileTestFactory.make(
            id: fileID,
            url: fixture.fileURL,
            title: "Local",
            fileFingerprint: fixture.fingerprint
        )

        let iTunesPlan = ITunesTaggingPlan(rows: [
            ITunesTaggingPlanRow(
                fileInput: makeITunesInput(id: fileID.uuidString),
                file: file,
                track: nil,
                changes: [
                    ITunesTaggingFieldChange(
                        field: .title,
                        localValue: "Local",
                        remoteValue: "Displayed iTunes Value",
                        status: .different,
                        willWrite: true
                    )
                ],
                issueMessage: nil
            )
        ])
        let musicBrainzPlan = MusicBrainzTaggingPlan(rows: [
            MusicBrainzTaggingPlanRow(
                fileInput: makeMusicBrainzInput(id: fileID.uuidString),
                file: file,
                track: nil,
                changes: [
                    MusicBrainzTaggingFieldChange(
                        field: .title,
                        localValue: "Local",
                        remoteValue: "Displayed MusicBrainz Value",
                        status: .different,
                        willWrite: true
                    )
                ],
                issueMessage: nil
            )
        ])

        let displayedITunesEntry = try XCTUnwrap(iTunesPlan.writeEntries.first)
        let displayedMusicBrainzEntry = try XCTUnwrap(musicBrainzPlan.writeEntries.first)

        XCTAssertEqual(displayedITunesEntry.values[.title], "Displayed iTunes Value")
        XCTAssertEqual(displayedMusicBrainzEntry.values[.title], "Displayed MusicBrainz Value")
        XCTAssertEqual(displayedITunesEntry.expectedFileFingerprint, fixture.fingerprint)
        XCTAssertEqual(displayedMusicBrainzEntry.expectedFileFingerprint, fixture.fingerprint)
    }

    func testProviderApplyRejectsFileChangedAfterDisplayedPlan() async throws {
        let fixture = try TemporaryFingerprintFixture()
        defer { fixture.remove() }

        let fileID = UUID()
        let file = AudioFileTestFactory.make(
            id: fileID,
            url: fixture.fileURL,
            title: "Local",
            fileFingerprint: fixture.fingerprint
        )
        let pipeline = FingerprintRecordingMetadataPipeline(reloadedFile: file)
        let viewModel = AudioViewModel(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])

        try Data(repeating: 0x42, count: 32).write(to: fixture.fileURL, options: .atomic)

        await viewModel.applyITunesTaggingPlan([
            ITunesTaggingWriteEntry(
                fileID: fileID,
                fileName: fixture.fileURL.lastPathComponent,
                values: [.title: "Displayed iTunes Value"],
                expectedFileFingerprint: fixture.fingerprint
            )
        ])

        XCTAssertEqual(pipeline.metadataWriteCount, 0)
        XCTAssertEqual(viewModel.files.first?.title, "Local")
    }

    private func makeITunesInput(id: String) -> ITunesFileSearchInput {
        ITunesFileSearchInput(
            id: id,
            displayTitle: "Local",
            title: "Local",
            artist: "",
            albumArtist: "",
            album: "",
            trackNumber: "",
            discNumber: "",
            trackTotal: 0,
            durationMilliseconds: nil,
            releaseDate: "",
            barcode: "",
            itunesAlbumID: "",
            itunesArtistID: "",
            itunesCatalogID: ""
        )
    }

    private func makeMusicBrainzInput(id: String) -> MusicBrainzFileSearchInput {
        MusicBrainzFileSearchInput(
            id: id,
            displayTitle: "Local",
            title: "Local",
            artist: "",
            albumArtist: "",
            album: "",
            trackNumber: ""
        )
    }

    private func makeITunesTrack(title: String) -> ITunesTrackResult {
        ITunesTrackResult(
            trackID: 300,
            collectionID: 100,
            artistID: 200,
            collectionArtistID: 201,
            trackName: title,
            artistName: "Artist",
            collectionArtistName: "Artist",
            collectionName: "Album",
            trackNumber: 1,
            trackCount: 1,
            discNumber: 1,
            discCount: 1,
            durationMilliseconds: nil,
            releaseDate: "2024-01-01",
            primaryGenreName: "Genre",
            country: "USA",
            copyright: "",
            contentAdvisoryRating: "",
            kind: "song",
            wrapperType: "track",
            trackExplicitness: "notExplicit",
            collectionExplicitness: "notExplicit",
            trackViewURL: nil,
            collectionViewURL: nil,
            artistViewURL: nil
        )
    }

    private func makeITunesDetail(track: ITunesTrackResult) -> ITunesAlbumDetail {
        ITunesAlbumDetail(
            album: ITunesAlbumResult(
                collectionID: 100,
                artistID: 200,
                collectionArtistID: 201,
                collectionName: "Album",
                artistName: "Artist",
                collectionArtistName: "Artist",
                trackCount: 1,
                releaseDate: "2024-01-01",
                primaryGenreName: "Genre",
                country: "USA",
                copyright: "",
                contentAdvisoryRating: "",
                collectionExplicitness: "notExplicit",
                collectionViewURL: nil,
                artistViewURL: nil,
                selectionMatchPreview: nil,
                selectionMatchScore: nil
            ),
            tracks: [track],
            selectionMatchPreview: nil
        )
    }

    private func makeMusicBrainzRelease() -> MusicBrainzReleaseDetail {
        MusicBrainzReleaseDetail(
            id: "release-id",
            title: "Album",
            artistCredit: "Artist",
            date: "2024-01-01",
            country: "US",
            status: "Official",
            barcode: "",
            packaging: "",
            asin: "",
            quality: "",
            language: "",
            script: "",
            annotation: "",
            genres: [],
            tags: [],
            releaseGroupTitle: "Album",
            releaseGroupID: "release-group-id",
            releaseGroupPrimaryType: "Album",
            releaseGroupSecondaryTypes: [],
            labels: [],
            media: [
                MusicBrainzReleaseDetail.Medium(
                    id: "medium-id",
                    title: "",
                    format: "Digital Media",
                    trackCount: 1,
                    discIDs: [],
                    tracks: [
                        MusicBrainzReleaseDetail.Medium.Track(
                            id: "track-id",
                            number: "1",
                            title: "Remote",
                            artistCredit: "Artist",
                            durationMilliseconds: nil,
                            recordingID: "",
                            isrcs: []
                        )
                    ]
                )
            ],
            selectionMatchPreview: nil
        )
    }

    private func syntheticFingerprint(path: String) -> AudioFileFingerprint {
        AudioFileFingerprint(
            normalizedPath: path,
            fileSize: 1,
            contentModificationDate: .distantPast,
            fileSystemNumber: 1,
            fileNumber: 1
        )
    }
}

private struct TemporaryFingerprintFixture {
    let directoryURL: URL
    let fileURL: URL
    let fingerprint: AudioFileFingerprint

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorPlanSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("fixture.mp3")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 16).write(to: fileURL)
        fingerprint = try AudioFileFingerprint.capture(at: fileURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private final class FingerprintRecordingMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let lock = NSLock()
    private let reloadedFile: AudioFile
    private var recordedMetadataWriteCount = 0

    init(reloadedFile: AudioFile) {
        self.reloadedFile = reloadedFile
    }

    var metadataWriteCount: Int {
        lock.withLock { recordedMetadataWriteCount }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        reloadedFile
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }
    nonisolated func rawMetadataPropertyMap(for url: URL) throws -> [String: String] { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        lock.withLock { recordedMetadataWriteCount += 1 }
        return AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPropertyMap(
        _ propertyMap: [String: String],
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
#endif
