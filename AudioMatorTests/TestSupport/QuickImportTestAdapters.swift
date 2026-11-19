import Foundation
import TagLibAudioMetadata
@testable import AudioMator

/// Deterministic synthetic candidate identities.
///
/// The canonical path and device/inode evidence mirror
/// `AudioFileTestFactory.fingerprint(for:)` so a fake loader snapshot from the
/// same URL passes the production canonical-location verification without any
/// real files. Tests that exercise retarget rejection use
/// `FileSystemQuickImportPathIdentityProvider` and real temporary entries.
final class SyntheticQuickImportIdentityProvider: QuickImportPathIdentityProviding, @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let identityPreparationCount: Int
        let fileKeyComputationCount: Int
        let parentKeyComputationCount: Int
        let fileIdentityCaptureCount: Int
        let parentIdentityCaptureCount: Int
    }

    private let lock = NSLock()
    private var identityPreparations = 0
    private var fileKeyComputations = 0
    private var parentKeyComputations = 0
    private var fileIdentityCaptures = 0
    private var parentIdentityCaptures = 0
    private var fileIdentityOverrides: [String: QuickImportEntryIdentity] = [:]

    /// Deterministic canonical comparison key used by this synthetic provider.
    static func canonicalKey(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
            .precomposedStringWithCanonicalMapping
    }

    /// Deterministic parent key used by this synthetic provider.
    static func parentKey(forFileURL url: URL) -> String {
        "synthetic-parent:" + url.standardizedFileURL.deletingLastPathComponent().path
    }

    static func syntheticEntryIdentity(for url: URL) -> QuickImportEntryIdentity {
        QuickImportEntryIdentity(
            device: 1,
            inode: UInt64(bitPattern: Int64(url.standardizedFileURL.path.hashValue))
        )
    }

    /// Overrides the captured device/inode evidence for one standardized path so
    /// journal/rename tests can present the same entry identity at two URLs.
    func setFileIdentityOverride(_ identity: QuickImportEntryIdentity?, for url: URL) {
        let path = url.standardizedFileURL.path
        lock.withLock {
            if let identity {
                fileIdentityOverrides[path] = identity
            } else {
                fileIdentityOverrides.removeValue(forKey: path)
            }
        }
    }

    func prepareIdentity(
        forFileURL url: URL,
        parent: QuickImportParentEvidence?
    ) -> QuickImportPathIdentity {
        let standardizedURL = url.standardizedFileURL
        lock.withLock {
            identityPreparations += 1
            fileKeyComputations += 1
            fileIdentityCaptures += 1
            if parent == nil {
                parentKeyComputations += 1
                parentIdentityCaptures += 1
            }
        }

        let canonicalPath = Self.canonicalKey(for: standardizedURL)
        let parentURL = standardizedURL.deletingLastPathComponent()
        let parentEvidence = parent ?? QuickImportParentEvidence(
            parentURL: parentURL,
            parentKey: "synthetic-parent:" + parentURL.path,
            parentCanonicalPath: parentURL.resolvingSymlinksInPath().path
                .precomposedStringWithCanonicalMapping,
            parentIsCaseSensitive: true,
            parentIdentity: QuickImportEntryIdentity(
                device: 1,
                inode: UInt64(bitPattern: Int64(parentURL.path.hashValue))
            )
        )
        return QuickImportPathIdentity(
            operationalURL: standardizedURL,
            canonicalPath: canonicalPath,
            fileKey: canonicalPath,
            directoryEntryKey: "entry:" + parentEvidence.parentCanonicalPath + "/"
                + standardizedURL.lastPathComponent,
            parentEvidence: parentEvidence,
            fileIdentity: lock.withLock {
                fileIdentityOverrides[standardizedURL.path]
                    ?? Self.syntheticEntryIdentity(for: standardizedURL)
            }
        )
    }

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(
                identityPreparationCount: identityPreparations,
                fileKeyComputationCount: fileKeyComputations,
                parentKeyComputationCount: parentKeyComputations,
                fileIdentityCaptureCount: fileIdentityCaptures,
                parentIdentityCaptureCount: parentIdentityCaptures
            )
        }
    }
}

/// Wraps the real filesystem identity provider and counts one call per candidate.
final class CountingFileSystemQuickImportIdentityProvider: QuickImportPathIdentityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let provider = FileSystemQuickImportPathIdentityProvider()
    private var identityPreparations = 0
    private var fileKeyComputations = 0
    private var parentKeyComputations = 0

    func prepareIdentity(
        forFileURL url: URL,
        parent: QuickImportParentEvidence?
    ) -> QuickImportPathIdentity {
        lock.withLock {
            identityPreparations += 1
            fileKeyComputations += 1
            if parent == nil { parentKeyComputations += 1 }
        }
        return provider.prepareIdentity(forFileURL: url, parent: parent)
    }

    var snapshot: (identityPreparations: Int, fileKeyComputations: Int, parentKeyComputations: Int) {
        lock.withLock { (identityPreparations, fileKeyComputations, parentKeyComputations) }
    }
}

/// Scripted security-scope adapter for the lease tests.
final class CountingQuickImportScopeAccess: QuickImportScopeAccessing, @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let startCount: Int
        let stopCount: Int
        let repeatedStartAttempts: Int
        let startCountsByURL: [URL: Int]
        let stopCountsByURL: [URL: Int]
    }

    private let lock = NSLock()
    private var defaultGrant: Bool
    private var grantsByURL: [URL: Bool] = [:]
    private var startsByURL: [URL: Int] = [:]
    private var stopsByURL: [URL: Int] = [:]

    init(defaultGrant: Bool = true) {
        self.defaultGrant = defaultGrant
    }

    func setDefaultGrant(_ granted: Bool) {
        lock.withLock { defaultGrant = granted }
    }

    func setGranted(_ granted: Bool, for url: URL) {
        lock.withLock { grantsByURL[url] = granted }
    }

    func startAccessingScope(for url: URL) -> Bool {
        lock.withLock {
            startsByURL[url, default: 0] += 1
            return grantsByURL[url] ?? defaultGrant
        }
    }

    func stopAccessingScope(for url: URL) {
        lock.withLock { stopsByURL[url, default: 0] += 1 }
    }

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(
                startCount: startsByURL.values.reduce(0, +),
                stopCount: stopsByURL.values.reduce(0, +),
                repeatedStartAttempts: startsByURL.values.reduce(0) { total, count in
                    total + max(0, count - 1)
                },
                startCountsByURL: startsByURL,
                stopCountsByURL: stopsByURL
            )
        }
    }
}

/// Reusable gate for behaviour lanes that need a load suspended between
/// preparation and publication.
actor QuickImportProgressiveGate {
    enum GateError: Error {
        case timedOut
    }

    private var enteredCount = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        enteredCount += 1
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered(atLeast count: Int = 1) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while enteredCount < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard enteredCount >= count else { throw GateError.timedOut }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func entered() -> Int { enteredCount }
}

/// Deterministic metadata pipeline for progressive lanes.
///
/// - `.synthetic`: returns `AudioFileTestFactory.make` snapshots so no disk read
///   happens; used for the 480/960/4,000 counter budgets.
/// - `.realFingerprint`: captures the file's real fingerprint when the read
///   starts (after any gate release), so a retarget between preparation and load
///   is observed exactly like the production adapter.
final class ProgressiveQuickImportMetadataPipeline: AudioMetadataPipeline, @unchecked Sendable {
    enum Mode {
        case synthetic
        case realFingerprint
    }

    private let lock = NSLock()
    private let mode: Mode
    private let version: MetadataFileVersion?
    private let gate: QuickImportProgressiveGate?
    private let gatedURLs: Set<URL>?
    private let failingURLs: Set<URL>
    private var failFirstAttemptsByURL: [URL: Int] = [:]
    private var attemptCountsByURL: [URL: Int] = [:]
    private var loads = 0
    private var loadedURLs: [URL] = []

    @MainActor
    init(
        mode: Mode = .synthetic,
        gate: QuickImportProgressiveGate? = nil,
        gatedURLs: Set<URL>? = nil,
        failingURLs: Set<URL> = []
    ) {
        self.mode = mode
        self.version = AudioFileTestFactory.fixtureFileVersion
        self.gate = gate
        self.gatedURLs = gatedURLs
        self.failingURLs = failingURLs
    }

    var loadCount: Int { lock.withLock { loads } }
    var loadedURLList: [URL] { lock.withLock { loadedURLs } }

    /// Scripted first-attempt failures for one URL. Used to drive an older
    /// request into a read failure while a newer request succeeds for the same
    /// key (D2 token-pruning race).
    func setFailFirstAttempts(_ count: Int, for url: URL) {
        lock.withLock { failFirstAttemptsByURL[url] = count }
    }

    func attemptCount(for url: URL) -> Int {
        lock.withLock { attemptCountsByURL[url] ?? 0 }
    }

    nonisolated func loadAudioFile(at url: URL, id: UUID) async throws -> AudioFile {
        let attempt = lock.withLock { () -> Int in
            loads += 1
            loadedURLs.append(url)
            let next = (attemptCountsByURL[url] ?? 0) + 1
            attemptCountsByURL[url] = next
            return next
        }
        if let gate, gatedURLs?.contains(url) ?? true {
            await gate.enter()
        }
        let failFirstAttempts = lock.withLock { failFirstAttemptsByURL[url] ?? 0 }
        if failingURLs.contains(url) || attempt <= failFirstAttempts {
            throw CocoaError(.fileReadNoPermission)
        }
        switch mode {
        case .synthetic:
            return await MainActor.run {
                AudioFileTestFactory.make(id: id, url: url)
            }
        case .realFingerprint:
            guard let version else {
                throw CocoaError(.fileReadUnknown)
            }
            let fingerprint = try AudioFileFingerprint.capture(at: url)
            return await MainActor.run {
                AudioFileTestFactory.makeObserved(
                    id: id,
                    url: url,
                    fileFingerprint: fingerprint,
                    metadataFileVersion: version
                )
            }
        }
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
    nonisolated func eraseAllMetadata(
        at url: URL,
        expectedVersion: MetadataFileVersion?
    ) throws -> AudioMetadataWriteResult {
        AudioMetadataWriteResult(warnings: [])
    }
}
