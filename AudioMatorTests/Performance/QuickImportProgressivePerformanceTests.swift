import Combine
import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

#if os(macOS)
/// Real progressive Quick Import sensor (AM-14 evidence).
///
/// This suite reports measured orchestration cost and asserts deterministic work
/// counters only. It deliberately has no wall-clock threshold and no `measure`
/// block: cumulative/max MainActor batch cost is recorded for the evidence record.
nonisolated final class QuickImportProgressivePerformanceTests: XCTestCase {
    @MainActor
    func testWorkBudgetsDecodeExcluded() async throws {
        try requireFixtures()
        for count in [480, 960, 4_000] {
            let report = try await runDecodeExcludedLane(count: count)
            print(report.reportLine)
            attach(report: report)
            XCTAssertEqual(report.identityPreparations, count)
            XCTAssertEqual(report.fileKeyComputations, count)
            XCTAssertEqual(report.parentKeyComputations, 1)
            XCTAssertEqual(report.publications, (count + 47) / 48)
            XCTAssertEqual(report.publishedRowCount, count)
            XCTAssertEqual(report.terminalMerges, 0)
            XCTAssertEqual(report.consistencyIssues, [])
        }
    }

    @MainActor
    func testWorkBudgetsDecodeIncludedRealFixtures() async throws {
        try requireFixtures()
        for count in [480, 960] {
            let report = try await runDecodeIncludedLane(count: count)
            print(report.reportLine)
            attach(report: report)
            XCTAssertEqual(report.identityPreparations, count)
            XCTAssertEqual(report.fileKeyComputations, count)
            XCTAssertEqual(report.parentKeyComputations, 1)
            XCTAssertEqual(report.publications, (count + 47) / 48)
            XCTAssertEqual(report.publishedRowCount, count)
            XCTAssertEqual(report.consistencyIssues, [])
        }
    }

    // MARK: - Lanes

    private struct Report {
        let hostName: String
        let operatingSystem: String
        let processorCount: Int
        let thermalState: String
        let fixtureCount: Int
        let loaderMode: String
        let decodeIncluded: Bool
        let identityPreparations: Int
        let fileKeyComputations: Int
        let parentKeyComputations: Int
        let publications: Int
        let publishedRowCount: Int
        let terminalMerges: Int
        let cumulativePublicationMilliseconds: Double
        let maximumPublicationMilliseconds: Double
        let wallClockMilliseconds: Double
        let consistencyIssues: [String]

        var reportLine: String {
            var parts: [String] = []
            parts.append("quickimport \(fixtureCount)")
            parts.append("decode=\(decodeIncluded ? "included" : "excluded")")
            parts.append("loader=\(loaderMode)")
            parts.append("host=\(hostName)")
            parts.append("os=\(operatingSystem)")
            parts.append("cpus=\(processorCount)")
            parts.append("thermal=\(thermalState)")
            parts.append("identityPreps=\(identityPreparations)")
            parts.append("fileKeys=\(fileKeyComputations)")
            parts.append("parentKeys=\(parentKeyComputations)")
            parts.append("publications=\(publications)")
            parts.append("publishedRows=\(publishedRowCount)")
            parts.append("terminalMerges=\(terminalMerges)")
            parts.append("cumulativePublishMs=\(String(format: "%.2f", cumulativePublicationMilliseconds))")
            parts.append("maxPublishMs=\(String(format: "%.2f", maximumPublicationMilliseconds))")
            parts.append("lanesWallMs=\(String(format: "%.2f", wallClockMilliseconds))")
            return parts.joined(separator: " ")
        }
    }

    private struct LaneHarness {
        let viewModel: AudioViewModel
        let userDefaults: UserDefaults
        let suiteName: String
        let journalDirectory: URL
        let issueLogURL: URL
        let workspaceDirectory: URL?

        @MainActor
        func tearDown() {
            viewModel.clearQuickImportFiles()
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: journalDirectory)
            try? FileManager.default.removeItem(at: issueLogURL)
            if let workspaceDirectory {
                try? FileManager.default.removeItem(at: workspaceDirectory)
            }
        }
    }

    @MainActor
    private func runDecodeExcludedLane(count: Int) async throws -> Report {
        let paths = Self.syntheticPaths(count: count)
        let identityProvider = SyntheticQuickImportIdentityProvider()
        let scopeAccess = CountingQuickImportScopeAccess()
        let pipeline = ProgressiveQuickImportMetadataPipeline()
        let harness = try makeHarness(
            pipeline: pipeline,
            provider: identityProvider,
            access: scopeAccess,
            policy: .forced48
        )
        defer { harness.tearDown() }

        let start = ContinuousClock.now
        harness.viewModel.importQuickFiles(from: paths)
        try await waitForImport(harness.viewModel, expectedCount: count)
        let wallClock = start.duration(to: ContinuousClock.now)
        return makeReport(
            harness: harness.viewModel,
            fixtureCount: count,
            loaderMode: "forced48/synthetic",
            decodeIncluded: false,
            identityPreparations: identityProvider.snapshot.identityPreparationCount,
            fileKeyComputations: identityProvider.snapshot.fileKeyComputationCount,
            parentKeyComputations: identityProvider.snapshot.parentKeyComputationCount,
            wallClock: wallClock,
            workspaceDirectory: nil
        )
    }

    @MainActor
    private func runDecodeIncludedLane(count: Int) async throws -> Report {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5Decode-\(count)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixtureURL = try fixtureSourceURL()
        var paths: [URL] = []
        paths.reserveCapacity(count)
        for index in 0..<count {
            let destination = root.appendingPathComponent(String(format: "%05d-track.mp3", index))
            try FileManager.default.copyItem(at: fixtureURL, to: destination)
            paths.append(destination)
        }

        let identityProvider = CountingFileSystemQuickImportIdentityProvider()
        let scopeAccess = CountingQuickImportScopeAccess()
        let harness = try makeHarness(
            pipeline: TagLibAudioMetadataPipeline(),
            provider: identityProvider,
            access: scopeAccess,
            policy: .forced48
        )
        defer { harness.tearDown() }

        let start = ContinuousClock.now
        harness.viewModel.importQuickFiles(from: paths)
        try await waitForImport(harness.viewModel, expectedCount: count, timeout: 180)
        let wallClock = start.duration(to: ContinuousClock.now)
        let providerSnapshot = identityProvider.snapshot
        return makeReport(
            harness: harness.viewModel,
            fixtureCount: count,
            loaderMode: "forced48/taglib",
            decodeIncluded: true,
            identityPreparations: providerSnapshot.identityPreparations,
            fileKeyComputations: providerSnapshot.fileKeyComputations,
            parentKeyComputations: providerSnapshot.parentKeyComputations,
            wallClock: wallClock,
            workspaceDirectory: root
        )
    }

    // MARK: - Report

    @MainActor
    private func makeReport(
        harness viewModel: AudioViewModel,
        fixtureCount: Int,
        loaderMode: String,
        decodeIncluded: Bool,
        identityPreparations: Int,
        fileKeyComputations: Int,
        parentKeyComputations: Int,
        wallClock: Duration,
        workspaceDirectory: URL?
    ) -> Report {
        let diagnostics = viewModel.quickImportDiagnostics()
        _ = workspaceDirectory
        return Report(
            hostName: ProcessInfo.processInfo.hostName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.activeProcessorCount,
            thermalState: String(describing: ProcessInfo.processInfo.thermalState),
            fixtureCount: fixtureCount,
            loaderMode: loaderMode,
            decodeIncluded: decodeIncluded,
            identityPreparations: identityPreparations,
            fileKeyComputations: fileKeyComputations,
            parentKeyComputations: parentKeyComputations,
            publications: diagnostics.metrics.publicationCount,
            publishedRowCount: diagnostics.metrics.publishedRowCount,
            terminalMerges: diagnostics.metrics.terminalMergeCount,
            cumulativePublicationMilliseconds: milliseconds(diagnostics.metrics.cumulativePublicationDuration),
            maximumPublicationMilliseconds: milliseconds(diagnostics.metrics.maximumPublicationDuration),
            wallClockMilliseconds: milliseconds(wallClock),
            consistencyIssues: diagnostics.consistencyIssues
        )
    }

    @MainActor
    private func attach(report: Report) {
        let attachment = XCTAttachment(string: report.reportLine)
        attachment.name = "quickimport-progressive-report"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Standalone evidence hook: xcodebuild records the attachment; the
        // disposable focused runner also copies the raw report lines for the
        // AM-14 evidence record.
        guard let path = ProcessInfo.processInfo.environment["F5_PROGRESSIVE_REPORT_PATH"] else {
            return
        }
        let line = report.reportLine + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Harness

    @MainActor
    private func makeHarness(
        pipeline: any AudioMetadataPipeline,
        provider: any QuickImportPathIdentityProviding,
        access: any QuickImportScopeAccessing,
        policy: QuickImportLoadPolicy
    ) throws -> LaneHarness {
        let suiteName = "AudioMator.F5Performance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let journalDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5PerfJournal-\(UUID().uuidString)", isDirectory: true)
        let issueLogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5PerfIssues-\(UUID().uuidString).json")
        let environment = QuickImportEnvironment(
            identityProvider: provider,
            scopeAccess: access,
            loadPolicy: policy
        )
        let viewModel = AudioViewModel(
            watchedFolderStore: WatchedFolderStore(userDefaults: defaults),
            fileAccessGrantStore: FileAccessGrantStore(userDefaults: defaults),
            metadataPipeline: pipeline,
            saveIssueLogStore: SaveIssueLogStore(fileURL: issueLogURL),
            conflictPolicyDefaults: defaults,
            renameJournalStore: LocalRenameJournalStore(directoryURL: journalDirectory),
            renameJournalAutoClassification: false,
            quickImportEnvironment: environment
        )
        return LaneHarness(
            viewModel: viewModel,
            userDefaults: defaults,
            suiteName: suiteName,
            journalDirectory: journalDirectory,
            issueLogURL: issueLogURL,
            workspaceDirectory: nil
        )
    }

    @MainActor
    private func waitForImport(
        _ viewModel: AudioViewModel,
        expectedCount: Int,
        timeout: TimeInterval = 120
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while (viewModel.activeQuickImportTaskCount != 0 || viewModel.files.count != expectedCount),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(viewModel.activeQuickImportTaskCount, 0)
        XCTAssertEqual(viewModel.files.count, expectedCount)
    }

    @MainActor
    private func requireFixtures() throws {
        try XCTSkipIf(
            AudioFileTestFactory.fixtureFileVersion == nil,
            "App-hosted fixture snapshot is unavailable in this runner"
        )
    }

    @MainActor
    private func fixtureSourceURL() throws -> URL {
        final class BundleToken {}
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(
            forResource: "testAudioFile.mp3",
            withExtension: nil,
            subdirectory: "Fixtures/Audio"
        ) ?? bundle.url(forResource: "testAudioFile.mp3", withExtension: nil) else {
            throw XCTSkip("The decoded MP3 fixture is unavailable in this runner")
        }
        return url
    }

    @MainActor
    private static func syntheticPaths(count: Int) -> [URL] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorF5PerfSynthetic-\(UUID().uuidString)", isDirectory: true)
        return (0..<count).map { index in
            root.appendingPathComponent(String(format: "%05d-track.mp3", index))
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
    }

    @MainActor
    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
#endif
