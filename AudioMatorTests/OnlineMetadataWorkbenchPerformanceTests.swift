import AppKit
import Combine
import SwiftUI
import XCTest
@testable import AudioMator

#if os(macOS)
@MainActor
final class OnlineMetadataWorkbenchPerformanceTests: XCTestCase {
    func testDeterministicScenarioMatrixCoversProviderEdgeCases() {
        for trackCount in OnlineMetadataWorkbenchPerformanceScenarioFactory.supportedTrackCounts {
            let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: trackCount)
            let client = SuspendedWorkbenchMusicBrainzClient()
            let musicBrainzStore = makeMusicBrainzStore(scenario: scenario, client: client)
            let iTunesStore = makeiTunesStore(scenario: scenario)

            XCTAssertEqual(scenario.files.count, trackCount)
            XCTAssertEqual(scenario.musicBrainzRelease.media.count, 2)
            XCTAssertEqual(scenario.iTunesDetail.tracks.map(\.discNumber).max(), 2)
            XCTAssertGreaterThan(scenario.musicBrainzPreview.unmatchedFiles.count, 0)
            XCTAssertGreaterThan(scenario.iTunesPreview.unmatchedFiles.count, 0)
            XCTAssertTrue(musicBrainzStore.hasDuplicateTrackAssignments)
            XCTAssertTrue(iTunesStore.hasDuplicateTrackAssignments)
            XCTAssertGreaterThan(scenario.musicBrainzRelease.title.count, 100)
            XCTAssertGreaterThan(scenario.iTunesDetail.album.collectionName.count, 100)

            let behaviorCounts = scenario.recordingBehaviors.values.reduce(into: [0, 0, 0]) { counts, behavior in
                switch behavior {
                case .success: counts[0] += 1
                case .failure: counts[1] += 1
                case .timeout: counts[2] += 1
                }
            }
            XCTAssertTrue(behaviorCounts.allSatisfy { $0 > 0 })
            musicBrainzStore.cancelPendingRecordingLoads()
        }
    }

    func testPlanGenerationUsesWarmMedianSamplesAcrossScenarioMatrix() {
        var report: [String] = []

        for trackCount in OnlineMetadataWorkbenchPerformanceScenarioFactory.supportedTrackCounts {
            let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: trackCount)
            let musicBrainzStore = makeMusicBrainzStore(
                scenario: scenario,
                client: SuspendedWorkbenchMusicBrainzClient()
            )
            musicBrainzStore.cancelPendingRecordingLoads()
            let iTunesStore = makeiTunesStore(scenario: scenario)

            let musicBrainzMedian = medianMilliseconds(warmupCount: 3, sampleCount: 11) {
                consume(musicBrainzStore.plan.changeCount)
            }
            let iTunesMedian = medianMilliseconds(warmupCount: 3, sampleCount: 11) {
                consume(iTunesStore.plan.changeCount)
            }

            XCTAssertGreaterThan(musicBrainzMedian, 0)
            XCTAssertGreaterThan(iTunesMedian, 0)
            report.append(measurementLine("musicbrainz.plan", trackCount: trackCount, milliseconds: musicBrainzMedian))
            report.append(measurementLine("itunes.plan", trackCount: trackCount, milliseconds: iTunesMedian))
        }

        recordPerformanceReport(named: "Plan generation medians", lines: report)
    }

    func testInitialReviewLayoutUsesWarmMedianSamplesForTwoHundredTracks() {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: 200)

        let iTunesMedian = medianMilliseconds(warmupCount: 1, sampleCount: 5) {
            let viewModel = makeViewModel(files: scenario.files)
            let store = makeiTunesStore(scenario: scenario)
            let hosted = HostedWorkbench(
                rootView: iTunesTaggingWorkbenchView(store: store, viewModel: viewModel)
            )
            hosted.stabilize()
            hosted.tearDown()
        }

        let musicBrainzMedian = medianMilliseconds(warmupCount: 1, sampleCount: 5) {
            let viewModel = makeViewModel(files: scenario.files)
            let store = makeMusicBrainzStore(
                scenario: scenario,
                client: SuspendedWorkbenchMusicBrainzClient()
            )
            let hosted = HostedWorkbench(
                rootView: MusicBrainzTaggingWorkbenchView(store: store, viewModel: viewModel)
            )
            hosted.stabilize()
            store.cancelPendingRecordingLoads()
            hosted.tearDown()
        }

        XCTAssertGreaterThan(iTunesMedian, 0)
        XCTAssertGreaterThan(musicBrainzMedian, 0)
        recordPerformanceReport(
            named: "Initial layout medians",
            lines: [
                measurementLine("itunes.initial-layout", trackCount: 200, milliseconds: iTunesMedian),
                measurementLine("musicbrainz.initial-layout", trackCount: 200, milliseconds: musicBrainzMedian)
            ]
        )
    }

    func testPageSectionContainerDoesNotNestLazyStacks() {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: 10)
        let viewModel = makeViewModel(files: scenario.files)

        let musicBrainzStore = makeMusicBrainzStore(
            scenario: scenario,
            client: SuspendedWorkbenchMusicBrainzClient()
        )
        let musicBrainzBody = MusicBrainzTaggingWorkbenchView(
            store: musicBrainzStore,
            viewModel: viewModel
        ).body
        XCTAssertFalse(
            containsLazyVStack(in: musicBrainzBody),
            "The page-level section container must stay eager so row-level lazy stacks do not enter a layout-estimation cycle."
        )
        musicBrainzStore.cancelPendingRecordingLoads()

        let iTunesStore = makeiTunesStore(scenario: scenario)
        let iTunesBody = iTunesTaggingWorkbenchView(
            store: iTunesStore,
            viewModel: viewModel
        ).body
        XCTAssertFalse(
            containsLazyVStack(in: iTunesBody),
            "The page-level section container must stay eager so row-level lazy stacks do not enter a layout-estimation cycle."
        )
    }

    func testSelectAllThenPreDiffScrollUsesWarmMedianSamples() async throws {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(
            trackCount: 21,
            musicBrainzTrackCount: 16
        )
        var musicBrainzSamples: [Double] = []
        var iTunesSamples: [Double] = []

        for iteration in 0..<6 {
            let viewModel = makeViewModel(files: scenario.files)
            let store = makeMusicBrainzStore(
                scenario: scenario,
                client: RelationHeavyWorkbenchMusicBrainzClient()
            )
            let hosted = HostedWorkbench(
                rootView: NavigationStack {
                    MusicBrainzTaggingWorkbenchView(store: store, viewModel: viewModel)
                }
            )
            try await hosted.stabilizeAsync()
            try await waitUntil(timeout: .seconds(5)) {
                store.recordingPreloadTotalCount > 0 &&
                    store.recordingPreloadCompletedCount == store.recordingPreloadTotalCount
            }
            store.selectAllAvailableFields()
            try await hosted.stabilizeAsync()

            let clock = ContinuousClock()
            let start = clock.now
            try await hosted.scrollDownAsync(distance: 7_000)
            let elapsed = durationMilliseconds(start.duration(to: clock.now))
            if iteration > 0 {
                musicBrainzSamples.append(elapsed)
            }
            hosted.tearDown()
            store.cancelPendingRecordingLoads()
        }

        for iteration in 0..<6 {
            let viewModel = makeViewModel(files: scenario.files)
            let store = makeiTunesStore(scenario: scenario)
            store.selectAllAvailableFields()
            let hosted = HostedWorkbench(
                rootView: NavigationStack {
                    iTunesTaggingWorkbenchView(store: store, viewModel: viewModel)
                }
            )
            try await hosted.stabilizeAsync()

            let clock = ContinuousClock()
            let start = clock.now
            try await hosted.scrollDownAsync(distance: 7_000)
            let elapsed = durationMilliseconds(start.duration(to: clock.now))
            if iteration > 0 {
                iTunesSamples.append(elapsed)
            }
            hosted.tearDown()
        }

        let musicBrainzMedian = median(musicBrainzSamples)
        let iTunesMedian = median(iTunesSamples)
        XCTAssertLessThan(musicBrainzMedian, 750)
        XCTAssertLessThan(iTunesMedian, 750)
        recordPerformanceReport(
            named: "Select All pre-diff scroll medians",
            lines: [
                measurementLine("musicbrainz.pre-diff-scroll", trackCount: 21, milliseconds: musicBrainzMedian),
                measurementLine("itunes.pre-diff-scroll", trackCount: 21, milliseconds: iTunesMedian)
            ]
        )
    }

    func testFieldToggleUpdateUsesWarmMedianSamplesForTwoHundredTracks() {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: 200)
        let viewModel = makeViewModel(files: scenario.files)

        let iTunesStore = makeiTunesStore(scenario: scenario)
        let iTunesHosted = HostedWorkbench(
            rootView: iTunesTaggingWorkbenchView(store: iTunesStore, viewModel: viewModel)
        )
        iTunesHosted.stabilize()
        let iTunesMedian = medianMilliseconds(
            warmupCount: 2,
            sampleCount: 9,
            prepare: {
                iTunesStore.setFieldSelected(true, for: .title)
                iTunesHosted.stabilize()
            },
            measure: {
                iTunesStore.setFieldSelected(false, for: .title)
                iTunesHosted.stabilize()
            }
        )
        iTunesHosted.tearDown()

        let musicBrainzStore = makeMusicBrainzStore(
            scenario: scenario,
            client: SuspendedWorkbenchMusicBrainzClient()
        )
        musicBrainzStore.cancelPendingRecordingLoads()
        let musicBrainzHosted = HostedWorkbench(
            rootView: MusicBrainzTaggingWorkbenchView(store: musicBrainzStore, viewModel: viewModel)
        )
        musicBrainzHosted.stabilize()
        let musicBrainzMedian = medianMilliseconds(
            warmupCount: 2,
            sampleCount: 9,
            prepare: {
                musicBrainzStore.setFieldSelected(true, for: .title)
                musicBrainzHosted.stabilize()
            },
            measure: {
                musicBrainzStore.setFieldSelected(false, for: .title)
                musicBrainzHosted.stabilize()
            }
        )
        musicBrainzHosted.tearDown()

        recordPerformanceReport(
            named: "Field toggle medians",
            lines: [
                measurementLine("itunes.field-toggle", trackCount: 200, milliseconds: iTunesMedian),
                measurementLine("musicbrainz.field-toggle", trackCount: 200, milliseconds: musicBrainzMedian)
            ]
        )
    }

    func testTrackAssignmentUpdateUsesWarmMedianSamplesForTwoHundredTracks() throws {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: 200)
        let viewModel = makeViewModel(files: scenario.files)

        let iTunesStore = makeiTunesStore(scenario: scenario)
        let iTunesAssignment = try XCTUnwrap(iTunesStore.assignments.first)
        let iTunesHosted = HostedWorkbench(
            rootView: iTunesTaggingWorkbenchView(store: iTunesStore, viewModel: viewModel)
        )
        iTunesHosted.stabilize()
        let iTunesMedian = medianMilliseconds(
            warmupCount: 2,
            sampleCount: 9,
            prepare: {
                iTunesStore.updateSelectedTrack(iTunesAssignment.initialTrackID, for: iTunesAssignment.id)
                iTunesHosted.stabilize()
            },
            measure: {
                iTunesStore.updateSelectedTrack(nil, for: iTunesAssignment.id)
                iTunesHosted.stabilize()
            }
        )
        iTunesHosted.tearDown()

        let musicBrainzStore = makeMusicBrainzStore(
            scenario: scenario,
            client: SuspendedWorkbenchMusicBrainzClient()
        )
        musicBrainzStore.cancelPendingRecordingLoads()
        let musicBrainzAssignment = try XCTUnwrap(musicBrainzStore.assignments.first)
        let musicBrainzHosted = HostedWorkbench(
            rootView: MusicBrainzTaggingWorkbenchView(store: musicBrainzStore, viewModel: viewModel)
        )
        musicBrainzHosted.stabilize()
        let musicBrainzMedian = medianMilliseconds(
            warmupCount: 2,
            sampleCount: 9,
            prepare: {
                musicBrainzStore.updateSelectedTrack(musicBrainzAssignment.initialTrackID, for: musicBrainzAssignment.id)
                musicBrainzHosted.stabilize()
            },
            measure: {
                musicBrainzStore.updateSelectedTrack(nil, for: musicBrainzAssignment.id)
                musicBrainzHosted.stabilize()
            }
        )
        musicBrainzStore.cancelPendingRecordingLoads()
        musicBrainzHosted.tearDown()

        recordPerformanceReport(
            named: "Track assignment medians",
            lines: [
                measurementLine("itunes.assignment", trackCount: 200, milliseconds: iTunesMedian),
                measurementLine("musicbrainz.assignment", trackCount: 200, milliseconds: musicBrainzMedian)
            ]
        )
    }

    func testPlanCacheInvalidatesOnlyAffectedAssignmentRows() throws {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: 200)

        let iTunesProbe = iTunesTaggingWorkbenchStore.PerformanceProbe()
        let iTunesStore = makeiTunesStore(scenario: scenario, performanceProbe: iTunesProbe)
        let iTunesAssignment = try XCTUnwrap(iTunesStore.assignments.first)
        consume(iTunesStore.plan.changeCount)
        consume(iTunesStore.plan.changeCount)
        XCTAssertEqual(iTunesProbe.planBuildCount, 1)
        XCTAssertEqual(iTunesProbe.planRowBuildCount, 200)

        iTunesStore.updateSelectedTrack(nil, for: iTunesAssignment.id)
        consume(iTunesStore.plan.changeCount)
        XCTAssertEqual(iTunesProbe.planBuildCount, 2)
        XCTAssertEqual(iTunesProbe.planRowBuildCount, 201)

        let musicBrainzProbe = MusicBrainzTaggingWorkbenchStore.PerformanceProbe()
        let musicBrainzStore = makeMusicBrainzStore(
            scenario: scenario,
            client: SuspendedWorkbenchMusicBrainzClient(),
            performanceProbe: musicBrainzProbe
        )
        musicBrainzStore.cancelPendingRecordingLoads()
        let musicBrainzAssignment = try XCTUnwrap(musicBrainzStore.assignments.first)
        consume(musicBrainzStore.plan.changeCount)
        consume(musicBrainzStore.plan.changeCount)
        XCTAssertEqual(musicBrainzProbe.planBuildCount, 1)
        XCTAssertEqual(musicBrainzProbe.planRowBuildCount, 200)

        musicBrainzStore.updateSelectedTrack(nil, for: musicBrainzAssignment.id)
        consume(musicBrainzStore.plan.changeCount)
        XCTAssertEqual(musicBrainzProbe.planBuildCount, 2)
        XCTAssertEqual(musicBrainzProbe.planRowBuildCount, 201)
        musicBrainzStore.cancelPendingRecordingLoads()
    }

    func testMusicBrainzRecordingDetailBatchUsesWarmMedianSamplesForTwoHundredTracks() async throws {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: 200)
        var samples: [Double] = []

        for iteration in 0..<6 {
            let client = MixedWorkbenchMusicBrainzClient(behaviors: scenario.recordingBehaviors)
            let performanceProbe = MusicBrainzTaggingWorkbenchStore.PerformanceProbe()
            let clock = ContinuousClock()
            let start = clock.now
            let store = makeMusicBrainzStore(
                scenario: scenario,
                client: client,
                detailTimeout: .seconds(30),
                performanceProbe: performanceProbe
            )
            var planEvaluationCount = 0
            let subscription = store.objectWillChange.sink {
                planEvaluationCount += 1
                self.consume(store.plan.changeCount)
            }

            try await waitUntil(timeout: .seconds(5)) {
                store.recordingPreloadCompletedCount == store.recordingPreloadTotalCount
            }
            let elapsed = durationMilliseconds(start.duration(to: clock.now))
            if iteration > 0 {
                samples.append(elapsed)
            }

            let states = store.recordingStates.values
            XCTAssertTrue(states.contains { if case .loaded = $0 { return true }; return false })
            XCTAssertTrue(states.contains { if case .failed = $0 { return true }; return false })
            XCTAssertEqual(planEvaluationCount, store.recordingPreloadTotalCount)
            XCTAssertEqual(performanceProbe.planBuildCount, 1)
            XCTAssertEqual(performanceProbe.planRowBuildCount, 200)
            withExtendedLifetime(subscription) {}
            store.cancelPendingRecordingLoads()
        }

        let median = median(samples)
        XCTAssertLessThan(median, 1_500)
        recordPerformanceReport(
            named: "Recording detail batch median",
            lines: [measurementLine("musicbrainz.recording-batch", trackCount: 200, milliseconds: median)]
        )
    }

    func testMusicBrainzLargeWorkbenchDoesNotStartUnboundedRecordingFanOut() async throws {
        let scenario = OnlineMetadataWorkbenchPerformanceScenarioFactory.make(trackCount: 200)
        let client = SuspendedWorkbenchMusicBrainzClient()
        let store = makeMusicBrainzStore(scenario: scenario, client: client)

        try await Task.sleep(for: .milliseconds(150))
        let requestCount = await client.requestCount
        store.cancelPendingRecordingLoads()

        XCTAssertLessThanOrEqual(requestCount, 1)
        XCTAssertTrue(store.recordingStates.values.allSatisfy { $0 == .idle })
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

    private func makeMusicBrainzStore(
        scenario: OnlineMetadataWorkbenchPerformanceScenario,
        client: some MusicBrainzBrowserClient,
        detailTimeout: Duration = .seconds(30),
        performanceProbe: MusicBrainzTaggingWorkbenchStore.PerformanceProbe? = nil
    ) -> MusicBrainzTaggingWorkbenchStore {
        MusicBrainzTaggingWorkbenchStore(
            release: scenario.musicBrainzRelease,
            preview: scenario.musicBrainzPreview,
            loadedFiles: scenario.files,
            browserStore: MusicBrainzBrowserStore(client: client, detailTimeout: detailTimeout),
            performanceProbe: performanceProbe
        )
    }

    private func makeiTunesStore(
        scenario: OnlineMetadataWorkbenchPerformanceScenario,
        performanceProbe: iTunesTaggingWorkbenchStore.PerformanceProbe? = nil
    ) -> iTunesTaggingWorkbenchStore {
        iTunesTaggingWorkbenchStore(
            detail: scenario.iTunesDetail,
            preview: scenario.iTunesPreview,
            loadedFiles: scenario.files,
            performanceProbe: performanceProbe
        )
    }

    private func makeViewModel(files: [AudioFile]) -> AudioViewModel {
        let suiteName = "AudioMator.OnlineMetadataWorkbenchPerformanceTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: userDefaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: userDefaults),
            metadataPipeline: TagLibAudioMetadataPipeline(),
            saveIssueLogStore: SaveIssueLogStore()
        )
        viewModel.files = files
        viewModel.setSelectedAudioIDs(Set(files.map(\.id)))
        return viewModel
    }

    private func render<Content: View>(_ content: Content) {
        let hosted = HostedWorkbench(rootView: content.frame(width: 400, height: 100))
        hosted.stabilize()
        hosted.tearDown()
    }

    private func medianMilliseconds(
        warmupCount: Int,
        sampleCount: Int,
        prepare: () -> Void = {},
        measure operation: () -> Void
    ) -> Double {
        for _ in 0..<warmupCount {
            prepare()
            operation()
        }

        let clock = ContinuousClock()
        let samples = (0..<sampleCount).map { _ in
            prepare()
            let start = clock.now
            operation()
            return durationMilliseconds(start.duration(to: clock.now))
        }
        return median(samples)
    }

    private func median(_ values: [Double]) -> Double {
        precondition(!values.isEmpty)
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func durationMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func measurementLine(_ name: String, trackCount: Int, milliseconds: Double) -> String {
        "\(name),tracks=\(trackCount),median_ms=\(String(format: "%.3f", milliseconds))"
    }

    private func recordPerformanceReport(named name: String, lines: [String]) {
        let report = lines.joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

    }

    private func consume(_ value: Int) {
        XCTAssertGreaterThanOrEqual(value, 0)
    }

    private func containsLazyVStack(in value: Any, depth: Int = 0) -> Bool {
        guard depth < 24 else { return false }
        if String(reflecting: type(of: value)).hasPrefix("SwiftUI.LazyVStack<") {
            return true
        }

        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle != .class else { return false }
        return mirror.children.contains { child in
            containsLazyVStack(in: child.value, depth: depth + 1)
        }
    }

    private func waitUntil(
        timeout: Duration,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for deterministic MusicBrainz recording states")
    }
}

@MainActor
private final class HostedWorkbench<Content: View> {
    private let host: NSHostingView<Content>
    private let window: NSWindow

    init(rootView: Content) {
        host = NSHostingView(rootView: rootView)
        host.frame = NSRect(x: 0, y: 0, width: 980, height: 700)
        window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
    }

    func stabilize() {
        host.layoutSubtreeIfNeeded()
        drainMainQueue()
        host.layoutSubtreeIfNeeded()
        drainMainQueue()
        host.layoutSubtreeIfNeeded()
    }

    func stabilizeAsync() async throws {
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        try await Task.sleep(for: .milliseconds(20))
        host.layoutSubtreeIfNeeded()
    }

    func scrollDownAsync(distance: CGFloat) async throws {
        try await stabilizeAsync()
        guard let scrollView = firstScrollView(in: host), let documentView = scrollView.documentView else {
            XCTFail("Unable to locate offscreen workbench scroll view")
            return
        }

        documentView.layoutSubtreeIfNeeded()
        let viewportHeight = max(scrollView.contentView.bounds.height, 1)
        let maximumY = max(0, documentView.bounds.height - viewportHeight)
        let destinationY = min(distance, maximumY)
        var targetY = 0.0

        while targetY < destinationY {
            targetY = min(targetY + viewportHeight / 2, destinationY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        host.layoutSubtreeIfNeeded()
    }

    func tearDown() {
        window.contentView = nil
    }

    private func drainMainQueue() {
        var completed = false
        DispatchQueue.main.async {
            completed = true
        }
        while !completed {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
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

private enum WorkbenchRecordingClientError: Error {
    case syntheticFailure
}

private actor RelationHeavyWorkbenchMusicBrainzClient: MusicBrainzBrowserClient {
    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        .recordings([])
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail {
        let relationshipTitles = [
            "Composer",
            "Lyricist",
            "Producer",
            "Engineer",
            "Remixer",
            "Phonographic copyright (℗) by"
        ]
        let relationshipGroups = (0..<24).map { groupIndex in
            let valueCount = groupIndex < 18 ? 2 : 1
            return MusicBrainzRelationshipGroup(
                title: relationshipTitles[groupIndex % relationshipTitles.count],
                values: (0..<valueCount).map { valueIndex in
                    "Relationship Credit \(id) \(groupIndex)-\(valueIndex) with deterministic long text"
                }
            )
        }

        return MusicBrainzRecordingDetail(
            id: id,
            title: "Remote Recording \(id)",
            artistCredit: "Remote Recording Artist",
            disambiguation: "offline relationship-heavy detail",
            firstReleaseDate: "2026-07-28",
            durationMilliseconds: 240_000,
            annotation: String(repeating: "Long offline annotation. ", count: 20),
            isrcs: ["OFFLINEISRC"],
            genres: [MusicBrainzTerm(name: "Rock", count: 10)],
            tags: [MusicBrainzTerm(name: "fixture", count: 5)],
            rating: nil,
            releases: fallbackReleases,
            relationshipGroups: relationshipGroups
        )
    }

    func releaseDetail(id: String) async throws -> MusicBrainzReleaseDetail {
        throw WorkbenchRecordingClientError.syntheticFailure
    }
}

private actor MixedWorkbenchMusicBrainzClient: MusicBrainzBrowserClient {
    private let behaviors: [String: WorkbenchRecordingBehavior]

    init(behaviors: [String: WorkbenchRecordingBehavior]) {
        self.behaviors = behaviors
    }

    func search(matching query: MusicBrainzSearchQuery, limit: Int) async throws -> MusicBrainzSearchResults {
        .recordings([])
    }

    func recordingDetail(
        id: String,
        fallbackReleases: [MusicBrainzRecordingResult.Release]
    ) async throws -> MusicBrainzRecordingDetail {
        switch behaviors[id] ?? .failure {
        case .success:
            return MusicBrainzRecordingDetail(
                id: id,
                title: "Remote Recording \(id)",
                artistCredit: "Remote Recording Artist",
                disambiguation: "offline deterministic detail",
                firstReleaseDate: "2026-07-28",
                durationMilliseconds: 240_000,
                annotation: String(repeating: "Long offline annotation. ", count: 20),
                isrcs: ["OFFLINEISRC"],
                genres: [MusicBrainzTerm(name: "Rock", count: 10)],
                tags: [MusicBrainzTerm(name: "fixture", count: 5)],
                rating: nil,
                releases: fallbackReleases,
                relationshipGroups: [
                    MusicBrainzRelationshipGroup(title: "Composer", values: ["Fixture Composer"]),
                    MusicBrainzRelationshipGroup(title: "Producer", values: ["Fixture Producer"])
                ]
            )
        case .failure:
            throw WorkbenchRecordingClientError.syntheticFailure
        case .timeout:
            throw AsyncOperationTimedOutError(operationName: "Offline MusicBrainz recording detail")
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
