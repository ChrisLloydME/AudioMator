import Foundation

/// Serializes mutations that touch the same normalized file URL.
///
/// A mutation may reserve more than one URL so multi-file operations such as a
/// rename transaction cannot overlap metadata writes to either the source or
/// destination path. Reservations are acquired atomically to avoid deadlocks.
actor FileMutationCoordinator {
    private struct Waiter {
        let id: UUID
        let keys: Set<String>
        let continuation: CheckedContinuation<Void, Error>
    }

    private var reservedKeys: Set<String> = []
    private var waiters: [Waiter] = []
    private var pendingWaiterIDs: Set<UUID> = []
    private var cancelledWaiterIDs: Set<UUID> = []

    var queuedMutationCount: Int {
        pendingWaiterIDs.count
    }

    func withExclusiveAccess<Value: Sendable>(
        to urls: [URL],
        perform operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let keys = Set(urls.map(Self.normalizedFileKey(for:)))
        try await acquire(keys)
        defer { release(keys) }
        try Task.checkCancellation()
        return try await operation()
    }

    nonisolated static func normalizedFileKey(for url: URL) -> String {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        return normalizedURL.path.precomposedStringWithCanonicalMapping
    }

    private func acquire(_ keys: Set<String>) async throws {
        guard !keys.isEmpty else { return }
        try Task.checkCancellation()

        if reservedKeys.isDisjoint(with: keys) {
            reservedKeys.formUnion(keys)
            return
        }

        let waiterID = UUID()
        pendingWaiterIDs.insert(waiterID)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueueWaiter(
                    Waiter(id: waiterID, keys: keys, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
    }

    private func enqueueWaiter(_ waiter: Waiter) {
        if cancelledWaiterIDs.remove(waiter.id) != nil {
            pendingWaiterIDs.remove(waiter.id)
            waiter.continuation.resume(throwing: CancellationError())
            return
        }

        if reservedKeys.isDisjoint(with: waiter.keys) {
            pendingWaiterIDs.remove(waiter.id)
            reservedKeys.formUnion(waiter.keys)
            waiter.continuation.resume()
            return
        }

        waiters.append(waiter)
    }

    private func cancelWaiter(id: UUID) {
        guard pendingWaiterIDs.contains(id) else { return }

        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            pendingWaiterIDs.remove(id)
            waiter.continuation.resume(throwing: CancellationError())
        } else {
            cancelledWaiterIDs.insert(id)
        }
    }

    private func release(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        reservedKeys.subtract(keys)

        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            guard reservedKeys.isDisjoint(with: waiter.keys) else {
                index += 1
                continue
            }

            waiters.remove(at: index)
            pendingWaiterIDs.remove(waiter.id)
            reservedKeys.formUnion(waiter.keys)
            waiter.continuation.resume()
        }
    }
}
