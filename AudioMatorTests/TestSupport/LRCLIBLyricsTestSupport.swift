import Foundation
import TagLibAudioMetadata
import XCTest
@testable import AudioMator

// MARK: - Gates

/// Async gate that deliberately does not observe task cancellation.
///
/// A non-cooperative provider is the adversarial case the AM-08 contract must
/// survive: closing the browser cannot rely on the provider cooperatively
/// returning or throwing.
nonisolated final class LRCLIBTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    nonisolated init(isOpen: Bool = false) {
        self.isOpen = isOpen
    }

    nonisolated func wait() async {
        let alreadyOpen = lock.withLock { isOpen }
        guard !alreadyOpen else { return }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock { () -> Bool in
                if isOpen {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    nonisolated func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            let pending = self.waiters
            self.waiters.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
    }
}

/// Synchronous gate used inside a pipeline's blocking write method.
///
/// `startedCount` lets a test observe that the non-interruptible commit actually
/// entered the writer before it decides to end the session.
nonisolated final class LRCLIBSyncGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _startedCount = 0

    nonisolated init() {}

    nonisolated var startedCount: Int {
        lock.withLock { _startedCount }
    }

    nonisolated func wait() {
        lock.withLock { _startedCount += 1 }
        semaphore.wait()
    }

    nonisolated func open() {
        semaphore.signal()
    }
}

// MARK: - Provider fakes

/// Recording LRCLIB fake that can gate every call and ignores cancellation.
nonisolated final class LRCLIBGatedClient: LRCLIBLyricsSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedQueries: [LRCLIBSearchQuery] = []
    private let gate: LRCLIBTestGate
    private let perCallGates: [LRCLIBTestGate]
    private let candidatesByTrackName: [String: [LRCLIBLyricsCandidate]]

    nonisolated init(
        gate: LRCLIBTestGate = LRCLIBTestGate(isOpen: true),
        perCallGates: [LRCLIBTestGate] = [],
        candidatesByTrackName: [String: [LRCLIBLyricsCandidate]] = [:]
    ) {
        self.gate = gate
        self.perCallGates = perCallGates
        self.candidatesByTrackName = candidatesByTrackName
    }

    nonisolated var queryCount: Int {
        lock.withLock { recordedQueries.count }
    }

    nonisolated var queries: [LRCLIBSearchQuery] {
        lock.withLock { recordedQueries }
    }

    nonisolated func search(
        matching query: LRCLIBSearchQuery,
        limit: Int
    ) async throws -> [LRCLIBLyricsCandidate] {
        let callIndex = lock.withLock { () -> Int in
            recordedQueries.append(query)
            return recordedQueries.count - 1
        }
        let callGate = perCallGates.indices.contains(callIndex) ? perCallGates[callIndex] : gate
        // Deliberately not cancellation-aware.
        await callGate.wait()
        // The query value is Sendable, but its stored fields keep app default
        // MainActor isolation; read the fixture key through the owning actor.
        let trackName = await MainActor.run { query.trackName }
        return Array((candidatesByTrackName[trackName] ?? []).prefix(max(1, limit)))
    }
}

/// Writing spy used to observe store intents/outcomes without touching disk.
@MainActor
final class LRCLIBRecordingWriter: LRCLIBLyricsWriting {
    private(set) var manualIntents: [LRCLIBLyricsManualWriteIntent] = []
    private(set) var autoIntents: [LRCLIBLyricsAutoWriteIntent] = []
    var manualOutcome: LRCLIBLyricsManualWriteOutcome = .rejected("recording writer")
    var autoOutcomeProvider: ((LRCLIBLyricsAutoWriteIntent) -> LRCLIBLyricsAutoWriteOutcome)?
    var autoGate: LRCLIBTestGate?

    func applyLRCLIBLyrics(
        _ intent: LRCLIBLyricsManualWriteIntent
    ) async -> LRCLIBLyricsManualWriteOutcome {
        manualIntents.append(intent)
        return manualOutcome
    }

    func applyLRCLIBLyricsAutoMatches(
        _ intent: LRCLIBLyricsAutoWriteIntent
    ) async -> LRCLIBLyricsAutoWriteOutcome {
        autoIntents.append(intent)
        await autoGate?.wait()
        if let autoOutcomeProvider {
            return autoOutcomeProvider(intent)
        }
        var summary = BatchMetadataOperationSummary(totalTargets: intent.entries.count)
        summary.succeeded = intent.entries.filter { $0.write != nil }.count
        let applied = intent.entries
            .filter { $0.write != nil }
            .map { LRCLIBLyricsAppliedEntry(fileID: $0.fileID, candidateID: $0.candidateID) }
        return LRCLIBLyricsAutoWriteOutcome(
            appliedEntries: applied,
            summary: summary,
            succeededCount: applied.count,
            didCancel: false,
            cancelledBeforeAnyStart: false
        )
    }
}

// MARK: - Mutation pipeline fakes

/// Records strict raw writes without touching disk. Used for rejection tests where
/// any writer call would be a failure.
nonisolated final class LRCLIBRecordingPipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct RawWriteRecord: Sendable {
        let url: URL
        let version: MetadataFileVersion
        let patch: RawMetadataPatch
    }

    private let lock = NSLock()
    private var records: [RawWriteRecord] = []
    private let reloadFile: AudioFile?
    private let warnings: [String]
    private let writeGate: LRCLIBSyncGate?

    nonisolated init(
        reloadFile: AudioFile?,
        warnings: [String] = [],
        writeGate: LRCLIBSyncGate? = nil
    ) {
        self.reloadFile = reloadFile
        self.warnings = warnings
        self.writeGate = writeGate
    }

    nonisolated var rawWrites: [RawWriteRecord] {
        lock.withLock { records }
    }

    nonisolated var rawWriteCount: Int {
        lock.withLock { records.count }
    }

    nonisolated var requiresTransactionalDirectoryAccess: Bool { false }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        guard let reloadFile else { throw CocoaError(.fileNoSuchFile) }
        return reloadFile
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? { nil }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap { [:] }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func writeReviewedRawPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        writeGate?.wait()
        lock.withLock {
            records.append(RawWriteRecord(url: url, version: expectedVersion, patch: patch))
        }
        return AudioMetadataWriteResult(warnings: warnings)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try TagLibAudioMetadataPipeline().projectMetadataWrite(intent, fileExtension: fileExtension)
    }
}

/// Forwards reads/writes to the pinned real package adapter while suppressing only
/// the interactive folder grant (headless tests must never present a modal panel).
/// Records the strict raw writes and can gate the committed reload so a test can
/// observe a commit that already crossed the admission boundary.
nonisolated final class LRCLIBRealReadbackPipeline: AudioMetadataPipeline, @unchecked Sendable {
    struct RawWriteRecord: Sendable {
        let url: URL
        let version: MetadataFileVersion
        let patch: RawMetadataPatch
    }

    private let base = TagLibAudioMetadataPipeline()
    private let lock = NSLock()
    private var records: [RawWriteRecord] = []
    private let reloadGate: LRCLIBTestGate?

    nonisolated init(reloadGate: LRCLIBTestGate? = nil) {
        self.reloadGate = reloadGate
    }

    nonisolated var rawWrites: [RawWriteRecord] {
        lock.withLock { records }
    }

    nonisolated var rawWriteCount: Int {
        lock.withLock { records.count }
    }

    nonisolated var requiresTransactionalDirectoryAccess: Bool { false }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        await reloadGate?.wait()
        return try await base.loadAudioFile(at: url, id: id)
    }

    nonisolated func conflictSnapshot(for url: URL) throws -> MetadataSnapshot {
        try base.conflictSnapshot(for: url)
    }

    nonisolated func metadataFileVersion(at url: URL) throws -> MetadataFileVersion {
        try base.metadataFileVersion(at: url)
    }

    nonisolated func rawMetadataDumpText(for url: URL) -> String? {
        base.rawMetadataDumpText(for: url)
    }

    nonisolated func rawMetadataValueMap(for url: URL) throws -> RawMetadataValueMap {
        try base.rawMetadataValueMap(for: url)
    }

    nonisolated func writeMetadata(
        _ edit: MetadataEditPayload,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.writeMetadata(edit, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeRawMetadataPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.writeRawMetadataPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func writeReviewedRawPatch(
        _ patch: RawMetadataPatch,
        to url: URL,
        expectedVersion: MetadataFileVersion
    ) throws -> AudioMetadataWriteResult {
        lock.withLock {
            records.append(RawWriteRecord(url: url, version: expectedVersion, patch: patch))
        }
        return try base.writeReviewedRawPatch(patch, to: url, expectedVersion: expectedVersion)
    }

    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        try base.eraseAllMetadata(at: url, expectedVersion: expectedVersion)
    }

    nonisolated func projectMetadataWrite(
        _ intent: ReviewedMetadataWrite.Intent,
        fileExtension: String
    ) throws -> MetadataWriteProjection {
        try base.projectMetadataWrite(intent, fileExtension: fileExtension)
    }
}

// MARK: - Fixture helpers

enum LRCLIBLyricsTestSupport {
    /// Creates one observed synthetic file backed by a real disposable file so the
    /// strict executor's captured-fingerprint validation can pass.
    @MainActor
    static func makeObservedFile(
        named name: String,
        directory: URL,
        title: String = "Observed Title",
        artist: String = "Observed Artist",
        duration: Double = 180
    ) throws -> AudioFile {
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data(repeating: 0x41, count: 64).write(to: url)
        }
        let fingerprint = try AudioFileFingerprint.capture(at: url)
        guard let version = AudioFileTestFactory.fixtureFileVersion else {
            throw CocoaError(.featureUnsupported)
        }
        // `makeObserved` does not carry artist/duration, but the auto-apply
        // confidence rule and the lyrics query both need them. Build the same
        // coherent observation through the general factory path instead.
        return AudioFileTestFactory.make(
            url: url,
            title: title,
            artist: artist,
            duration: duration,
            fileFingerprint: fingerprint,
            metadataFileVersion: version
        )
    }

    @MainActor
    static func makeTemporaryDirectory(prefix: String = "LRCLIBLyrics") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeCandidate(
        id: Int,
        track: String,
        artist: String,
        album: String = "",
        duration: Double? = 180,
        plainLyrics: String? = nil,
        syncedLyrics: String? = nil,
        instrumental: Bool = false
    ) -> LRCLIBLyricsCandidate {
        LRCLIBLyricsCandidate(
            id: id,
            name: track,
            trackName: track,
            artistName: artist,
            albumName: album,
            duration: duration,
            instrumental: instrumental,
            plainLyrics: plainLyrics,
            syncedLyrics: syncedLyrics
        )
    }

    @MainActor
    static func waitUntil(
        deadlineSeconds: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(deadlineSeconds))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    static func waitForOperationToDrain(
        _ store: LRCLIBLyricsBrowserStore,
        deadlineSeconds: TimeInterval = 5
    ) async throws {
        try await waitUntil(deadlineSeconds: deadlineSeconds) {
            !store.isOperationActive && !store.hasDrainingOperations
        }
    }
}
