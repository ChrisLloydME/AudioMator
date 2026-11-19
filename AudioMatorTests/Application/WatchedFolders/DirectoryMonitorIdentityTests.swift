import Darwin
import Foundation
import XCTest
@testable import AudioMator

#if os(macOS)
/// OS-backed identity tests for the F4 directory-monitor layer (AM-07).
///
/// These tests use disposable temporary directories and the real native
/// descriptor adapter unless a test explicitly wraps it to inject a failure or
/// count balanced closes. Identity/status assertions are synchronous and
/// independent of dispatch timing; only genuine event-delivery tests wait, and
/// every wait has an explicit bound.
@MainActor
final class DirectoryMonitorIdentityTests: XCTestCase {
    // MARK: - Identity capture

    func testReconciliationCapturesDescriptorDeviceInodeAndDirectoryKind() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let controller = DirectoryMonitorController(
            rootURL: fixture.rootURL,
            limit: 8,
            onEvent: { _ in }
        )
        defer { controller.stop() }

        let result = controller.reconcile(directories: [fixture.watchedURL])

        XCTAssertEqual(result.totalDirectoryCount, 2)
        XCTAssertEqual(result.monitoredDirectoryCount, 2)
        XCTAssertEqual(result.activeDirectoryCount, 2)
        XCTAssertEqual(result.failedToOpenCount, 0)
        XCTAssertEqual(result.omittedByLimitCount, 0)
        XCTAssertTrue(result.needsFollowUpScan)
        XCTAssertFalse(result.isDegraded)

        let watchedBinding = try XCTUnwrap(result.binding(forKey: fixture.watchedKey))
        let pathIdentity = try XCTUnwrap(NativeDirectoryMonitorFileSystem().identity(at: fixture.watchedURL))
        XCTAssertEqual(watchedBinding.identity, pathIdentity)
        XCTAssertEqual(watchedBinding.identity.kind, .directory)
        XCTAssertNotEqual(watchedBinding.identity.inode, 0)

        let rootBinding = try XCTUnwrap(result.binding(forKey: fixture.rootKey))
        XCTAssertEqual(rootBinding.identity, pathIdentityFor(fixture.rootURL))
        XCTAssertNotEqual(watchedBinding.instanceToken, rootBinding.instanceToken)
    }

    func testDescriptorIdentityReportsDirectoryAndNonDirectoryKinds() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let fileURL = fixture.watchedURL.appendingPathComponent("plain.txt")
        try Data("not a directory".utf8).write(to: fileURL)

        let fileSystem = NativeDirectoryMonitorFileSystem()
        let directoryIdentity = try XCTUnwrap(fileSystem.identity(at: fixture.watchedURL))
        XCTAssertEqual(directoryIdentity.kind, .directory)
        XCTAssertTrue(directoryIdentity.isDirectory)

        let fileIdentity = try XCTUnwrap(fileSystem.identity(at: fileURL))
        XCTAssertEqual(fileIdentity.kind, .regularFile)
        XCTAssertFalse(fileIdentity.isDirectory)
    }

    func testMonitorRejectsNonDirectoryDescriptor() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let fileURL = fixture.watchedURL.appendingPathComponent("plain.txt")
        try Data("not a directory".utf8).write(to: fileURL)

        let monitor = DirectoryMonitor(
            url: fileURL,
            eventHandler: { _ in }
        )
        XCTAssertNil(monitor)
    }

    // MARK: - Same-key replacement (OS-backed rebinding)

    func testSameKeyDirectoryReplacementRebindsAndStaleInstanceCannotInvalidate() async throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let recorder = DirectoryMonitorEventRecorder()
        let controller = DirectoryMonitorController(
            rootURL: fixture.rootURL,
            limit: 8,
            onEvent: { event in recorder.record(event) }
        )
        defer { controller.stop() }

        try Data("original".utf8).write(to: fixture.watchedURL.appendingPathComponent("original.txt"))
        let initial = controller.reconcile(directories: [fixture.watchedURL])
        XCTAssertEqual(initial.activeDirectoryCount, 2)
        XCTAssertFalse(initial.isDegraded)
        let originalBinding = try XCTUnwrap(initial.binding(forKey: fixture.watchedKey))

        // Readiness barrier: a real directory-entry event must be observed before
        // the replacement scenario relies on later event delivery.
        try Data("ready".utf8).write(to: fixture.watchedURL.appendingPathComponent("ready.txt"))
        let sawReadyEvent = await waitUntil {
            !recorder.events(forKey: fixture.watchedKey).isEmpty
        }
        XCTAssertTrue(sawReadyEvent, "monitor delivered no readiness event")
        await settle(for: .milliseconds(100))
        recorder.reset()

        // Rename the monitored child away and recreate the same pathname before
        // any rescan. The replacement gets a uniquely named entry that the old
        // descriptor can never observe.
        let movedURL = fixture.rootURL.appendingPathComponent("MovedAway", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.watchedURL, to: movedURL)
        try FileManager.default.createDirectory(at: fixture.watchedURL, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(
            to: fixture.watchedURL.appendingPathComponent("replacement-only.wav")
        )

        let sawTerminalEvent = await waitUntil {
            recorder.events(forKey: fixture.watchedKey).contains {
                $0.instanceToken == originalBinding.instanceToken && $0.isTerminal
            }
        }
        XCTAssertTrue(sawTerminalEvent, "detached instance reported no terminal event")
        let terminalEvents = recorder.events(forKey: fixture.watchedKey).filter {
            $0.instanceToken == originalBinding.instanceToken && $0.isTerminal
        }
        XCTAssertEqual(terminalEvents.count, 1)
        XCTAssertTrue(terminalEvents[0].flags.contains(.rename))

        // The original watcher no longer satisfies the authorized entry: it is
        // not the active binding, its token is not current and the captured
        // identity no longer matches the pathname.
        XCTAssertNil(controller.binding(forKey: fixture.watchedKey))
        XCTAssertFalse(controller.isCurrent(originalBinding.instanceToken, forKey: fixture.watchedKey))
        let replacementIdentity = try XCTUnwrap(
            NativeDirectoryMonitorFileSystem().identity(at: fixture.watchedURL)
        )
        XCTAssertEqual(replacementIdentity.kind, .directory)
        XCTAssertNotEqual(originalBinding.identity, replacementIdentity)

        // Its descriptor still follows the moved-away inode, but the controller
        // treats the instance as detached and never accepts further events.
        let eventsForOriginalBefore = recorder.events(forKey: fixture.watchedKey).filter {
            $0.instanceToken == originalBinding.instanceToken
        }
        try Data("elsewhere".utf8).write(to: movedURL.appendingPathComponent("moved-inode-entry.wav"))
        await settle(for: .milliseconds(300))
        let eventsForOriginalAfter = recorder.events(forKey: fixture.watchedKey).filter {
            $0.instanceToken == originalBinding.instanceToken
        }
        XCTAssertEqual(eventsForOriginalAfter.count, eventsForOriginalBefore.count)

        // Reconciling the unchanged path key must compare identities, open a
        // fresh real descriptor and verify it against the current path.
        let rebound = controller.reconcile(directories: [fixture.watchedURL])
        XCTAssertEqual(rebound.activeDirectoryCount, 2)
        XCTAssertEqual(rebound.reboundDirectoryCount, 1)
        XCTAssertEqual(rebound.failedToOpenCount, 0)
        XCTAssertEqual(rebound.omittedByLimitCount, 0)
        XCTAssertTrue(rebound.needsFollowUpScan)
        XCTAssertFalse(rebound.isDegraded)
        let reboundBinding = try XCTUnwrap(rebound.binding(forKey: fixture.watchedKey))
        XCTAssertNotEqual(reboundBinding.instanceToken, originalBinding.instanceToken)
        XCTAssertEqual(reboundBinding.identity, replacementIdentity)

        // A late callback from the superseded instance cannot invalidate the
        // replacement binding or change the current status.
        let staleEvent = DirectoryMonitorEvent(
            instanceToken: originalBinding.instanceToken,
            identity: originalBinding.identity,
            flags: [.write]
        )
        XCTAssertFalse(controller.receive(staleEvent, forKey: fixture.watchedKey))
        XCTAssertEqual(controller.snapshot().droppedStaleEventCount, 1)
        XCTAssertEqual(
            controller.binding(forKey: fixture.watchedKey)?.instanceToken,
            reboundBinding.instanceToken
        )
        XCTAssertFalse(controller.isCurrent(originalBinding.instanceToken, forKey: fixture.watchedKey))
        XCTAssertTrue(controller.isCurrent(reboundBinding.instanceToken, forKey: fixture.watchedKey))

        // The rebound real descriptor observes new entries in the replacement.
        try Data("rebound".utf8).write(to: fixture.watchedURL.appendingPathComponent("rebound-observed.wav"))
        let sawReboundEvent = await waitUntil {
            recorder.events(forKey: fixture.watchedKey).contains {
                $0.instanceToken == reboundBinding.instanceToken && !$0.isTerminal
            }
        }
        XCTAssertTrue(sawReboundEvent, "rebound descriptor did not observe the replacement directory")
    }

    func testSameKeyRootReplacementRebindsRootDescriptor() async throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorRootReplacement-\(UUID().uuidString)", isDirectory: true)
        let rootURL = baseURL.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let recorder = DirectoryMonitorEventRecorder()
        let controller = DirectoryMonitorController(
            rootURL: rootURL,
            limit: 4,
            onEvent: { event in recorder.record(event) }
        )
        defer { controller.stop() }

        let rootKey = FileSystemPathSemantics.key(for: rootURL.standardizedFileURL)
        let initial = controller.reconcile(directories: [])
        XCTAssertEqual(initial.activeDirectoryCount, 1)
        let firstBinding = try XCTUnwrap(initial.binding(forKey: rootKey))

        try Data("ready".utf8).write(to: rootURL.appendingPathComponent("ready.txt"))
        let sawReadyEvent = await waitUntil { !recorder.events(forKey: rootKey).isEmpty }
        XCTAssertTrue(sawReadyEvent, "root monitor delivered no readiness event")
        await settle(for: .milliseconds(100))
        recorder.reset()

        let movedURL = baseURL.appendingPathComponent("LibraryMoved", isDirectory: true)
        try FileManager.default.moveItem(at: rootURL, to: movedURL)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)

        let sawTerminalEvent = await waitUntil {
            recorder.events(forKey: rootKey).contains {
                $0.instanceToken == firstBinding.instanceToken && $0.isTerminal
            }
        }
        XCTAssertTrue(sawTerminalEvent, "root instance reported no terminal event")
        XCTAssertNil(controller.binding(forKey: rootKey))

        let second = controller.reconcile(directories: [])
        XCTAssertEqual(second.activeDirectoryCount, 1)
        XCTAssertEqual(second.reboundDirectoryCount, 1)
        XCTAssertTrue(second.needsFollowUpScan)
        let secondBinding = try XCTUnwrap(second.binding(forKey: rootKey))
        XCTAssertNotEqual(secondBinding.instanceToken, firstBinding.instanceToken)
        XCTAssertEqual(
            secondBinding.identity,
            try XCTUnwrap(NativeDirectoryMonitorFileSystem().identity(at: rootURL))
        )
        XCTAssertNotEqual(firstBinding.identity, secondBinding.identity)

        try Data("new".utf8).write(to: rootURL.appendingPathComponent("root-rebound-entry.wav"))
        let sawReboundEvent = await waitUntil {
            recorder.events(forKey: rootKey).contains {
                $0.instanceToken == secondBinding.instanceToken && !$0.isTerminal
            }
        }
        XCTAssertTrue(sawReboundEvent, "rebound root descriptor did not observe the replacement")
    }

    // MARK: - Reconciliation identity/status (timing-independent)

    func testUnchangedAttachmentsKeepInstanceTokensAndRequestNoFollowUpScan() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let controller = DirectoryMonitorController(rootURL: fixture.rootURL, limit: 8, onEvent: { _ in })
        defer { controller.stop() }

        let first = controller.reconcile(directories: [fixture.watchedURL])
        XCTAssertTrue(first.needsFollowUpScan)
        let second = controller.reconcile(directories: [fixture.watchedURL])

        XCTAssertEqual(second.reconciliationGeneration, first.reconciliationGeneration &+ 1)
        XCTAssertEqual(controller.snapshot().reconciliationGeneration, second.reconciliationGeneration)
        XCTAssertEqual(second.activeDirectoryCount, 2)
        XCTAssertEqual(second.reboundDirectoryCount, 0)
        XCTAssertEqual(second.closedDirectoryCount, 0)
        XCTAssertEqual(second.failedToOpenCount, 0)
        XCTAssertFalse(second.needsFollowUpScan)
        XCTAssertFalse(second.isDegraded)
        XCTAssertEqual(
            second.bindings.map(\.instanceToken),
            first.bindings.map(\.instanceToken)
        )

        // A scan with unchanged attachments schedules no follow-up scan.
        XCTAssertEqual(controller.snapshot().bindings.map(\.instanceToken), first.bindings.map(\.instanceToken))
    }

    func testMissingRootIsReportedDegradedWithoutActiveDescriptor() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorMissing-\(UUID().uuidString)", isDirectory: true)
        let controller = DirectoryMonitorController(rootURL: missingURL, limit: 8, onEvent: { _ in })
        defer { controller.stop() }

        let result = controller.reconcile(directories: [])

        XCTAssertEqual(result.totalDirectoryCount, 1)
        XCTAssertEqual(result.monitoredDirectoryCount, 1)
        XCTAssertEqual(result.activeDirectoryCount, 0)
        XCTAssertEqual(result.failedToOpenCount, 1)
        XCTAssertEqual(result.identityMismatchCount, 0)
        XCTAssertEqual(result.omittedByLimitCount, 0)
        XCTAssertTrue(result.bindings.isEmpty)
        XCTAssertTrue(result.isDegraded)
    }

    func testDescriptorIdentityMismatchIsRejectedAndCandidateDescriptorsAreClosed() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let fileSystem = InstrumentedDirectoryMonitorFileSystem(
            descriptorIdentityTransform: { identity in
                DirectoryMonitorIdentity(
                    device: identity.device,
                    inode: identity.inode &+ 1,
                    kind: identity.kind
                )
            }
        )
        let controller = DirectoryMonitorController(
            rootURL: fixture.watchedURL,
            limit: 1,
            fileSystem: fileSystem,
            onEvent: { _ in }
        )
        defer { controller.stop() }

        let result = controller.reconcile(directories: [])

        XCTAssertEqual(result.activeDirectoryCount, 0)
        XCTAssertEqual(result.failedToOpenCount, 0)
        XCTAssertEqual(result.identityMismatchCount, 1)
        XCTAssertTrue(result.isDegraded)
        XCTAssertTrue(result.bindings.isEmpty)
        XCTAssertEqual(fileSystem.openAttempts, DirectoryMonitorController.maximumBindingAttempts)
        XCTAssertEqual(fileSystem.closedDescriptors, DirectoryMonitorController.maximumBindingAttempts)
    }

    func testCapOmissionAndRootPriorityAreReportedDegraded() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let nestedURLs = try (0..<4).map { index in
            let url = fixture.rootURL.appendingPathComponent("nested-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let limited = DirectoryMonitorController(
            rootURL: fixture.rootURL,
            limit: 2,
            onEvent: { _ in }
        )
        defer { limited.stop() }
        let limitedResult = limited.reconcile(directories: nestedURLs)

        XCTAssertEqual(limitedResult.totalDirectoryCount, 5)
        XCTAssertEqual(limitedResult.monitoredDirectoryCount, 2)
        XCTAssertEqual(limitedResult.omittedByLimitCount, 3)
        XCTAssertEqual(limitedResult.activeDirectoryCount, 2)
        XCTAssertTrue(limitedResult.isDegraded)
        let limitedKeys = Set(limitedResult.bindings.map(\.key))
        XCTAssertTrue(limitedKeys.contains(fixture.rootKey))
        XCTAssertEqual(limitedResult.bindings.first?.key, fixture.rootKey)
        let omittedNestedKey = FileSystemPathSemantics.key(
            for: nestedURLs[3].standardizedFileURL
        )
        XCTAssertFalse(limitedKeys.contains(omittedNestedKey))

        let expanded = DirectoryMonitorController(
            rootURL: fixture.rootURL,
            limit: 8,
            onEvent: { _ in }
        )
        defer { expanded.stop() }
        let expandedResult = expanded.reconcile(directories: nestedURLs)

        XCTAssertEqual(expandedResult.monitoredDirectoryCount, 5)
        XCTAssertEqual(expandedResult.activeDirectoryCount, 5)
        XCTAssertEqual(expandedResult.omittedByLimitCount, 0)
        XCTAssertEqual(expandedResult.failedToOpenCount, 0)
        XCTAssertFalse(expandedResult.isDegraded)
        XCTAssertTrue(expandedResult.bindings.map(\.key).contains(fixture.rootKey))
        XCTAssertTrue(expandedResult.bindings.map(\.key).contains(omittedNestedKey))
    }

    func testDirectoryLeavingPlanClosesDescriptorAndReappearanceUsesFreshInstance() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let nestedAURL = fixture.rootURL.appendingPathComponent("NestedA", isDirectory: true)
        let nestedBURL = fixture.rootURL.appendingPathComponent("NestedB", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedBURL, withIntermediateDirectories: true)
        let nestedAKey = FileSystemPathSemantics.key(for: nestedAURL.standardizedFileURL)
        let controller = DirectoryMonitorController(rootURL: fixture.rootURL, limit: 8, onEvent: { _ in })
        defer { controller.stop() }

        let full = controller.reconcile(directories: [fixture.watchedURL, nestedAURL, nestedBURL])
        XCTAssertEqual(full.activeDirectoryCount, 4)
        let previousNestedABinding = try XCTUnwrap(full.binding(forKey: nestedAKey))

        let withoutNestedA = controller.reconcile(directories: [fixture.watchedURL, nestedBURL])
        XCTAssertEqual(withoutNestedA.activeDirectoryCount, 3)
        XCTAssertEqual(withoutNestedA.closedDirectoryCount, 1)
        XCTAssertNil(withoutNestedA.binding(forKey: nestedAKey))
        XCTAssertNil(controller.binding(forKey: nestedAKey))

        let reappeared = controller.reconcile(directories: [fixture.watchedURL, nestedAURL, nestedBURL])
        XCTAssertEqual(reappeared.activeDirectoryCount, 4)
        XCTAssertTrue(reappeared.needsFollowUpScan)
        let reboundNestedABinding = try XCTUnwrap(reappeared.binding(forKey: nestedAKey))
        XCTAssertNotEqual(reboundNestedABinding.instanceToken, previousNestedABinding.instanceToken)
        XCTAssertEqual(
            reboundNestedABinding.identity,
            try XCTUnwrap(NativeDirectoryMonitorFileSystem().identity(at: nestedAURL))
        )

        // A callback queued for the removed instance cannot act on the reappeared one.
        let staleEvent = DirectoryMonitorEvent(
            instanceToken: previousNestedABinding.instanceToken,
            identity: previousNestedABinding.identity,
            flags: [.write]
        )
        XCTAssertFalse(controller.receive(staleEvent, forKey: nestedAKey))
        XCTAssertEqual(
            controller.binding(forKey: nestedAKey)?.instanceToken,
            reboundNestedABinding.instanceToken
        )
    }

    func testStoppedFolderLifetimeDropsLateEventsAndReportsNoActiveDirectories() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let controller = DirectoryMonitorController(rootURL: fixture.rootURL, limit: 8, onEvent: { _ in })

        let result = controller.reconcile(directories: [fixture.watchedURL])
        let binding = try XCTUnwrap(result.binding(forKey: fixture.watchedKey))

        controller.stop()
        let lateEvent = DirectoryMonitorEvent(
            instanceToken: binding.instanceToken,
            identity: binding.identity,
            flags: [.write]
        )
        XCTAssertFalse(controller.receive(lateEvent, forKey: fixture.watchedKey))

        let snapshot = controller.snapshot()
        XCTAssertTrue(snapshot.isStopped)
        XCTAssertTrue(snapshot.bindings.isEmpty)
        XCTAssertEqual(snapshot.droppedStaleEventCount, 1)

        let afterStop = controller.reconcile(directories: [fixture.watchedURL])
        XCTAssertEqual(afterStop.activeDirectoryCount, 0)
        XCTAssertTrue(afterStop.bindings.isEmpty)
    }

    // MARK: - Terminal events

    func testTerminalEventClosesInstanceAndStopsDeliveringEvents() async throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let fileSystem = InstrumentedDirectoryMonitorFileSystem()
        let sink = DirectoryMonitorEventSink()
        let queue = DispatchQueue(label: "AudioMatorTests.DirectoryMonitor.\(UUID().uuidString)")
        let monitor = try XCTUnwrap(
            DirectoryMonitor(
                url: fixture.watchedURL,
                fileSystem: fileSystem,
                queue: queue,
                eventHandler: { event in sink.record(event) }
            )
        )
        XCTAssertEqual(monitor.currentState, .ready)
        XCTAssertFalse(monitor.isActive)

        monitor.start()
        XCTAssertTrue(monitor.isActive)
        XCTAssertEqual(
            monitor.identity,
            try XCTUnwrap(NativeDirectoryMonitorFileSystem().identity(at: fixture.watchedURL))
        )

        try Data("ready".utf8).write(to: fixture.watchedURL.appendingPathComponent("ready.txt"))
        let sawReadyEvent = await waitUntil { !sink.events.isEmpty }
        XCTAssertTrue(sawReadyEvent, "monitor delivered no readiness event")
        await settle(for: .milliseconds(100))
        sink.reset()

        let movedURL = fixture.rootURL.appendingPathComponent("TerminalMoved", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.watchedURL, to: movedURL)

        let sawTerminalEvent = await waitUntil { sink.events.contains(where: \.isTerminal) }
        XCTAssertTrue(sawTerminalEvent, "monitor delivered no terminal event")
        let terminalEvent = try XCTUnwrap(sink.events.first(where: \.isTerminal))
        XCTAssertTrue(terminalEvent.flags.contains(.rename))
        XCTAssertEqual(terminalEvent.instanceToken, monitor.instanceToken)
        XCTAssertEqual(terminalEvent.identity, monitor.identity)
        XCTAssertEqual(monitor.currentState, .terminal(flags: terminalEvent.flags))
        XCTAssertFalse(monitor.isActive)
        XCTAssertTrue(monitor.isTerminal)

        let closedOnce = await waitUntil { fileSystem.closedDescriptors == 1 }
        XCTAssertTrue(closedOnce, "terminal instance did not close its descriptor")

        // No further events are delivered from the terminal instance.
        let eventCountAfterTerminal = sink.events.count
        try Data("after".utf8).write(to: movedURL.appendingPathComponent("after-terminal.txt"))
        await settle(for: .milliseconds(300))
        XCTAssertEqual(sink.events.count, eventCountAfterTerminal)
        XCTAssertEqual(fileSystem.closedDescriptors, 1)
        monitor.stop()
    }

    // MARK: - Cancellation and balanced close

    func testStopClosesDescriptorExactlyOnce() async throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let fileSystem = InstrumentedDirectoryMonitorFileSystem()
        let queue = DispatchQueue(label: "AudioMatorTests.DirectoryMonitorStop.\(UUID().uuidString)")
        let monitor = try XCTUnwrap(
            DirectoryMonitor(
                url: fixture.watchedURL,
                fileSystem: fileSystem,
                queue: queue,
                eventHandler: { _ in }
            )
        )
        XCTAssertEqual(fileSystem.closedDescriptors, 0)

        monitor.start()
        XCTAssertTrue(monitor.isActive)
        monitor.stop()
        XCTAssertEqual(monitor.currentState, .stopped)

        let closedOnce = await waitUntil { fileSystem.closedDescriptors == 1 }
        XCTAssertTrue(closedOnce, "stopped monitor did not close its descriptor")
        monitor.stop()
        await settle(for: .milliseconds(100))
        XCTAssertEqual(fileSystem.closedDescriptors, 1)
    }

    func testStopBeforeStartClosesDescriptorSynchronously() throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let fileSystem = InstrumentedDirectoryMonitorFileSystem()
        let queue = DispatchQueue(label: "AudioMatorTests.DirectoryMonitorNeverStarted.\(UUID().uuidString)")
        let monitor = try XCTUnwrap(
            DirectoryMonitor(
                url: fixture.watchedURL,
                fileSystem: fileSystem,
                queue: queue,
                eventHandler: { _ in }
            )
        )
        XCTAssertEqual(fileSystem.closedDescriptors, 0)

        monitor.stop()
        XCTAssertEqual(monitor.currentState, .stopped)
        XCTAssertEqual(fileSystem.closedDescriptors, 1)
        monitor.stop()
        XCTAssertEqual(fileSystem.closedDescriptors, 1)
    }

    // MARK: - Platform limitation controls

    func testDirectoryDescriptorReportsEntryCreationButNotInPlaceFileWrites() async throws {
        let fixture = try DirectoryMonitorFixture()
        defer { fixture.cleanup() }
        let sink = DirectoryMonitorEventSink()
        let queue = DispatchQueue(label: "AudioMatorTests.DirectoryMonitorLimits.\(UUID().uuidString)")
        let monitor = try XCTUnwrap(
            DirectoryMonitor(
                url: fixture.watchedURL,
                queue: queue,
                eventHandler: { event in sink.record(event) }
            )
        )
        defer { monitor.stop() }
        monitor.start()

        // Positive control: creating a directory entry is reported.
        let existingURL = fixture.watchedURL.appendingPathComponent("track.bin")
        try Data("before".utf8).write(to: existingURL)
        let sawCreationEvent = await waitUntil { !sink.events.isEmpty }
        XCTAssertTrue(sawCreationEvent, "directory descriptor did not report entry creation")
        await settle(for: .milliseconds(100))
        sink.reset()

        // Documented platform limitation: an in-place content write to an
        // already indexed file is not a directory-entry event. The directory-only
        // mechanism therefore keeps the selected-file activation refresh.
        let handle = try FileHandle(forWritingTo: existingURL)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data("after!".utf8))
        try handle.close()

        await settle(for: .milliseconds(400))
        XCTAssertTrue(
            sink.events.isEmpty,
            "unexpected directory event for an in-place write; the documented limitation changed"
        )
        XCTAssertTrue(monitor.isActive)
    }

    // MARK: - Helpers

    private func pathIdentityFor(_ url: URL) -> DirectoryMonitorIdentity? {
        NativeDirectoryMonitorFileSystem().identity(at: url)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func settle(for duration: Duration = .milliseconds(300)) async {
        try? await Task.sleep(for: duration)
    }
}

// MARK: - Fixtures

private struct DirectoryMonitorFixture {
    let rootURL: URL
    let watchedURL: URL

    init() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMatorDirectoryMonitorIdentity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let watchedURL = baseURL.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedURL, withIntermediateDirectories: true)
        self.rootURL = baseURL
        self.watchedURL = watchedURL
    }

    var rootKey: String {
        FileSystemPathSemantics.key(for: rootURL.standardizedFileURL)
    }

    var watchedKey: String {
        FileSystemPathSemantics.key(for: watchedURL.standardizedFileURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

/// Wraps the native adapter so tests can count balanced opens/closes and inject
/// a descriptor identity that no longer matches the path.
private nonisolated final class InstrumentedDirectoryMonitorFileSystem: DirectoryMonitorFileSystem, @unchecked Sendable {
    private let base: any DirectoryMonitorFileSystem
    private let descriptorIdentityTransform: (@Sendable (DirectoryMonitorIdentity) -> DirectoryMonitorIdentity)?
    private let lock = NSLock()
    private var openAttemptCount = 0
    private var closedDescriptorCount = 0

    nonisolated init(
        base: any DirectoryMonitorFileSystem = NativeDirectoryMonitorFileSystem(),
        descriptorIdentityTransform: (@Sendable (DirectoryMonitorIdentity) -> DirectoryMonitorIdentity)? = nil
    ) {
        self.base = base
        self.descriptorIdentityTransform = descriptorIdentityTransform
    }

    nonisolated var openAttempts: Int {
        lock.withLock { openAttemptCount }
    }

    nonisolated var closedDescriptors: Int {
        lock.withLock { closedDescriptorCount }
    }

    nonisolated func openDirectoryDescriptor(at url: URL) -> CInt {
        lock.withLock { openAttemptCount += 1 }
        return base.openDirectoryDescriptor(at: url)
    }

    nonisolated func identity(ofDescriptor descriptor: CInt) -> DirectoryMonitorIdentity? {
        guard let identity = base.identity(ofDescriptor: descriptor) else { return nil }
        return descriptorIdentityTransform?(identity) ?? identity
    }

    nonisolated func identity(at url: URL) -> DirectoryMonitorIdentity? {
        base.identity(at: url)
    }

    nonisolated func closeDescriptor(_ descriptor: CInt) {
        lock.withLock { closedDescriptorCount += 1 }
        base.closeDescriptor(descriptor)
    }
}

/// Thread-safe event recorder for controller-level tests.
private nonisolated final class DirectoryMonitorEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DirectoryMonitorControllerEvent] = []

    nonisolated func record(_ event: DirectoryMonitorControllerEvent) {
        lock.withLock { storage.append(event) }
    }

    nonisolated var events: [DirectoryMonitorControllerEvent] {
        lock.withLock { storage }
    }

    nonisolated func events(forKey key: String) -> [DirectoryMonitorControllerEvent] {
        lock.withLock { storage.filter { $0.key == key } }
    }

    nonisolated func reset() {
        lock.withLock { storage.removeAll() }
    }
}

/// Thread-safe event recorder for direct monitor tests.
private nonisolated final class DirectoryMonitorEventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DirectoryMonitorEvent] = []

    nonisolated func record(_ event: DirectoryMonitorEvent) {
        lock.withLock { storage.append(event) }
    }

    nonisolated var events: [DirectoryMonitorEvent] {
        lock.withLock { storage }
    }

    nonisolated func reset() {
        lock.withLock { storage.removeAll() }
    }
}
#endif
