import XCTest
@testable import AudioMator

// MARK: – Test seams

/// Counting/barrier planner used to instrument the real converter controller.
/// It wraps the production planner so plans stay real, while every invocation
/// can be counted, held, or cancelled by the test.
private nonisolated final class ConverterTestPlannerWorker: MetadataFilenamePlanWorking, @unchecked Sendable {
    private let lock = NSLock()
    private let base: any MetadataFilenamePlanWorking
    private var inputs: [MetadataFilenamePlannerInput] = []
    private var holdsInvocations = false
    private var heldContinuations: [CheckedContinuation<Void, Never>] = []
    private var invocationWaiters: [CheckedContinuation<Void, Never>] = []
    private var durations: [Duration] = []

    init(base: any MetadataFilenamePlanWorking = MetadataFilenamePlannerWorker()) {
        self.base = base
    }

    var invocationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inputs.count
    }

    var invokedInputs: [MetadataFilenamePlannerInput] {
        lock.lock()
        defer { lock.unlock() }
        return inputs
    }

    var workerDurations: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return durations
    }

    func holdInvocations() {
        lock.lock()
        holdsInvocations = true
        lock.unlock()
    }

    func releaseNextHeldInvocation() {
        lock.lock()
        guard !heldContinuations.isEmpty else {
            lock.unlock()
            return
        }
        let continuation = heldContinuations.removeFirst()
        lock.unlock()
        continuation.resume()
    }

    func waitForInvocationCount(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if inputs.count >= count {
                lock.unlock()
                continuation.resume()
            } else {
                invocationWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    nonisolated func makePlan(_ input: MetadataFilenamePlannerInput) async throws -> MetadataFilenameConverterResult {
        let (waiters, shouldHold) = lock.withLock { () -> ([CheckedContinuation<Void, Never>], Bool) in
            inputs.append(input)
            let waiters = invocationWaiters
            invocationWaiters.removeAll()
            return (waiters, holdsInvocations)
        }
        for waiter in waiters {
            waiter.resume()
        }

        if shouldHold {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock { heldContinuations.append(continuation) }
            }
        }
        try Task.checkCancellation()

        let clock = ContinuousClock()
        let start = clock.now
        let result = try await base.makePlan(input)
        let elapsed = clock.now - start
        lock.withLock { durations.append(elapsed) }
        return result
    }
}

/// Deterministic debounce clock. Either returns immediately (the consumer
/// awaits settlement itself) or holds sleepers until the test releases them.
private nonisolated final class ConverterTestClock: MetadataFilenameDebounceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var durations: [Duration] = []
    private var isGated: Bool
    private var heldContinuations: [CheckedContinuation<Void, Never>] = []
    private var sleeperCount = 0
    private var sleeperWaiters: [CheckedContinuation<Void, Never>] = []

    init(gated: Bool = false) {
        isGated = gated
    }

    var recordedDurations: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return durations
    }

    nonisolated func sleep(for duration: Duration) async throws {
        let (waiters, gated) = lock.withLock { () -> ([CheckedContinuation<Void, Never>], Bool) in
            durations.append(duration)
            sleeperCount += 1
            let waiters = sleeperWaiters
            sleeperWaiters.removeAll()
            return (waiters, isGated)
        }
        for waiter in waiters {
            waiter.resume()
        }

        if gated {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    if !isGated { return true }
                    heldContinuations.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        try Task.checkCancellation()
    }

    func waitForSleeperCount(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if sleeperCount >= count {
                lock.unlock()
                continuation.resume()
            } else {
                sleeperWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func releaseAllSleepers() {
        lock.lock()
        isGated = false
        let continuations = heldContinuations
        heldContinuations.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

/// Gated external-file loader so a late load completion can be raced against
/// manual typing.
private nonisolated final class ConverterTestLoaderGate: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            entered = true
            let waiters = entryWaiters
            entryWaiters.removeAll()
            releaseContinuations.append(continuation)
            lock.unlock()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitForEntry() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if entered {
                lock.unlock()
                continuation.resume()
            } else {
                entryWaiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

/// Records the mutation-scope requests the converter makes.
private nonisolated final class ConverterTestScopeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [[URL]] = []

    var requestedURLs: [[URL]] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func request(_ urls: [URL]) -> String? {
        lock.lock()
        requests.append(urls)
        lock.unlock()
        return nil
    }
}

// MARK: – Fixtures

@MainActor
private final class ConverterTestFixture {
    let directory: URL
    let files: [AudioFile]

    init(fileCount: Int = 2) {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorConverterTests-\(UUID().uuidString)", isDirectory: true)
        var files: [AudioFile] = []
        for index in 0..<fileCount {
            let suffix = Self.suffix(for: index)
            files.append(
                AudioFileTestFactory.make(
                    url: directory.appendingPathComponent("Original \(suffix).mp3"),
                    title: suffix,
                    comment: "Comment \(suffix)"
                )
            )
        }
        self.files = files
    }

    static func suffix(for index: Int) -> String {
        switch index {
        case 0: return "Alpha"
        case 1: return "Beta"
        case 2: return "Gamma"
        default: return "Track\(index)"
        }
    }

    func refreshedFile(at index: Int, title: String? = nil) -> AudioFile {
        let original = files[index]
        return AudioFileTestFactory.make(
            id: original.id,
            url: original.url,
            title: title ?? original.title,
            comment: original.comment
        )
    }
}

@MainActor
private func makeStore(
    worker: any MetadataFilenamePlanWorking = MetadataFilenamePlannerWorker(),
    clock: any MetadataFilenameDebounceClock = ConverterTestClock(),
    scopeRecorder: ConverterTestScopeRecorder? = nil
) -> MetadataFilenameToolStore {
    let store = MetadataFilenameToolStore(worker: worker, clock: clock)
    if let scopeRecorder {
        store.setScopeRequester { urls in
            scopeRecorder.request(urls)
        }
    }
    return store
}

@MainActor
private func present(_ fixture: ConverterTestFixture, in store: MetadataFilenameToolStore) {
    store.present(targetFileIDs: fixture.files.map(\.id))
    store.refresh(files: fixture.files, filesRevision: UUID(), projector: nil)
}

@MainActor
private func settle(_ store: MetadataFilenameToolStore) async {
    await store.waitForPlanSettlement()
}

// MARK: – Regressions

nonisolated final class MetadataFilenameConverterPlanTests: XCTestCase {
    @MainActor
    func testOnePlannerInvocationPerSettledInputAndNoneForReadsOrDispatch() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        XCTAssertEqual(worker.invocationCount, 1)
        XCTAssertEqual(store.displayRenamePlan().rows.count, 2)

        // Reads and dispatch never recompute: the stored plan is consumed.
        for _ in 0..<50 {
            XCTAssertEqual(store.displayRenamePlan().rows.count, 2)
            XCTAssertFalse(store.previewPhaseMessage() != nil)
            _ = store.targetCount
        }
        XCTAssertEqual(worker.invocationCount, 1)

        let dispatch = store.beginDispatch(for: .metadataToFilename)
        XCTAssertNotNil(dispatch)
        XCTAssertEqual(worker.invocationCount, 1)
        XCTAssertEqual(dispatch?.result.renamePlan?.rows.count, 2)
        XCTAssertTrue(store.finishDispatch(dispatch!))
        XCTAssertEqual(worker.invocationCount, 1)
    }

    @MainActor
    func testInactiveModeAndIdleRefreshNeverInvokeThePlanner() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        store.refresh(files: fixture.files, filesRevision: UUID(), projector: nil)
        store.selectMode(nil)
        await settle(store)
        XCTAssertEqual(worker.invocationCount, 0)
        XCTAssertEqual(store.targetCount, 2)
        XCTAssertTrue(store.readyResult(for: .metadataToFilename) == nil)
    }

    @MainActor
    func testDebounceUsesTheStoredOneHundredFiftyMillisecondInterval() async {
        let fixture = ConverterTestFixture()
        let clock = ConverterTestClock()
        let store = makeStore(clock: clock)
        present(fixture, in: store)

        store.selectMode(.metadataToFilename)
        await settle(store)
        XCTAssertEqual(workerInterval(from: clock), .milliseconds(150))
        XCTAssertEqual(store.debounceIntervalForTesting, .milliseconds(150))
    }

    private func workerInterval(from clock: ConverterTestClock) -> Duration? {
        clock.recordedDurations.last
    }

    @MainActor
    func testGatedDebounceCoalescesRapidEditsIntoOnePlannerInvocation() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let clock = ConverterTestClock(gated: true)
        let store = makeStore(worker: worker, clock: clock)
        present(fixture, in: store)

        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await clock.waitForSleeperCount(1)

        store.updateTemplate("{{artist}}", for: .metadataToFilename)
        store.updateTemplate("{{comment}}", for: .metadataToFilename)
        await clock.waitForSleeperCount(2)
        XCTAssertEqual(worker.invocationCount, 0)

        clock.releaseAllSleepers()
        await settle(store)
        XCTAssertEqual(worker.invocationCount, 1)
        XCTAssertEqual(worker.invokedInputs.last?.template, "{{comment}}")
        XCTAssertEqual(store.displayRenamePlan().template, "{{comment}}")
    }

    @MainActor
    func testHoldAndReplaceTwiceOnlyLatestStartsAfterSlotRelease() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        worker.holdInvocations()
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await worker.waitForInvocationCount(1)
        let firstInputID = worker.invokedInputs[0].inputID

        // Replace the input twice while the first worker is still held.
        store.updateTemplate("{{artist}}", for: .metadataToFilename)
        await store.waitForDebounceResolutionForTesting()
        store.updateTemplate("{{comment}}", for: .metadataToFilename)
        await store.waitForDebounceResolutionForTesting()

        XCTAssertEqual(worker.invocationCount, 1, "Only one worker may run at a time")
        XCTAssertNil(store.readyResult(for: .metadataToFilename), "A superseded input cannot publish")
        XCTAssertNil(store.beginDispatch(for: .metadataToFilename), "A superseded input cannot enable Apply")
        XCTAssertEqual(store.currentInputIDForTesting == firstInputID, false)

        worker.releaseNextHeldInvocation()
        await worker.waitForInvocationCount(2)
        XCTAssertEqual(worker.invokedInputs[1].template, "{{comment}}")
        XCTAssertEqual(worker.invocationCount, 2, "The replaced middle input is coalesced away")

        worker.releaseNextHeldInvocation()
        await settle(store)
        XCTAssertEqual(store.displayRenamePlan().template, "{{comment}}")
        XCTAssertTrue(store.displayRenamePlan().canApply)
    }

    @MainActor
    func testStaleCompletionCannotReplaceACurrentResult() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)

        let currentInputID = store.currentInputIDForTesting
        XCTAssertNotNil(currentInputID)
        let currentRows = store.displayRenamePlan().rows.count

        // A late completion for an old presentation must be ignored.
        store.deliverCompletionForTesting(
            inputID: currentInputID!,
            presentationID: UUID(),
            mode: .metadataToFilename,
            result: .empty(for: .metadataToFilename)
        )
        XCTAssertEqual(store.displayRenamePlan().rows.count, currentRows)

        // A late completion for a superseded input in the same presentation
        // must be ignored too, even after a current result exists.
        store.deliverCompletionForTesting(
            inputID: UUID(),
            presentationID: store.presentationID,
            mode: .metadataToFilename,
            result: .empty(for: .metadataToFilename)
        )
        XCTAssertEqual(store.displayRenamePlan().rows.count, currentRows)
        XCTAssertNotNil(store.beginDispatch(for: .metadataToFilename))
    }

    @MainActor
    func testModeSwitchAndReopenCancelInFlightWork() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        worker.holdInvocations()
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await worker.waitForInvocationCount(1)

        // Switching mode invalidates the in-flight plan and starts the new mode
        // only when the cancelled worker relinquishes its slot.
        store.selectMode(.metadataToCSV)
        store.updateTemplate("{{fileName}},{{title}}", for: .metadataToCSV)
        await store.waitForDebounceResolutionForTesting()
        XCTAssertEqual(worker.invocationCount, 1)
        XCTAssertNil(store.readyResult(for: .metadataToFilename))

        // Reopening the converter replaces the presentation entirely.
        present(fixture, in: store)
        store.selectMode(.metadataToText)
        store.updateTemplate("{{title}}", for: .metadataToText)
        await store.waitForDebounceResolutionForTesting()
        XCTAssertEqual(worker.invocationCount, 1)

        worker.releaseNextHeldInvocation()
        await worker.waitForInvocationCount(2)
        XCTAssertEqual(worker.invokedInputs[1].mode, .metadataToText)
        worker.releaseNextHeldInvocation()
        await settle(store)
        XCTAssertEqual(store.readyResult(for: .metadataToText)?.mode, .metadataToText)
        XCTAssertNil(store.readyResult(for: .metadataToFilename))
    }

    @MainActor
    func testLoaderCompletionAfterManualTypingCannotReplaceTheText() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)
        store.selectMode(.csvToMetadata)
        store.updateTemplate("{{fileName}},{{title}}", for: .csvToMetadata)
        store.setFirstCSVRowIsHeader(false)
        await settle(store)

        let gate = ConverterTestLoaderGate()
        store.loadExternalTextFile(
            from: fixture.directory.appendingPathComponent("import.csv"),
            for: .csvToMetadata
        ) { _ in
            await gate.wait()
            return "Original Alpha.mp3,Loaded Title"
        }
        await gate.waitForEntry()
        store.setExternalSource("Original Alpha.mp3,Manual Title", for: .csvToMetadata)
        await settle(store)
        gate.release()
        for _ in 0..<5 {
            await Task.yield()
        }
        await settle(store)

        XCTAssertEqual(store.externalSource(for: .csvToMetadata), "Original Alpha.mp3,Manual Title")
        XCTAssertNil(store.externalFileError)
        XCTAssertEqual(store.externalSourceURL(for: .csvToMetadata), nil)
        let plan = store.displayImportPlan(for: .csvToMetadata)
        XCTAssertTrue(plan.rows.contains { row in
            row.changes.contains { $0.importedValue == "Manual Title" }
        })
        XCTAssertFalse(plan.rows.contains { row in
            row.changes.contains { $0.importedValue == "Loaded Title" }
        })
    }

    @MainActor
    func testFileRevisionChangeInvalidatesTheReadyPlanAndApply() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        XCTAssertEqual(worker.invocationCount, 1)
        guard let dispatch = store.beginDispatch(for: .metadataToFilename) else {
            return XCTFail("Expected a ready plan to dispatch")
        }
        XCTAssertTrue(store.finishDispatch(dispatch))

        let updated = fixture.refreshedFile(at: 0, title: "Revised")
        var files = fixture.files
        files[0] = updated
        store.refresh(files: files, filesRevision: UUID(), projector: nil)
        await settle(store)
        XCTAssertEqual(worker.invocationCount, 2)
        XCTAssertTrue(store.displayRenamePlan().rows.contains { $0.currentName.contains("Original Alpha") })
        XCTAssertTrue(store.displayRenamePlan().rows.contains { $0.previewName == "Revised.mp3" })
    }

    @MainActor
    func testMissingTargetDisablesApplyWithoutRecomputingOnReads() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        XCTAssertEqual(worker.invocationCount, 1)

        store.refresh(files: [], filesRevision: UUID(), projector: nil)
        await settle(store)
        XCTAssertFalse(store.isTargetResolutionComplete)
        XCTAssertEqual(store.targetCount, 0)
        XCTAssertNil(store.beginDispatch(for: .metadataToFilename))
        let countAfterRefresh = worker.invocationCount
        for _ in 0..<20 {
            _ = store.displayRenamePlan()
            _ = store.beginDispatch(for: .metadataToFilename)
        }
        XCTAssertEqual(worker.invocationCount, countAfterRefresh)
    }

    @MainActor
    func testReorderedTargetsPublishANewOrderedPlan() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        XCTAssertEqual(store.displayRenamePlan().rows.map(\.id), fixture.files.map(\.id))

        let reversed = Array(fixture.files.reversed())
        store.present(targetFileIDs: reversed.map(\.id))
        store.refresh(files: reversed, filesRevision: UUID(), projector: nil)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        XCTAssertEqual(store.displayRenamePlan().rows.map(\.id), reversed.map(\.id))
        XCTAssertNotEqual(store.displayRenamePlan().rows.map(\.id), fixture.files.map(\.id))
    }

    @MainActor
    func testOlderApplyCompletionCannotClearANewerDispatch() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)

        guard let firstDispatch = store.beginDispatch(for: .metadataToFilename) else {
            return XCTFail("Expected the first ready plan to dispatch")
        }
        XCTAssertTrue(store.isApplying)

        // Reopening replaces the presentation while the write is in flight.
        present(fixture, in: store)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        guard let secondDispatch = store.beginDispatch(for: .metadataToFilename) else {
            return XCTFail("Expected the reopened presentation to dispatch")
        }
        XCTAssertTrue(store.isApplying)

        XCTAssertFalse(store.finishDispatch(firstDispatch))
        XCTAssertTrue(store.isApplying, "An older completion must not clear newer progress")
        XCTAssertTrue(store.isDispatchCurrent(secondDispatch))
        XCTAssertTrue(store.finishDispatch(secondDispatch))
        XCTAssertFalse(store.isApplying)
    }

    @MainActor
    func testAllSevenModesPublishTheirOwnStoredPlan() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        let textImportSource = "Original Alpha.mp3 | Imported Alpha\nOriginal Beta.mp3 | Imported Beta"
        let csvImportSource = "Original Alpha.mp3,Imported Alpha\nOriginal Beta.mp3,Imported Beta"

        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.updateTemplate("{{title}}", for: .filenameToMetadata)
        store.updateTemplate("{{title}}", for: .metadataToText)
        store.updateTemplate("{{fileName}} | {{title}}", for: .textToMetadata)
        store.setExternalSource(textImportSource, for: .textToMetadata)
        store.updateTemplate("{{fileName}},{{title}}", for: .metadataToCSV)
        store.updateTemplate("{{fileName}},{{title}}", for: .csvToMetadata)
        store.setExternalSource(csvImportSource, for: .csvToMetadata)
        store.setFirstCSVRowIsHeader(false)
        store.setFieldTransferOptions(source: .comment, destination: .genre, operation: .copy)

        var expectedInvocations = 0
        for mode in MetadataConverterMode.allCases {
            store.selectMode(mode)
            await settle(store)
            expectedInvocations += 1
            XCTAssertEqual(worker.invocationCount, expectedInvocations, "\(mode) must plan exactly once")

            switch mode {
            case .metadataToFilename:
                XCTAssertEqual(store.displayRenamePlan().rows.count, 2)
                XCTAssertTrue(store.displayRenamePlan().canApply)
            case .filenameToMetadata:
                XCTAssertEqual(store.displayFilenameMetadataPlan().rows.count, 2)
                XCTAssertTrue(store.displayFilenameMetadataPlan().canApply)
            case .metadataToText:
                let plan = store.displayTextExportPlan()
                XCTAssertEqual(plan.rows.count, 2)
                XCTAssertFalse(plan.outputText.isEmpty)
                guard let dispatch = store.beginDispatch(for: mode) else {
                    return XCTFail("Expected a ready text export plan")
                }
                XCTAssertNotNil(dispatch.encodedExportText)
                XCTAssertTrue(store.finishDispatch(dispatch))
            case .textToMetadata:
                XCTAssertEqual(store.displayImportPlan(for: mode).writeEntries.count, 2)
            case .metadataToCSV:
                let plan = store.displayCSVExportPlan()
                XCTAssertEqual(plan.rows.count, 2)
                XCTAssertFalse(plan.outputText.isEmpty)
                guard let dispatch = store.beginDispatch(for: mode) else {
                    return XCTFail("Expected a ready CSV export plan")
                }
                XCTAssertNotNil(dispatch.encodedExportText)
                XCTAssertTrue(store.finishDispatch(dispatch))
            case .csvToMetadata:
                XCTAssertEqual(store.displayImportPlan(for: mode).writeEntries.count, 2)
            case .metadataFieldTransfer:
                XCTAssertEqual(store.displayImportPlan(for: mode).writeEntries.count, 2)
            }
            store.selectMode(nil)
        }
    }

    @MainActor
    func testOpenerAndExportDispatchNeverRequestMutationScope() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let scope = ConverterTestScopeRecorder()
        let store = makeStore(worker: worker, scopeRecorder: scope)
        present(fixture, in: store)
        XCTAssertEqual(scope.requestedURLs.count, 0, "Opening the converter needs no mutation scope")

        store.updateTemplate("{{title}}", for: .metadataToText)
        store.selectMode(.metadataToText)
        await settle(store)
        XCTAssertEqual(scope.requestedURLs.count, 0)

        guard let textDispatch = store.beginDispatch(for: .metadataToText) else {
            return XCTFail("Expected a ready text export plan")
        }
        XCTAssertEqual(scope.requestedURLs.count, 0, "Text export needs no mutation scope")
        XCTAssertNotNil(textDispatch.encodedExportText)
        XCTAssertTrue(store.finishDispatch(textDispatch))

        store.selectMode(.metadataToCSV)
        store.updateTemplate("{{fileName}},{{title}}", for: .metadataToCSV)
        await settle(store)
        guard let csvDispatch = store.beginDispatch(for: .metadataToCSV) else {
            return XCTFail("Expected a ready CSV export plan")
        }
        XCTAssertEqual(scope.requestedURLs.count, 0, "CSV export needs no mutation scope")
        XCTAssertNotNil(csvDispatch.encodedExportText)
        XCTAssertTrue(store.finishDispatch(csvDispatch))
    }

    @MainActor
    func testInvalidAndNoOpApplyPlansRequestNoMutationScope() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let scope = ConverterTestScopeRecorder()
        let store = makeStore(worker: worker, scopeRecorder: scope)
        present(fixture, in: store)

        // Rename template that reproduces the current filenames: a no-op plan.
        store.updateTemplate("Original {{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        XCTAssertFalse(store.displayRenamePlan().canApply)
        XCTAssertNil(store.beginDispatch(for: .metadataToFilename))
        XCTAssertEqual(scope.requestedURLs.count, 0)

        // Invalid CSV template: rejected without any write request.
        store.selectMode(.csvToMetadata)
        store.updateTemplate("", for: .csvToMetadata)
        await settle(store)
        XCTAssertNil(store.beginDispatch(for: .csvToMetadata))
        XCTAssertEqual(scope.requestedURLs.count, 0)

        // Missing target resolves to no executable entry.
        store.refresh(files: [], filesRevision: UUID(), projector: nil)
        await settle(store)
        XCTAssertNil(store.beginDispatch(for: .csvToMetadata))
        XCTAssertEqual(scope.requestedURLs.count, 0)
    }

    @MainActor
    func testOneEligibleCapturedWriteRequestsOnlyItsOwnDirectory() async {
        let fixture = ConverterTestFixture(fileCount: 1)
        let worker = ConverterTestPlannerWorker()
        let scope = ConverterTestScopeRecorder()
        let store = makeStore(worker: worker, scopeRecorder: scope)
        present(fixture, in: store)
        store.updateTemplate("{{fileName}},{{title}}", for: .csvToMetadata)
        store.setExternalSource("Original Alpha.mp3,Captured Title", for: .csvToMetadata)
        store.setFirstCSVRowIsHeader(false)
        store.selectMode(.csvToMetadata)
        await settle(store)

        let plan = store.displayImportPlan(for: .csvToMetadata)
        XCTAssertEqual(plan.writeEntries.count, 1)
        let invocationsBeforeDispatch = worker.invocationCount
        guard let dispatch = store.beginDispatch(for: .csvToMetadata) else {
            return XCTFail("Expected one eligible captured write")
        }
        XCTAssertEqual(scope.requestedURLs.count, 1)
        let expectedDirectory = fixture.files[0].url.deletingLastPathComponent()
        let requestedDirectories = Set(
            (scope.requestedURLs.first ?? []).map { $0.deletingLastPathComponent() }
        )
        XCTAssertEqual(requestedDirectories, [expectedDirectory])
        XCTAssertEqual(worker.invocationCount, invocationsBeforeDispatch, "Dispatch consumes the captured plan")
        XCTAssertTrue(store.finishDispatch(dispatch))
    }

    @MainActor
    func testCancelledWorkerDoesNotPublishAfterSlotRelease() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        worker.holdInvocations()
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await worker.waitForInvocationCount(1)

        // Cancelling the presentation leaves the slot held until the worker
        // returns; the stale completion must stay silent.
        store.present(targetFileIDs: fixture.files.map(\.id))
        XCTAssertFalse(store.isApplying)
        worker.releaseNextHeldInvocation()
        await settle(store)
        XCTAssertNil(store.readyResult(for: .metadataToFilename))
        XCTAssertNil(store.previewPhaseMessage())
        XCTAssertEqual(worker.invocationCount, 1)
    }

    @MainActor
    func testCancelPresentationCancelsInFlightWorkAndClearsRetainedState() async {
        let fixture = ConverterTestFixture()
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)

        worker.holdInvocations()
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await worker.waitForInvocationCount(1)

        let priorPresentationID = store.presentationID
        store.cancelPresentation()
        XCTAssertNotEqual(store.presentationID, priorPresentationID)
        if case .idle = store.planState {
            // Expected idle state after cancellation.
        } else {
            XCTFail("Expected .idle planState after cancelPresentation, got \(store.planState)")
        }
        XCTAssertTrue(store.targetFiles.isEmpty)

        worker.releaseNextHeldInvocation()
        await settle(store)
        if case .idle = store.planState {
            // Worker returning after cancelPresentation must not repopulate planState.
        } else {
            XCTFail("Expected .idle planState after stale worker return, got \(store.planState)")
        }
    }

    @MainActor
    func testBeginDispatchRecordsScopeRequestErrorWhenAccessDenied() async {
        let fixture = ConverterTestFixture(fileCount: 1)
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        store.setScopeRequester { _ in "Folder access denied by test." }
        present(fixture, in: store)
        store.updateTemplate("{{fileName}},{{title}}", for: .csvToMetadata)
        store.setExternalSource("Original Alpha.mp3,Captured Title", for: .csvToMetadata)
        store.setFirstCSVRowIsHeader(false)
        store.selectMode(.csvToMetadata)
        await settle(store)

        XCTAssertNil(store.beginDispatch(for: .csvToMetadata))
        XCTAssertEqual(store.lastScopeRequestError, "Folder access denied by test.")
        XCTAssertFalse(store.isApplying)
    }

    @MainActor
    func testInactiveModeOptionChangeDoesNotReplanActiveMode() async {
        let fixture = ConverterTestFixture(fileCount: 1)
        let worker = ConverterTestPlannerWorker()
        let store = makeStore(worker: worker)
        present(fixture, in: store)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        await settle(store)
        let settledInvocations = worker.invocationCount

        // Mutating CSV and field-transfer options while rename mode is active
        // must not trigger replanning of the active mode.
        store.setIncludeCSVHeaderRow(false)
        store.setFirstCSVRowIsHeader(false)
        store.setFieldTransferOptions(source: .album, destination: .comment, operation: .cut)
        await settle(store)

        XCTAssertEqual(worker.invocationCount, settledInvocations)
    }

    @MainActor
    func testPresentationResetClearsDraftAndApplyOwnership() {
        let fixture = ConverterTestFixture()
        let store = makeStore()
        present(fixture, in: store)
        store.updateTemplate("{{title}}", for: .metadataToFilename)
        store.selectMode(.metadataToFilename)
        XCTAssertNotNil(store.selectedMode)

        store.present(targetFileIDs: fixture.files.map(\.id))
        XCTAssertNil(store.selectedMode)
        XCTAssertEqual(store.template(for: .metadataToFilename), "{{title}}", "Templates survive a reseed")
        XCTAssertEqual(store.externalSource(for: .textToMetadata), "")
        XCTAssertEqual(store.targetCount, 0)
        XCTAssertNil(store.beginDispatch(for: .metadataToFilename))
    }

    @MainActor
    func testTargetIndexIsBuiltOncePerTrackedRevision() {
        let fixture = ConverterTestFixture()
        let store = makeStore()
        let revision = UUID()
        store.present(targetFileIDs: fixture.files.map(\.id))
        store.refresh(files: fixture.files, filesRevision: revision, projector: nil)
        XCTAssertEqual(store.targetIndexBuildCount, 1)

        // Draft edits with an unchanged revision reuse the ordered index.
        for template in ["{{title}}", "{{artist}}", "{{comment}}"] {
            store.updateTemplate(template, for: .metadataToFilename)
        }
        store.selectMode(.metadataToFilename)
        store.refresh(files: fixture.files, filesRevision: revision, projector: nil)
        XCTAssertEqual(store.targetIndexBuildCount, 1)

        let updatedRevision = UUID()
        store.refresh(files: fixture.files, filesRevision: updatedRevision, projector: nil)
        XCTAssertEqual(store.targetIndexBuildCount, 2)
    }
}
