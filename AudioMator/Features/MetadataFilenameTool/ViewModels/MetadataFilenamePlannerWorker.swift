import Foundation

/// The immutable, value-only input one active converter mode is planned from.
///
/// The store captures this on the main actor from the reviewed `AudioFile`
/// snapshots and view draft values, then hands it to a `@concurrent` worker.
/// Nothing in it references the live view model or any UI object, and the
/// planning types it reaches are `nonisolated`/`Sendable`, so planning can run
/// entirely off the main actor.
nonisolated struct MetadataFilenamePlannerInput: Sendable {
    /// Identity of this exact captured input. Only a result carrying the
    /// current ID may publish or dispatch.
    let inputID: UUID
    /// Identity of the converter presentation that captured the input.
    let presentationID: UUID
    /// Cheap change detector for the captured file order/revision and draft.
    let signature: MetadataFilenamePlanInputSignature
    let mode: MetadataConverterMode
    /// Ordered reviewed snapshots. `snapshotID` is the tracked revision.
    let targets: [AudioFile]
    let template: String
    let replaceUnderscoresWithSpaces: Bool
    let includeCSVHeaderRow: Bool
    let firstCSVRowIsHeader: Bool
    let clearBlankImportedValues: Bool
    let sourceText: String
    let transferSource: MetadataExchangeField
    let transferDestination: MetadataExchangeField
    let transferOperation: MetadataFieldTransferOperation
    /// Adapter used only for deterministic plan-time projection. Optional so
    /// previews stay available when a caller has no projector.
    let projector: (any AudioMetadataPipeline)?
}

/// Cheap identity for a captured input. Derived from tracked revisions and
/// order, never from rehashing the external source document.
nonisolated struct MetadataFilenamePlanInputSignature: Hashable, Sendable {
    nonisolated struct Target: Hashable, Sendable {
        let id: AudioFile.ID
        let snapshotID: UUID
    }

    let presentationID: UUID
    let mode: MetadataConverterMode
    let targets: [Target]
    let template: String
    let replaceUnderscoresWithSpaces: Bool
    let includeCSVHeaderRow: Bool
    let firstCSVRowIsHeader: Bool
    let clearBlankImportedValues: Bool
    /// Token advanced by the session on every source/document edit or load.
    let sourceRevision: UUID
    let transferSource: MetadataExchangeField
    let transferDestination: MetadataExchangeField
    let transferOperation: MetadataFieldTransferOperation
}

/// One typed plan result for exactly one active mode. The store publishes this
/// value and every preview, count, gating check, export and write consumes it;
/// no consumer recomputes a plan.
nonisolated enum MetadataFilenameConverterResult: Sendable {
    case rename(FileRenamePlan)
    case filenameMetadata(FilenameMetadataPlan)
    case textExport(MetadataTextExportPlan, encodedText: String)
    case textImport(MetadataExchangeImportPlan)
    case csvExport(MetadataCSVExportPlan, encodedText: String)
    case csvImport(MetadataExchangeImportPlan)
    case fieldTransfer(MetadataExchangeImportPlan)

    nonisolated var mode: MetadataConverterMode {
        switch self {
        case .rename: return .metadataToFilename
        case .filenameMetadata: return .filenameToMetadata
        case .textExport: return .metadataToText
        case .textImport: return .textToMetadata
        case .csvExport: return .metadataToCSV
        case .csvImport: return .csvToMetadata
        case .fieldTransfer: return .metadataFieldTransfer
        }
    }

    /// Whether the captured plan may dispatch a write or export. Exports keep
    /// their existing `canExport` rule; writes keep their existing `canApply`
    /// rule, including no-op eligibility.
    nonisolated var isDispatchable: Bool {
        switch self {
        case .rename(let plan): return plan.canApply
        case .filenameMetadata(let plan): return plan.canApply
        case .textExport(let plan, _): return plan.canExport
        case .textImport(let plan), .csvImport(let plan), .fieldTransfer(let plan):
            return plan.canApply
        case .csvExport(let plan, _): return plan.canExport
        }
    }

    nonisolated var requiresWriteScope: Bool {
        switch self {
        case .textExport, .csvExport:
            return false
        case .rename, .filenameMetadata, .textImport, .csvImport, .fieldTransfer:
            return true
        }
    }

    /// The exact captured target URLs whose directories a write needs. Empty
    /// for exports and for plans with no executable target (which are refused
    /// before any scope request).
    nonisolated var executableTargetURLs: [URL] {
        switch self {
        case .rename(let plan):
            return plan.operations.flatMap { [$0.sourceURL, $0.destinationURL] }
        case .filenameMetadata(let plan):
            return plan.writeEntries.map { $0.write.target.url }
        case .textImport(let plan), .csvImport(let plan), .fieldTransfer(let plan):
            return plan.writeEntries.map { $0.write.target.url }
        case .textExport, .csvExport:
            return []
        }
    }

    nonisolated var renamePlan: FileRenamePlan? {
        guard case .rename(let plan) = self else { return nil }
        return plan
    }

    nonisolated var filenameMetadataPlan: FilenameMetadataPlan? {
        guard case .filenameMetadata(let plan) = self else { return nil }
        return plan
    }

    nonisolated var textExportPlan: MetadataTextExportPlan? {
        guard case .textExport(let plan, _) = self else { return nil }
        return plan
    }

    nonisolated var textImportPlan: MetadataExchangeImportPlan? {
        guard case .textImport(let plan) = self else { return nil }
        return plan
    }

    nonisolated var csvExportPlan: MetadataCSVExportPlan? {
        guard case .csvExport(let plan, _) = self else { return nil }
        return plan
    }

    nonisolated var csvImportPlan: MetadataExchangeImportPlan? {
        guard case .csvImport(let plan) = self else { return nil }
        return plan
    }

    nonisolated var fieldTransferPlan: MetadataExchangeImportPlan? {
        guard case .fieldTransfer(let plan) = self else { return nil }
        return plan
    }

    /// Encoded export document built exactly once when the plan was published.
    nonisolated var encodedExportText: String? {
        switch self {
        case .textExport(_, let encodedText), .csvExport(_, let encodedText):
            return encodedText
        case .rename, .filenameMetadata, .textImport, .csvImport, .fieldTransfer:
            return nil
        }
    }

    /// An inert value used while the active plan is pending, rejected or idle.
    static func empty(for mode: MetadataConverterMode) -> MetadataFilenameConverterResult {
        switch mode {
        case .metadataToFilename:
            return .rename(FileRenamePlan(template: "", validationMessage: nil, rows: [], operations: []))
        case .filenameToMetadata:
            return .filenameMetadata(FilenameMetadataPlan(
                template: "",
                replaceUnderscoresWithSpaces: false,
                validationMessage: nil,
                rows: []
            ))
        case .metadataToText:
            return .textExport(MetadataTextExportPlan(validationMessage: nil, rows: []), encodedText: "")
        case .textToMetadata:
            return .textImport(MetadataExchangeImportPlan(validationMessage: nil, rows: []))
        case .metadataToCSV:
            return .csvExport(
                MetadataCSVExportPlan(
                    validationMessage: nil,
                    columns: [],
                    rows: [],
                    includeHeaderRow: true,
                    delimiter: ","
                ),
                encodedText: ""
            )
        case .csvToMetadata:
            return .csvImport(MetadataExchangeImportPlan(validationMessage: nil, rows: []))
        case .metadataFieldTransfer:
            return .fieldTransfer(MetadataExchangeImportPlan(validationMessage: nil, rows: []))
        }
    }
}

/// The single plan-state contract owned by `MetadataFilenameToolStore`.
nonisolated enum MetadataFilenamePlanState: Sendable {
    case idle
    case pending(inputID: UUID)
    case ready(inputID: UUID, result: MetadataFilenameConverterResult)
    case rejected(inputID: UUID, reason: String)

    nonisolated var inputID: UUID? {
        switch self {
        case .idle: return nil
        case .pending(let inputID), .rejected(let inputID, _): return inputID
        case .ready(let inputID, _): return inputID
        }
    }

    nonisolated var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    nonisolated var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Injectable async planner boundary. Tests substitute a counting/barrier fake
/// to assert invocation ownership; production uses the `@concurrent` default.
protocol MetadataFilenamePlanWorking: Sendable {
    nonisolated func makePlan(_ input: MetadataFilenamePlannerInput) async throws -> MetadataFilenameConverterResult
}

/// Injectable debounce clock. Production sleeps for the real interval; tests
/// gate the wake-up so coalescing and slot ownership are deterministic.
protocol MetadataFilenameDebounceClock: Sendable {
    nonisolated func sleep(for duration: Duration) async throws
}

nonisolated struct MetadataFilenameContinuousClock: MetadataFilenameDebounceClock {
    nonisolated func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Default production planner. Runs on the concurrent executor, returns only
/// value results and never publishes or touches the live model.
nonisolated struct MetadataFilenamePlannerWorker: MetadataFilenamePlanWorking {
    @concurrent
    nonisolated func makePlan(_ input: MetadataFilenamePlannerInput) async throws -> MetadataFilenameConverterResult {
        try Task.checkCancellation()

        let result: MetadataFilenameConverterResult
        switch input.mode {
        case .metadataToFilename:
            result = .rename(
                makeFileRenamePlan(template: input.template, targetFiles: input.targets)
            )
        case .filenameToMetadata:
            result = .filenameMetadata(
                makeFilenameMetadataPlan(
                    template: input.template,
                    targetFiles: input.targets,
                    replaceUnderscoresWithSpaces: input.replaceUnderscoresWithSpaces,
                    projector: input.projector
                )
            )
        case .metadataToText:
            let plan = MetadataExchangePlanner.makeTextExportPlan(
                template: input.template,
                targetFiles: input.targets
            )
            try Task.checkCancellation()
            result = .textExport(plan, encodedText: plan.outputText)
        case .textToMetadata:
            result = .textImport(
                MetadataExchangePlanner.makeTextImportPlan(
                    template: input.template,
                    sourceText: input.sourceText,
                    targetFiles: input.targets,
                    clearBlankImportedValues: input.clearBlankImportedValues,
                    projector: input.projector
                )
            )
        case .metadataToCSV:
            let plan = MetadataExchangePlanner.makeCSVExportPlan(
                template: input.template,
                includeHeaderRow: input.includeCSVHeaderRow,
                targetFiles: input.targets
            )
            try Task.checkCancellation()
            result = .csvExport(plan, encodedText: plan.outputText)
        case .csvToMetadata:
            result = .csvImport(
                MetadataExchangePlanner.makeCSVImportPlan(
                    template: input.template,
                    sourceText: input.sourceText,
                    firstRowIsHeader: input.firstCSVRowIsHeader,
                    targetFiles: input.targets,
                    clearBlankImportedValues: input.clearBlankImportedValues,
                    projector: input.projector
                )
            )
        case .metadataFieldTransfer:
            result = .fieldTransfer(
                MetadataFieldTransferPlanner.makePlan(
                    source: input.transferSource,
                    destination: input.transferDestination,
                    operation: input.transferOperation,
                    targetFiles: input.targets,
                    projector: input.projector
                )
            )
        }

        try Task.checkCancellation()
        return result
    }
}
