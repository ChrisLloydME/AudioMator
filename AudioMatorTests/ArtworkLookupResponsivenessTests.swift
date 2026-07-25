import XCTest
@testable import AudioMator

@MainActor
final class ArtworkLookupResponsivenessTests: XCTestCase {
    func testNonCooperativeSearchTimesOutAndClearsLoadingState() async throws {
        let gate = ArtworkLookupGate()
        let service = NonCooperativeArtworkService(searchGate: gate)
        let viewModel = makeViewModel(service: service)
        let file = makeArtworkFile()
        viewModel.mergeQuickImportFiles([file])

        viewModel.findOnlineArtwork(for: file)
        await gate.waitUntilStarted()

        try await waitUntil {
            viewModel.artworkLookupSession?.isLoading == false
        }

        XCTAssertEqual(
            viewModel.artworkLookupSession?.errorMessage,
            "iTunes artwork search timed out. Please try again."
        )
        XCTAssertNotNil(viewModel.artworkLookupSession)
        await gate.release()
    }

    func testDismissedNonCooperativeSearchDoesNotRetainViewModel() async throws {
        let gate = ArtworkLookupGate()
        let service = NonCooperativeArtworkService(searchGate: gate)
        var viewModel: AudioViewModel? = makeViewModel(service: service)
        weak let weakViewModel = viewModel
        let file = makeArtworkFile()
        viewModel?.mergeQuickImportFiles([file])

        viewModel?.findOnlineArtwork(for: file)
        await gate.waitUntilStarted()
        viewModel?.dismissArtworkLookup()
        viewModel = nil

        try await waitUntil { weakViewModel == nil }
        await gate.release()
    }

    func testCancelledSearchClearsLoadingState() async throws {
        let gate = ArtworkLookupGate()
        let service = NonCooperativeArtworkService(searchGate: gate)
        let viewModel = makeViewModel(service: service)
        let file = makeArtworkFile()
        viewModel.mergeQuickImportFiles([file])

        viewModel.findOnlineArtwork(for: file)
        await gate.waitUntilStarted()
        viewModel.artworkLookupTask?.cancel()

        try await waitUntil {
            viewModel.artworkLookupSession?.isLoading == false
        }
        XCTAssertEqual(
            viewModel.artworkLookupSession?.errorMessage,
            "The artwork search was cancelled."
        )
        await gate.release()
    }

    func testNonCooperativeDownloadTimesOutAndClearsApplyingState() async throws {
        let gate = ArtworkLookupGate()
        let result = makeArtworkResult()
        let service = NonCooperativeArtworkService(
            searchResults: [result],
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service)
        let file = makeArtworkFile()
        viewModel.mergeQuickImportFiles([file])

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.isLoading == false
        }
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted()

        try await waitUntil {
            viewModel.artworkLookupSession?.isApplying == false
        }

        XCTAssertEqual(
            viewModel.artworkLookupSession?.errorMessage,
            "iTunes artwork download timed out. Please try again."
        )
        XCTAssertNotNil(viewModel.artworkLookupSession)
        await gate.release()
    }

    func testDismissedNonCooperativeDownloadDoesNotRetainViewModel() async throws {
        let gate = ArtworkLookupGate()
        let result = makeArtworkResult()
        let service = NonCooperativeArtworkService(
            searchResults: [result],
            downloadGate: gate
        )
        var viewModel: AudioViewModel? = makeViewModel(service: service)
        weak let weakViewModel = viewModel
        let file = makeArtworkFile()
        viewModel?.mergeQuickImportFiles([file])

        viewModel?.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel?.artworkLookupSession?.isLoading == false
        }
        viewModel?.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted()
        viewModel?.dismissArtworkLookup()
        viewModel = nil

        try await waitUntil { weakViewModel == nil }
        await gate.release()
    }

    private func makeViewModel(
        service: any iTunesArtworkServicing
    ) -> AudioViewModel {
        AudioViewModel(
            metadataPipeline: ArtworkLookupMetadataPipeline(),
            artworkLookupService: service,
            artworkLookupOperationTimeout: .milliseconds(40)
        )
    }

    private func makeArtworkFile() -> AudioFile {
        AudioFileTestFactory.make(
            url: URL(fileURLWithPath: "/tmp/artwork-lookup.mp3"),
            title: "Test Track",
            album: "Test Album"
        )
    }

    private func makeArtworkResult() -> iTunesArtworkSearchResult {
        iTunesArtworkSearchResult(
            id: "1",
            title: "Test Album",
            subtitle: "Test Artist",
            thumbnailURL: URL(string: "https://example.com/cover.jpg"),
            standardURL: nil,
            hiresURL: nil,
            uncompressedURL: nil,
            pixelWidth: 600,
            pixelHeight: 600
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for artwork lookup state")
    }
}

private final class NonCooperativeArtworkService: iTunesArtworkServicing, @unchecked Sendable {
    private let searchResults: [iTunesArtworkSearchResult]
    private let searchGate: ArtworkLookupGate?
    private let downloadGate: ArtworkLookupGate?

    init(
        searchResults: [iTunesArtworkSearchResult] = [],
        searchGate: ArtworkLookupGate? = nil,
        downloadGate: ArtworkLookupGate? = nil
    ) {
        self.searchResults = searchResults
        self.searchGate = searchGate
        self.downloadGate = downloadGate
    }

    func search(
        _ request: iTunesArtworkSearchRequest
    ) async throws -> [iTunesArtworkSearchResult] {
        if let searchGate {
            await searchGate.wait()
        }
        return searchResults
    }

    func downloadArtworkData(
        for result: iTunesArtworkSearchResult
    ) async throws -> iTunesDownloadedArtwork {
        if let downloadGate {
            await downloadGate.wait()
        }
        return iTunesDownloadedArtwork(pngData: Data())
    }
}

private actor ArtworkLookupGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class ArtworkLookupMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url)
        }
    }

    func rawMetadataDumpText(for url: URL) -> String? { nil }
    func rawMetadataPropertyMap(for url: URL) throws -> [String: String] { [:] }

    func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    func writeRawMetadataPropertyMap(
        _ propertyMap: [String: String],
        to url: URL
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    func eraseAllMetadata(at url: URL) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    func writeTrackNumberText(
        _ trackNumberText: String,
        discNumberText: String?,
        to url: URL,
        verifyAfterWrite: Bool
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
