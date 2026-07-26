import AppKit
import SwiftUI
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class OnlineMetadataWorkbenchPerformanceTests: XCTestCase {
    func testLargeReviewAndApplyPagesFinishInitialLayoutWithinBudget() {
        let fixture = makeLargeFixture(trackCount: 200)
        let viewModel = AudioViewModel()
        viewModel.files = fixture.files
        viewModel.setSelectedAudioIDs(Set(fixture.files.map(\.id)))

        let iTunesStore = iTunesTaggingWorkbenchStore(
            detail: fixture.iTunesDetail,
            preview: fixture.iTunesPreview,
            loadedFiles: fixture.files
        )
        let iTunesElapsed = renderAndMeasure(
            iTunesTaggingWorkbenchView(store: iTunesStore, viewModel: viewModel)
        )

        let musicBrainzClient = SuspendedWorkbenchMusicBrainzClient()
        let browserStore = MusicBrainzBrowserStore(
            client: musicBrainzClient,
            detailTimeout: .seconds(30)
        )
        let musicBrainzStore = MusicBrainzTaggingWorkbenchStore(
            release: fixture.musicBrainzRelease,
            preview: fixture.musicBrainzPreview,
            loadedFiles: fixture.files,
            browserStore: browserStore
        )
        let musicBrainzElapsed = renderAndMeasure(
            MusicBrainzTaggingWorkbenchView(store: musicBrainzStore, viewModel: viewModel)
        )
        musicBrainzStore.cancelPendingRecordingLoads()

        XCTAssertLessThan(iTunesElapsed, .seconds(2), "Large iTunes Review & Apply layout blocked the main actor")
        XCTAssertLessThan(musicBrainzElapsed, .seconds(2), "Large MusicBrainz Review & Apply layout blocked the main actor")
    }

    func testMusicBrainzLargeWorkbenchDoesNotStartUnboundedRecordingFanOut() async throws {
        let fixture = makeLargeFixture(trackCount: 200)
        let client = SuspendedWorkbenchMusicBrainzClient()
        let browserStore = MusicBrainzBrowserStore(
            client: client,
            detailTimeout: .seconds(30)
        )
        let store = MusicBrainzTaggingWorkbenchStore(
            release: fixture.musicBrainzRelease,
            preview: fixture.musicBrainzPreview,
            loadedFiles: fixture.files,
            browserStore: browserStore
        )

        try await Task.sleep(for: .milliseconds(150))
        let requestCount = await client.requestCount
        store.cancelPendingRecordingLoads()
        let recoveredStates = fixture.musicBrainzPreview.matchedAssignments.map {
            store.recordingState(for: $0.track.recordingID)
        }

        XCTAssertLessThanOrEqual(
            requestCount,
            4,
            "MusicBrainz API throttling must not leave one in-flight task per album track"
        )
        XCTAssertTrue(recoveredStates.allSatisfy { $0 == .idle })
    }

    func testMusicBrainzRecordingPumpFinishesAfterSuccessFailureAndTimeout() async throws {
        for behavior in [WorkbenchRecordingBehavior.success, .failure, .timeout] {
            let fixture = makeLargeFixture(trackCount: 3)
            let client = ScriptedWorkbenchMusicBrainzClient(behavior: behavior)
            let browserStore = MusicBrainzBrowserStore(
                client: client,
                detailTimeout: behavior == .timeout ? .milliseconds(20) : .seconds(1)
            )
            let store = MusicBrainzTaggingWorkbenchStore(
                release: fixture.musicBrainzRelease,
                preview: fixture.musicBrainzPreview,
                loadedFiles: fixture.files,
                browserStore: browserStore
            )

            try await waitUntil {
                store.recordingPreloadCompletedCount == 3
            }

            let states = fixture.musicBrainzPreview.matchedAssignments.map {
                store.recordingState(for: $0.track.recordingID)
            }
            let requestCount = await client.requestCount
            XCTAssertEqual(requestCount, 3)
            switch behavior {
            case .success:
                XCTAssertTrue(states.allSatisfy {
                    if case .loaded = $0 { return true }
                    return false
                })
            case .failure, .timeout:
                XCTAssertTrue(states.allSatisfy {
                    if case .failed = $0 { return true }
                    return false
                })
            }
        }
    }

    func testAppKitTrackSelectionValuesStayAlignedWithSeparatorMenuItem() {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItem(withTitle: "Unassigned")
        popUp.menu?.addItem(.separator())
        popUp.addItem(withTitle: "Track One")
        popUp.addItem(withTitle: "Track Two")

        let values = OnlineMetadataWorkbenchPopUpMapping.selectionValues(for: [101, 202])

        XCTAssertEqual(values.count, popUp.numberOfItems)
        XCTAssertNil(values[0])
        XCTAssertNil(values[1])
        XCTAssertEqual(values[2], 101)
        XCTAssertEqual(values[3], 202)

        popUp.selectItem(at: 2)
        XCTAssertEqual(popUp.titleOfSelectedItem, "Track One")
        XCTAssertEqual(values[popUp.indexOfSelectedItem], 101)

        popUp.selectItem(at: 3)
        XCTAssertEqual(popUp.titleOfSelectedItem, "Track Two")
        XCTAssertEqual(values[popUp.indexOfSelectedItem], 202)
    }

    func testDeferredSelectionMenuDoesNotBuildOptionsBeforeOpening() {
        let options = (0..<100).map(Option.init(id:))
        let deferredCounter = InvocationCounter()
        let pickerCounter = InvocationCounter()

        render(
            DeferredSelectionMenu(
                options: options,
                selection: .constant(0),
                selectionValue: \.id,
                optionTitle: { option in
                    deferredCounter.count += 1
                    return "Track \(option.id)"
                }
            )
        )

        render(
            Picker("Track", selection: .constant(0)) {
                ForEach(options) { option in
                    CountedPickerOption(option: option, counter: pickerCounter)
                }
            }
            .pickerStyle(.menu)
        )

        XCTAssertLessThan(deferredCounter.count, options.count)
        XCTAssertGreaterThanOrEqual(pickerCounter.count, options.count)
    }

    private func render<Content: View>(_ content: Content) {
        let host = NSHostingView(rootView: content.frame(width: 400, height: 100))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
    }

    private func renderAndMeasure<Content: View>(_ content: Content) -> Duration {
        let host = NSHostingView(rootView: content.frame(width: 980, height: 700))
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 700)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host

        let clock = ContinuousClock()
        let startedAt = clock.now
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        let elapsed = startedAt.duration(to: clock.now)
        window.contentView = nil
        return elapsed
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for MusicBrainz recording pump")
    }

    private func makeLargeFixture(trackCount: Int) -> LargeWorkbenchFixture {
        let files = (1...trackCount).map { index in
            AudioFileTestFactory.make(
                url: URL(fileURLWithPath: "/tmp/workbench-\(index).flac"),
                title: "Local Track \(index)",
                artist: "Local Artist",
                album: "Local Album",
                track: index,
                trackTotal: trackCount,
                disc: 1
            )
        }
        let musicBrainzInputs = files.enumerated().map { offset, file in
            MusicBrainzFileSearchInput(
                id: file.id.uuidString,
                displayTitle: file.url.lastPathComponent,
                title: file.title,
                artist: file.artist,
                albumArtist: file.albumArtist,
                album: file.album,
                trackNumber: String(offset + 1),
                discNumber: "1",
                trackTotal: trackCount,
                durationMilliseconds: nil,
                releaseDate: "",
                isrc: "",
                barcode: ""
            )
        }
        let musicBrainzTracks = (1...trackCount).map { index in
            MusicBrainzReleaseMatchTrack(
                id: "mb-track-\(index)",
                mediumTitle: "",
                mediumFormat: "Digital Media",
                mediumPosition: 1,
                mediumTrackCount: trackCount,
                releaseMediumCount: 1,
                number: String(index),
                title: "Remote Track \(index)",
                artistCredit: "Remote Artist",
                durationMilliseconds: nil,
                recordingID: "mb-recording-\(index)",
                isrcs: []
            )
        }
        let musicBrainzAssignments = zip(musicBrainzInputs, musicBrainzTracks).map { input, track in
            MusicBrainzReleaseMatchAssignment(
                id: "mb-assignment-\(track.id)",
                file: input,
                track: track,
                score: 1,
                reason: "performance fixture"
            )
        }
        let musicBrainzPreview = MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: trackCount,
            matchedAssignments: musicBrainzAssignments,
            unmatchedFiles: [],
            unassignedTracks: [],
            averageTrackScore: 1,
            overallScore: 1,
            selectionLooksMixed: false
        )
        let musicBrainzRelease = MusicBrainzReleaseDetail(
            id: "mb-release",
            title: "Remote Album",
            artistCredit: "Remote Artist",
            date: "2026-01-01",
            country: "US",
            status: "Official",
            barcode: "",
            packaging: "",
            asin: "",
            quality: "",
            language: "eng",
            script: "Latn",
            annotation: "",
            genres: [],
            tags: [],
            releaseGroupTitle: "Remote Album",
            releaseGroupID: "mb-group",
            releaseGroupPrimaryType: "Album",
            releaseGroupSecondaryTypes: [],
            labels: [],
            media: [
                MusicBrainzReleaseDetail.Medium(
                    id: "mb-medium",
                    title: "",
                    format: "Digital Media",
                    trackCount: trackCount,
                    discIDs: [],
                    tracks: musicBrainzTracks.map { track in
                        MusicBrainzReleaseDetail.Medium.Track(
                            id: track.id,
                            number: track.number,
                            title: track.title,
                            artistCredit: track.artistCredit,
                            durationMilliseconds: track.durationMilliseconds,
                            recordingID: track.recordingID,
                            isrcs: track.isrcs
                        )
                    }
                )
            ],
            selectionMatchPreview: musicBrainzPreview
        )

        let iTunesInputs = files.enumerated().map { offset, file in
            iTunesFileSearchInput(
                id: file.id.uuidString,
                displayTitle: file.url.lastPathComponent,
                title: file.title,
                artist: file.artist,
                albumArtist: file.albumArtist,
                album: file.album,
                trackNumber: String(offset + 1),
                discNumber: "1",
                trackTotal: trackCount,
                durationMilliseconds: nil,
                releaseDate: "",
                barcode: "",
                itunesAlbumID: "",
                itunesArtistID: "",
                itunesCatalogID: ""
            )
        }
        let iTunesTracks = (1...trackCount).map { index in
            iTunesTrackResult(
                trackID: index,
                collectionID: 10,
                artistID: 20,
                collectionArtistID: 20,
                trackName: "Remote Track \(index)",
                artistName: "Remote Artist",
                collectionArtistName: "Remote Artist",
                collectionName: "Remote Album",
                trackNumber: index,
                trackCount: trackCount,
                discNumber: 1,
                discCount: 1,
                durationMilliseconds: nil,
                releaseDate: "2026-01-01",
                primaryGenreName: "Rock",
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
        let iTunesAlbum = iTunesAlbumResult(
            collectionID: 10,
            artistID: 20,
            collectionArtistID: 20,
            collectionName: "Remote Album",
            artistName: "Remote Artist",
            collectionArtistName: "Remote Artist",
            trackCount: trackCount,
            releaseDate: "2026-01-01",
            primaryGenreName: "Rock",
            country: "USA",
            copyright: "",
            contentAdvisoryRating: "",
            collectionExplicitness: "notExplicit",
            collectionViewURL: nil,
            artistViewURL: nil,
            selectionMatchPreview: nil,
            selectionMatchScore: nil
        )
        let iTunesAssignments = zip(iTunesInputs, iTunesTracks).map { input, track in
            iTunesAlbumMatchAssignment(
                id: "itunes-assignment-\(track.trackID)",
                file: input,
                track: track,
                score: 1,
                reason: "performance fixture"
            )
        }
        let iTunesPreview = iTunesAlbumMatchPreview(
            totalSelectedFiles: trackCount,
            matchedAssignments: iTunesAssignments,
            unmatchedFiles: [],
            unassignedTracks: [],
            overallScore: 1
        )

        return LargeWorkbenchFixture(
            files: files,
            musicBrainzRelease: musicBrainzRelease,
            musicBrainzPreview: musicBrainzPreview,
            iTunesDetail: iTunesAlbumDetail(
                album: iTunesAlbum,
                tracks: iTunesTracks,
                selectionMatchPreview: iTunesPreview
            ),
            iTunesPreview: iTunesPreview
        )
    }
}

private struct LargeWorkbenchFixture {
    let files: [AudioFile]
    let musicBrainzRelease: MusicBrainzReleaseDetail
    let musicBrainzPreview: MusicBrainzReleaseMatchPreview
    let iTunesDetail: iTunesAlbumDetail
    let iTunesPreview: iTunesAlbumMatchPreview
}

private actor SuspendedWorkbenchMusicBrainzClient: MusicBrainzBrowserClient {
    private(set) var requestCount = 0

    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        .recordings([])
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail {
        requestCount += 1
        try await Task.sleep(for: .seconds(30))
        throw CancellationError()
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        throw CancellationError()
    }
}

private enum WorkbenchRecordingBehavior: Sendable {
    case success
    case failure
    case timeout
}

private enum WorkbenchRecordingClientError: Error {
    case syntheticFailure
}

private actor ScriptedWorkbenchMusicBrainzClient: MusicBrainzBrowserClient {
    private(set) var requestCount = 0
    private let behavior: WorkbenchRecordingBehavior

    init(behavior: WorkbenchRecordingBehavior) {
        self.behavior = behavior
    }

    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        .recordings([])
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail {
        requestCount += 1
        switch behavior {
        case .success:
            return MusicBrainzRecordingDetail(
                id: id,
                title: "Remote Track",
                artistCredit: "Remote Artist",
                disambiguation: "",
                firstReleaseDate: "2026-01-01",
                durationMilliseconds: nil,
                annotation: "",
                isrcs: [],
                genres: [],
                tags: [],
                rating: nil,
                releases: fallbackReleases,
                relationshipGroups: []
            )
        case .failure:
            throw WorkbenchRecordingClientError.syntheticFailure
        case .timeout:
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        throw WorkbenchRecordingClientError.syntheticFailure
    }
}

private struct Option: Identifiable {
    let id: Int
}

@MainActor
private final class InvocationCounter {
    var count = 0
}

private struct CountedPickerOption: View {
    let option: Option
    let counter: InvocationCounter

    var body: some View {
        let _ = incrementCounter()
        Text("Track \(option.id)")
            .tag(option.id)
    }

    @MainActor
    private func incrementCounter() {
        counter.count += 1
    }
}
#endif
