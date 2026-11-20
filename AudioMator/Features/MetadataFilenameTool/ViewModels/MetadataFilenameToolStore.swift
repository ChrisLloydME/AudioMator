import Combine
import Foundation

/// One captured plan handed to the view for dispatch. Capturing a dispatch is
/// the only way Apply/Export can reach the application model, so a pending or
/// superseded plan can never start a write or an export.
nonisolated struct MetadataFilenameConverterDispatch: Sendable, Identifiable {
    let id: UUID
    let presentationID: UUID
    let mode: MetadataConverterMode
    let result: MetadataFilenameConverterResult

    nonisolated var encodedExportText: String? { result.encodedExportText }
}

/// Owns the active converter mode's plan worker, its published plan state and
/// the converter session draft.
///
/// The store captures a value-only `MetadataFilenamePlannerInput` on the main
/// actor, coalesces relevant edits through the injectable debounce clock, runs
/// at most one planner at a time with only the latest input pending, and is the
/// only object allowed to advance `planState`. A stale completion — even one
/// from a worker that ignored cancellation — cannot publish because it must
/// match the current input and presentation identity.
@MainActor
final class MetadataFilenameToolStore: ObservableObject {
    static let defaultDebounce: Duration = .milliseconds(150)

    // MARK: – Published conversion session state

    @Published private(set) var targetFileIDs: [AudioFile.ID] = []
    @Published private(set) var presentationID = UUID()
    /// Ordered reviewed target snapshots for the current presentation.
    @Published private(set) var targetFiles: [AudioFile] = []
    @Published private(set) var isTargetResolutionComplete = true
    @Published private(set) var planState: MetadataFilenamePlanState = .idle
    @Published private(set) var isApplying = false
    @Published private(set) var lastScopeRequestError: String?

    @Published private(set) var selectedMode: MetadataConverterMode?
    @Published private(set) var metadataToFilenameTemplate = ""
    @Published private(set) var filenameToMetadataTemplate = ""
    @Published private(set) var metadataToTextTemplate = "{{trackNumber}}. {{artist}} - {{title}}"
    @Published private(set) var textToMetadataTemplate = "{{fileName}} | {{title}} | {{artist}} | {{album}}"
    @Published private(set) var metadataToCSVTemplate = "{{fileName}},{{trackNumber}},{{title}},{{artist}},{{album}}"
    @Published private(set) var csvToMetadataTemplate = "{{fileName}},{{trackNumber}},{{title}},{{artist}},{{album}}"
    @Published private(set) var textImportSource = ""
    @Published private(set) var csvImportSource = ""
    @Published private(set) var selectedTextImportURL: URL?
    @Published private(set) var selectedCSVImportURL: URL?
    @Published private(set) var externalFileError: String?
    @Published private(set) var includeCSVHeaderRow = true
    @Published private(set) var firstCSVRowIsHeader = true
    @Published private(set) var clearBlankTextImportedValues = false
    @Published private(set) var clearBlankCSVImportedValues = false
    @Published private(set) var replaceUnderscoresWithSpaces = false
    @Published private(set) var fieldTransferSource: MetadataExchangeField = .artist
    @Published private(set) var fieldTransferDestination: MetadataExchangeField = .albumArtist
    @Published private(set) var fieldTransferOperation: MetadataFieldTransferOperation = .copy

    // MARK: – Seams

    private let worker: any MetadataFilenamePlanWorking
    private let clock: any MetadataFilenameDebounceClock
    private let debounceInterval: Duration
    private var scopeRequester: (([URL]) -> String?)?

    // MARK: – Planning ownership

    private var latestInput: MetadataFilenamePlannerInput?
    private var activeSignature: MetadataFilenamePlanInputSignature?
    private var currentInputID: UUID?
    private var debounceToken: UUID?
    private var debounceTask: Task<Void, Never>?
    private var workerTask: Task<Void, Never>?
    private var activeDispatch: MetadataFilenameConverterDispatch?
    private var isRequestingScope = false
    private var settlementWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: – Target resolution cache (one ordered lookup per tracked revision)

    private var cachedFilesRevision: UUID?
    private var filesIndex: [AudioFile.ID: AudioFile] = [:]
    private var duplicateFileIDs: Set<AudioFile.ID> = []
    private var cachedTargetPresentationID: UUID?
    private var cachedTargetRevision: UUID?
    private var cachedTargetIDs: [AudioFile.ID] = []
    private var resolvedTargetsAreCached = false

    /// Test-facing preparation counter: how many times the visible collection
    /// index was built. One per relevant file revision, never per view read.
    private(set) var targetIndexBuildCount = 0

    // MARK: – Projector / source identity

    private var projector: (any AudioMetadataPipeline)?
    private var sourceRevision = UUID()
    private var externalLoadIDs: [MetadataConverterMode: UUID] = [:]
    private var externalLoadTasks: [MetadataConverterMode: Task<Void, Never>] = [:]

    init(
        worker: any MetadataFilenamePlanWorking = MetadataFilenamePlannerWorker(),
        clock: any MetadataFilenameDebounceClock = MetadataFilenameContinuousClock(),
        debounceInterval: Duration = MetadataFilenameToolStore.defaultDebounce
    ) {
        self.worker = worker
        self.clock = clock
        self.debounceInterval = debounceInterval
    }

    /// Production wiring for the one write-scope request the converter is
    /// allowed to make: executable captured targets at Apply.
    func setScopeRequester(_ requester: (([URL]) -> String?)?) {
        scopeRequester = requester
    }

    // MARK: – Presentation

    /// Starts a new presentation for the given ordered targets. Cancels all
    /// in-flight planning and external loads; the caller supplies the visible
    /// collection through `refresh(files:revision:projector:)`.
    func present(targetFileIDs: [AudioFile.ID]) {
        var seenIDs: Set<AudioFile.ID> = []
        self.targetFileIDs = targetFileIDs.filter { seenIDs.insert($0).inserted }
        presentationID = UUID()
        resetPresentationState()
    }

    /// Cancels the current presentation (for example when closing the converter
    /// window), cancelling any in-flight planning or external file loads and
    /// releasing large retained plans and indexes.
    func cancelPresentation() {
        presentationID = UUID()
        cancelAllPlanning()
        cancelExternalLoads()
        lastScopeRequestError = nil
        targetFiles = []
        filesIndex = [:]
        duplicateFileIDs = []
        cachedFilesRevision = nil
        cachedTargetPresentationID = nil
        cachedTargetRevision = nil
        cachedTargetIDs = []
        resolvedTargetsAreCached = false
        activeDispatch = nil
        isApplying = false
        notifySettlementIfQuiescent()
    }

    private func resetPresentationState() {
        cancelAllPlanning()
        cancelExternalLoads()
        lastScopeRequestError = nil
        selectedMode = nil
        textImportSource = ""
        csvImportSource = ""
        selectedTextImportURL = nil
        selectedCSVImportURL = nil
        externalFileError = nil
        includeCSVHeaderRow = true
        firstCSVRowIsHeader = true
        clearBlankTextImportedValues = false
        clearBlankCSVImportedValues = false
        replaceUnderscoresWithSpaces = false
        fieldTransferSource = .artist
        fieldTransferDestination = .albumArtist
        fieldTransferOperation = .copy
        sourceRevision = UUID()
        activeDispatch = nil
        isApplying = false
        planState = .idle
        targetFiles = []
        isTargetResolutionComplete = true
        resolvedTargetsAreCached = false
        cachedTargetPresentationID = nil
        cachedTargetRevision = nil
        cachedTargetIDs = []
        notifySettlementIfQuiescent()
    }

    /// Presents the current visible collection snapshot. The index is rebuilt
    /// only when the tracked file revision changes, so repeated draft edits do
    /// not regroup the collection.
    func refresh(
        files: [AudioFile],
        filesRevision: UUID,
        projector: (any AudioMetadataPipeline)?
    ) {
        self.projector = projector
        if cachedFilesRevision != filesRevision {
            cachedFilesRevision = filesRevision
            rebuildFilesIndex(files)
        }
        resolveTargetsIfNeeded()
        schedulePlanning()
    }

    private func rebuildFilesIndex(_ files: [AudioFile]) {
        var index: [AudioFile.ID: AudioFile] = [:]
        index.reserveCapacity(files.count)
        var duplicates: Set<AudioFile.ID> = []
        for file in files {
            if index.updateValue(file, forKey: file.id) != nil {
                duplicates.insert(file.id)
            }
        }
        filesIndex = index
        duplicateFileIDs = duplicates
        resolvedTargetsAreCached = false
        targetIndexBuildCount += 1
    }

    private func resolveTargetsIfNeeded() {
        guard
            !resolvedTargetsAreCached
                || cachedTargetPresentationID != presentationID
                || cachedTargetRevision != cachedFilesRevision
                || cachedTargetIDs != targetFileIDs
        else { return }

        var resolved: [AudioFile] = []
        resolved.reserveCapacity(targetFileIDs.count)
        var isComplete = true
        for id in targetFileIDs {
            guard !duplicateFileIDs.contains(id), let file = filesIndex[id] else {
                isComplete = false
                resolved = []
                break
            }
            resolved.append(file)
        }

        targetFiles = resolved
        isTargetResolutionComplete = isComplete
        resolvedTargetsAreCached = true
        cachedTargetPresentationID = presentationID
        cachedTargetRevision = cachedFilesRevision
        cachedTargetIDs = targetFileIDs
    }

    // MARK: – Draft mutations

    func selectMode(_ mode: MetadataConverterMode?) {
        selectedMode = mode
        externalFileError = nil
        if mode == nil {
            cancelAllPlanning()
            return
        }
        schedulePlanning()
    }

    /// Field-transfer choices are part of the active plan input, so changing
    /// them invalidates the ready plan exactly like a template edit.
    func setFieldTransferOptions(
        source: MetadataExchangeField,
        destination: MetadataExchangeField,
        operation: MetadataFieldTransferOperation
    ) {
        guard
            source != fieldTransferSource
                || destination != fieldTransferDestination
                || operation != fieldTransferOperation
        else { return }
        fieldTransferSource = source
        fieldTransferDestination = destination
        fieldTransferOperation = operation
        schedulePlanning()
    }

    func template(for mode: MetadataConverterMode) -> String {
        switch mode {
        case .metadataToFilename: return metadataToFilenameTemplate
        case .filenameToMetadata: return filenameToMetadataTemplate
        case .metadataToText: return metadataToTextTemplate
        case .textToMetadata: return textToMetadataTemplate
        case .metadataToCSV: return metadataToCSVTemplate
        case .csvToMetadata: return csvToMetadataTemplate
        case .metadataFieldTransfer: return ""
        }
    }

    func updateTemplate(_ template: String, for mode: MetadataConverterMode) {
        switch mode {
        case .metadataToFilename:
            metadataToFilenameTemplate = template
        case .filenameToMetadata:
            filenameToMetadataTemplate = template
        case .metadataToText:
            metadataToTextTemplate = template
        case .textToMetadata:
            textToMetadataTemplate = template
        case .metadataToCSV:
            metadataToCSVTemplate = template
        case .csvToMetadata:
            csvToMetadataTemplate = template
        case .metadataFieldTransfer:
            return
        }
        schedulePlanning()
    }

    func setReplaceUnderscoresWithSpaces(_ enabled: Bool) {
        replaceUnderscoresWithSpaces = enabled
        schedulePlanning()
    }

    func setIncludeCSVHeaderRow(_ enabled: Bool) {
        includeCSVHeaderRow = enabled
        schedulePlanning()
    }

    func setFirstCSVRowIsHeader(_ enabled: Bool) {
        firstCSVRowIsHeader = enabled
        schedulePlanning()
    }

    func externalSource(for mode: MetadataConverterMode) -> String {
        mode == .csvToMetadata ? csvImportSource : textImportSource
    }

    func externalSourceURL(for mode: MetadataConverterMode) -> URL? {
        mode == .csvToMetadata ? selectedCSVImportURL : selectedTextImportURL
    }

    func clearBlankImportedValues(for mode: MetadataConverterMode) -> Bool {
        mode == .csvToMetadata ? clearBlankCSVImportedValues : clearBlankTextImportedValues
    }

    /// Manual source typing supersedes any earlier external-file load for the
    /// mode: the stale loader can no longer replace or error over this text.
    func setExternalSource(_ text: String, for mode: MetadataConverterMode) {
        cancelExternalLoad(for: mode)
        if mode == .csvToMetadata {
            csvImportSource = text
            selectedCSVImportURL = nil
        } else {
            textImportSource = text
            selectedTextImportURL = nil
        }
        externalFileError = nil
        advanceSourceRevision()
        schedulePlanning()
    }

    func setClearBlankImportedValues(_ enabled: Bool, for mode: MetadataConverterMode) {
        if mode == .csvToMetadata {
            clearBlankCSVImportedValues = enabled
        } else if mode == .textToMetadata {
            clearBlankTextImportedValues = enabled
        }
        schedulePlanning()
    }

    /// Loads an external text/CSV document with presentation and load identity
    /// checks, and propagates task cancellation into the loader.
    func loadExternalTextFile(
        from url: URL,
        for mode: MetadataConverterMode,
        loader: @escaping @Sendable (URL) async throws -> String
    ) {
        guard mode == .textToMetadata || mode == .csvToMetadata else { return }
        cancelExternalLoad(for: mode)
        let loadID = UUID()
        let capturedPresentationID = presentationID
        externalLoadIDs[mode] = loadID
        externalLoadTasks[mode] = Task { [weak self] in
            do {
                let text = try await loader(url)
                guard !Task.isCancelled else { return }
                self?.finishExternalLoad(
                    mode: mode,
                    presentationID: capturedPresentationID,
                    loadID: loadID,
                    text: text,
                    url: url,
                    errorMessage: nil
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishExternalLoad(
                    mode: mode,
                    presentationID: capturedPresentationID,
                    loadID: loadID,
                    text: nil,
                    url: nil,
                    errorMessage: (error as NSError).localizedDescription
                )
            }
        }
    }

    private func finishExternalLoad(
        mode: MetadataConverterMode,
        presentationID capturedPresentationID: UUID,
        loadID: UUID,
        text: String?,
        url: URL?,
        errorMessage: String?
    ) {
        guard
            capturedPresentationID == presentationID,
            selectedMode == mode,
            externalLoadIDs[mode] == loadID
        else { return }

        externalLoadTasks[mode] = nil
        externalLoadIDs[mode] = nil
        guard let text else {
            externalFileError = errorMessage
            return
        }
        externalFileError = nil
        if mode == .csvToMetadata {
            csvImportSource = text
            selectedCSVImportURL = url
        } else {
            textImportSource = text
            selectedTextImportURL = url
        }
        advanceSourceRevision()
        schedulePlanning()
    }

    private func cancelExternalLoad(for mode: MetadataConverterMode) {
        externalLoadIDs[mode] = nil
        externalLoadTasks[mode]?.cancel()
        externalLoadTasks[mode] = nil
    }

    private func cancelExternalLoads() {
        for mode in externalLoadTasks.keys {
            externalLoadTasks[mode]?.cancel()
        }
        externalLoadTasks.removeAll()
        externalLoadIDs.removeAll()
    }

    private func advanceSourceRevision() {
        sourceRevision = UUID()
    }

    // MARK: – Read-only projections consumed by the view

    var targetCount: Int { targetFiles.count }

    var selectionSummaryText: String {
        targetCount == 1 ? "1 selected file" : "\(targetCount) selected files"
    }

    var isPlanning: Bool { planState.isPending }

    /// The current ready result for a mode, or nil while pending/rejected/
    /// superseded. Reading it never recomputes a plan.
    func readyResult(for mode: MetadataConverterMode) -> MetadataFilenameConverterResult? {
        guard case .ready(let inputID, let result) = planState,
              inputID == currentInputID,
              result.mode == mode
        else { return nil }
        return result
    }

    /// The single value every preview/count/gating consumer should display.
    func displayResult(for mode: MetadataConverterMode) -> MetadataFilenameConverterResult {
        readyResult(for: mode) ?? .empty(for: mode)
    }

    /// Stored-plan display accessors. These never build a plan; they only
    /// unwrap the value the store already published for the active input.
    func displayRenamePlan() -> FileRenamePlan {
        displayResult(for: .metadataToFilename).renamePlan
            ?? emptyResult(for: .metadataToFilename)
    }

    func displayFilenameMetadataPlan() -> FilenameMetadataPlan {
        displayResult(for: .filenameToMetadata).filenameMetadataPlan
            ?? emptyFilenameMetadataPlan()
    }

    func displayTextExportPlan() -> MetadataTextExportPlan {
        displayResult(for: .metadataToText).textExportPlan
            ?? MetadataTextExportPlan(validationMessage: nil, rows: [])
    }

    func displayCSVExportPlan() -> MetadataCSVExportPlan {
        displayResult(for: .metadataToCSV).csvExportPlan
            ?? MetadataCSVExportPlan(
                validationMessage: nil,
                columns: [],
                rows: [],
                includeHeaderRow: true,
                delimiter: ","
            )
    }

    func displayImportPlan(for mode: MetadataConverterMode) -> MetadataExchangeImportPlan {
        displayResult(for: mode).textImportPlan
            ?? displayResult(for: mode).csvImportPlan
            ?? displayResult(for: mode).fieldTransferPlan
            ?? MetadataExchangeImportPlan(validationMessage: nil, rows: [])
    }

    private func emptyResult(for mode: MetadataConverterMode) -> FileRenamePlan {
        guard case .rename(let plan) = MetadataFilenameConverterResult.empty(for: mode) else {
            return FileRenamePlan(template: "", validationMessage: nil, rows: [], operations: [])
        }
        return plan
    }

    private func emptyFilenameMetadataPlan() -> FilenameMetadataPlan {
        guard case .filenameMetadata(let plan) = MetadataFilenameConverterResult.empty(for: .filenameToMetadata) else {
            return FilenameMetadataPlan(
                template: "",
                replaceUnderscoresWithSpaces: false,
                validationMessage: nil,
                rows: []
            )
        }
        return plan
    }

    var isPlanRejected: Bool {
        if case .rejected = planState { return true }
        return false
    }

    /// Non-nil when the preview should show a phase message instead of plan
    /// counts: planning is pending or the worker rejected the input.
    func previewPhaseMessage() -> String? {
        switch planState {
        case .idle, .ready:
            return nil
        case .pending:
            return String(localized: "Preparing preview…")
        case .rejected(_, let reason):
            return reason
        }
    }

    // MARK: – Dispatch

    /// Captures the exact currently ready plan for dispatch. An applying,
    /// pending, superseded or non-dispatchable plan returns nil.
    ///
    /// Folder-access requests may pump the run loop (modal panel). Re-verify
    /// presentation, mode, input identity and plan readiness afterward so a
    /// closed, reopened or edited presentation can never dispatch a stale plan.
    func beginDispatch(for mode: MetadataConverterMode) -> MetadataFilenameConverterDispatch? {
        guard !isApplying, !isRequestingScope else { return nil }
        lastScopeRequestError = nil
        guard selectedMode == mode,
              let initialResult = readyResult(for: mode),
              initialResult.isDispatchable else {
            return nil
        }
        let capturedPresentationID = presentationID
        let capturedInputID = currentInputID

        if initialResult.requiresWriteScope, let scopeRequester {
            let urls = initialResult.executableTargetURLs
            guard !urls.isEmpty else { return nil }
            isRequestingScope = true
            let scopeError = scopeRequester(urls)
            isRequestingScope = false

            guard presentationID == capturedPresentationID,
                  currentInputID == capturedInputID,
                  selectedMode == mode,
                  !isApplying else {
                return nil
            }
            if let scopeError {
                lastScopeRequestError = scopeError
                return nil
            }
        }

        guard presentationID == capturedPresentationID,
              currentInputID == capturedInputID,
              selectedMode == mode,
              !isApplying,
              let currentResult = readyResult(for: mode),
              currentResult.isDispatchable else {
            return nil
        }

        let dispatch = MetadataFilenameConverterDispatch(
            id: UUID(),
            presentationID: capturedPresentationID,
            mode: mode,
            result: currentResult
        )
        activeDispatch = dispatch
        isApplying = true
        return dispatch
    }

    /// True when this dispatch still owns the current presentation's apply
    /// lifecycle. An older completion must not clear newer progress or errors.
    func isDispatchCurrent(_ dispatch: MetadataFilenameConverterDispatch) -> Bool {
        activeDispatch?.id == dispatch.id && dispatch.presentationID == presentationID
    }

    /// Completes a dispatch only when it is still the current one for the
    /// current presentation.
    @discardableResult
    func finishDispatch(_ dispatch: MetadataFilenameConverterDispatch) -> Bool {
        guard isDispatchCurrent(dispatch) else { return false }
        activeDispatch = nil
        isApplying = false
        return true
    }

    // MARK: – Planning lifecycle

    private func schedulePlanning() {
        guard selectedMode != nil else {
            cancelAllPlanning()
            return
        }
        resolveTargetsIfNeeded()
        guard let input = makeInputIfNeeded() else { return }

        // A superseded worker is cancelled, but its slot stays occupied until
        // it actually returns; only then may the latest input start.
        workerTask?.cancel()
        latestInput = input
        currentInputID = input.inputID
        activeSignature = input.signature
        planState = .pending(inputID: input.inputID)
        beginDebounce(for: input)
    }

    private func makeInputIfNeeded() -> MetadataFilenamePlannerInput? {
        guard let mode = selectedMode else { return nil }
        let signature = makeSignature(mode: mode)
        if signature == activeSignature {
            switch planState {
            case .pending, .ready:
                return nil
            case .idle, .rejected:
                break
            }
        }
        return MetadataFilenamePlannerInput(
            inputID: UUID(),
            presentationID: presentationID,
            signature: signature,
            mode: mode,
            targets: targetFiles,
            template: template(for: mode),
            replaceUnderscoresWithSpaces: replaceUnderscoresWithSpaces,
            includeCSVHeaderRow: includeCSVHeaderRow,
            firstCSVRowIsHeader: firstCSVRowIsHeader,
            clearBlankImportedValues: clearBlankImportedValues(for: mode),
            sourceText: externalSource(for: mode),
            transferSource: fieldTransferSource,
            transferDestination: fieldTransferDestination,
            transferOperation: fieldTransferOperation,
            projector: projector
        )
    }

    private func makeSignature(mode: MetadataConverterMode) -> MetadataFilenamePlanInputSignature {
        // Scope every mode-specific option to the active mode so mutating an
        // inactive mode's defaults or draft never invalidates or replans the
        // currently displayed mode.
        MetadataFilenamePlanInputSignature(
            presentationID: presentationID,
            mode: mode,
            targets: targetFiles.map {
                MetadataFilenamePlanInputSignature.Target(id: $0.id, snapshotID: $0.snapshotID)
            },
            template: mode == .metadataFieldTransfer ? "" : template(for: mode),
            replaceUnderscoresWithSpaces: mode == .filenameToMetadata ? replaceUnderscoresWithSpaces : false,
            includeCSVHeaderRow: mode == .metadataToCSV ? includeCSVHeaderRow : false,
            firstCSVRowIsHeader: mode == .csvToMetadata ? firstCSVRowIsHeader : false,
            clearBlankImportedValues: (mode == .textToMetadata || mode == .csvToMetadata)
                ? clearBlankImportedValues(for: mode) : false,
            sourceRevision: (mode == .textToMetadata || mode == .csvToMetadata)
                ? sourceRevision : Self.inactiveSourceRevision,
            transferSource: mode == .metadataFieldTransfer ? fieldTransferSource : .title,
            transferDestination: mode == .metadataFieldTransfer ? fieldTransferDestination : .artist,
            transferOperation: mode == .metadataFieldTransfer ? fieldTransferOperation : .copy
        )
    }

    private static let inactiveSourceRevision = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()

    private func beginDebounce(for input: MetadataFilenamePlannerInput) {
        debounceToken = input.inputID
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.clock.sleep(for: self.debounceInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.debounceElapsed(token: input.inputID)
        }
    }

    private func debounceElapsed(token: UUID) {
        guard debounceToken == token else { return }
        debounceTask = nil
        startWorkerIfIdle()
        notifySettlementIfQuiescent()
    }

    private func startWorkerIfIdle() {
        guard workerTask == nil, let input = latestInput else { return }
        latestInput = nil
        workerTask = Task { [weak self, worker] in
            let outcome: Result<MetadataFilenameConverterResult, Error>
            do {
                try Task.checkCancellation()
                outcome = .success(try await worker.makePlan(input))
            } catch {
                outcome = .failure(error)
            }
            self?.completeWorker(input: input, outcome: outcome)
        }
    }

    private func completeWorker(
        input: MetadataFilenamePlannerInput,
        outcome: Result<MetadataFilenameConverterResult, Error>
    ) {
        workerTask = nil
        applyCompletion(
            inputID: input.inputID,
            presentationID: input.presentationID,
            mode: input.mode,
            outcome: outcome
        )
        startWorkerIfIdle()
        notifySettlementIfQuiescent()
    }

    /// The single acceptance guard. Compares the captured presentation, input
    /// and mode identity before publishing, so a stale completion — including a
    /// worker that ignored cancellation — cannot replace the current result.
    private func applyCompletion(
        inputID: UUID,
        presentationID: UUID,
        mode: MetadataConverterMode,
        outcome: Result<MetadataFilenameConverterResult, Error>
    ) {
        guard inputID == currentInputID, presentationID == self.presentationID else { return }
        switch outcome {
        case .success(let result):
            guard result.mode == mode else {
                planState = .rejected(
                    inputID: inputID,
                    reason: String(localized: "This converter returned a result for a different mode. Reopen the tool and try again.")
                )
                return
            }
            planState = .ready(inputID: inputID, result: result)
        case .failure(let error):
            guard !(error is CancellationError) else { return }
            planState = .rejected(inputID: inputID, reason: error.localizedDescription)
        }
    }

    /// Test seam: inject a completion that did not come from the current worker
    /// slot, to exercise the stale-result acceptance guard directly.
    func deliverCompletionForTesting(
        inputID: UUID,
        presentationID: UUID,
        mode: MetadataConverterMode,
        result: MetadataFilenameConverterResult
    ) {
        applyCompletion(
            inputID: inputID,
            presentationID: presentationID,
            mode: mode,
            outcome: .success(result)
        )
    }

    private func cancelAllPlanning() {
        debounceToken = nil
        debounceTask?.cancel()
        debounceTask = nil
        workerTask?.cancel()
        latestInput = nil
        currentInputID = nil
        activeSignature = nil
        planState = .idle
    }

    // MARK: – Test synchronization

    /// Lets tests wait out the debounce without a wall-clock sleep. Only used
    /// with an immediately returning test clock.
    func waitForDebounceResolutionForTesting() async {
        while debounceTask != nil {
            await Task.yield()
        }
    }

    /// Waits until no debounce/worker work remains, so tests never depend on
    /// wall-clock sleeps.
    func waitForPlanSettlement() async {
        guard !isQuiescent else { return }
        await withCheckedContinuation { continuation in
            settlementWaiters.append(continuation)
        }
    }

    private var isQuiescent: Bool {
        debounceTask == nil && workerTask == nil && latestInput == nil
    }

    private func notifySettlementIfQuiescent() {
        guard isQuiescent, !settlementWaiters.isEmpty else { return }
        let waiters = settlementWaiters
        settlementWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: – Test introspection

    var currentInputIDForTesting: UUID? { currentInputID }
    var activeDispatchIDForTesting: UUID? { activeDispatch?.id }
    var debounceIntervalForTesting: Duration { debounceInterval }
    var pendingInputExistsForTesting: Bool { latestInput != nil }
}
