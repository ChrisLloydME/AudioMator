import Foundation

/// Serializes mutations that touch the same normalized file URL.
///
/// A mutation may reserve more than one URL so multi-file operations such as a
/// rename transaction cannot overlap metadata writes to either the source or
/// destination path. Reservations are acquired atomically to avoid deadlocks.
actor FileMutationCoordinator {
    private struct Waiter {
        let keys: Set<String>
        let continuation: CheckedContinuation<Void, Never>
    }

    private var reservedKeys: Set<String> = []
    private var waiters: [Waiter] = []

    func withExclusiveAccess<Value: Sendable>(
        to urls: [URL],
        perform operation: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        let keys = Set(urls.map(Self.normalizedFileKey(for:)))
        await acquire(keys)
        defer { release(keys) }
        return try await operation()
    }

    nonisolated static func normalizedFileKey(for url: URL) -> String {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        return normalizedURL.path.precomposedStringWithCanonicalMapping
    }

    private func acquire(_ keys: Set<String>) async {
        guard !keys.isEmpty else { return }

        if reservedKeys.isDisjoint(with: keys) {
            reservedKeys.formUnion(keys)
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(Waiter(keys: keys, continuation: continuation))
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
            reservedKeys.formUnion(waiter.keys)
            waiter.continuation.resume()
        }
    }
}
