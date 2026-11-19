import XCTest
@testable import AudioMator

/// Deterministic controller benchmark for E4/AM-13.
///
/// Asserts only bounded work (invocation counts and plan row counts) and
/// reports worker vs main-actor timings. It deliberately sets no wall-clock
/// threshold: the ordinary suite must not fail on a loaded machine.
@MainActor
final class MetadataFilenamePlannerBenchmarkTests: XCTestCase {
    private nonisolated final class BenchmarkWorker: MetadataFilenamePlanWorking, @unchecked Sendable {
        private let lock = NSLock()
        private let base = MetadataFilenamePlannerWorker()
        private var invocationCount = 0
        private var durations: [Duration] = []

        var invocations: Int {
            lock.lock()
            defer { lock.unlock() }
            return invocationCount
        }

        var workerDurations: [Duration] {
            lock.lock()
            defer { lock.unlock() }
            return durations
        }

        nonisolated func makePlan(
            _ input: MetadataFilenamePlannerInput
        ) async throws -> MetadataFilenameConverterResult {
            lock.lock()
            invocationCount += 1
            lock.unlock()
            let clock = ContinuousClock()
            let start = clock.now
            let result = try await base.makePlan(input)
            let elapsed = clock.now - start
            lock.lock()
            durations.append(elapsed)
            lock.unlock()
            return result
        }
    }

    private nonisolated final class BenchmarkClock: MetadataFilenameDebounceClock, @unchecked Sendable {
        nonisolated func sleep(for duration: Duration) async throws {
            try Task.checkCancellation()
        }
    }

    func testControllerReportsBoundedWorkForTenThousandAndOneHundredThousandInputs() async {
        let tenThousand = await measureCSVImportPlan(
            fileCount: 10_000,
            label: "10k CSV import"
        )
        XCTAssertEqual(tenThousand.invocations, 1)
        XCTAssertEqual(tenThousand.rows, 10_000)
        XCTAssertEqual(tenThousand.encodedPlanRows, 10_000)

        let oneHundredThousand = await measureTextExportPlan(
            fileCount: 100_000,
            label: "100k text export"
        )
        XCTAssertEqual(oneHundredThousand.invocations, 1)
        XCTAssertEqual(oneHundredThousand.rows, 100_000)
    }

    private struct Measurement: Sendable {
        let invocations: Int
        let rows: Int
        let encodedPlanRows: Int
        let workerDuration: Duration
        let totalDuration: Duration
        let mainActorReadDuration: Duration
    }

    private func measureCSVImportPlan(fileCount: Int, label: String) async -> Measurement {
        let clock = ContinuousClock()
        let files = syntheticFiles(count: fileCount)
        let csv = (0..<fileCount)
            .map { index in "file-\(index).mp3,Imported Title \(index)" }
            .joined(separator: "\n")

        let worker = BenchmarkWorker()
        let store = MetadataFilenameToolStore(worker: worker, clock: BenchmarkClock())
        store.present(targetFileIDs: files.map(\.id))
        store.refresh(files: files, filesRevision: UUID(), projector: nil)
        store.updateTemplate("{{fileName}},{{title}}", for: .csvToMetadata)
        store.setExternalSource(csv, for: .csvToMetadata)
        store.setFirstCSVRowIsHeader(false)

        let start = clock.now
        store.selectMode(.csvToMetadata)
        await store.waitForPlanSettlement()
        let totalDuration = clock.now - start

        let readStart = clock.now
        for _ in 0..<200 {
            _ = store.displayImportPlan(for: .csvToMetadata).rows.count
            _ = store.targetCount
            _ = store.previewPhaseMessage()
        }
        let mainActorReadDuration = clock.now - readStart
        let plan = store.displayImportPlan(for: .csvToMetadata)
        let measurement = Measurement(
            invocations: worker.invocations,
            rows: plan.rows.count,
            encodedPlanRows: plan.writeEntries.count,
            workerDuration: worker.workerDurations.last ?? .zero,
            totalDuration: totalDuration,
            mainActorReadDuration: mainActorReadDuration
        )
        report(label: label, measurement: measurement)
        return measurement
    }

    private func measureTextExportPlan(fileCount: Int, label: String) async -> Measurement {
        let clock = ContinuousClock()
        let files = syntheticFiles(count: fileCount)
        let worker = BenchmarkWorker()
        let store = MetadataFilenameToolStore(worker: worker, clock: BenchmarkClock())
        store.present(targetFileIDs: files.map(\.id))
        store.refresh(files: files, filesRevision: UUID(), projector: nil)
        store.updateTemplate("{{title}} — {{artist}}", for: .metadataToText)

        let start = clock.now
        store.selectMode(.metadataToText)
        await store.waitForPlanSettlement()
        let totalDuration = clock.now - start

        let readStart = clock.now
        for _ in 0..<200 {
            _ = store.displayTextExportPlan().rows.count
            _ = store.targetCount
            _ = store.previewPhaseMessage()
        }
        let mainActorReadDuration = clock.now - readStart
        let plan = store.displayTextExportPlan()
        let measurement = Measurement(
            invocations: worker.invocations,
            rows: plan.rows.count,
            encodedPlanRows: plan.rows.count,
            workerDuration: worker.workerDurations.last ?? .zero,
            totalDuration: totalDuration,
            mainActorReadDuration: mainActorReadDuration
        )
        report(label: label, measurement: measurement)
        return measurement
    }

    private func report(label: String, measurement: Measurement) {
        print(
            "[E4 benchmark] \(label): invocations=\(measurement.invocations) "
                + "rows=\(measurement.rows) worker=\(measurement.workerDuration) "
                + "total=\(measurement.totalDuration) "
                + "200-main-actor-reads=\(measurement.mainActorReadDuration)"
        )
    }

    private func syntheticFiles(count: Int) -> [AudioFile] {
        let directory = URL(fileURLWithPath: "/tmp/AudioMatorE4Benchmark", isDirectory: true)
        var files: [AudioFile] = []
        files.reserveCapacity(count)
        for index in 0..<count {
            files.append(
                AudioFileTestFactory.make(
                    url: directory.appendingPathComponent("file-\(index).mp3"),
                    title: "Title \(index)",
                    artist: "Artist \(index)"
                )
            )
        }
        return files
    }
}
