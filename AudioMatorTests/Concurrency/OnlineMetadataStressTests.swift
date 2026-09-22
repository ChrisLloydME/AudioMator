import Darwin
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class OnlineMetadataStressTests: XCTestCase {
    func testLargeMusicBrainzReleasePresentationRunsOffMainAndCompletesWithinDeadline() async throws {
        let fixture = makeMusicBrainzFixture(trackCount: 200)
        let startGate = StressOperationGate()

        let presentationTask = Task {
            try await withAsyncTimeout(
                .seconds(5),
                operationName: "MusicBrainz presentation stress",
                priority: .userInitiated
            ) {
                startGate.blockUntilReleased()
                let ranOnMainThread = pthread_main_np() != 0
                let presentation = MusicBrainzMetadataComparisonBuilder.presentation(
                    for: fixture.release,
                    fallbackFiles: fixture.files
                )
                return StressPresentationResult(
                    ranOnMainThread: ranOnMainThread,
                    presentation: presentation
                )
            }
        }
        let operationStarted = try await waitUntil { startGate.didStart }

        XCTAssertTrue(operationStarted)
        XCTAssertTrue(
            Thread.isMainThread,
            "The main actor must remain schedulable while presentation work is blocked off-main."
        )

        startGate.release()
        let result = try await presentationTask.value
        XCTAssertFalse(result.ranOnMainThread)
        XCTAssertEqual(result.presentation.preview?.matchedFileCount, fixture.files.count)
        XCTAssertEqual(result.presentation.comparisonGroups.count, fixture.files.count)
        XCTAssertTrue(result.presentation.comparisonGroups.allSatisfy { !$0.rows.isEmpty })
    }

    private func makeMusicBrainzFixture(
        trackCount: Int
    ) -> (files: [MusicBrainzFileSearchInput], release: MusicBrainzReleaseDetail) {
        let files = (1...trackCount).map { index in
            MusicBrainzFileSearchInput(
                id: "file-\(index)",
                displayTitle: "Track \(index)",
                title: "Track \(index)",
                artist: "Stress Artist",
                albumArtist: "Stress Artist",
                album: "Stress Album",
                trackNumber: String(index),
                discNumber: "1",
                trackTotal: trackCount,
                durationMilliseconds: 180_000 + index,
                releaseDate: "2026-01-01",
                isrc: "ISRC\(index)",
                barcode: "123456789012"
            )
        }
        let tracks = (1...trackCount).map { index in
            MusicBrainzReleaseDetail.Medium.Track(
                id: "track-\(index)",
                number: String(index),
                title: "Track \(index)",
                artistCredit: "Stress Artist",
                durationMilliseconds: 180_000 + index,
                recordingID: "recording-\(index)",
                isrcs: ["ISRC\(index)"]
            )
        }
        let release = MusicBrainzReleaseDetail(
            id: "stress-release",
            title: "Stress Album",
            artistCredit: "Stress Artist",
            date: "2026-01-01",
            country: "US",
            status: "Official",
            barcode: "123456789012",
            packaging: "",
            asin: "",
            quality: "",
            language: "eng",
            script: "Latn",
            annotation: "",
            genres: [],
            tags: [],
            releaseGroupTitle: "Stress Album",
            releaseGroupID: "stress-group",
            releaseGroupPrimaryType: "Album",
            releaseGroupSecondaryTypes: [],
            labels: [],
            media: [
                MusicBrainzReleaseDetail.Medium(
                    id: "stress-medium",
                    title: "",
                    format: "Digital Media",
                    trackCount: trackCount,
                    discIDs: [],
                    tracks: tracks
                )
            ],
            selectionMatchPreview: nil
        )
        return (files, release)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private nonisolated struct StressPresentationResult: Sendable {
    let ranOnMainThread: Bool
    let presentation: MusicBrainzReleaseMetadataPresentation
}

private nonisolated final class StressOperationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var started = false

    var didStart: Bool {
        lock.withLock { started }
    }

    func blockUntilReleased() {
        lock.withLock { started = true }
        semaphore.wait()
    }

    func release() {
        semaphore.signal()
    }
}
#endif
