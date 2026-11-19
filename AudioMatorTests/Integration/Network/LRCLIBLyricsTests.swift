import Foundation
import XCTest
import TagLibAudioMetadata
@testable import AudioMator

/// AM-05: LRCLIB synced lyrics are bound to the reviewed file revision captured at
/// seed, and every write flows through the shared strict reviewed-write route.
nonisolated final class LRCLIBLyricsTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Unchanged client/ranker coverage

    @MainActor
    func testSearchRequestUsesExpectedQueryItemsAndHeaders() throws {
        let client = LRCLIBClient()
        let request = try client.makeSearchRequest(
            for: LRCLIBSearchQuery(
                trackName: "Sweeter Than Fiction",
                artistName: "Taylor Swift",
                albumName: "Single",
                durationSeconds: 235
            )
        )

        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "lrclib.net")
        XCTAssertEqual(components.path, "/api/search")

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(queryItems["track_name"], "Sweeter Than Fiction")
        XCTAssertEqual(queryItems["artist_name"], "Taylor Swift")
        XCTAssertEqual(queryItems["album_name"], "Single")
        XCTAssertEqual(queryItems["duration"], "235")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("AudioMator/") == true)
    }

    @MainActor
    func testFileAndCandidateInputsRejectUnrepresentableDurations() {
        let file = AudioFileTestFactory.make(
            title: "Extreme Duration",
            duration: .greatestFiniteMagnitude
        )
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 1,
            track: "Extreme Duration",
            artist: "Artist",
            duration: .greatestFiniteMagnitude
        )

        XCTAssertNil(LRCLIBFileSearchInput(file: file).durationSeconds)
        XCTAssertNil(candidate.durationSeconds)
    }

    @MainActor
    func testCandidateRankingHandlesExtremeDurationDistanceWithoutOverflow() {
        let query = LRCLIBSearchQuery(
            trackName: "Title",
            artistName: "Artist",
            albumName: "Album",
            durationSeconds: .min
        )
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 1,
            track: "Title",
            artist: "Artist",
            album: "Album",
            duration: 1
        )

        XCTAssertEqual(LRCLIBCandidateRanker.score(candidate: candidate, query: query), 80)
    }

    @MainActor
    func testSearchDecodesSyncedPlainInstrumentalAndEmptyResults() async throws {
        let payload = """
        [
          {
            "id": 1,
            "name": "Synced",
            "trackName": "Synced Song",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 200,
            "instrumental": false,
            "plainLyrics": "plain",
            "syncedLyrics": "[00:01.00]synced"
          },
          {
            "id": 2,
            "name": "Plain",
            "trackName": "Plain Song",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 201,
            "instrumental": false,
            "plainLyrics": "plain only",
            "syncedLyrics": null
          },
          {
            "id": 3,
            "name": "Instrumental",
            "trackName": "Instrumental Song",
            "artistName": "Artist",
            "albumName": "Album",
            "duration": 202,
            "instrumental": true,
            "plainLyrics": null,
            "syncedLyrics": null
          }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, payload)
        }

        let client = LRCLIBClient(session: makeMockSession())
        let results = try await client.search(
            matching: LRCLIBSearchQuery(trackName: "Song", artistName: "Artist", albumName: "", durationSeconds: nil),
            limit: 20
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results[0].hasSyncedLyrics)
        XCTAssertTrue(results[1].hasPlainLyrics)
        XCTAssertFalse(results[1].hasSyncedLyrics)
        XCTAssertTrue(results[2].instrumental)
        XCTAssertEqual(results[2].lyricsAvailabilityLabel, "Instrumental")
    }

    @MainActor
    func testRankingSortsExactSyncedDurationCloseCandidateFirst() {
        let query = LRCLIBSearchQuery(
            trackName: "Sweeter Than Fiction",
            artistName: "Taylor Swift",
            albumName: "Single",
            durationSeconds: 235
        )
        let candidates = [
            LRCLIBLyricsTestSupport.makeCandidate(id: 1, track: "Sweeter Than Fiction", artist: "Taylor Swift", album: "Single", duration: 235, syncedLyrics: "[00:01.00]Line"),
            LRCLIBLyricsTestSupport.makeCandidate(id: 2, track: "Sweeter Than Fiction", artist: "Taylor Swift", album: "Single", duration: 260, plainLyrics: "Line"),
            LRCLIBLyricsTestSupport.makeCandidate(id: 3, track: "Sweeter", artist: "Other Artist", album: "Other", duration: 235, syncedLyrics: "[00:01.00]Line")
        ]

        let ranked = LRCLIBCandidateRanker.rankedCandidates(candidates, for: query)

        XCTAssertEqual(ranked.map(\.id), [1, 2, 3])
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    // MARK: - Seed binding (AM-05)

    @MainActor
    func testSeedCapturesReviewedTargetBesideMetadataOnlyQuery() throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = try LRCLIBLyricsTestSupport.makeObservedFile(named: "seed.mp3", directory: directory)
        let store = LRCLIBLyricsBrowserStore(client: LRCLIBGatedClient())

        store.seed(from: [file])

        let row = try XCTUnwrap(store.rows.first)
        XCTAssertEqual(row.input.fileName, file.url.lastPathComponent)
        XCTAssertEqual(row.input.title, file.title)
        let target = try XCTUnwrap(row.target)
        XCTAssertEqual(target.id, file.id)
        XCTAssertEqual(target.url, file.url)
        XCTAssertEqual(target.fingerprint, file.fileFingerprint)
        XCTAssertEqual(target.version, file.metadataFileVersion)
        // The HTTP query DTO stays metadata-only.
        XCTAssertEqual(store.currentFile?.query.trackName, LRCLIBFileSearchInput(file: file).title)
    }

    @MainActor
    func testSeedWithoutAuthorityStillSearchesAndPreviews() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let observed = try LRCLIBLyricsTestSupport.makeObservedFile(named: "recovery.mp3", directory: directory)
        let recoveryProjection = observed.projectingRecoveryState()
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 7,
            track: observed.title,
            artist: observed.artist,
            syncedLyrics: "[00:01.00]Line"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: recoveryProjection).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: recoveryProjection)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([recoveryProjection])
        let store = LRCLIBLyricsBrowserStore(client: client)

        store.seed(from: [recoveryProjection])
        XCTAssertNil(store.rows.first?.target)
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)
        XCTAssertEqual(store.searchState, .loaded)
        XCTAssertEqual(store.selectedCandidate?.id, candidate.id)

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)
        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(store.appliedCandidateID)
    }

    @MainActor
    func testManualIntentCarriesTargetCandidateAndLyrics() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = try LRCLIBLyricsTestSupport.makeObservedFile(named: "manual-intent.mp3", directory: directory)
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 11,
            track: file.title,
            artist: file.artist,
            syncedLyrics: "  [00:01.00]Line\n"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: file).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: file)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([file])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [file])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        let record = try XCTUnwrap(pipeline.rawWrites.first)
        XCTAssertEqual(record.url, file.url)
        XCTAssertEqual(record.version, file.metadataFileVersion)
        XCTAssertEqual(record.patch.valuesToSet["LYRICS"], ["[00:01.00]Line"])
        XCTAssertEqual(record.patch.removingKeys, [])
        XCTAssertEqual(record.patch.valuesToSet.count, 1)
        XCTAssertEqual(store.appliedCandidateID, candidate.id)
    }

    @MainActor
    func testBulkEntryCarriesSeedTargetPerMatch() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = try LRCLIBLyricsTestSupport.makeObservedFile(named: "bulk-intent.mp3", directory: directory)
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 21,
            track: file.title,
            artist: file.artist,
            syncedLyrics: "[00:01.00]Bulk"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: file).title: [candidate]]
        )
        let writer = LRCLIBRecordingWriter()
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [file])

        XCTAssertTrue(store.startAutoApply(writer: writer))
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        let intent = try XCTUnwrap(writer.autoIntents.first)
        let entry = try XCTUnwrap(intent.entries.first)
        XCTAssertEqual(entry.fileID, file.id)
        XCTAssertEqual(entry.fileName, file.url.lastPathComponent)
        XCTAssertEqual(entry.candidateID, candidate.id)
        XCTAssertEqual(entry.lyrics, "[00:01.00]Bulk")
        XCTAssertEqual(entry.write?.target.id, file.id)
        XCTAssertEqual(entry.write?.target.fingerprint, file.fileFingerprint)
        XCTAssertEqual(entry.write?.target.version, file.metadataFileVersion)
    }

    // MARK: - Strict manual application (AM-05)

    @MainActor
    func testManualApplyRejectsChangedRevisionAfterSamePathReload() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixture = try LRCLIBLyricsTestSupport.makeObservedFile(named: "reload.mp3", directory: directory)
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 31,
            track: fixture.title,
            artist: fixture.artist,
            syncedLyrics: "[00:01.00]Old"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: fixture).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: fixture)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [fixture])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        // The app observes a reload of the same path under the same stable UUID.
        try Data(repeating: 0x42, count: 128).write(to: fixture.url)
        let reloaded = AudioFileTestFactory.makeObserved(
            id: fixture.id,
            url: fixture.url,
            title: "Edited on disk",
            fileFingerprint: try AudioFileFingerprint.capture(at: fixture.url),
            metadataFileVersion: try XCTUnwrap(fixture.metadataFileVersion)
        )
        viewModel.mergeQuickImportFiles([reloaded])

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(store.appliedCandidateID)
        XCTAssertEqual(viewModel.metadataWriteHUD?.style, .failure)
    }

    @MainActor
    func testManualApplyRejectsReplacedFileWithReusedUUID() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixture = try LRCLIBLyricsTestSupport.makeObservedFile(named: "replace.mp3", directory: directory)
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 41,
            track: fixture.title,
            artist: fixture.artist,
            syncedLyrics: "[00:01.00]Old"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: fixture).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: fixture)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [fixture])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        // Replace the file at the same path; the app reuses the stable UUID.
        try FileManager.default.removeItem(at: fixture.url)
        try Data(repeating: 0x43, count: 96).write(to: fixture.url)
        let replaced = AudioFileTestFactory.makeObserved(
            id: fixture.id,
            url: fixture.url,
            title: "Replacement",
            fileFingerprint: try AudioFileFingerprint.capture(at: fixture.url),
            metadataFileVersion: try XCTUnwrap(fixture.metadataFileVersion)
        )
        viewModel.mergeQuickImportFiles([replaced])

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(store.appliedCandidateID)
    }

    @MainActor
    func testManualApplyRejectsEqualFingerprintDifferentPackageVersion() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixture = try LRCLIBLyricsTestSupport.makeObservedFile(named: "version.mp3", directory: directory)
        let otherFixture = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: otherFixture) }
        let otherVersion = try MetadataTestTokens.mintedVersion(at: otherFixture)
        let capturedVersion = try XCTUnwrap(fixture.metadataFileVersion)
        XCTAssertNotEqual(otherVersion, capturedVersion, "Two real package tokens must differ for this control")

        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 51,
            track: fixture.title,
            artist: fixture.artist,
            syncedLyrics: "[00:01.00]Old"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: fixture).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: fixture)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [fixture])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        let sameFingerprintDifferentVersion = AudioFileTestFactory.makeObserved(
            id: fixture.id,
            url: fixture.url,
            title: fixture.title,
            fileFingerprint: try XCTUnwrap(fixture.fileFingerprint),
            metadataFileVersion: otherVersion
        )
        viewModel.mergeQuickImportFiles([sameFingerprintDifferentVersion])

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(store.appliedCandidateID)
    }

    @MainActor
    func testManualApplyAcceptsEqualObservationRefresh() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixture = try LRCLIBLyricsTestSupport.makeObservedFile(named: "equal.mp3", directory: directory)
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 61,
            track: fixture.title,
            artist: fixture.artist,
            syncedLyrics: "[00:01.00]Equal"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: fixture).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: fixture)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [fixture])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        // Republishing the same coherent observation is not a false conflict.
        viewModel.mergeQuickImportFiles([fixture])

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 1)
        XCTAssertEqual(pipeline.rawWrites.first?.version, fixture.metadataFileVersion)
        XCTAssertEqual(store.appliedCandidateID, candidate.id)
    }

    @MainActor
    func testManualApplyRejectsChangedFileWhileQueuedOnReservation() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixture = try LRCLIBLyricsTestSupport.makeObservedFile(named: "queued.mp3", directory: directory)
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 71,
            track: fixture.title,
            artist: fixture.artist,
            syncedLyrics: "[00:01.00]Queued"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: fixture).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: fixture)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [fixture])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        let release = LRCLIBTestGate()
        let holder = Task {
            try? await viewModel.fileMutationCoordinator.withExclusiveAccess(to: [fixture.url]) {
                await release.wait()
            }
        }
        store.startManualApply(writer: viewModel)
        try await waitForQueuedMutation(in: viewModel)

        // The file changes while the strict write waits for its reservation.
        try Data(repeating: 0x44, count: 128).write(to: fixture.url)
        let changed = AudioFileTestFactory.makeObserved(
            id: fixture.id,
            url: fixture.url,
            title: "Changed while queued",
            fileFingerprint: try AudioFileFingerprint.capture(at: fixture.url),
            metadataFileVersion: try XCTUnwrap(fixture.metadataFileVersion)
        )
        viewModel.mergeQuickImportFiles([changed])

        release.open()
        await holder.value
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(store.appliedCandidateID)
    }

    @MainActor
    func testManualApplyRejectsUnsupportedCapabilityAndFormatWithoutWriterCalls() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        for (name, expectedRejection) in [
            ("unsupported.xm", LRCLIBLyricsWriteRejection.unsupportedLyricsCapability),
            ("unsupported.txt", LRCLIBLyricsWriteRejection.unsupportedFormat)
        ] {
            let file = try LRCLIBLyricsTestSupport.makeObservedFile(named: name, directory: directory)
            let candidate = LRCLIBLyricsTestSupport.makeCandidate(
                id: name.hashValue,
                track: file.title,
                artist: file.artist,
                syncedLyrics: "[00:01.00]Line"
            )
            let client = LRCLIBGatedClient(
                candidatesByTrackName: [LRCLIBFileSearchInput(file: file).title: [candidate]]
            )
            let pipeline = LRCLIBRecordingPipeline(reloadFile: file)
            let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
            viewModel.mergeQuickImportFiles([file])
            let store = LRCLIBLyricsBrowserStore(client: client)
            store.seed(from: [file])
            store.searchCurrentFile()
            try await waitForSearchToFinish(store)

            store.startManualApply(writer: viewModel)
            try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

            XCTAssertEqual(pipeline.rawWriteCount, 0, name)
            XCTAssertNil(store.appliedCandidateID, name)

            let direct = LRCLIBLyricsWriteIntentBuilder.reviewedLyricsWrite(
                lyrics: "[00:01.00]Line",
                target: store.rows.first?.target
            )
            guard case .failure(let rejection) = direct else {
                return XCTFail("Expected \(expectedRejection) for \(name)")
            }
            XCTAssertEqual(rejection, expectedRejection, name)
        }
    }

    @MainActor
    func testManualApplyReportsRealWarnings() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixture = try LRCLIBLyricsTestSupport.makeObservedFile(named: "warnings.mp3", directory: directory)
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 81,
            track: fixture.title,
            artist: fixture.artist,
            syncedLyrics: "[00:01.00]Warned"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: fixture).title: [candidate]]
        )
        let warning = "Your changes were saved, but the file couldn’t be reloaded."
        let pipeline = LRCLIBRecordingPipeline(reloadFile: fixture, warnings: [warning])
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([fixture])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [fixture])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 1)
        XCTAssertEqual(store.appliedCandidateID, candidate.id)
        let entry = try XCTUnwrap(viewModel.saveIssueLogStore.entries.first)
        XCTAssertEqual(entry.title, "Lyrics Saved with Warnings")
        XCTAssertTrue(entry.issues.contains { $0.messages.contains(warning) })
    }

    @MainActor
    func testManualApplyRejectsRefreshRequiredSeed() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fixture = try LRCLIBLyricsTestSupport.makeObservedFile(named: "recovery-required.mp3", directory: directory)
        let projected = fixture.projectingRecoveryState()
        let candidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 91,
            track: projected.title,
            artist: projected.artist,
            syncedLyrics: "[00:01.00]Line"
        )
        let client = LRCLIBGatedClient(
            candidatesByTrackName: [LRCLIBFileSearchInput(file: projected).title: [candidate]]
        )
        let pipeline = LRCLIBRecordingPipeline(reloadFile: nil)
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([projected])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [projected])
        store.searchCurrentFile()
        try await waitForSearchToFinish(store)

        store.startManualApply(writer: viewModel)
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWriteCount, 0)
        XCTAssertNil(store.appliedCandidateID)
    }

    @MainActor
    func testManualApplyWritesLyricsAndPreservesUnrelatedTagsOnRealFixtures() async throws {
        for fileExtension in ["flac", "m4a"] {
            let fixtureURL = try MetadataTestTokens.makeFixtureCopy(fileExtension: fileExtension)
            addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fixtureURL) }
            let base = TagLibAudioMetadataPipeline()
            _ = try? base.writeRawMetadataPatch(
                RawMetadataPatch(valuesToSet: [
                    "TITLE": ["Reviewed Title"],
                    "ARTIST": ["Reviewed Artist"],
                    "CUSTOM-KEEP": ["untouched"]
                ]),
                to: fixtureURL,
                expectedVersion: nil
            )
            let file = try await MetadataTestTokens.makeVerifiedAudioFile(at: fixtureURL)
            let input = LRCLIBFileSearchInput(file: file)
            let syncedLyrics = "[00:01.00]\(fileExtension) line"
            let candidate = LRCLIBLyricsTestSupport.makeCandidate(
                id: fileExtension == "flac" ? 101 : 102,
                track: input.title,
                artist: input.artist,
                syncedLyrics: syncedLyrics
            )
            let client = LRCLIBGatedClient(candidatesByTrackName: [input.title: [candidate]])
            let pipeline = LRCLIBRealReadbackPipeline()
            let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
            viewModel.mergeQuickImportFiles([file])
            let store = LRCLIBLyricsBrowserStore(client: client)
            store.seed(from: [file])
            store.searchCurrentFile()
            try await waitForSearchToFinish(store)

            let beforeMap = try base.rawMetadataValueMap(for: fixtureURL)
            store.startManualApply(writer: viewModel)
            try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

            XCTAssertEqual(pipeline.rawWriteCount, 1, fileExtension)
            XCTAssertEqual(pipeline.rawWrites.first?.version, file.metadataFileVersion, fileExtension)
            XCTAssertEqual(store.appliedCandidateID, candidate.id, fileExtension)

            let afterMap = try base.rawMetadataValueMap(for: fixtureURL)
            XCTAssertEqual(afterMap["LYRICS"], [syncedLyrics], fileExtension)
            XCTAssertEqual(afterMap["TITLE"], beforeMap["TITLE"], fileExtension)
            XCTAssertEqual(afterMap["ARTIST"], beforeMap["ARTIST"], fileExtension)
            XCTAssertEqual(afterMap["CUSTOM-KEEP"], ["untouched"], fileExtension)
            if fileExtension == "flac" {
                // The package exposes an audio-content identity for FLAC; M4A does
                // not in this pinned 0.8.1 surface, so that check is flac-only and
                // the tag-map readback above remains the independent disk evidence.
                let snapshot = try TagLibMetadataManager.readSnapshot(from: fixtureURL, includingAudioContent: true)
                XCTAssertNotNil(snapshot.audioContentIdentity, fileExtension)
            }
        }
    }

    // MARK: - Bulk application (AM-05 mixed queue)

    @MainActor
    func testAutoApplyUsesOnlyHighConfidenceSyncedMatches() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = try LRCLIBLyricsTestSupport.makeObservedFile(
            named: "confidence.mp3",
            directory: directory,
            title: "Correct Song",
            artist: "Correct Artist"
        )
        let input = LRCLIBFileSearchInput(file: file)
        let wrongArtist = LRCLIBLyricsTestSupport.makeCandidate(
            id: 1,
            track: "Correct Song",
            artist: "Different Artist",
            syncedLyrics: "[00:01.00]Wrong"
        )
        let plainOnly = LRCLIBLyricsTestSupport.makeCandidate(
            id: 2,
            track: "Correct Song",
            artist: "Correct Artist",
            plainLyrics: "plain"
        )
        let exact = LRCLIBLyricsTestSupport.makeCandidate(
            id: 3,
            track: "Correct Song",
            artist: "Correct Artist",
            syncedLyrics: "[00:01.00]Right"
        )
        let client = LRCLIBGatedClient(candidatesByTrackName: [input.title: [wrongArtist, plainOnly, exact]])
        let writer = LRCLIBRecordingWriter()
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [file])

        XCTAssertTrue(store.startAutoApply(writer: writer))
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        let intent = try XCTUnwrap(writer.autoIntents.first)
        XCTAssertEqual(intent.entries.count, 1)
        XCTAssertEqual(intent.entries.first?.candidateID, exact.id)
        XCTAssertEqual(intent.entries.first?.lyrics, "[00:01.00]Right")
        XCTAssertNotNil(intent.entries.first?.write)
    }

    @MainActor
    func testBulkMixedSuccessStaleUnsupportedAccountsEveryEntryOnce() async throws {
        let directory = try LRCLIBLyricsTestSupport.makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let base = TagLibAudioMetadataPipeline()
        let fixtureURL = try MetadataTestTokens.makeFixtureCopy(fileExtension: "flac")
        addTeardownBlock { MetadataTestTokens.removeFixtureCopy(at: fixtureURL) }
        let eligibleURL = directory.appendingPathComponent("eligible.flac")
        let staleURL = directory.appendingPathComponent("stale.flac")
        try FileManager.default.copyItem(at: fixtureURL, to: eligibleURL)
        try FileManager.default.copyItem(at: fixtureURL, to: staleURL)
        _ = try? base.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: [
                "TITLE": ["Eligible Song"],
                "ARTIST": ["Eligible Artist"]
            ]),
            to: eligibleURL,
            expectedVersion: nil
        )
        _ = try? base.writeRawMetadataPatch(
            RawMetadataPatch(valuesToSet: [
                "TITLE": ["Stale Song"],
                "ARTIST": ["Stale Artist"]
            ]),
            to: staleURL,
            expectedVersion: nil
        )
        let eligible = try await MetadataTestTokens.makeVerifiedAudioFile(at: eligibleURL)
        let stale = try await MetadataTestTokens.makeVerifiedAudioFile(at: staleURL)

        let unsupported = try LRCLIBLyricsTestSupport.makeObservedFile(
            named: "unsupported.xm",
            directory: directory,
            title: "Unsupported Song",
            artist: "Unsupported Artist"
        )

        let eligibleInput = LRCLIBFileSearchInput(file: eligible)
        let staleInput = LRCLIBFileSearchInput(file: stale)
        let unsupportedInput = LRCLIBFileSearchInput(file: unsupported)
        let eligibleCandidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 201,
            track: eligibleInput.title,
            artist: eligibleInput.artist,
            duration: eligibleInput.durationSeconds.map(Double.init),
            syncedLyrics: "[00:01.00]Eligible"
        )
        let staleCandidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 202,
            track: staleInput.title,
            artist: staleInput.artist,
            duration: staleInput.durationSeconds.map(Double.init),
            syncedLyrics: "[00:01.00]Stale"
        )
        let unsupportedCandidate = LRCLIBLyricsTestSupport.makeCandidate(
            id: 203,
            track: unsupportedInput.title,
            artist: unsupportedInput.artist,
            duration: unsupportedInput.durationSeconds.map(Double.init),
            syncedLyrics: "[00:01.00]Unsupported"
        )
        let client = LRCLIBGatedClient(candidatesByTrackName: [
            eligibleInput.title: [eligibleCandidate],
            staleInput.title: [staleCandidate],
            unsupportedInput.title: [unsupportedCandidate]
        ])
        let pipeline = LRCLIBRealReadbackPipeline()
        let viewModel = AudioViewModelTestFactory.make(metadataPipeline: pipeline)
        viewModel.mergeQuickImportFiles([eligible, stale, unsupported])
        let store = LRCLIBLyricsBrowserStore(client: client)
        store.seed(from: [eligible, stale, unsupported])

        // Invalidate the second target after review without publishing a reload:
        // the captured observation is now stale for the strict route.
        let unsupportedBytesBefore = try Data(contentsOf: unsupported.url)
        try Data(repeating: 0x55, count: 128).write(to: staleURL)
        let staleBytesAfterChange = try Data(contentsOf: staleURL)

        XCTAssertTrue(store.startAutoApply(writer: viewModel))
        try await LRCLIBLyricsTestSupport.waitForOperationToDrain(store)

        XCTAssertEqual(pipeline.rawWrites.count, 1)
        XCTAssertEqual(pipeline.rawWrites.first?.url, eligibleURL)
        let afterMap = try base.rawMetadataValueMap(for: eligibleURL)
        XCTAssertEqual(afterMap["LYRICS"], ["[00:01.00]Eligible"])
        XCTAssertEqual(try Data(contentsOf: staleURL), staleBytesAfterChange)
        // The unsupported fixture is not a parseable audio container, so its
        // independent evidence is bytes-unchanged rather than a package read.
        XCTAssertEqual(try Data(contentsOf: unsupported.url), unsupportedBytesBefore)

        let entry = try XCTUnwrap(viewModel.saveIssueLogStore.entries.first)
        XCTAssertTrue(entry.summary.contains("1 of 3"), entry.summary)
        XCTAssertEqual(Set(entry.issues.map(\.fileName)), ["stale.flac", "unsupported.xm"])
        // The store marks the committed row's original candidate once; the current
        // row is still the first (eligible) row because the bulk job never navigates.
        XCTAssertEqual(store.currentIndex, 0)
        XCTAssertEqual(store.appliedCandidateID, eligibleCandidate.id)
    }

    // MARK: - Helpers

    @MainActor
    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @MainActor
    private func waitForSearchToFinish(
        _ store: LRCLIBLyricsBrowserStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await LRCLIBLyricsTestSupport.waitUntil(deadlineSeconds: 3) {
            store.searchState != .searching
        }
        XCTAssertNotEqual(store.searchState, .searching, "Timed out waiting for LRCLIB search", file: file, line: line)
    }

    @MainActor
    private func waitForQueuedMutation(
        in viewModel: AudioViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            let count = await viewModel.fileMutationCoordinator.queuedMutationCount
            if count > 0 {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected the strict write to queue behind the reservation", file: file, line: line)
    }
}

// MARK: - URL protocol fake

private nonisolated final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: LRCLIBClientError.invalidResponse)
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
