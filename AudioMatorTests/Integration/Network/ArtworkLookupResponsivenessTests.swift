import XCTest
import TagLibAudioMetadata
@testable import AudioMator

nonisolated final class ArtworkLookupResponsivenessTests: XCTestCase {
    // MARK: - Search lifecycle

    @MainActor
    func testNonCooperativeSearchTimesOutAndClearsLoadingState() async throws {
        let gate = ArtworkLookupGate()
        let service = NonCooperativeArtworkService(searchGate: gate)
        let viewModel = makeViewModel(service: service)
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        await gate.waitUntilStarted()

        try await waitUntil {
            viewModel.artworkLookupSession?.isLoading == false
        }

        XCTAssertEqual(
            viewModel.artworkLookupSession?.searchFailureMessage,
            "Searching iTunes for artwork took too long to complete."
        )
        XCTAssertNil(viewModel.artworkLookupSession?.downloadFault)
        XCTAssertTrue(viewModel.artworkLookupSession?.results.isEmpty == true)
        XCTAssertNotNil(viewModel.artworkLookupSession)
        await gate.release()
    }

    @MainActor
    func testDismissedNonCooperativeSearchDoesNotRetainViewModel() async throws {
        let gate = ArtworkLookupGate()
        let service = NonCooperativeArtworkService(searchGate: gate)
        var viewModel: AudioViewModel? = makeViewModel(service: service)
        weak let weakViewModel = viewModel
        let file = makeArtworkFile()
        viewModel?.mergeQuickImportFiles([file])
        viewModel?.setSelectedAudioIDs([file.id])

        viewModel?.findOnlineArtwork(for: file)
        await gate.waitUntilStarted()
        viewModel?.dismissArtworkLookup()
        viewModel = nil

        try await waitUntil { weakViewModel == nil }
        await gate.release()
    }

    @MainActor
    func testCancelledSearchClearsLoadingState() async throws {
        let gate = ArtworkLookupGate()
        let service = NonCooperativeArtworkService(searchGate: gate)
        let viewModel = makeViewModel(service: service)
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        await gate.waitUntilStarted()
        viewModel.artworkLookupTask?.cancel()

        try await waitUntil {
            viewModel.artworkLookupSession?.isLoading == false
        }
        XCTAssertEqual(
            viewModel.artworkLookupSession?.searchCancellationMessage,
            "Artwork search cancelled."
        )
        XCTAssertNil(viewModel.artworkLookupSession?.searchFailureMessage)
        await gate.release()
    }

    // MARK: - Download lifecycle

    @MainActor
    func testNonCooperativeDownloadTimesOutAndClearsApplyingState() async throws {
        let gate = ArtworkLookupGate()
        let result = makeArtworkResult()
        let service = NonCooperativeArtworkService(
            searchResults: [result],
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service)
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

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
            viewModel.artworkLookupSession?.downloadFault,
            .failed(
                candidateID: result.id,
                message: "Downloading artwork from iTunes took too long to complete."
            )
        )
        XCTAssertNil(viewModel.artworkLookupSession?.searchFailureMessage)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1)
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, result.id)
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertNotNil(viewModel.artworkLookupSession)
        await gate.release()
    }

    @MainActor
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
        viewModel?.setSelectedAudioIDs([file.id])

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

    @MainActor
    func testDownloadFailureKeepsResultsAndSameCandidateRetrySucceeds() async throws {
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            downloadOutcomes: [.failure(.downloadFailed), .success(expectedPNG)],
            expectedPNGData: expectedPNG
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        let initialSearchCallCount = await service.recordedSearchCallCount()
        XCTAssertEqual(initialSearchCallCount, 1)
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)

        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession?.downloadFault != nil
        }

        XCTAssertEqual(
            viewModel.artworkLookupSession?.downloadFault,
            .failed(candidateID: result.id, message: "The artwork download failed.")
        )
        // The failed download keeps the grid and the selected candidate, and the
        // Apply affordance becomes an explicit same-candidate retry.
        XCTAssertEqual(viewModel.artworkLookupSession?.searchState, .results)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1)
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, result.id)
        XCTAssertNil(viewModel.artworkLookupSession?.searchFailureMessage)
        XCTAssertTrue(viewModel.artworkLookupSession?.canSelectCandidate == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.isRetryingSelectedCandidate == true)
        XCTAssertEqual(viewModel.edit?.artworkEditAction, .unchanged)
        let failedDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(failedDownloadCandidateIDs, [result.id])

        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        let retriedSearchCallCount = await service.recordedSearchCallCount()
        XCTAssertEqual(retriedSearchCallCount, 1, "Retry must not repeat the search")
        let retriedDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(retriedDownloadCandidateIDs, [result.id, result.id])
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testDownloadFailureAllowsSelectingAnotherCandidateAndApplying() async throws {
        let candidateA = makeArtworkResult(id: "a", title: "Candidate A")
        let candidateB = makeArtworkResult(id: "b", title: "Candidate B")
        let secondCandidatePNG = makeExpectedPNGData(seed: 0x2)
        let service = ControllableArtworkService(
            searchOutcomes: [.success([candidateA, candidateB])],
            downloadOutcomes: [.failure(.downloadFailed), .success(secondCandidatePNG)]
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, candidateA.id)

        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession?.downloadFault != nil
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.downloadFault?.candidateID, candidateA.id)

        viewModel.selectArtworkLookupResult(id: candidateB.id)
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, candidateB.id)
        XCTAssertNil(viewModel.artworkLookupSession?.downloadFault, "Selecting another candidate replaces the fault")
        XCTAssertFalse(viewModel.artworkLookupSession?.isRetryingSelectedCandidate == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)

        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        let alternateSearchCallCount = await service.recordedSearchCallCount()
        XCTAssertEqual(alternateSearchCallCount, 1)
        let alternateDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(alternateDownloadCandidateIDs, [candidateA.id, candidateB.id])
        try assertStagedArtwork(secondCandidatePNG, in: viewModel)
    }

    @MainActor
    func testDownloadTimeoutIsRetryableAndKeepsResults() async throws {
        let gate = ArtworkLookupGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = NonCooperativeArtworkService(
            searchResults: [result],
            downloadGate: gate,
            downloadData: expectedPNG
        )
        let viewModel = makeViewModel(service: service)
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

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
            viewModel.artworkLookupSession?.downloadFault?.message,
            "Downloading artwork from iTunes took too long to complete."
        )
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1)
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)

        await gate.release()
        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testDuplicateApplyStartsSingleDownload() async throws {
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: expectedPNG,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        XCTAssertTrue(viewModel.artworkLookupSession?.isApplying == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canSelectCandidate == true)

        viewModel.applySelectedArtworkLookupResult()
        viewModel.selectArtworkLookupResult(id: result.id)
        let duplicateApplyDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(duplicateApplyDownloadCandidateIDs, [result.id])

        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        let completedDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(completedDownloadCandidateIDs, [result.id])
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testCancelDownloadKeepsResultsAndAllowsRetry() async throws {
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: expectedPNG,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        viewModel.cancelSelectedArtworkDownload()

        XCTAssertEqual(
            viewModel.artworkLookupSession?.downloadFault,
            .cancelled(candidateID: result.id, message: "Artwork download cancelled.")
        )
        XCTAssertFalse(viewModel.artworkLookupSession?.isApplying == true)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1)
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, result.id)
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.canSelectCandidate == true)
        XCTAssertNil(viewModel.artworkLookupSession?.searchFailureMessage)
        XCTAssertEqual(viewModel.edit?.artworkEditAction, .unchanged)

        await gate.releaseAll()
        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        let retriedDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(retriedDownloadCandidateIDs, [result.id, result.id])
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testLateDownloadCompletionAfterDismissOrNewSessionIsIgnored() async throws {
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result]), .success([result])],
            expectedPNGData: expectedPNG,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        let firstSessionID = try XCTUnwrap(viewModel.artworkLookupSession?.id)
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        viewModel.dismissArtworkLookup()
        XCTAssertNil(viewModel.artworkLookupSession)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            guard let session = viewModel.artworkLookupSession else { return false }
            return session.id != firstSessionID && session.searchState == .results
        }
        let secondSessionID = try XCTUnwrap(viewModel.artworkLookupSession?.id)

        await gate.releaseAll()
        try await waitUntilAsync {
            await service.recordedCompletedDownloadCount() >= 1
        }
        try await Task.sleep(for: .milliseconds(40))

        // The superseded attempt cannot publish a fault, a staged draft, or close
        // the newer session.
        XCTAssertEqual(viewModel.artworkLookupSession?.id, secondSessionID)
        XCTAssertEqual(viewModel.artworkLookupSession?.searchState, .results)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1)
        XCTAssertNil(viewModel.artworkLookupSession?.download)
        XCTAssertNil(viewModel.artworkLookupSession?.downloadFault)
        XCTAssertEqual(viewModel.edit?.artworkEditAction, .unchanged)
        XCTAssertNil(viewModel.multiEdit)
    }

    @MainActor
    func testLateCancelledAttemptCannotClearNewerAttempt() async throws {
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: expectedPNG,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }

        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)
        let firstAttempt = try XCTUnwrap(viewModel.artworkLookupSession?.download)

        viewModel.cancelSelectedArtworkDownload()
        viewModel.applySelectedArtworkLookupResult()
        let secondAttempt = try XCTUnwrap(viewModel.artworkLookupSession?.download)
        XCTAssertNotEqual(firstAttempt.id, secondAttempt.id)
        await gate.waitUntilStarted(2)

        // Let the cancelled attempt's late handler run; it must not clear the
        // newer attempt's progress state or its task handle.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.artworkLookupSession?.download?.id, secondAttempt.id)
        XCTAssertTrue(viewModel.artworkLookupSession?.isApplying == true)
        XCTAssertNil(viewModel.artworkLookupSession?.downloadFault)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)

        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        let racyAttemptDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(racyAttemptDownloadCandidateIDs, [result.id, result.id])
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    // MARK: - Search fault separation

    @MainActor
    func testSearchFaultIsSeparateFromDownloadFaultAndRetryRecovers() async throws {
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.failure(.searchFailed), .success([result])],
            downloadOutcomes: [.success(expectedPNG)],
            expectedPNGData: expectedPNG
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .failed(message: "The artwork search failed.")
        }

        XCTAssertEqual(viewModel.artworkLookupSession?.searchFailureMessage, "The artwork search failed.")
        XCTAssertNil(viewModel.artworkLookupSession?.downloadFault)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canSelectCandidate == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.showsSearchRetry == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.results.isEmpty == true)
        let failedSessionID = try XCTUnwrap(viewModel.artworkLookupSession?.id)

        viewModel.applySelectedArtworkLookupResult()
        viewModel.selectArtworkLookupResult(id: result.id)
        XCTAssertTrue(viewModel.artworkLookupSession?.results.isEmpty == true)
        let noDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(noDownloadCandidateIDs, [])

        viewModel.retryArtworkSearch()
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        let retriedSearchCallCount = await service.recordedSearchCallCount()
        XCTAssertEqual(retriedSearchCallCount, 2)
        XCTAssertEqual(viewModel.artworkLookupSession?.id, failedSessionID, "Search retry keeps the sheet session")
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1)
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, result.id)

        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testSearchFailureCannotBeClearedByCandidateSelectionOrDownload() async throws {
        let service = ControllableArtworkService(
            searchOutcomes: [.failure(.searchFailed), .failure(.searchFailed)]
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .failed(message: "The artwork search failed.")
        }
        let failedSessionID = try XCTUnwrap(viewModel.artworkLookupSession?.id)

        viewModel.selectArtworkLookupResult(id: "candidate")
        viewModel.applySelectedArtworkLookupResult()

        XCTAssertEqual(viewModel.artworkLookupSession?.id, failedSessionID)
        XCTAssertEqual(viewModel.artworkLookupSession?.searchState, .failed(message: "The artwork search failed."))
        XCTAssertNil(viewModel.artworkLookupSession?.download)
        XCTAssertNil(viewModel.artworkLookupSession?.downloadFault)
        let adverseSearchCallCount = await service.recordedSearchCallCount()
        let adverseDownloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(adverseSearchCallCount, 1)
        XCTAssertEqual(adverseDownloadCandidateIDs, [])
        XCTAssertEqual(viewModel.edit?.artworkEditAction, .unchanged)
    }

    @MainActor
    func testApplyPredicateAcrossSearchingResolvingFailedAndApplying() async throws {
        let searchGate = ArtworkLookupGate()
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result]), .failure(.searchFailed)],
            expectedPNGData: expectedPNG,
            searchGate: searchGate,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        await searchGate.waitUntilStarted()

        // Searching: no selection, no apply.
        XCTAssertTrue(viewModel.artworkLookupSession?.isLoading == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canSelectCandidate == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.showsSearchRetry == true)

        await searchGate.release()
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }

        // Settled: apply and selection enabled.
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.canSelectCandidate == true)
        XCTAssertEqual(viewModel.artworkLookupSession?.applyActionTitle, "Use Selected Artwork")

        // Downloading: apply and selection disabled, cancellation available.
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)
        XCTAssertTrue(viewModel.artworkLookupSession?.isApplying == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canSelectCandidate == true)

        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        // Failed search: no stale selection can enable apply, retry available.
        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .failed(message: "The artwork search failed.")
        }
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertFalse(viewModel.artworkLookupSession?.canSelectCandidate == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.showsSearchRetry == true)
    }

    // MARK: - Candidate preview identity

    @MainActor
    func testSelectedPreviewFallbackRestartsForCandidateAAndCannotBeAdvancedByCandidateB() async throws {
        let a1 = URL(string: "https://example.com/a-hires.jpg")!
        let a2 = URL(string: "https://example.com/a-standard.jpg")!
        let b1 = URL(string: "https://example.com/b-hires.jpg")!
        let b2 = URL(string: "https://example.com/b-standard.jpg")!
        let candidateA = makeArtworkResult(
            id: "a",
            title: "Candidate A",
            hiresURL: a1,
            standardURL: a2
        )
        let candidateB = makeArtworkResult(
            id: "b",
            title: "Candidate B",
            hiresURL: b1,
            standardURL: b2
        )
        let service = ControllableArtworkService(searchOutcomes: [.success([candidateA, candidateB])])
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }

        // Candidate A starts at the first preferred preview URL, in order.
        var candidateAFallback = ArtworkPreviewFallback(
            urls: try XCTUnwrap(viewModel.artworkLookupSession?.selectedResult).preferredPreviewURLs
        )
        XCTAssertEqual(candidateAFallback.currentURL, a1)
        XCTAssertTrue(candidateAFallback.advance(afterFailedURL: a1))
        XCTAssertEqual(candidateAFallback.currentURL, a2)

        viewModel.selectArtworkLookupResult(id: candidateB.id)
        var candidateBFallback = ArtworkPreviewFallback(
            urls: try XCTUnwrap(viewModel.artworkLookupSession?.selectedResult).preferredPreviewURLs
        )
        // A candidate switch starts the fallback at URL 0 for the new candidate.
        XCTAssertEqual(candidateBFallback.currentURL, b1)
        XCTAssertEqual(candidateBFallback.urls, [b1, b2], "Fallback must preserve preferred URL order")

        // Candidate A's delayed failure cannot advance candidate B.
        XCTAssertFalse(candidateBFallback.advance(afterFailedURL: a2))
        XCTAssertEqual(candidateBFallback.currentURL, b1)

        // The last URL failure has no successor.
        var lastURLFallback = ArtworkPreviewFallback(urls: [b1, b2], index: 1)
        XCTAssertFalse(lastURLFallback.hasSuccessor)
        XCTAssertFalse(lastURLFallback.advance(afterFailedURL: b2))
        XCTAssertEqual(lastURLFallback.currentURL, b2)

        // In-place identity reset (the state boundary the preview uses) also
        // returns the new candidate to its first URL after a stale selection.
        candidateAFallback.reset()
        XCTAssertEqual(candidateAFallback.currentURL, a1)
    }

    // MARK: - Staging boundary

    @MainActor
    func testArtworkStagingLeavesFileBytesUnchangedUntilInspectorSave() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkLookupResponsivenessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("staged-artwork.mp3")
        let originalBytes = Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        try originalBytes.write(to: fileURL)

        let expectedPNG = makeExpectedPNGData()
        let recorder = ArtworkWriteRecorder()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            downloadOutcomes: [.success(expectedPNG)],
            expectedPNGData: expectedPNG
        )
        let viewModel = AudioViewModelTestFactory.make(
            metadataPipeline: ArtworkLookupMetadataPipeline(writeRecorder: recorder),
            artworkLookupService: service,
            artworkLookupOperationTimeout: .seconds(5)
        )
        let file = AudioFileTestFactory.make(
            url: fileURL,
            title: "Test Track",
            album: "Test Album"
        )
        prepareLookupDraft(for: file, in: viewModel)
        viewModel.setSelectedAudioIDs([file.id])
        var draft = try XCTUnwrap(viewModel.edit)
        draft.title = "Edited Title"
        draft.comment = "Edited Comment"
        viewModel.edit = draft

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        // Staging only: the file bytes and the metadata pipeline are untouched
        // until the separate Inspector Save.
        XCTAssertEqual(try Data(contentsOf: fileURL), originalBytes)
        XCTAssertEqual(recorder.invocationCount, 0)
        XCTAssertNil(viewModel.multiEdit)

        let stagedAction = try XCTUnwrap(viewModel.edit?.artworkEditAction)
        guard case .replace(let pendingArtwork) = stagedAction else {
            return XCTFail("Expected staged artwork replacement, got \(stagedAction)")
        }
        XCTAssertEqual(pendingArtwork.data, expectedPNG)
        XCTAssertEqual(pendingArtwork.mimeType, "image/png")

        // Unrelated draft fields survive the artwork handoff.
        XCTAssertEqual(viewModel.edit?.title, "Edited Title")
        XCTAssertEqual(viewModel.edit?.comment, "Edited Comment")
        XCTAssertEqual(viewModel.editSourceFileID, file.id)
        XCTAssertTrue(viewModel.hasUnsavedInspectorChanges)
    }

    // MARK: - Destination-draft ownership (N4b)

    @MainActor
    func testOnlineDownloadRejectsWhenSelectionChangesBeforeCompletion() async throws {
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: expectedPNG,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let fileA = makeArtworkFile(url: URL(fileURLWithPath: "/tmp/artwork-a.mp3"), title: "Track A")
        let fileB = makeArtworkFile(url: URL(fileURLWithPath: "/tmp/artwork-b.mp3"), title: "Track B")
        viewModel.mergeQuickImportFiles([fileA, fileB])
        viewModel.setSelectedAudioIDs([fileA.id, fileB.id])

        viewModel.findOnlineArtwork(for: [fileA, fileB])
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        XCTAssertEqual(
            viewModel.artworkLookupSession?.transfer?.command.targetIDs,
            [fileA.id, fileB.id],
            "The session must capture the ordered draft target set"
        )

        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        // The draft changes while the download is gated: a new single-file draft
        // for B owns the Inspector now.
        viewModel.setSelectedAudioIDs([fileB.id])
        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession?.downloadFault?.isTransferFault == true
        }

        let fault = try XCTUnwrap(viewModel.artworkLookupSession?.downloadFault)
        guard case .staleSelection(let message) = fault else {
            return XCTFail("Expected a stale-selection destination fault, got \(fault)")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNil(viewModel.artworkLookupSession?.download)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1, "Grid and selected candidate stay available")
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, result.id)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.canSelectCandidate == true)
        XCTAssertEqual(viewModel.editSourceFileID, fileB.id)
        XCTAssertEqual(viewModel.edit?.artworkEditAction, .unchanged)
        XCTAssertNil(viewModel.multiEdit)
    }

    @MainActor
    func testOnlineDownloadRejectsWhenCapturedTargetIsRemoved() async throws {
        let gate = ArtworkCallGate()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: makeExpectedPNGData(),
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        viewModel.removeQuickImportFile(id: file.id)
        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession?.downloadFault?.isTransferFault == true
        }

        XCTAssertTrue(viewModel.artworkLookupSession?.downloadFault?.isRetryable == false)
        XCTAssertNil(viewModel.edit, "No draft is created for a removed captured target")
        XCTAssertNil(viewModel.multiEdit)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.count, 1)
    }

    @MainActor
    func testNewerClearSupersedesPendingOnlineDownload() async throws {
        let gate = ArtworkCallGate()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: makeExpectedPNGData(),
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        // A newer synchronous artwork command owns the draft and supersedes the
        // pending download.
        viewModel.clearArtwork(for: file)
        XCTAssertEqual(viewModel.edit?.artworkEditAction, .remove)

        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession?.downloadFault?.isTransferFault == true
        }

        XCTAssertEqual(
            viewModel.edit?.artworkEditAction,
            .remove,
            "The late download must not overwrite the newer Clear command"
        )
        if case .superseded? = viewModel.artworkLookupSession?.downloadFault {
            // expected
        } else {
            XCTFail("Expected the pending download to be superseded, got \(String(describing: viewModel.artworkLookupSession?.downloadFault))")
        }
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)
    }

    @MainActor
    func testUnrelatedTextEditDuringDownloadStagesArtworkAndKeepsText() async throws {
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: expectedPNG,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        let capturedCommand = try XCTUnwrap(viewModel.artworkLookupSession?.transfer?.command)
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        // An unrelated text edit advances the draft edit generation only.
        viewModel.edit?.title = "Edited While Waiting"
        XCTAssertTrue(
            viewModel.isCurrentArtworkCommand(capturedCommand),
            "Unrelated text edits must preserve artwork command authority"
        )

        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        XCTAssertEqual(viewModel.edit?.title, "Edited While Waiting")
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testOnlineLookupWithoutInspectorDraftIsPreviewOnly() async throws {
        let expectedPNG = makeExpectedPNGData()
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: expectedPNG
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        viewModel.mergeQuickImportFiles([file])

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }

        XCTAssertTrue(viewModel.artworkLookupSession?.isPreviewOnly == true)
        XCTAssertNil(viewModel.artworkLookupSession?.transfer)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)

        viewModel.applySelectedArtworkLookupResult()
        try await Task.sleep(for: .milliseconds(30))
        let downloadCandidateIDs = await service.recordedDownloadCandidateIDs()
        XCTAssertEqual(downloadCandidateIDs, [], "Preview-only lookups never download or stage")
        XCTAssertNil(viewModel.edit)
        XCTAssertNil(viewModel.multiEdit)

        viewModel.dismissArtworkLookup()
    }

    // MARK: - Storefront selection

    @MainActor
    func testSelectingStorefrontCancelsDelayedSearchAndNeverPublishesStaleResults() async throws {
        let usGate = ArtworkLookupGate()
        let jpGate = ArtworkLookupGate()
        let usResult = makeArtworkResult(id: "us-1", title: "US Cover")
        let jpResult = makeArtworkResult(id: "jp-1", title: "JP Cover")
        let expectedPNG = makeExpectedPNGData(seed: 0x9)
        let service = ControllableArtworkService(
            searchOutcomes: [.success([usResult]), .success([jpResult])],
            expectedPNGData: expectedPNG,
            searchGatesByCountry: ["us": usGate, "jp": jpGate]
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        await usGate.waitUntilStarted()
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .us)
        XCTAssertTrue(viewModel.artworkLookupSession?.canChangeStorefront == true)

        viewModel.selectArtworkLookupStorefront(.jp)
        await jpGate.waitUntilStarted()
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .jp)
        XCTAssertEqual(viewModel.artworkLookupStorefront, .jp)
        XCTAssertTrue(viewModel.artworkLookupSession?.isLoading == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.results.isEmpty == true)

        // Release the superseded US search first; it must not publish into the JP session
        // or disturb JP's loading state.
        await usGate.release()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .jp)
        XCTAssertTrue(viewModel.artworkLookupSession?.isLoading == true)
        XCTAssertTrue(viewModel.artworkLookupSession?.results.isEmpty == true)

        await jpGate.release()
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .jp)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.map(\.id), [jpResult.id])
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, jpResult.id)

        let requests = await service.recordedSearchRequests()
        XCTAssertEqual(requests.map(\.country), ["us", "jp"])

        // The captured Inspector draft authority survives storefront switching.
        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testStorefrontSelectionRetainsChoiceAcrossSessionsAndRetriesInActiveStorefront() async throws {
        let usResult = makeArtworkResult(id: "us-1", title: "US Cover")
        let jpResult = makeArtworkResult(id: "jp-1", title: "JP Cover")
        let expectedPNG = makeExpectedPNGData(seed: 0x7)
        let service = ControllableArtworkService(
            searchOutcomes: [
                .success([usResult]),
                .failure(.searchFailed),
                .success([jpResult]),
                .success([jpResult])
            ],
            expectedPNGData: expectedPNG
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }

        viewModel.selectArtworkLookupStorefront(.jp)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .failed(message: "The artwork search failed.")
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .jp)
        XCTAssertTrue(viewModel.artworkLookupSession?.showsSearchRetry == true)

        // Retrying a failed search must keep the selected storefront.
        viewModel.retryArtworkSearch()
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .jp)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.map(\.id), [jpResult.id])

        viewModel.applySelectedArtworkLookupResult()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }
        try assertStagedArtwork(expectedPNG, in: viewModel)

        // Subsequent artwork lookup sessions remember the selected storefront.
        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .jp)

        let requests = await service.recordedSearchRequests()
        XCTAssertEqual(requests.map(\.country), ["us", "jp", "jp", "jp"])
    }

    @MainActor
    func testStorefrontSelectionIsBlockedWhileDownloadIsInFlight() async throws {
        let gate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData(seed: 0x4)
        let result = makeArtworkResult()
        let service = ControllableArtworkService(
            searchOutcomes: [.success([result])],
            expectedPNGData: expectedPNG,
            downloadGate: gate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        viewModel.applySelectedArtworkLookupResult()
        await gate.waitUntilStarted(1)

        XCTAssertFalse(viewModel.artworkLookupSession?.canChangeStorefront == true)
        viewModel.selectArtworkLookupStorefront(.gb)
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .us)
        XCTAssertEqual(viewModel.artworkLookupStorefront, .us)

        await gate.releaseAll()
        try await waitUntil {
            viewModel.artworkLookupSession == nil
        }

        let requests = await service.recordedSearchRequests()
        XCTAssertEqual(requests.map(\.country), ["us"])
        try assertStagedArtwork(expectedPNG, in: viewModel)
    }

    @MainActor
    func testStorefrontSwitchClearsCandidateDownloadFaultButPreservesTransferFault() async throws {
        let candidateA = makeArtworkResult(id: "a", title: "Candidate A")
        let candidateB = makeArtworkResult(id: "b", title: "Candidate B")
        let candidateC = makeArtworkResult(id: "c", title: "Candidate C")
        let downloadGate = ArtworkCallGate()
        let expectedPNG = makeExpectedPNGData(seed: 0x5)
        let service = ControllableArtworkService(
            searchOutcomes: [.success([candidateA]), .success([candidateB]), .success([candidateC])],
            downloadOutcomes: [.failure(.downloadFailed), .success(expectedPNG)],
            expectedPNGData: expectedPNG,
            downloadGate: downloadGate
        )
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let fileA = makeArtworkFile(url: URL(fileURLWithPath: "/tmp/storefront-a.mp3"), title: "Track A")
        let fileB = makeArtworkFile(url: URL(fileURLWithPath: "/tmp/storefront-b.mp3"), title: "Track B")
        viewModel.mergeQuickImportFiles([fileA, fileB])
        viewModel.setSelectedAudioIDs([fileA.id])

        // 1. A candidate-scoped download failure is cleared when switching storefronts.
        viewModel.findOnlineArtwork(for: fileA)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        viewModel.applySelectedArtworkLookupResult()
        await downloadGate.waitUntilStarted(1)
        await downloadGate.releaseNext()
        try await waitUntil {
            viewModel.artworkLookupSession?.downloadFault != nil
        }
        XCTAssertTrue(viewModel.artworkLookupSession?.downloadFault?.isRetryable == true)

        viewModel.selectArtworkLookupStorefront(.de)
        XCTAssertNil(viewModel.artworkLookupSession?.downloadFault)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .de)
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, candidateB.id)
        XCTAssertTrue(viewModel.artworkLookupSession?.canApplySelectedResult == true)

        // 2. A destination-draft transfer fault is terminal and survives storefront switches.
        viewModel.applySelectedArtworkLookupResult()
        await downloadGate.waitUntilStarted(2)
        viewModel.setSelectedAudioIDs([fileB.id])
        await downloadGate.releaseNext()
        try await waitUntil {
            viewModel.artworkLookupSession?.downloadFault?.isTransferFault == true
        }
        let terminalFault = try XCTUnwrap(viewModel.artworkLookupSession?.downloadFault)

        viewModel.selectArtworkLookupStorefront(.gb)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        XCTAssertEqual(viewModel.artworkLookupSession?.storefront, .gb)
        XCTAssertEqual(viewModel.artworkLookupSession?.selectedResultID, candidateC.id)
        XCTAssertEqual(viewModel.artworkLookupSession?.downloadFault, terminalFault)
        XCTAssertFalse(viewModel.artworkLookupSession?.canApplySelectedResult == true)

        let requests = await service.recordedSearchRequests()
        XCTAssertEqual(requests.map(\.country), ["us", "de", "gb"])
    }

    @MainActor
    func testSelectingSameStorefrontDoesNotRestartSearch() async throws {
        let result = makeArtworkResult(id: "us-only", title: "US Cover")
        let service = ControllableArtworkService(searchOutcomes: [.success([result])])
        let viewModel = makeViewModel(service: service, timeout: .seconds(5))
        let file = makeArtworkFile()
        prepareLookupDraft(for: file, in: viewModel)

        viewModel.findOnlineArtwork(for: file)
        try await waitUntil {
            viewModel.artworkLookupSession?.searchState == .results
        }
        let originalAttemptID = viewModel.artworkLookupSession?.searchAttemptID

        viewModel.selectArtworkLookupStorefront(.us)
        XCTAssertEqual(viewModel.artworkLookupSession?.searchAttemptID, originalAttemptID)
        XCTAssertEqual(viewModel.artworkLookupSession?.results.map(\.id), [result.id])
        let callCount = await service.recordedSearchCallCount()
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Helpers

    /// Selects the file so F3-b creates the Inspector draft that authorizes the
    /// online artwork transfer; production Inspector lookups always have one.
    @MainActor
    private func prepareLookupDraft(for file: AudioFile, in viewModel: AudioViewModel) {
        viewModel.mergeQuickImportFiles([file])
        viewModel.setSelectedAudioIDs([file.id])
    }

    @MainActor
    private func makeViewModel(
        service: any iTunesArtworkServicing,
        timeout: Duration = .milliseconds(40)
    ) -> AudioViewModel {
        AudioViewModelTestFactory.make(
            metadataPipeline: ArtworkLookupMetadataPipeline(),
            artworkLookupService: service,
            artworkLookupOperationTimeout: timeout
        )
    }

    @MainActor
    private func makeArtworkFile(
        url: URL = URL(fileURLWithPath: "/tmp/artwork-lookup.mp3"),
        title: String = "Test Track"
    ) -> AudioFile {
        AudioFileTestFactory.make(
            url: url,
            title: title,
            album: "Test Album"
        )
    }

    private func makeArtworkResult(
        id: String = "1",
        title: String = "Test Album",
        hiresURL: URL? = nil,
        standardURL: URL? = nil
    ) -> iTunesArtworkSearchResult {
        iTunesArtworkSearchResult(
            id: id,
            title: title,
            subtitle: "Test Artist",
            thumbnailURL: nil,
            standardURL: standardURL,
            hiresURL: hiresURL,
            uncompressedURL: nil,
            pixelWidth: 600,
            pixelHeight: 600
        )
    }

    @MainActor
    private func makeExpectedPNGData(seed: UInt8 = 0x1) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, seed, seed, seed, seed])
    }

    @MainActor
    private func assertStagedArtwork(
        _ expectedPNG: Data,
        in viewModel: AudioViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let stagedAction = try XCTUnwrap(viewModel.edit?.artworkEditAction, file: file, line: line)
        guard case .replace(let pendingArtwork) = stagedAction else {
            return XCTFail("Expected staged artwork replacement, got \(stagedAction)", file: file, line: line)
        }
        XCTAssertEqual(pendingArtwork.data, expectedPNG, file: file, line: line)
        XCTAssertEqual(pendingArtwork.mimeType, "image/png", file: file, line: line)
    }

    @MainActor
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

    private func waitUntilAsync(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for artwork lookup state")
    }
}

// MARK: - Controllable service

private enum ArtworkServiceTestError: LocalizedError, Sendable {
    case searchFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .searchFailed:
            return "The artwork search failed."
        case .downloadFailed:
            return "The artwork download failed."
        }
    }
}

private actor ArtworkServiceScript {
    private var searchOutcomes: [Result<[iTunesArtworkSearchResult], ArtworkServiceTestError>]
    private var downloadOutcomes: [Result<Data, ArtworkServiceTestError>]
    private let expectedPNGData: Data
    private let searchGate: ArtworkLookupGate?
    private let searchGatesByCountry: [String: ArtworkLookupGate]
    private let downloadGate: ArtworkCallGate?

    private var searchRequests: [iTunesArtworkSearchRequest] = []
    private var downloadCandidateIDs: [String] = []
    private var completedDownloadCount = 0

    init(
        searchOutcomes: [Result<[iTunesArtworkSearchResult], ArtworkServiceTestError>],
        downloadOutcomes: [Result<Data, ArtworkServiceTestError>],
        expectedPNGData: Data,
        searchGate: ArtworkLookupGate?,
        searchGatesByCountry: [String: ArtworkLookupGate],
        downloadGate: ArtworkCallGate?
    ) {
        self.searchOutcomes = searchOutcomes
        self.downloadOutcomes = downloadOutcomes
        self.expectedPNGData = expectedPNGData
        self.searchGate = searchGate
        self.searchGatesByCountry = searchGatesByCountry
        self.downloadGate = downloadGate
    }

    func recordSearch(_ request: iTunesArtworkSearchRequest) async throws -> [iTunesArtworkSearchResult] {
        searchRequests.append(request)
        if let countryGate = searchGatesByCountry[request.country] {
            await countryGate.wait()
        } else if let searchGate {
            await searchGate.wait()
        }
        let outcome = nextSearchOutcome()
        switch outcome {
        case .success(let results):
            return results
        case .failure(let error):
            throw error
        }
    }

    func recordDownload(candidateID: String) async throws -> Data {
        downloadCandidateIDs.append(candidateID)
        if let downloadGate {
            await downloadGate.wait()
        }
        let outcome = nextDownloadOutcome()
        completedDownloadCount += 1
        switch outcome {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    func recordedSearchCallCount() -> Int {
        searchRequests.count
    }

    func recordedSearchRequests() -> [iTunesArtworkSearchRequest] {
        searchRequests
    }

    func recordedDownloadCandidateIDs() -> [String] {
        downloadCandidateIDs
    }

    func recordedCompletedDownloadCount() -> Int {
        completedDownloadCount
    }

    private func nextSearchOutcome() -> Result<[iTunesArtworkSearchResult], ArtworkServiceTestError> {
        if searchOutcomes.count > 1 {
            return searchOutcomes.removeFirst()
        }
        return searchOutcomes.first ?? .success([])
    }

    private func nextDownloadOutcome() -> Result<Data, ArtworkServiceTestError> {
        if downloadOutcomes.count > 1 {
            return downloadOutcomes.removeFirst()
        }
        return downloadOutcomes.first ?? .success(expectedPNGData)
    }
}

private final class ControllableArtworkService: iTunesArtworkServicing, @unchecked Sendable {
    private let script: ArtworkServiceScript

    init(
        searchOutcomes: [Result<[iTunesArtworkSearchResult], ArtworkServiceTestError>] = [.success([])],
        downloadOutcomes: [Result<Data, ArtworkServiceTestError>] = [],
        expectedPNGData: Data = Data(),
        searchGate: ArtworkLookupGate? = nil,
        searchGatesByCountry: [String: ArtworkLookupGate] = [:],
        downloadGate: ArtworkCallGate? = nil
    ) {
        self.script = ArtworkServiceScript(
            searchOutcomes: searchOutcomes,
            downloadOutcomes: downloadOutcomes,
            expectedPNGData: expectedPNGData,
            searchGate: searchGate,
            searchGatesByCountry: searchGatesByCountry,
            downloadGate: downloadGate
        )
    }

    func search(
        _ request: iTunesArtworkSearchRequest
    ) async throws -> [iTunesArtworkSearchResult] {
        try await script.recordSearch(request)
    }

    func downloadArtworkData(
        for result: iTunesArtworkSearchResult
    ) async throws -> iTunesDownloadedArtwork {
        iTunesDownloadedArtwork(pngData: try await script.recordDownload(candidateID: result.id))
    }

    func recordedSearchCallCount() async -> Int {
        await script.recordedSearchCallCount()
    }

    func recordedSearchRequests() async -> [iTunesArtworkSearchRequest] {
        await script.recordedSearchRequests()
    }

    func recordedDownloadCandidateIDs() async -> [String] {
        await script.recordedDownloadCandidateIDs()
    }

    func recordedCompletedDownloadCount() async -> Int {
        await script.recordedCompletedDownloadCount()
    }
}

private actor ArtworkCallGate {
    private var startedCount = 0
    private var isReleased = false
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        startedCount += 1
        resumeReadyStartWaiters()
        guard !isReleased else { return }
        await withCheckedContinuation { pendingContinuations.append($0) }
    }

    func waitUntilStarted(_ count: Int) async {
        guard startedCount < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func releaseNext() {
        guard !pendingContinuations.isEmpty else { return }
        pendingContinuations.removeFirst().resume()
    }

    func releaseAll() {
        isReleased = true
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func resumeReadyStartWaiters() {
        let ready = startWaiters.filter { $0.count <= startedCount }
        startWaiters.removeAll { $0.count <= startedCount }
        ready.forEach { $0.continuation.resume() }
    }
}

// MARK: - Non-cooperative service (timeout coverage)

private final class NonCooperativeArtworkService: iTunesArtworkServicing, @unchecked Sendable {
    private let searchResults: [iTunesArtworkSearchResult]
    private let searchGate: ArtworkLookupGate?
    private let downloadGate: ArtworkLookupGate?
    private let downloadData: Data

    init(
        searchResults: [iTunesArtworkSearchResult] = [],
        searchGate: ArtworkLookupGate? = nil,
        downloadGate: ArtworkLookupGate? = nil,
        downloadData: Data = Data()
    ) {
        self.searchResults = searchResults
        self.searchGate = searchGate
        self.downloadGate = downloadGate
        self.downloadData = downloadData
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
        return iTunesDownloadedArtwork(pngData: downloadData)
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

// MARK: - Metadata pipeline

private nonisolated final class ArtworkWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var invocationCount: Int {
        lock.withLock { count }
    }

    func recordWrite() {
        lock.withLock { count += 1 }
    }
}

private nonisolated final class ArtworkLookupMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    private let writeRecorder: ArtworkWriteRecorder?

    init(writeRecorder: ArtworkWriteRecorder? = nil) {
        self.writeRecorder = writeRecorder
    }

    func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await MainActor.run {
            AudioFileTestFactory.make(id: id, url: url)
        }
    }

    func rawMetadataDumpText(for url: URL) -> String? { nil }
    func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        writeRecorder?.recordWrite()
        return AudioMetadataWriteResult(warnings: [])
    }

    func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        writeRecorder?.recordWrite()
        return AudioMetadataWriteResult(warnings: [])
    }

    func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        writeRecorder?.recordWrite()
        return AudioMetadataWriteResult(warnings: [])
    }
}
