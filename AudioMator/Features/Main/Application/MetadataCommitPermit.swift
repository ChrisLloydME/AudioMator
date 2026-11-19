import Foundation
import os

/// One-file commit admission shared by the MainActor owner and the detached
/// worker.
///
/// The MainActor owner can revoke the permit synchronously while the worker is
/// between its final eligibility check and the synchronous package write. The
/// first transition out of `pending` wins; the critical section holds only
/// state, never file or actor work.
nonisolated final class MetadataCommitPermit: Sendable {
    enum PrecommitRejection: Sendable, Equatable {
        case cancelled
        case ineligible(String)
    }

    enum AdmissionResult: Sendable, Equatable {
        case admitted
        case revoked(PrecommitRejection)
    }

    private enum State {
        case pending
        case admitted
        case revoked(PrecommitRejection)
    }

    private let state = OSAllocatedUnfairLock(initialState: State.pending)

    nonisolated init() {}

    /// The recorded rejection, if a transition out of `pending` already
    /// rejected admission.
    nonisolated var rejection: PrecommitRejection? {
        state.withLock { state in
            guard case .revoked(let rejection) = state else { return nil }
            return rejection
        }
    }

    /// Revokes pending admission. Admission already granted is never revoked:
    /// a commit that crossed the boundary reports its real outcome.
    nonisolated func revoke(reason: PrecommitRejection) {
        state.withLock { state in
            guard case .pending = state else { return }
            state = .revoked(reason)
        }
    }

    /// Admits the commit unless the permit was already revoked. Idempotent for
    /// an already-admitted permit.
    nonisolated func admit() -> AdmissionResult {
        state.withLock { state in
            switch state {
            case .pending:
                state = .admitted
                return .admitted
            case .admitted:
                return .admitted
            case .revoked(let rejection):
                return .revoked(rejection)
            }
        }
    }
}
