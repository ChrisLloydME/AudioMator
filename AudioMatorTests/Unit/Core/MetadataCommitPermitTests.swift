import Foundation
import XCTest
@testable import AudioMator

nonisolated final class MetadataCommitPermitTests: XCTestCase {
    func testFirstTransitionOutOfPendingWins() {
        let permit = MetadataCommitPermit()
        XCTAssertNil(permit.rejection)

        XCTAssertEqual(permit.admit(), .admitted)
        XCTAssertNil(permit.rejection)

        // Admission already granted is never revoked: the real commit outcome is
        // reported even when cancellation arrives afterwards.
        permit.revoke(reason: .cancelled)
        XCTAssertNil(permit.rejection)
        XCTAssertEqual(permit.admit(), .admitted)
    }

    func testRevokedPermitReturnsRecordedRejectionAndNeverAdmits() {
        let cancelledPermit = MetadataCommitPermit()
        cancelledPermit.revoke(reason: .cancelled)
        XCTAssertEqual(cancelledPermit.rejection, .cancelled)
        XCTAssertEqual(cancelledPermit.admit(), .revoked(.cancelled))
        XCTAssertEqual(cancelledPermit.admit(), .revoked(.cancelled))

        let ineligiblePermit = MetadataCommitPermit()
        ineligiblePermit.revoke(reason: .ineligible("removed from membership"))
        XCTAssertEqual(ineligiblePermit.rejection, .ineligible("removed from membership"))
        XCTAssertEqual(ineligiblePermit.admit(), .revoked(.ineligible("removed from membership")))
    }

    func testConcurrentAdmitAndRevokeRemainConsistent() {
        for _ in 0..<100 {
            let permit = MetadataCommitPermit()
            let admission = LockedAdmissionBox()

            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    admission.store(permit.admit())
                } else {
                    permit.revoke(reason: .cancelled)
                }
            }

            switch admission.value {
            case .admitted:
                XCTAssertNil(permit.rejection, "An admitted permit cannot be relabelled as revoked")
                XCTAssertEqual(permit.admit(), .admitted)
            case .revoked(.cancelled):
                XCTAssertEqual(permit.rejection, .cancelled)
                XCTAssertEqual(permit.admit(), .revoked(.cancelled))
            case .revoked(.ineligible), .none:
                XCTFail("Unexpected admission outcome: \(String(describing: admission.value))")
            }
        }
    }

    @MainActor
    func testRegistryRevokesByFileAndByOperation() {
        let registry = MetadataCommitPermitRegistry()
        let fileA = UUID()
        let fileB = UUID()
        let operation = UUID()

        let permitA = registry.register(fileID: fileA, operationID: operation)
        let permitB = registry.register(fileID: fileB, operationID: operation)

        XCTAssertTrue(permitA === registry.permit(forFileID: fileA, operationID: operation))
        XCTAssertTrue(permitB === registry.permit(forFileID: fileB, operationID: operation))
        XCTAssertEqual(registry.activePermitCount, 2)

        // Re-registering the same file/operation pair returns the same permit so a
        // retry cannot provide a second admission gate for one write.
        XCTAssertTrue(registry.register(fileID: fileA, operationID: operation) === permitA)
        XCTAssertEqual(registry.activePermitCount, 2)

        registry.revoke(fileID: fileA, reason: .ineligible("removed from membership"))
        XCTAssertEqual(permitA.rejection, .ineligible("removed from membership"))
        XCTAssertNil(permitB.rejection)

        registry.revoke(operationID: operation, reason: .cancelled)
        XCTAssertEqual(permitB.rejection, .cancelled)

        registry.unregister(fileID: fileA, operationID: operation)
        XCTAssertNil(registry.permit(forFileID: fileA, operationID: operation))
        XCTAssertEqual(registry.activePermitCount, 1)

        registry.unregister(operationID: operation)
        XCTAssertEqual(registry.activePermitCount, 0)
    }

    @MainActor
    func testRegistryRevokesEverythingForOneOperationAcrossFiles() {
        let registry = MetadataCommitPermitRegistry()
        let operation = UUID()
        let otherOperation = UUID()
        let fileIDs = [UUID(), UUID(), UUID()]

        let permits = fileIDs.map { registry.register(fileID: $0, operationID: operation) }
        let otherPermit = registry.register(fileID: fileIDs[0], operationID: otherOperation)
        XCTAssertEqual(registry.activePermitCount, 4)

        registry.revoke(operationID: operation, reason: .cancelled)
        XCTAssertTrue(permits.allSatisfy { $0.rejection == .cancelled })
        XCTAssertNil(otherPermit.rejection)

        registry.unregister(operationID: operation)
        XCTAssertEqual(registry.activePermitCount, 1)

        registry.removeAll()
        XCTAssertEqual(registry.activePermitCount, 0)
    }
}

private nonisolated final class LockedAdmissionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MetadataCommitPermit.AdmissionResult?

    func store(_ result: MetadataCommitPermit.AdmissionResult) {
        lock.withLock { stored = result }
    }

    var value: MetadataCommitPermit.AdmissionResult? {
        lock.withLock { stored }
    }
}
