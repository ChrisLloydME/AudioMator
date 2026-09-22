import AppKit
import SwiftUI
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class OnlineMetadataPageTraversalTests: XCTestCase {
    func testSearchPagesRenderAndRecoverAfterSuccessFailureTimeoutAndCancellation() async throws {
        let fixture = makeFixture()
        let viewModel = makeViewModel(file: fixture.file)

        for behavior in [TraversalBehavior.success, .failure, .timeout, .cancelled] {
            let musicBrainzStore = MusicBrainzBrowserStore(
                client: TraversalMusicBrainzClient(fixture: fixture.musicBrainz, behavior: behavior),
                operationTimeout: .milliseconds(behavior == .timeout ? 30 : 500)
            )
            musicBrainzStore.apply(seed: fixture.musicBrainz.seed)
            musicBrainzStore.search()
            if behavior == .cancelled {
                try await Task.sleep(for: .milliseconds(20))
                musicBrainzStore.closeWindowSession()
            } else {
                try await waitUntil { !musicBrainzStore.isSearching }
            }
            assertRecoveredState(
                behavior: behavior,
                isLoading: musicBrainzStore.isSearching,
                errorMessage: musicBrainzStore.errorMessage
            )
            await render(
                AnyView(
                    OnlineMetadataBrowserView(
                        store: musicBrainzStore,
                        lrclibStore: LRCLIBLyricsBrowserStore(),
                        viewModel: viewModel,
                        initialSource: .musicBrainz
                    )
                ),
                label: "MusicBrainz search \(behavior)"
            )

            let iTunesStore = iTunesBrowserStore(
                client: TraversaliTunesClient(fixture: fixture.iTunes, behavior: behavior),
                operationTimeout: .milliseconds(behavior == .timeout ? 30 : 500)
            )
            iTunesStore.seed(from: [fixture.file])
            iTunesStore.search()
            if behavior == .cancelled {
                try await Task.sleep(for: .milliseconds(20))
                iTunesStore.closeWindowSession()
            } else {
                try await waitUntil { !iTunesStore.isSearching }
            }
            assertRecoveredState(
                behavior: behavior,
                isLoading: iTunesStore.isSearching,
                errorMessage: iTunesStore.errorMessage
            )
            await render(
                AnyView(
                    OnlineMetadataBrowserView(
                        store: MusicBrainzBrowserStore(
                            client: TraversalMusicBrainzClient(
                                fixture: fixture.musicBrainz,
                                behavior: .success
                            )
                        ),
                        lrclibStore: LRCLIBLyricsBrowserStore(),
                        viewModel: viewModel,
                        iTunesStore: iTunesStore,
                        initialSource: .iTunes
                    )
                ),
                label: "iTunes search \(behavior)"
            )
        }
    }

    func testAllReachableDetailWorkbenchComparisonAndArtworkSurfacesRender() async throws {
        let fixture = makeFixture()
        let viewModel = makeViewModel(file: fixture.file)
        let musicBrainzStore = MusicBrainzBrowserStore(
            client: TraversalMusicBrainzClient(fixture: fixture.musicBrainz, behavior: .success)
        )
        musicBrainzStore.apply(seed: fixture.musicBrainz.seed)
        let iTunesStore = iTunesBrowserStore(
            client: TraversaliTunesClient(fixture: fixture.iTunes, behavior: .success)
        )
        iTunesStore.seed(from: [fixture.file])

        await render(
            AnyView(
                OnlineMetadataBrowserView(
                    store: musicBrainzStore,
                    lrclibStore: LRCLIBLyricsBrowserStore(),
                    viewModel: viewModel
                )
            ),
            label: "source picker"
        )
        await render(
            AnyView(
                MusicBrainzMetadataDetailView(
                    store: musicBrainzStore,
                    viewModel: viewModel,
                    destination: .recording(fixture.musicBrainz.recordingResult)
                )
            ),
            label: "MusicBrainz recording detail",
            settleTime: 0.15
        )
        await render(
            AnyView(
                MusicBrainzMetadataDetailView(
                    store: musicBrainzStore,
                    viewModel: viewModel,
                    destination: .release(fixture.musicBrainz.releaseResult)
                )
            ),
            label: "MusicBrainz release detail and comparison",
            settleTime: 0.2
        )
        await render(
            AnyView(
                MusicBrainzMetadataDetailView(
                    store: musicBrainzStore,
                    viewModel: viewModel,
                    destination: .track(fixture.musicBrainz.release.media[0].tracks[0])
                )
            ),
            label: "MusicBrainz track detail",
            settleTime: 0.15
        )
        await render(
            AnyView(
                MusicBrainzTaggingWorkbenchView(
                    store: MusicBrainzTaggingWorkbenchStore(
                        release: fixture.musicBrainz.release,
                        preview: fixture.musicBrainz.preview,
                        loadedFiles: [fixture.file],
                        browserStore: musicBrainzStore
                    ),
                    viewModel: viewModel
                )
            ),
            label: "MusicBrainz tagging workbench",
            settleTime: 0.15
        )

        await render(
            AnyView(
                iTunesTrackDetailView(
                    track: fixture.iTunes.track,
                    store: iTunesStore,
                    viewModel: viewModel
                )
            ),
            label: "iTunes track detail"
        )
        await render(
            AnyView(
                iTunesAlbumDetailView(
                    album: fixture.iTunes.album,
                    store: iTunesStore,
                    viewModel: viewModel
                )
            ),
            label: "iTunes album detail and comparison",
            settleTime: 0.2
        )
        await render(
            AnyView(
                iTunesTaggingWorkbenchView(
                    store: iTunesTaggingWorkbenchStore(
                        detail: fixture.iTunes.detail,
                        preview: fixture.iTunes.preview,
                        loadedFiles: [fixture.file]
                    ),
                    viewModel: viewModel
                )
            ),
            label: "iTunes tagging workbench",
            settleTime: 0.15
        )

        let artworkResult = iTunesArtworkSearchResult(
            id: "artwork",
            title: "Traversal Album",
            subtitle: "Traversal Artist",
            thumbnailURL: nil,
            standardURL: nil,
            hiresURL: nil,
            uncompressedURL: nil,
            pixelWidth: 1_200,
            pixelHeight: 1_200
        )
        let artworkStates: [ArtworkLookupSession] = [
            ArtworkLookupSession(
                fileIDs: [fixture.file.id],
                selectionTitle: "Traversal Album",
                request: ArtworkLookupRequestDescriptor(
                    query: "Traversal Album",
                    entity: .album,
                    source: .album
                ),
                isLoading: true
            ),
            ArtworkLookupSession(
                fileIDs: [fixture.file.id],
                selectionTitle: "Traversal Album",
                request: ArtworkLookupRequestDescriptor(
                    query: "Traversal Album",
                    entity: .album,
                    source: .album
                ),
                isLoading: false,
                errorMessage: "Synthetic artwork failure"
            ),
            ArtworkLookupSession(
                fileIDs: [fixture.file.id],
                selectionTitle: "Traversal Album",
                request: ArtworkLookupRequestDescriptor(
                    query: "Traversal Album",
                    entity: .album,
                    source: .album
                ),
                isLoading: false,
                results: [artworkResult],
                selectedResultID: artworkResult.id
            )
        ]
        for (index, session) in artworkStates.enumerated() {
            viewModel.artworkLookupSession = session
            await render(
                AnyView(AlbumArtworkLookupSheet(viewModel: viewModel)),
                label: "artwork state \(index)"
            )
        }
    }

    private func assertRecoveredState(
        behavior: TraversalBehavior,
        isLoading: Bool,
        errorMessage: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(isLoading, file: file, line: line)
        switch behavior {
        case .success, .cancelled:
            XCTAssertNil(errorMessage, file: file, line: line)
        case .failure, .timeout:
            XCTAssertNotNil(errorMessage, file: file, line: line)
        }
    }

    private func render(
        _ view: AnyView,
        label: String,
        settleTime: TimeInterval = 0.08,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let host = NSHostingView(rootView: view.frame(width: 980, height: 700))
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
        try? await Task.sleep(for: .seconds(settleTime))
        host.layoutSubtreeIfNeeded()
        let elapsed = startedAt.duration(to: clock.now)

        let mainActorPulse = expectation(description: "\(label) main event-loop pulse")
        DispatchQueue.main.async {
            mainActorPulse.fulfill()
        }
        await fulfillment(of: [mainActorPulse], timeout: 0.25)

        XCTAssertLessThan(elapsed, .seconds(2), "\(label) layout exceeded its budget", file: file, line: line)
        XCTAssertEqual(host.frame.size.width, 980, file: file, line: line)
        XCTAssertEqual(host.frame.size.height, 700, file: file, line: line)

        window.contentView = nil
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
        XCTAssertTrue(condition(), "Timed out waiting for traversal state")
    }

    private func makeViewModel(file: AudioFile) -> AudioViewModel {
        let viewModel = AudioViewModel()
        viewModel.files = [file]
        viewModel.setSelectedAudioIDs([file.id])
        return viewModel
    }

    private func makeFixture() -> TraversalFixture {
        let file = AudioFileTestFactory.make(
            title: "Traversal Track",
            artist: "Traversal Artist",
            album: "Traversal Album",
            track: 1,
            trackTotal: 1
        )
        let musicBrainzInput = MusicBrainzFileSearchInput(
            id: file.id.uuidString,
            displayTitle: file.url.lastPathComponent,
            title: file.title,
            artist: file.artist,
            albumArtist: file.artist,
            album: file.album,
            trackNumber: "1",
            discNumber: "1",
            trackTotal: 1
        )
        let musicBrainzTrack = MusicBrainzReleaseMatchTrack(
            id: "mb-track",
            mediumTitle: "",
            mediumFormat: "Digital Media",
            mediumPosition: 1,
            mediumTrackCount: 1,
            releaseMediumCount: 1,
            number: "1",
            title: "Traversal Track",
            artistCredit: "Traversal Artist",
            durationMilliseconds: nil,
            recordingID: "mb-recording",
            isrcs: []
        )
        let musicBrainzPreview = MusicBrainzReleaseMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [
                MusicBrainzReleaseMatchAssignment(
                    id: "mb-assignment",
                    file: musicBrainzInput,
                    track: musicBrainzTrack,
                    score: 1,
                    reason: "traversal"
                )
            ],
            unmatchedFiles: [],
            unassignedTracks: [],
            averageTrackScore: 1,
            overallScore: 1,
            selectionLooksMixed: false
        )
        let musicBrainzRelease = MusicBrainzReleaseDetail(
            id: "mb-release",
            title: "Traversal Album",
            artistCredit: "Traversal Artist",
            date: "2026-01-01",
            country: "US",
            status: "Official",
            barcode: "",
            packaging: "",
            asin: "",
            quality: "",
            language: "eng",
            script: "Latn",
            annotation: "Traversal annotation",
            genres: [MusicBrainzTerm(name: "Rock", count: 1)],
            tags: [],
            releaseGroupTitle: "Traversal Album",
            releaseGroupID: "mb-group",
            releaseGroupPrimaryType: "Album",
            releaseGroupSecondaryTypes: [],
            labels: [],
            media: [
                MusicBrainzReleaseDetail.Medium(
                    id: "mb-medium",
                    title: "",
                    format: "Digital Media",
                    trackCount: 1,
                    discIDs: [],
                    tracks: [
                        MusicBrainzReleaseDetail.Medium.Track(
                            id: "mb-track",
                            number: "1",
                            title: "Traversal Track",
                            artistCredit: "Traversal Artist",
                            durationMilliseconds: nil,
                            recordingID: "mb-recording",
                            isrcs: []
                        )
                    ]
                )
            ],
            selectionMatchPreview: musicBrainzPreview
        )
        let recordingResult = MusicBrainzRecordingResult(
            id: "mb-recording",
            title: "Traversal Track",
            artistCredit: "Traversal Artist",
            score: 100,
            disambiguation: "",
            firstReleaseDate: "2026-01-01",
            durationMilliseconds: nil,
            releases: [
                MusicBrainzRecordingResult.Release(
                    id: "mb-release",
                    title: "Traversal Album",
                    date: "2026-01-01",
                    country: "US",
                    status: "Official"
                )
            ]
        )
        let recordingDetail = MusicBrainzRecordingDetail(
            id: "mb-recording",
            title: "Traversal Track",
            artistCredit: "Traversal Artist",
            disambiguation: "",
            firstReleaseDate: "2026-01-01",
            durationMilliseconds: nil,
            annotation: "Traversal annotation",
            isrcs: [],
            genres: [],
            tags: [],
            rating: nil,
            releases: recordingResult.releases,
            relationshipGroups: [
                MusicBrainzRelationshipGroup(title: "producer", values: ["Traversal Producer"])
            ]
        )
        let releaseResult = MusicBrainzReleaseSearchResult(
            id: musicBrainzRelease.id,
            title: musicBrainzRelease.title,
            artistCredit: musicBrainzRelease.artistCredit,
            score: 100,
            date: musicBrainzRelease.date,
            country: musicBrainzRelease.country,
            status: musicBrainzRelease.status,
            mediaFormats: ["Digital Media"],
            releaseGroup: nil,
            selectionMatchPreview: musicBrainzPreview,
            selectionMatchScore: 1
        )
        let musicBrainzSeed = MusicBrainzSearchSeed(
            mode: .file,
            title: file.title,
            artist: file.artist,
            albumArtist: file.artist,
            album: file.album,
            trackNumber: "1",
            trackTotal: 1,
            durationMilliseconds: nil,
            releaseDate: "2026-01-01",
            isrc: "",
            barcode: "",
            musicBrainzAlbumID: "",
            musicBrainzTrackID: "",
            fileInputs: [musicBrainzInput],
            link: "",
            sourceDescription: "Traversal fixture"
        )

        let iTunesTrack = iTunesTrackResult(
            trackID: 1,
            collectionID: 10,
            artistID: 20,
            collectionArtistID: 20,
            trackName: "Traversal Track",
            artistName: "Traversal Artist",
            collectionArtistName: "Traversal Artist",
            collectionName: "Traversal Album",
            trackNumber: 1,
            trackCount: 1,
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
        let iTunesAlbum = iTunesAlbumResult(
            collectionID: 10,
            artistID: 20,
            collectionArtistID: 20,
            collectionName: "Traversal Album",
            artistName: "Traversal Artist",
            collectionArtistName: "Traversal Artist",
            trackCount: 1,
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
        let iTunesInput = iTunesFileSearchInput(
            id: file.id.uuidString,
            displayTitle: file.url.lastPathComponent,
            title: file.title,
            artist: file.artist,
            albumArtist: file.artist,
            album: file.album,
            trackNumber: "1",
            discNumber: "1",
            trackTotal: 1,
            durationMilliseconds: nil,
            releaseDate: "2026-01-01",
            barcode: "",
            itunesAlbumID: "",
            itunesArtistID: "",
            itunesCatalogID: ""
        )
        let iTunesPreview = iTunesAlbumMatchPreview(
            totalSelectedFiles: 1,
            matchedAssignments: [
                iTunesAlbumMatchAssignment(
                    id: "itunes-assignment",
                    file: iTunesInput,
                    track: iTunesTrack,
                    score: 1,
                    reason: "traversal"
                )
            ],
            unmatchedFiles: [],
            unassignedTracks: [],
            overallScore: 1
        )
        let iTunesDetail = iTunesAlbumDetail(
            album: iTunesAlbum,
            tracks: [iTunesTrack],
            selectionMatchPreview: iTunesPreview
        )

        return TraversalFixture(
            file: file,
            musicBrainz: TraversalMusicBrainzFixture(
                seed: musicBrainzSeed,
                recordingResult: recordingResult,
                recordingDetail: recordingDetail,
                releaseResult: releaseResult,
                release: musicBrainzRelease,
                preview: musicBrainzPreview
            ),
            iTunes: TraversaliTunesFixture(
                track: iTunesTrack,
                album: iTunesAlbum,
                detail: iTunesDetail,
                preview: iTunesPreview
            )
        )
    }
}

private nonisolated enum TraversalBehavior: CustomStringConvertible, Equatable, Sendable {
    case success
    case failure
    case timeout
    case cancelled

    var description: String {
        switch self {
        case .success: return "success"
        case .failure: return "failure"
        case .timeout: return "timeout"
        case .cancelled: return "cancelled"
        }
    }

    func waitIfNeeded() async throws {
        if self == .timeout || self == .cancelled {
            try await Task.sleep(for: .seconds(30))
        }
    }
}

private nonisolated struct TraversalFixture: Sendable {
    let file: AudioFile
    let musicBrainz: TraversalMusicBrainzFixture
    let iTunes: TraversaliTunesFixture
}

private nonisolated struct TraversalMusicBrainzFixture: Sendable {
    let seed: MusicBrainzSearchSeed
    let recordingResult: MusicBrainzRecordingResult
    let recordingDetail: MusicBrainzRecordingDetail
    let releaseResult: MusicBrainzReleaseSearchResult
    let release: MusicBrainzReleaseDetail
    let preview: MusicBrainzReleaseMatchPreview
}

private nonisolated struct TraversaliTunesFixture: Sendable {
    let track: iTunesTrackResult
    let album: iTunesAlbumResult
    let detail: iTunesAlbumDetail
    let preview: iTunesAlbumMatchPreview
}

private nonisolated struct TraversalMusicBrainzClient: MusicBrainzBrowserClient, Sendable {
    let fixture: TraversalMusicBrainzFixture
    let behavior: TraversalBehavior

    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        try await behavior.waitIfNeeded()
        if behavior == .failure { throw URLError(.cannotParseResponse) }
        return .recordings([fixture.recordingResult])
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail {
        try await behavior.waitIfNeeded()
        if behavior == .failure { throw URLError(.cannotParseResponse) }
        return fixture.recordingDetail
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        try await behavior.waitIfNeeded()
        if behavior == .failure { throw URLError(.cannotParseResponse) }
        return fixture.release
    }
}

private nonisolated struct TraversaliTunesClient: iTunesBrowserClient, Sendable {
    let fixture: TraversaliTunesFixture
    let behavior: TraversalBehavior

    func search(matching query: iTunesSearchQuery, limit: Int) async throws -> iTunesSearchResults {
        try await behavior.waitIfNeeded()
        if behavior == .failure { throw URLError(.cannotParseResponse) }
        return .tracks([fixture.track])
    }

    func albumDetail(collectionID: Int, country: String) async throws -> iTunesAlbumDetail {
        try await behavior.waitIfNeeded()
        if behavior == .failure { throw URLError(.cannotParseResponse) }
        return fixture.detail
    }
}
#endif
