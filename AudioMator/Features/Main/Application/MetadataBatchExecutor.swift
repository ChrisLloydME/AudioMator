import Foundation

/// Overlaps independent file transactions without flooding the disk or creating
/// a task for every selected file. The per-file executor still reserves paths.
@MainActor
enum MetadataBatchExecutor {
    static let maximumConcurrentMutations = 4

    static func execute<Result: Sendable>(
        count: Int,
        maximumConcurrentMutations: Int = maximumConcurrentMutations,
        operation: @escaping @MainActor @Sendable (Int) async -> Result,
        onCompletion: @MainActor (Int, Result) -> Void
    ) async {
        guard count > 0 else { return }
        let limit = min(count, max(1, maximumConcurrentMutations))
        await withTaskGroup(of: (Int, Result).self) { group in
            var nextIndex = limit
            for index in 0..<limit {
                group.addTask {
                    (index, await operation(index))
                }
            }
            while let (index, result) = await group.next() {
                onCompletion(index, result)
                if nextIndex < count {
                    let next = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (next, await operation(next))
                    }
                }
            }
        }
    }
}
