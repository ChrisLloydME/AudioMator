import Foundation
import TagLibAudioMetadata

/// One immutable semantic write captured for a reviewed renumber row.
///
/// The payload was built with the track-number component setter from the same
/// reviewed `AudioFile` observation that supplied the target and the projection.
/// The strict executor consumes exactly this value, so Apply cannot rebuild a
/// different patch from the current file collection.
nonisolated struct TrackRenumberFrozenWrite: Sendable {
    let target: ReviewedMetadataTarget
    let payload: MetadataEditPayload
    let projection: MetadataWriteProjection

    nonisolated var reviewedWrite: ReviewedMetadataWrite {
        ReviewedMetadataWrite(target: target, intent: .semantic(payload), projection: projection)
    }
}

/// Why an ordered target was classified as skipped before any number was
/// assigned. Skipped rows never consume a slot.
nonisolated enum TrackRenumberSkipReason: Equatable, Sendable {
    case duplicateTarget
    case fileNotLoaded
    case missingReviewedRevision
    case requiresMetadataRefresh
    case recoveryBlocked
    case unsupportedFormat
    case unsupportedTrackCapability
    /// The start-number field itself is invalid; no sequence can be numbered.
    case invalidStartNumber

    nonisolated var message: String {
        switch self {
        case .duplicateTarget:
            return String(localized: "This file appears more than once in the target list, so it is numbered only once.")
        case .fileNotLoaded:
            return String(localized: "This file is no longer loaded in AudioMator. Import it again before applying changes.")
        case .missingReviewedRevision:
            return String(localized: "This file doesn’t have a reviewed revision. Reload it, then reopen track renumbering.")
        case .requiresMetadataRefresh:
            return String(localized: "The file couldn’t be checked after it moved. Close this tool and choose Reload from Disk from the file’s context menu before changing track numbers.")
        case .recoveryBlocked:
            return String(localized: "The file must be reloaded before it can be changed.")
        case .unsupportedFormat:
            return String(localized: "AudioMator doesn’t support saving metadata to this file format.")
        case .unsupportedTrackCapability:
            return String(localized: "This file format doesn’t support saving Track Number.")
        case .invalidStartNumber:
            return String(localized: "Enter a valid start number before applying changes.")
        }
    }

    /// Rows that count in the unsupported/skip summary.
    nonisolated var countsAsUnsupported: Bool {
        switch self {
        case .unsupportedFormat, .unsupportedTrackCapability:
            return true
        default:
            return false
        }
    }

    nonisolated var countsAsDuplicate: Bool {
        self == .duplicateTarget
    }

    /// Rows that keep the file unchanged but are reported as failures (a
    /// precondition the user must resolve), matching the old refresh-required
    /// reporting.
    nonisolated var countsAsFailure: Bool {
        switch self {
        case .fileNotLoaded, .missingReviewedRevision, .requiresMetadataRefresh, .recoveryBlocked:
            return true
        default:
            return false
        }
    }

    nonisolated var blocksNumbering: Bool {
        self != .invalidStartNumber
    }
}

/// Reason a planned number could not be written even though the target was
/// otherwise eligible. The attempted value is retained for the preview.
nonisolated enum TrackRenumberValueRejection: Error, Equatable, Sendable {
    case exceedsSharedComponentMaximum(attempted: Int)
    case exceedsContainerComponentMaximum(attempted: Int, maximum: Int)

    nonisolated var attemptedNumber: Int {
        switch self {
        case .exceedsSharedComponentMaximum(let attempted),
             .exceedsContainerComponentMaximum(let attempted, _):
            return attempted
        }
    }

    nonisolated var message: String {
        switch self {
        case .exceedsSharedComponentMaximum:
            return String(localized: "This track number is too large to save.")
        case .exceedsContainerComponentMaximum(_, let maximum):
            return String(localized: "This file format can store track numbers only up to \(maximum).")
        }
    }
}

/// A row-level rejection produced after numbering. The row keeps its planned
/// slot so no other reviewed assignment shifts.
nonisolated enum TrackRenumberRowRejection: Equatable, Sendable {
    case number(TrackRenumberValueRejection)
    case capability(String)
    case validation(String)

    nonisolated var message: String {
        switch self {
        case .number(let rejection):
            return rejection.message
        case .capability(let message), .validation(let message):
            return message
        }
    }
}

/// One ordered row of the reviewed plan.
nonisolated struct TrackRenumberRow: Sendable {
    nonisolated enum Disposition: Sendable {
        case executable(TrackRenumberFrozenWrite)
        /// The stored numeric value already equals the reviewed number. The row
        /// keeps its slot and causes no disk write.
        case unchanged
        case skipped(TrackRenumberSkipReason)
        case rejected(TrackRenumberRowRejection)
    }

    let id: AudioFile.ID
    let fileName: String
    let assignedNumber: Int?
    let disposition: Disposition

    nonisolated var executableWrite: TrackRenumberFrozenWrite? {
        guard case .executable(let write) = disposition else { return nil }
        return write
    }

    nonisolated var isExecutable: Bool {
        executableWrite != nil
    }

    nonisolated var isUnchanged: Bool {
        if case .unchanged = disposition { return true }
        return false
    }

    nonisolated var skipReason: TrackRenumberSkipReason? {
        guard case .skipped(let reason) = disposition else { return nil }
        return reason
    }

    nonisolated var rejection: TrackRenumberRowRejection? {
        guard case .rejected(let rejection) = disposition else { return nil }
        return rejection
    }

    /// Preview reason for a row that will not be written.
    nonisolated var issueMessage: String? {
        if let skipReason, skipReason != .invalidStartNumber { return skipReason.message }
        return rejection?.message
    }
}

/// The single reviewed plan consumed by both the renumber preview and the
/// writer. Every count, displayed number, range, skip and validity state derives
/// from this value.
///
/// Numbering is positional over eligible rows only: unsupported, duplicate,
/// recovery-blocked, refresh-required and unreviewed rows are classified before
/// numbering and do not consume a slot. Unchanged rows and value-rejected rows
/// keep the slot they were assigned.
nonisolated struct TrackRenumberPlan: Sendable {
    let direction: TrackRenumberDirection
    let startInput: TrackRenumberStartNumberInput
    let rows: [TrackRenumberRow]
    /// The exact ordered target IDs the plan was built from. Apply compares this
    /// with the current resolved scope and refuses to dispatch a stale plan.
    let orderedTargetIDs: [AudioFile.ID]

    static let empty = TrackRenumberPlan(
        direction: .ascending,
        startInput: .valid(defaultTrackRenumberStartNumber),
        rows: [],
        orderedTargetIDs: []
    )

    nonisolated var startNumber: Int? { startInput.startNumber }
    nonisolated var isStartValid: Bool { startInput.isValid }
    nonisolated var validationMessage: String? { startInput.validationMessage }
    nonisolated var totalTargets: Int { rows.count }
    nonisolated var isEmpty: Bool { rows.isEmpty }

    nonisolated var executableRows: [TrackRenumberRow] { rows.filter(\.isExecutable) }
    nonisolated var executableCount: Int { executableRows.count }
    nonisolated var unchangedCount: Int { rows.filter(\.isUnchanged).count }

    nonisolated var skippedUnsupportedCount: Int {
        rows.filter { $0.skipReason?.countsAsUnsupported == true }.count
    }

    nonisolated var skippedDuplicateCount: Int {
        rows.filter { $0.skipReason?.countsAsDuplicate == true }.count
    }

    /// Rows reported as failures without attempting a write (preconditions and
    /// value/capability rejections).
    nonisolated var failedRowCount: Int {
        rows.filter { row in
            if let skipReason = row.skipReason { return skipReason.countsAsFailure }
            return row.rejection != nil
        }.count
    }

    /// Rows the preview lists as not applied, in order.
    nonisolated var issueRows: [TrackRenumberRow] {
        rows.filter { $0.issueMessage != nil }
    }

    /// Assigned numbers in reviewed order. Includes unchanged rows because they
    /// keep their slot. Rejected-value rows keep their attempted number here so
    /// the preview can show the exact reviewed attempt.
    nonisolated var numberedRows: [TrackRenumberRow] {
        rows.filter { $0.assignedNumber != nil }
    }

    nonisolated var previewNumbers: [Int] {
        numberedRows.compactMap(\.assignedNumber)
    }

    nonisolated var firstPreviewNumber: Int? { previewNumbers.first }
    nonisolated var lastPreviewNumber: Int? { previewNumbers.last }

    nonisolated func matchesOrderedTargets(_ ids: [AudioFile.ID]) -> Bool {
        ids == orderedTargetIDs
    }

    /// Counts derived from the plan before execution. The writer starts from this
    /// value and adds per-row runtime outcomes.
    nonisolated func resultBaseline() -> TrackRenumberResult {
        var result = TrackRenumberResult(
            totalTargets: rows.count,
            succeeded: 0,
            failed: 0,
            failures: [],
            warnings: []
        )
        result.validationMessage = validationMessage
        result.unchanged = unchangedCount
        for row in rows {
            switch row.disposition {
            case .executable, .unchanged:
                break
            case .skipped(let reason):
                if reason.countsAsUnsupported {
                    result.skippedUnsupported += 1
                } else if reason.countsAsDuplicate {
                    result.skippedDuplicate += 1
                } else if reason.countsAsFailure {
                    result.failed += 1
                    result.failures.append(
                        TrackRenumberFailure(fileName: row.fileName, reason: reason.message)
                    )
                }
            case .rejected(let rejection):
                result.failed += 1
                result.failures.append(
                    TrackRenumberFailure(fileName: row.fileName, reason: rejection.message)
                )
            }
        }
        return result
    }
}

/// Checked positional number assignment shared by preview and writer.
nonisolated enum TrackRenumberNumbering {
    /// Returns the reviewed number for one eligible slot, or the reason the
    /// checked arithmetic cannot represent it. The caller applies no clamping and
    /// does not shift other slots.
    nonisolated static func plannedNumber(
        slotIndex: Int,
        slotCount: Int,
        startNumber: Int,
        direction: TrackRenumberDirection,
        fileExtension: String
    ) -> Result<Int, TrackRenumberValueRejection> {
        precondition(slotCount > 0, "A numbered plan has at least one eligible slot.")
        precondition(slotIndex >= 0 && slotIndex < slotCount, "Slot index must address a numbered row.")

        let offset: Int
        switch direction {
        case .ascending:
            offset = slotIndex
        case .descending:
            offset = slotCount - 1 - slotIndex
        }

        let (attempted, overflow) = startNumber.addingReportingOverflow(offset)
        guard !overflow else {
            return .failure(.exceedsSharedComponentMaximum(attempted: Int.max))
        }
        guard attempted <= AudioFormatNumberBounds.int32ComponentMaximum else {
            return .failure(.exceedsSharedComponentMaximum(attempted: attempted))
        }
        let containerMaximum = AudioFormatNumberBounds.componentMaximum(forFileExtension: fileExtension)
        guard attempted <= containerMaximum else {
            return .failure(.exceedsContainerComponentMaximum(attempted: attempted, maximum: containerMaximum))
        }
        return .success(attempted)
    }
}

/// Builds the reviewed renumber plan from ordered reviewed files.
///
/// Planning is pure: it captures targets, numbers, frozen payloads and
/// projections, but performs no disk I/O. The caller supplies the current
/// recovery-blocked IDs and the adapter projection (when available). Without a
/// projector the planner falls back to the same fail-closed declared `.track`
/// capability check used by the strict route.
nonisolated enum TrackRenumberPlanner {
    private struct Candidate {
        let file: AudioFile
        let target: ReviewedMetadataTarget?
        let skipReason: TrackRenumberSkipReason?

        var isEligible: Bool { skipReason == nil }
    }

    @MainActor
    static func makePlan(
        orderedFiles: [AudioFile],
        selectedIDs: Set<AudioFile.ID>,
        direction: TrackRenumberDirection,
        startNumberText: String,
        recoveryBlockedIDs: Set<AudioFile.ID> = [],
        projector: (any AudioMetadataPipeline)? = nil
    ) -> TrackRenumberPlan {
        let targets = selectedIDs.isEmpty
            ? orderedFiles
            : orderedFiles.filter { selectedIDs.contains($0.id) }
        let orderedTargetIDs = targets.map(\.id)
        let startInput = trackRenumberStartNumberInput(startNumberText)

        var seenIDs = Set<AudioFile.ID>()
        var seenURLKeys = Set<String>()
        var candidates: [Candidate] = []
        candidates.reserveCapacity(targets.count)

        for file in targets {
            let urlKey = FileSystemPathSemantics.key(for: file.url)
            if seenIDs.contains(file.id) || seenURLKeys.contains(urlKey) {
                candidates.append(Candidate(file: file, target: nil, skipReason: .duplicateTarget))
                continue
            }
            seenIDs.insert(file.id)
            seenURLKeys.insert(urlKey)

            if recoveryBlockedIDs.contains(file.id) {
                candidates.append(Candidate(file: file, target: nil, skipReason: .recoveryBlocked))
                continue
            }
            if file.requiresMetadataRefreshBeforeWriting {
                candidates.append(Candidate(file: file, target: nil, skipReason: .requiresMetadataRefresh))
                continue
            }
            guard let target = ReviewedMetadataTarget(verified: file) else {
                candidates.append(Candidate(file: file, target: nil, skipReason: .missingReviewedRevision))
                continue
            }
            let fileExtension = file.url.pathExtension
            guard let writableFields = AudioFormatSupport.writableMetadataFields(for: fileExtension) else {
                candidates.append(Candidate(file: file, target: nil, skipReason: .unsupportedFormat))
                continue
            }
            guard writableFields.contains(.track) else {
                candidates.append(Candidate(file: file, target: nil, skipReason: .unsupportedTrackCapability))
                continue
            }
            candidates.append(Candidate(file: file, target: target, skipReason: nil))
        }

        let slotCount = candidates.filter(\.isEligible).count
        var rows: [TrackRenumberRow] = []
        rows.reserveCapacity(candidates.count)
        var nextSlotIndex = 0

        for candidate in candidates {
            if let skipReason = candidate.skipReason {
                rows.append(
                    TrackRenumberRow(
                        id: candidate.file.id,
                        fileName: candidate.file.url.lastPathComponent,
                        assignedNumber: nil,
                        disposition: .skipped(skipReason)
                    )
                )
                continue
            }
            guard let target = candidate.target else {
                // Defensive: an eligible candidate always carries a target.
                rows.append(
                    TrackRenumberRow(
                        id: candidate.file.id,
                        fileName: candidate.file.url.lastPathComponent,
                        assignedNumber: nil,
                        disposition: .skipped(.missingReviewedRevision)
                    )
                )
                continue
            }
            guard let startNumber = startInput.startNumber else {
                rows.append(
                    TrackRenumberRow(
                        id: candidate.file.id,
                        fileName: candidate.file.url.lastPathComponent,
                        assignedNumber: nil,
                        disposition: .skipped(.invalidStartNumber)
                    )
                )
                continue
            }

            let slotIndex = nextSlotIndex
            nextSlotIndex += 1
            switch TrackRenumberNumbering.plannedNumber(
                slotIndex: slotIndex,
                slotCount: slotCount,
                startNumber: startNumber,
                direction: direction,
                fileExtension: candidate.file.url.pathExtension
            ) {
            case .failure(let rejection):
                rows.append(
                    TrackRenumberRow(
                        id: candidate.file.id,
                        fileName: candidate.file.url.lastPathComponent,
                        assignedNumber: rejection.attemptedNumber,
                        disposition: .rejected(.number(rejection))
                    )
                )
            case .success(let number):
                rows.append(
                    makeRow(
                        file: candidate.file,
                        target: target,
                        assignedNumber: number,
                        projector: projector
                    )
                )
            }
        }

        return TrackRenumberPlan(
            direction: direction,
            startInput: startInput,
            rows: rows,
            orderedTargetIDs: orderedTargetIDs
        )
    }

    /// Plan-time projection used when the adapter does not implement
    /// `projectMetadataWrite`: the declared `.track` capability check above
    /// already failed closed, so the synthesized projection can only describe the
    /// reviewed track-only change.
    private nonisolated static func declaredCapabilityProjection(
        requestedFields: Set<MetadataFieldKey>,
        assignedNumber: Int
    ) -> MetadataWriteProjection {
        MetadataWriteProjection(
            requestedFields: requestedFields,
            effectiveFields: requestedFields,
            componentOperations: [
                MetadataNumberComponentOperation(field: .track, value: assignedNumber)
            ],
            validation: .executable
        )
    }

    /// Builds the frozen track-only write for one numbered row and classifies a
    /// numeric no-op as unchanged.
    @MainActor
    private static func makeRow(
        file: AudioFile,
        target: ReviewedMetadataTarget,
        assignedNumber: Int,
        projector: (any AudioMetadataPipeline)?
    ) -> TrackRenumberRow {
        let fileName = file.url.lastPathComponent

        func rejected(_ rejection: TrackRenumberRowRejection) -> TrackRenumberRow {
            TrackRenumberRow(
                id: file.id,
                fileName: fileName,
                assignedNumber: assignedNumber,
                disposition: .rejected(rejection)
            )
        }

        var edit = SingleFileEditModel(from: file)
        edit.setTrackNumberText(String(assignedNumber))
        let payload = MetadataEditPayload(edit, comparedTo: file)

        // A numeric match (including stored padded text such as "007") requests no
        // field and must not reach a writer; the raw text is preserved untouched.
        if payload.requestedFields.isEmpty {
            return TrackRenumberRow(
                id: file.id,
                fileName: fileName,
                assignedNumber: assignedNumber,
                disposition: .unchanged
            )
        }

        // Renumbering is a track-component intent only. The total and the complete
        // disc pair stay untouched by construction.
        let trackOnlyFields: Set<MetadataFieldKey> = [.track]
        guard payload.requestedFields == trackOnlyFields else {
            return rejected(.capability(String(localized: "Track renumbering can change only Track Number in this file.")))
        }

        let projection: MetadataWriteProjection
        if let projector {
            do {
                projection = try projector.projectMetadataWrite(
                    .semantic(payload),
                    fileExtension: file.url.pathExtension
                )
            } catch let error as CocoaError where error.code == .featureUnsupported {
                // An adapter that predates plan-time projection reports
                // `featureUnsupported`. Fall back to the declared `.track`
                // capability truth already validated above. A real adapter failure
                // (any other error, or an explicit rejection) still fails closed.
                projection = declaredCapabilityProjection(
                    requestedFields: trackOnlyFields,
                    assignedNumber: assignedNumber
                )
            } catch {
                return rejected(.capability((error as NSError).localizedDescription))
            }
        } else {
            // No projector was supplied (pure planner tests): synthesize the same
            // track-only truth from the declared capability checks.
            projection = declaredCapabilityProjection(
                requestedFields: trackOnlyFields,
                assignedNumber: assignedNumber
            )
        }

        switch projection.validation {
        case .executable:
            if projection.isNoOp {
                return TrackRenumberRow(
                    id: file.id,
                    fileName: fileName,
                    assignedNumber: assignedNumber,
                    disposition: .unchanged
                )
            }
            guard projection.requestedFields == trackOnlyFields,
                  projection.componentOperations == [
                    MetadataNumberComponentOperation(field: .track, value: assignedNumber)
                  ] else {
                return rejected(.capability(String(localized: "The reviewed track-only change isn’t supported for this file.")))
            }
            let frozenWrite = TrackRenumberFrozenWrite(
                target: target,
                payload: payload,
                projection: projection
            )
            return TrackRenumberRow(
                id: file.id,
                fileName: fileName,
                assignedNumber: assignedNumber,
                disposition: .executable(frozenWrite)
            )
        case .rejected(let message):
            return rejected(.validation(message))
        case .unsupported(let fields):
            return rejected(
                .capability(
                    String(localized: "Changes to \(fields.count) metadata fields can’t be saved in this file format.")
                )
            )
        }
    }
}
