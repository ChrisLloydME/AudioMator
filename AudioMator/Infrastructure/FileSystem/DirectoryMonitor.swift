import Darwin
import Foundation

// MARK: - Planning

struct DirectoryMonitoringPlan: Equatable, Sendable {
    let monitoredURLs: [URL]
    let totalDirectoryCount: Int
    let omittedByLimitCount: Int

    nonisolated static func make(
        directories: [URL],
        rootURL: URL,
        limit: Int
    ) -> DirectoryMonitoringPlan {
        let boundedLimit = max(1, limit)
        var urlsByPath: [String: URL] = [:]

        for url in directories + [rootURL] {
            let normalizedURL = url.standardizedFileURL
            let path = FileSystemPathSemantics.key(for: normalizedURL)
            urlsByPath[path] = normalizedURL
        }

        let normalizedRootURL = rootURL.standardizedFileURL
        let normalizedRootPath = FileSystemPathSemantics.key(for: normalizedRootURL)
        let nestedURLs = urlsByPath
            .filter { $0.key != normalizedRootPath }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.value)
        let orderedURLs = [urlsByPath[normalizedRootPath] ?? normalizedRootURL] + nestedURLs
        let monitoredURLs = Array(orderedURLs.prefix(boundedLimit))

        return DirectoryMonitoringPlan(
            monitoredURLs: monitoredURLs,
            totalDirectoryCount: orderedURLs.count,
            omittedByLimitCount: max(0, orderedURLs.count - monitoredURLs.count)
        )
    }
}

struct DirectoryMonitoringStatus: Equatable, Sendable {
    let totalDirectoryCount: Int
    let monitoredDirectoryCount: Int
    let omittedByLimitCount: Int
    let failedToOpenCount: Int
    let scanFailureCount: Int
    let metadataReadFailureCount: Int

    var isDegraded: Bool {
        omittedByLimitCount > 0 || failedToOpenCount > 0 || scanFailureCount > 0 || metadataReadFailureCount > 0
    }

    var message: String {
        guard isDegraded else {
            return "Automatic refresh is monitoring all \(monitoredDirectoryCount) folders."
        }

        var reasons: [String] = []
        if omittedByLimitCount > 0 {
            reasons.append(omittedByLimitCount == 1 ? String(localized: "1 folder exceeds the monitoring limit") : String(localized: "\(omittedByLimitCount) folders exceed the monitoring limit"))
        }
        if failedToOpenCount > 0 {
            reasons.append(failedToOpenCount == 1 ? String(localized: "1 folder couldn’t be opened") : String(localized: "\(failedToOpenCount) folders couldn't be opened"))
        }
        if scanFailureCount > 0 {
            reasons.append(scanFailureCount == 1
                ? String(localized: "1 folder scan couldn’t be completed")
                : String(localized: "\(scanFailureCount) folder scans couldn't be completed"))
        }
        if metadataReadFailureCount > 0 {
            reasons.append(metadataReadFailureCount == 1
                ? String(localized: "1 audio file couldn’t be read")
                : String(localized: "\(metadataReadFailureCount) audio files couldn't be read"))
        }

        var message = String(localized: "Automatic refresh is active for \(monitoredDirectoryCount) of \(totalDirectoryCount) folders. \(reasons.joined(separator: ", ")).")
        if omittedByLimitCount > 0 || failedToOpenCount > 0 {
            message += " " + String(localized: "Changes in unmonitored subfolders may not appear until a scan succeeds.")
        }
        if metadataReadFailureCount > 0 {
            message += " " + String(localized: "Previously loaded metadata is still shown where available.")
        }
        if scanFailureCount > 0 {
            message += " " + String(localized: "The previous file list will stay visible until a scan completes successfully.")
        }
        return message
    }
}

// MARK: - Identity

/// File kind reported by `fstat(2)` for a monitored descriptor.
///
/// Monitoring accepts only directory descriptors. Keeping the kind instead of a
/// bare "open succeeded" boolean makes an unexpected regular file, symlink or
/// special node an explicit rejection.
nonisolated enum DirectoryMonitorNodeKind: Equatable, Hashable, Sendable {
    case directory
    case regularFile
    case symbolicLink
    case other(mode: UInt16)

    nonisolated init(fileMode: mode_t) {
        switch fileMode & S_IFMT {
        case S_IFDIR: self = .directory
        case S_IFREG: self = .regularFile
        case S_IFLNK: self = .symbolicLink
        default: self = .other(mode: fileMode & S_IFMT)
        }
    }
}

/// The identity of the directory entry an open descriptor refers to.
///
/// A path is not an identity: the same pathname can be unlinked and recreated
/// with a different inode while the old descriptor keeps watching the old
/// directory. Device and inode are captured with `fstat` on the opened
/// descriptor, so they describe what the descriptor actually watches rather
/// than what the pathname meant a moment earlier.
nonisolated struct DirectoryMonitorIdentity: Equatable, Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let kind: DirectoryMonitorNodeKind

    nonisolated init(device: UInt64, inode: UInt64, kind: DirectoryMonitorNodeKind) {
        self.device = device
        self.inode = inode
        self.kind = kind
    }

    nonisolated init(fileStat info: stat) {
        self.init(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            kind: DirectoryMonitorNodeKind(fileMode: info.st_mode)
        )
    }

    nonisolated var isDirectory: Bool {
        kind == .directory
    }
}

/// Stable identity of one installed monitor instance.
///
/// A replacement monitor for the same pathname gets a new token. Consumers must
/// ignore events whose token no longer belongs to the active binding.
nonisolated struct DirectoryMonitorInstanceToken: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let rawValue: UUID

    nonisolated init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    nonisolated var description: String { rawValue.uuidString }
    nonisolated var debugDescription: String { "DirectoryMonitorInstanceToken(\(rawValue.uuidString))" }
}

// MARK: - Events

/// Directory-descriptor event bits surfaced by the monitor.
///
/// For a directory descriptor these are directory-entry events (entry creation,
/// removal or rename) and directory-level terminal events. They are not a
/// promise about in-place content writes to an already indexed file: the
/// directory-only mechanism does not observe those on APFS, which is why the
/// app keeps the selected-file activation refresh and explicit reload.
nonisolated enum DirectoryMonitorEventFlag: String, CaseIterable, Hashable, Sendable {
    case write
    case delete
    case rename
    case attrib
    case extend
    case link
    case revoke
    case funlock

    /// Events after which the descriptor can no longer be trusted to watch the
    /// authorized path. The instance is terminal and its descriptor is closed.
    nonisolated static let terminalFlags: Set<DirectoryMonitorEventFlag> = [.delete, .rename, .revoke]

    nonisolated static func flags(from event: DispatchSource.FileSystemEvent) -> Set<DirectoryMonitorEventFlag> {
        var flags: Set<DirectoryMonitorEventFlag> = []
        if event.contains(.write) { flags.insert(.write) }
        if event.contains(.delete) { flags.insert(.delete) }
        if event.contains(.rename) { flags.insert(.rename) }
        if event.contains(.attrib) { flags.insert(.attrib) }
        if event.contains(.extend) { flags.insert(.extend) }
        if event.contains(.link) { flags.insert(.link) }
        if event.contains(.revoke) { flags.insert(.revoke) }
        if event.contains(.funlock) { flags.insert(.funlock) }
        return flags
    }
}

/// One delivery from a monitor instance.
nonisolated struct DirectoryMonitorEvent: Equatable, Sendable {
    let instanceToken: DirectoryMonitorInstanceToken
    let identity: DirectoryMonitorIdentity
    let flags: Set<DirectoryMonitorEventFlag>

    nonisolated var isTerminal: Bool {
        !flags.isDisjoint(with: DirectoryMonitorEventFlag.terminalFlags)
    }
}

nonisolated enum DirectoryMonitorState: Equatable, Sendable {
    /// The descriptor is open but the dispatch source has not started.
    case ready
    /// The dispatch source is installed and the instance can deliver events.
    case active
    /// A terminal event was observed; the instance can never be active again.
    case terminal(flags: Set<DirectoryMonitorEventFlag>)
    /// The instance was explicitly stopped; the descriptor is closing/closed.
    case stopped
}

// MARK: - Injectable file-system seam

/// The two platform calls the identity layer needs: open an event-only
/// descriptor and stat a descriptor or pathname.
///
/// Platform calls stay in the single native implementation so tests can wrap a
/// real descriptor, count balanced closes, and inject an open failure or an
/// identity mismatch without depending on dispatch timing.
nonisolated protocol DirectoryMonitorFileSystem: Sendable {
    /// Opens an event-only descriptor for `url`. The caller owns the descriptor
    /// and must close it with `closeDescriptor(_:)`; `-1` means the open failed.
    nonisolated func openDirectoryDescriptor(at url: URL) -> CInt
    /// `fstat` identity of an open descriptor. This is the identity the monitor
    /// actually watches, not the pathname's current identity.
    nonisolated func identity(ofDescriptor descriptor: CInt) -> DirectoryMonitorIdentity?
    /// `stat` identity of the current pathname, following symlinks. Used to
    /// prove a descriptor still refers to the authorized entry.
    nonisolated func identity(at url: URL) -> DirectoryMonitorIdentity?
    nonisolated func closeDescriptor(_ descriptor: CInt)
}

nonisolated struct NativeDirectoryMonitorFileSystem: DirectoryMonitorFileSystem {
    nonisolated init() {}

    nonisolated func openDirectoryDescriptor(at url: URL) -> CInt {
        url.path.withCString { open($0, O_EVTONLY) }
    }

    nonisolated func identity(ofDescriptor descriptor: CInt) -> DirectoryMonitorIdentity? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        return DirectoryMonitorIdentity(fileStat: info)
    }

    nonisolated func identity(at url: URL) -> DirectoryMonitorIdentity? {
        var info = stat()
        let result = url.path.withCString { stat($0, &info) }
        guard result == 0 else { return nil }
        return DirectoryMonitorIdentity(fileStat: info)
    }

    nonisolated func closeDescriptor(_ descriptor: CInt) {
        close(descriptor)
    }
}

/// Owns exactly one descriptor and closes it at most once.
///
/// The dispatch cancel handler and `stop()`/`deinit` can race; the lock keeps
/// the close balanced in every sequence, including a monitor that is released
/// without an explicit `stop()`.
private nonisolated final class DirectoryMonitorDescriptorOwner: @unchecked Sendable {
    private let fileSystem: any DirectoryMonitorFileSystem
    private let lock = NSLock()
    private var descriptor: CInt

    nonisolated init(descriptor: CInt, fileSystem: any DirectoryMonitorFileSystem) {
        self.descriptor = descriptor
        self.fileSystem = fileSystem
    }

    nonisolated var isOpen: Bool {
        lock.withLock { descriptor >= 0 }
    }

    nonisolated func close() {
        lock.lock()
        let descriptor = self.descriptor
        self.descriptor = -1
        lock.unlock()
        guard descriptor >= 0 else { return }
        fileSystem.closeDescriptor(descriptor)
    }

    deinit {
        close()
    }
}

// MARK: - Monitor

/// One directory monitor instance with identity, typed events and a terminal
/// state.
///
/// Descriptor ownership: the instance owns the descriptor from `init` until
/// `stop()`, a terminal event, or deallocation. The dispatch cancel handler is
/// the only asynchronous close path and it is balanced by the descriptor
/// owner's once-only close.
///
/// Late events: after `stop()` or a terminal event the instance never changes
/// state again and never delivers a further callback. Consumers additionally
/// match `instanceToken` because a callback queued before cancellation may still
/// be delivered to the owner after a replacement instance was installed.
nonisolated final class DirectoryMonitor: @unchecked Sendable {
    let instanceToken: DirectoryMonitorInstanceToken
    let url: URL
    let identity: DirectoryMonitorIdentity

    private let fileSystem: any DirectoryMonitorFileSystem
    private let queue: DispatchQueue
    private let eventHandler: @Sendable (DirectoryMonitorEvent) -> Void
    private let lock = NSLock()
    private let descriptorOwner: DirectoryMonitorDescriptorOwner
    private let fileDescriptor: CInt
    private var source: DispatchSourceFileSystemObject?
    private var state: DirectoryMonitorState = .ready

    /// Typed initializer used by the reconciliation controller and native tests.
    init?(
        url: URL,
        fileSystem: any DirectoryMonitorFileSystem = NativeDirectoryMonitorFileSystem(),
        queue: DispatchQueue = DispatchQueue(label: "AudioMator.DirectoryMonitor", qos: .utility),
        eventHandler: @escaping @Sendable (DirectoryMonitorEvent) -> Void
    ) {
        let descriptor = fileSystem.openDirectoryDescriptor(at: url)
        guard descriptor >= 0 else { return nil }

        let owner = DirectoryMonitorDescriptorOwner(descriptor: descriptor, fileSystem: fileSystem)
        guard let identity = fileSystem.identity(ofDescriptor: descriptor), identity.isDirectory else {
            owner.close()
            return nil
        }

        self.instanceToken = DirectoryMonitorInstanceToken()
        self.url = url
        self.identity = identity
        self.fileSystem = fileSystem
        self.queue = queue
        self.eventHandler = eventHandler
        self.descriptorOwner = owner
        self.fileDescriptor = descriptor
    }

    /// Compatibility seam for the current `AudioViewModel` call site, which
    /// still passes an untyped closure. The reconciliation wiring migrates the
    /// call site to the typed initializer and then this overload can be removed.
    convenience init?(
        url: URL,
        queue: DispatchQueue = DispatchQueue(label: "AudioMator.DirectoryMonitor", qos: .utility),
        eventHandler: @escaping @Sendable () -> Void
    ) {
        self.init(url: url, queue: queue) { _ in eventHandler() }
    }

    nonisolated var currentState: DirectoryMonitorState {
        lock.withLock { state }
    }

    nonisolated var isActive: Bool {
        lock.withLock { state == .active }
    }

    nonisolated var isTerminal: Bool {
        if case .terminal = currentState { return true }
        return false
    }

    nonisolated func start() {
        lock.lock()
        guard state == .ready else {
            lock.unlock()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleEvent()
        }
        // Capture only the owner: if the monitor is released while the source is
        // being cancelled, the descriptor is still closed exactly once.
        source.setCancelHandler { [descriptorOwner] in
            descriptorOwner.close()
        }
        self.source = source
        state = .active
        lock.unlock()
        source.resume()
    }

    nonisolated func stop() {
        lock.lock()
        guard state != .stopped else {
            lock.unlock()
            return
        }
        let previousState = state
        state = .stopped
        let source = self.source
        self.source = nil
        lock.unlock()

        switch previousState {
        case .ready:
            // Never started: no source owns the descriptor, close it directly.
            descriptorOwner.close()
        case .active, .terminal:
            // Close through the cancel handler; a terminal event already called
            // cancel, in which case this is a no-op.
            source?.cancel()
        case .stopped:
            break
        }
    }

    deinit {
        stop()
    }

    private nonisolated func handleEvent() {
        lock.lock()
        guard state == .active, let source else {
            lock.unlock()
            return
        }
        let flags = DirectoryMonitorEventFlag.flags(from: source.data)
        guard !flags.isEmpty else {
            lock.unlock()
            return
        }

        let event = DirectoryMonitorEvent(
            instanceToken: instanceToken,
            identity: identity,
            flags: flags
        )

        if event.isTerminal {
            // Mark terminal before delivering: a consumer can never observe the
            // instance as active after its terminal event, and no later event is
            // delivered from this descriptor.
            state = .terminal(flags: flags)
            lock.unlock()
            source.cancel()
            eventHandler(event)
        } else {
            lock.unlock()
            eventHandler(event)
        }
    }
}

// MARK: - Reconciliation

/// One installed monitor binding: the path key, the identity captured from the
/// descriptor and the instance token events carry.
nonisolated struct DirectoryMonitorBinding: Equatable, Sendable {
    let key: String
    let url: URL
    let identity: DirectoryMonitorIdentity
    let instanceToken: DirectoryMonitorInstanceToken
}

nonisolated struct DirectoryMonitorControllerSnapshot: Equatable, Sendable {
    let bindings: [DirectoryMonitorBinding]
    let droppedStaleEventCount: Int
    let terminalEventCount: Int
    let reconciliationGeneration: UInt64
    let isStopped: Bool

    nonisolated var activeDirectoryCount: Int { bindings.count }
}

/// The outcome of one identity-aware reconciliation pass.
nonisolated struct DirectoryMonitorReconciliation: Equatable, Sendable {
    let totalDirectoryCount: Int
    let monitoredDirectoryCount: Int
    let activeDirectoryCount: Int
    let omittedByLimitCount: Int
    let failedToOpenCount: Int
    let reboundDirectoryCount: Int
    let closedDirectoryCount: Int
    let droppedStaleEventCount: Int
    let terminalEventCount: Int
    /// Monotonic per-controller reconciliation counter. A consumer that applies
    /// results asynchronously must discard a result older than the latest
    /// generation it already published.
    let reconciliationGeneration: UInt64
    /// True when a follow-up scan must run to cover the scan-before-attach
    /// interval: a descriptor was installed for a new or rebound directory.
    let needsFollowUpScan: Bool
    let bindings: [DirectoryMonitorBinding]

    /// Degraded status is derived from the reconciliation itself, never from a
    /// timing heuristic: omitted directories, directories that could not be
    /// bound to their current identity, or a planned directory without an
    /// active descriptor.
    nonisolated var isDegraded: Bool {
        omittedByLimitCount > 0
            || failedToOpenCount > 0
            || activeDirectoryCount < monitoredDirectoryCount
    }

    nonisolated func binding(forKey key: String) -> DirectoryMonitorBinding? {
        bindings.first { $0.key == key }
    }
}

/// An event forwarded by the controller after its instance-token guard accepted it.
nonisolated struct DirectoryMonitorControllerEvent: Equatable, Sendable {
    let key: String
    let url: URL
    let identity: DirectoryMonitorIdentity
    let instanceToken: DirectoryMonitorInstanceToken
    let flags: Set<DirectoryMonitorEventFlag>

    nonisolated var isTerminal: Bool {
        !flags.isDisjoint(with: DirectoryMonitorEventFlag.terminalFlags)
    }
}

/// Owns the monitors for one watched-folder root and reconciles them against the
/// current planned directory set.
///
/// Contract:
/// - A monitored directory is active only while the identity captured from its
///   open descriptor matches the current authorized path.
/// - Reconciliation compares retained and planned identities even when the path
///   key is unchanged, reopens stale instances and verifies the newly opened
///   descriptor still identifies the current path before installing it.
/// - The cap and root priority come from `DirectoryMonitoringPlan`; no extra
///   per-file watchers are created.
/// - Events from a cancelled or superseded instance are dropped by instance
///   token and counted, so they cannot invalidate a replacement binding.
/// - `stop()` marks the folder lifetime over; late events are dropped.
///
/// Descriptor/path I/O runs synchronously on the calling thread (expected to be
/// an off-MainActor reconciliation task) with the controller lock held; event
/// handlers are invoked outside the lock.
nonisolated final class DirectoryMonitorController: @unchecked Sendable {
    /// A same-key replacement can race the open; verification is bounded rather
    /// than unbounded and a failure is reported as degraded for the next pass.
    nonisolated static let maximumBindingAttempts = 2

    let rootURL: URL
    private let limit: Int
    private let fileSystem: any DirectoryMonitorFileSystem
    private let queue: DispatchQueue
    private let onEvent: @Sendable (DirectoryMonitorControllerEvent) -> Void

    private let lock = NSLock()
    private var monitors: [String: DirectoryMonitor] = [:]
    /// Keys whose active instance was detached (terminal event) or whose stale
    /// descriptor had to be closed. The next successful bind for the key is a
    /// rebound rather than an initial install.
    private var invalidatedKeys: Set<String> = []
    private var isStopped = false
    private var droppedStaleEventCount = 0
    private var terminalEventCount = 0
    private var reconciliationGeneration: UInt64 = 0

    nonisolated init(
        rootURL: URL,
        limit: Int,
        fileSystem: any DirectoryMonitorFileSystem = NativeDirectoryMonitorFileSystem(),
        queue: DispatchQueue = DispatchQueue(label: "AudioMator.DirectoryMonitorController", qos: .utility),
        onEvent: @escaping @Sendable (DirectoryMonitorControllerEvent) -> Void
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.limit = max(1, limit)
        self.fileSystem = fileSystem
        self.queue = queue
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    /// Reconciles the installed descriptors with the current planned set.
    nonisolated func reconcile(directories: [URL]) -> DirectoryMonitorReconciliation {
        let plan = DirectoryMonitoringPlan.make(
            directories: directories,
            rootURL: rootURL,
            limit: limit
        )
        let normalizedDirectories = Self.urlsByKey(plan.monitoredURLs)

        lock.lock()
        defer { lock.unlock() }
        reconciliationGeneration &+= 1
        let generation = reconciliationGeneration

        guard !isStopped else {
            return DirectoryMonitorReconciliation(
                totalDirectoryCount: plan.totalDirectoryCount,
                monitoredDirectoryCount: plan.monitoredURLs.count,
                activeDirectoryCount: 0,
                omittedByLimitCount: plan.omittedByLimitCount,
                failedToOpenCount: 0,
                reboundDirectoryCount: 0,
                closedDirectoryCount: 0,
                droppedStaleEventCount: droppedStaleEventCount,
                terminalEventCount: terminalEventCount,
                reconciliationGeneration: generation,
                needsFollowUpScan: false,
                bindings: []
            )
        }

        var reboundDirectoryCount = 0
        var closedDirectoryCount = 0
        var failedToOpenCount = 0
        var needsFollowUpScan = false

        // Directories that left the plan are closed before new descriptors are
        // opened, so a shrinking set releases its descriptors promptly.
        for key in Array(monitors.keys) where normalizedDirectories[key] == nil {
            monitors[key]?.stop()
            monitors.removeValue(forKey: key)
            invalidatedKeys.remove(key)
            closedDirectoryCount += 1
        }
        for key in Array(invalidatedKeys) where normalizedDirectories[key] == nil {
            invalidatedKeys.remove(key)
        }

        for (key, url) in normalizedDirectories {
            let currentPathIdentity = fileSystem.identity(at: url)
            if let current = monitors[key],
               current.isActive,
               let currentPathIdentity,
               currentPathIdentity == current.identity {
                continue
            }

            let hadExistingMonitor = monitors[key] != nil
            let wasInvalidated = invalidatedKeys.contains(key)
            if let candidate = bindMonitor(url: url, key: key) {
                if let existing = monitors[key] {
                    existing.stop()
                    closedDirectoryCount += 1
                }
                monitors[key] = candidate
                candidate.start()
                invalidatedKeys.remove(key)
                if hadExistingMonitor || wasInvalidated {
                    reboundDirectoryCount += 1
                }
                // A newly installed or rebound descriptor cannot have seen the
                // scan-before-attach interval, so exactly one follow-up scan is
                // required. A scan with unchanged attachments requests none.
                needsFollowUpScan = true
            } else {
                failedToOpenCount += 1
                if let existing = monitors[key] {
                    // Inaccessible or mismatched path: never count an old or
                    // inaccessible descriptor as active.
                    existing.stop()
                    monitors.removeValue(forKey: key)
                    invalidatedKeys.insert(key)
                    closedDirectoryCount += 1
                }
            }
        }

        let bindings = Self.bindings(from: monitors)
        let result = DirectoryMonitorReconciliation(
            totalDirectoryCount: plan.totalDirectoryCount,
            monitoredDirectoryCount: plan.monitoredURLs.count,
            activeDirectoryCount: bindings.count,
            omittedByLimitCount: plan.omittedByLimitCount,
            failedToOpenCount: failedToOpenCount,
            reboundDirectoryCount: reboundDirectoryCount,
            closedDirectoryCount: closedDirectoryCount,
            droppedStaleEventCount: droppedStaleEventCount,
            terminalEventCount: terminalEventCount,
            reconciliationGeneration: generation,
            needsFollowUpScan: needsFollowUpScan,
            bindings: bindings
        )
        return result
    }

    nonisolated func snapshot() -> DirectoryMonitorControllerSnapshot {
        lock.withLock {
            DirectoryMonitorControllerSnapshot(
                bindings: Self.bindings(from: monitors),
                droppedStaleEventCount: droppedStaleEventCount,
                terminalEventCount: terminalEventCount,
                reconciliationGeneration: reconciliationGeneration,
                isStopped: isStopped
            )
        }
    }

    nonisolated func binding(forKey key: String) -> DirectoryMonitorBinding? {
        lock.withLock {
            guard let monitor = monitors[key], monitor.isActive else { return nil }
            return DirectoryMonitorBinding(
                key: key,
                url: monitor.url,
                identity: monitor.identity,
                instanceToken: monitor.instanceToken
            )
        }
    }

    /// Late-callback guard for asynchronous consumers: true only when
    /// `instanceToken` still belongs to the active descriptor for `key`.
    nonisolated func isCurrent(_ instanceToken: DirectoryMonitorInstanceToken, forKey key: String) -> Bool {
        lock.withLock {
            guard let monitor = monitors[key] else { return false }
            return monitor.isActive && monitor.instanceToken == instanceToken
        }
    }

    /// Routes one monitor event through the instance-token guard.
    ///
    /// A terminal accepted event removes the instance: its descriptor has already
    /// closed itself and it can never be the active binding again. Internal so
    /// tests can inject a stale callback without depending on dispatch timing.
    @discardableResult
    nonisolated func receive(_ event: DirectoryMonitorEvent, forKey key: String) -> Bool {
        lock.lock()
        if isStopped {
            droppedStaleEventCount += 1
            lock.unlock()
            return false
        }
        guard let monitor = monitors[key], monitor.instanceToken == event.instanceToken else {
            droppedStaleEventCount += 1
            lock.unlock()
            return false
        }
        if event.isTerminal {
            terminalEventCount += 1
            invalidatedKeys.insert(key)
            monitors.removeValue(forKey: key)
        }
        lock.unlock()

        onEvent(
            DirectoryMonitorControllerEvent(
                key: key,
                url: monitor.url,
                identity: monitor.identity,
                instanceToken: event.instanceToken,
                flags: event.flags
            )
        )
        return true
    }

    /// Ends the folder lifetime. Monitors are stopped and their descriptors
    /// closed; late events are counted and dropped instead of forwarded.
    nonisolated func stop() {
        let monitors: [DirectoryMonitor]
        lock.lock()
        isStopped = true
        monitors = Array(self.monitors.values)
        self.monitors.removeAll()
        invalidatedKeys.removeAll()
        lock.unlock()
        monitors.forEach { $0.stop() }
    }

    private nonisolated func bindMonitor(url: URL, key: String) -> DirectoryMonitor? {
        for _ in 0..<Self.maximumBindingAttempts {
            guard let candidate = DirectoryMonitor(
                url: url,
                fileSystem: fileSystem,
                queue: queue,
                eventHandler: { [weak self] event in
                    self?.receive(event, forKey: key)
                }
            ) else {
                continue
            }

            // The descriptor identity is what the monitor would watch. The path
            // identity is what the authorized path currently names. Installing a
            // descriptor that does not match would recreate AM-07, so a mismatch
            // closes the candidate and retries (bounded).
            guard let pathIdentity = fileSystem.identity(at: url), pathIdentity == candidate.identity else {
                candidate.stop()
                continue
            }
            return candidate
        }
        return nil
    }

    private nonisolated static func bindings(from monitors: [String: DirectoryMonitor]) -> [DirectoryMonitorBinding] {
        monitors.compactMap { key, monitor -> DirectoryMonitorBinding? in
            guard monitor.isActive else { return nil }
            return DirectoryMonitorBinding(
                key: key,
                url: monitor.url,
                identity: monitor.identity,
                instanceToken: monitor.instanceToken
            )
        }
        .sorted { $0.key < $1.key }
    }

    private nonisolated static func urlsByKey(_ urls: [URL]) -> [String: URL] {
        var urlsByKey: [String: URL] = [:]
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            urlsByKey[FileSystemPathSemantics.key(for: standardizedURL)] = standardizedURL
        }
        return urlsByKey
    }
}
