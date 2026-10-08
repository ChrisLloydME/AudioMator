import XCTest
@testable import AudioMatorCoreLogic

final class AsyncOperationDeadlineTests: XCTestCase {
    func testReturnsSuccessfulSendableValue() async throws {
        let result = try await withAsyncTimeout(.seconds(5), operationName: "Success") {
            ["title", "artist"]
        }
        XCTAssertEqual(result, ["title", "artist"])
    }

    func testPreservesOperationError() async {
        do {
            let _: Int = try await withAsyncTimeout(.seconds(5), operationName: "Failure") {
                throw OperationError.failed
            }
            XCTFail("Expected the operation error")
        } catch {
            XCTAssertEqual(error as? OperationError, .failed)
        }
    }

    func testTimeoutReturnsBeforeUncooperativeOperationFinishes() async {
        let release = DeadlineTestSignal()
        let finished = DeadlineTestSignal()

        do {
            let _: Int = try await withAsyncTimeout(.milliseconds(50), operationName: "Blocked") {
                await release.wait()
                await finished.signal()
                return 42
            }
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(
                error as? AsyncOperationTimedOutError,
                AsyncOperationTimedOutError(operationName: "Blocked")
            )
        }

        // Allow the losing operation to return after the continuation was resumed.
        await release.signal()
        await finished.wait()
    }

    func testCancellationReturnsBeforeUncooperativeOperationFinishes() async {
        let started = DeadlineTestSignal()
        let release = DeadlineTestSignal()
        let finished = DeadlineTestSignal()
        let task = Task.detached {
            try await withAsyncTimeout(.seconds(5), operationName: "Cancelled") {
                await started.signal()
                await release.wait()
                await finished.signal()
                return 42
            }
        }
        await started.wait()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        await release.signal()
        await finished.wait()
    }
}

private enum OperationError: Error {
    case failed
}

private actor DeadlineTestSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
