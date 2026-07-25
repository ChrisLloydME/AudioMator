import Foundation

struct AsyncOperationTimedOutError: LocalizedError, Equatable, Sendable {
    let operationName: String

    var errorDescription: String? {
        "\(operationName) timed out. Please try again."
    }
}

/// Waits for an asynchronous operation without requiring that operation to cooperate
/// with cancellation. Once the first terminal outcome wins, later outcomes are ignored.
nonisolated func withAsyncTimeout<Value: Sendable>(
    _ timeout: Duration,
    operationName: String,
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let completion = AsyncOperationCompletion<Value>()
    let operationTask = Task.detached(priority: priority) {
        do {
            completion.resolve(.success(try await operation()))
        } catch {
            completion.resolve(.failure(error))
        }
    }
    let timeoutTask = Task.detached {
        do {
            try await Task.sleep(for: timeout)
            completion.resolve(
                .failure(AsyncOperationTimedOutError(operationName: operationName))
            )
        } catch {
            // The operation completed or the caller cancelled before the deadline.
        }
    }

    return try await withTaskCancellationHandler {
        defer {
            operationTask.cancel()
            timeoutTask.cancel()
        }
        return try await completion.value()
    } onCancel: {
        completion.resolve(.failure(CancellationError()))
        operationTask.cancel()
        timeoutTask.cancel()
    }
}

private nonisolated final class AsyncOperationCompletion<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var resolvedResult: Result<Value, Error>?

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let result = lock.withLock { () -> Result<Value, Error>? in
                if let resolvedResult {
                    return resolvedResult
                }
                self.continuation = continuation
                return nil
            }

            if let result {
                continuation.resume(with: result)
            }
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Value, Error>? in
            guard resolvedResult == nil else { return nil }
            resolvedResult = result
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
