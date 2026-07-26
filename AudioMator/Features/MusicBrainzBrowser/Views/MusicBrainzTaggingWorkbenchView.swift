import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MusicBrainzTaggingWorkbenchView: View {
    @ObservedObject var store: MusicBrainzTaggingWorkbenchStore
    @ObservedObject var viewModel: AudioViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying: Bool = false
    @State private var applyTask: Task<Void, Never>?

    var body: some View {
        let plan = store.plan

        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    summarySection(plan: plan)
                    fieldSelectionSection
                    assignmentSection
                    diffSection(plan: plan)
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .audiomatorScrollEdgeEffect(.soft, for: .vertical)

            Divider()

            actionBar(plan: plan)
        }
        .modifier(MusicBrainzWorkbenchFrameModifier())
        .background(Color(platformColor: .audiomatorWindowBackground))
        .navigationTitle("Review & Apply Tags")
        .task {
            store.refreshLoadedFiles(viewModel.files)
        }
        .onChange(of: viewModel.files.map(\.middleListContentFingerprint)) { _, _ in
            store.refreshLoadedFiles(viewModel.files)
        }
        .onDisappear {
            applyTask?.cancel()
            applyTask = nil
            isApplying = false
            store.cancelPendingRecordingLoads()
        }
        .overlay {
            if let progress = viewModel.metadataSaveProgress {
                MetadataSaveProgressOverlay(progress: progress)
            }
        }
    }

    private func summarySection(plan: MusicBrainzTaggingPlan) -> some View {
        MetadataSectionCard(title: "Summary", symbolName: "text.badge.checkmark") {
            SummaryRow(
                title: "Release",
                value: summaryReleaseLine
            )
            MetadataCardDivider()
            SummaryRow(
                title: "Selected Fields",
                value: store.isLoadingFieldAvailability ? "Loading" : "\(store.selectedAvailableFields.count)"
            )
            MetadataCardDivider()
            SummaryRow(
                title: "Files With Changes",
                value: "\(plan.filesWithChangesCount)"
            )
            MetadataCardDivider()
            SummaryRow(
                title: "Pending Writes",
                value: "\(plan.changeCount)"
            )

            if plan.unresolvedIssueCount > 0 || store.hasDuplicateTrackAssignments || store.hasPendingRecordingLoads || store.recordingFailureCount > 0 {
                MetadataCardDivider()

                VStack(alignment: .leading, spacing: 8) {
                    if store.hasDuplicateTrackAssignments {
                        WarningLabel(
                            text: "Some MusicBrainz tracks are assigned to more than one file."
                        )
                    }

                    if store.hasPendingRecordingLoads {
                        WarningLabel(
                            text: "MusicBrainz recording details are still loading. Applying is disabled until they finish."
                        )
                    }

                    if store.recordingFailureCount > 0 {
                        WarningLabel(
                            text: "Some recording-detail lookups failed. Those fields will keep their current file tags."
                        )
                    }

                    if plan.unresolvedIssueCount > 0 {
                        WarningLabel(
                            text: "\(plan.unresolvedIssueCount) file(s) cannot be written until they are assigned to a MusicBrainz track and remain loaded."
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    private var fieldSelectionSection: some View {
        MetadataSectionCard(title: "Fields", symbolName: "checklist.checked") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Choose exactly which MusicBrainz values should overwrite the current file tags.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    fieldSelectionActions
                }

                if store.isLoadingFieldAvailability {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)

                            Text("Loading MusicBrainz fields…")
                                .font(.system(size: 13, weight: .medium))
                        }

                        if store.recordingPreloadTotalCount > 0 {
                            ProgressView(
                                value: Double(store.recordingPreloadCompletedCount),
                                total: Double(store.recordingPreloadTotalCount)
                            )

                            Text("\(store.recordingPreloadCompletedCount) of \(store.recordingPreloadTotalCount) recording details loaded")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 360, alignment: .leading)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(store.availableFields) { field in
                            Toggle(isOn: fieldBinding(field)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.displayName)
                                        .font(.system(size: 13, weight: .medium))

                                    Text(field.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif
                            .disabled(isApplying)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var fieldSelectionActions: some View {
        HStack(spacing: 8) {
            Button("Select All") {
                store.selectAllAvailableFields()
            }
            .disabled(isApplying || store.isLoadingFieldAvailability || store.availableFields.isEmpty || store.selectedAvailableFields.count == store.availableFields.count)

            Button("Deselect All") {
                store.deselectAllFields()
            }
            .disabled(isApplying || store.selectedAvailableFields.isEmpty)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var assignmentSection: some View {
        MetadataSectionCard(title: "Assignments", symbolName: "link", lazyContent: true) {
            ForEach(Array(store.assignments.enumerated()), id: \.element.id) { index, assignment in
                AssignmentEditorRow(
                    assignment: assignment,
                    tracks: store.availableTracks,
                    isDuplicate: store.isDuplicateAssignment(assignment),
                    selection: trackSelectionBinding(for: assignment),
                    selectedTrack: store.track(for: assignment)
                )
                .disabled(isApplying)

                if index < store.assignments.count - 1 {
                    MetadataCardDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func diffSection(plan: MusicBrainzTaggingPlan) -> some View {
        MetadataSectionCard(title: "Diff Preview", symbolName: "arrow.left.arrow.right", lazyContent: true) {
            if plan.rows.isEmpty {
                ContentUnavailableView(
                    "Nothing to Preview",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Choose fields and assignments to generate a write plan.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ForEach(Array(plan.rows.enumerated()), id: \.element.id) { index, row in
                    PlanRowView(
                        row: row,
                        recordingState: recordingState(for: row)
                    )

                    if index < plan.rows.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }

    private func actionBar(plan: MusicBrainzTaggingPlan) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let reason = store.applyDisabledReason(using: plan) {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                applyTags(plan: plan)
            } label: {
                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 92)
                } else {
                    Text("Apply Tags")
                        .frame(minWidth: 92)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(isApplying || viewModel.metadataSaveProgress != nil || !store.canApply(using: plan))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var summaryReleaseLine: String {
        [store.release.title, store.release.artistCredit, store.release.date]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func fieldBinding(_ field: MusicBrainzTagWriteField) -> Binding<Bool> {
        Binding(
            get: { store.isFieldSelected(field) },
            set: { store.setFieldSelected($0, for: field) }
        )
    }

    private func trackSelectionBinding(
        for assignment: MusicBrainzTaggingWorkbenchStore.AssignmentDraft
    ) -> Binding<String?> {
        Binding(
            get: { store.selectedTrackID(for: assignment.id) },
            set: { store.updateSelectedTrack($0, for: assignment.id) }
        )
    }

    private func recordingState(for row: MusicBrainzTaggingPlanRow) -> MusicBrainzTaggingWorkbenchStore.RecordingLookupState? {
        guard let track = row.track, row.changes.contains(where: { $0.field.requiresRecordingDetail }) else {
            return nil
        }

        return store.recordingState(for: track.recordingID)
    }

    private func applyTags(plan: MusicBrainzTaggingPlan) {
        let entries = plan.writeEntries
        guard !entries.isEmpty, viewModel.metadataSaveProgress == nil else { return }
        guard applyTask == nil else { return }
        isApplying = true

        applyTask = Task {
            defer {
                isApplying = false
                applyTask = nil
            }
            await viewModel.applyMusicBrainzTaggingPlan(entries)
            guard !Task.isCancelled else { return }
            store.refreshLoadedFiles(viewModel.files)
        }
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 140, alignment: .leading)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 620, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}

private struct WarningLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

private struct MusicBrainzWorkbenchFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #else
        content
            .frame(
                minWidth: 920,
                idealWidth: 960,
                maxWidth: 1100,
                minHeight: 600,
                idealHeight: 640,
                maxHeight: 820
            )
        #endif
    }
}

#if os(macOS)
private struct MusicBrainzAssignmentsAppKitList: NSViewRepresentable {
    let assignments: [MusicBrainzTaggingWorkbenchStore.AssignmentDraft]
    let tracks: [MusicBrainzReleaseMatchTrack]
    let isApplying: Bool
    let selectedTrackID: (MusicBrainzTaggingWorkbenchStore.AssignmentDraft) -> String?
    let selectedTrack: (MusicBrainzTaggingWorkbenchStore.AssignmentDraft) -> MusicBrainzReleaseMatchTrack?
    let isDuplicate: (MusicBrainzTaggingWorkbenchStore.AssignmentDraft) -> Bool
    let onSelectTrack: (String?, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MusicBrainzWorkbenchContainerView {
        MusicBrainzWorkbenchContainerView()
    }

    func updateNSView(_ nsView: MusicBrainzWorkbenchContainerView, context: Context) {
        context.coordinator.parent = self
        let snapshot = Snapshot(
            assignments: assignments.map { assignment in
                AssignmentSnapshot(
                    id: assignment.id,
                    displayTitle: assignment.fileInput.preferredDisplayTitle,
                    artist: assignment.fileInput.artist,
                    album: assignment.fileInput.album,
                    initialReason: assignment.initialReason,
                    selectedTrackID: selectedTrackID(assignment),
                    isDuplicate: isDuplicate(assignment)
                )
            },
            tracks: tracks.map { track in
                TrackSnapshot(
                    id: track.id,
                    number: track.number,
                    title: track.title,
                    artistCredit: track.artistCredit,
                    mediumTitle: track.mediumTitle,
                    mediumFormat: track.mediumFormat,
                    mediumPosition: track.mediumPosition,
                    releaseMediumCount: track.releaseMediumCount
                )
            },
            isApplying: isApplying
        )
        guard snapshot != context.coordinator.lastSnapshot else { return }
        context.coordinator.lastSnapshot = snapshot

        var views: [NSView] = []
        for (index, assignment) in assignments.enumerated() {
            views.append(MusicBrainzWorkbenchAppKitFactory.assignmentRow(
                assignment: assignment,
                tracks: tracks,
                isDuplicate: isDuplicate(assignment),
                selectedTrackID: selectedTrackID(assignment),
                selectedTrack: selectedTrack(assignment),
                isApplying: isApplying,
                target: context.coordinator,
                action: #selector(Coordinator.selectTrack(_:))
            ))
            if index < assignments.count - 1 {
                views.append(MusicBrainzWorkbenchAppKitFactory.divider())
            }
        }
        nsView.replaceArrangedSubviews(with: views)
    }

    struct Snapshot: Equatable {
        let assignments: [AssignmentSnapshot]
        let tracks: [TrackSnapshot]
        let isApplying: Bool
    }

    struct AssignmentSnapshot: Equatable {
        let id: String
        let displayTitle: String
        let artist: String
        let album: String
        let initialReason: String?
        let selectedTrackID: String?
        let isDuplicate: Bool
    }

    struct TrackSnapshot: Equatable {
        let id: String
        let number: String
        let title: String
        let artistCredit: String
        let mediumTitle: String
        let mediumFormat: String
        let mediumPosition: Int
        let releaseMediumCount: Int
    }

    final class Coordinator: NSObject {
        var parent: MusicBrainzAssignmentsAppKitList
        var lastSnapshot: Snapshot?

        init(parent: MusicBrainzAssignmentsAppKitList) {
            self.parent = parent
        }

        @objc
        func selectTrack(_ sender: MusicBrainzAssignmentPopUpButton) {
            guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < sender.selectionValues.count else { return }
            parent.onSelectTrack(sender.selectionValues[sender.indexOfSelectedItem], sender.assignmentID)
        }
    }
}

private struct MusicBrainzDiffPreviewAppKitList: NSViewRepresentable {
    let rows: [MusicBrainzTaggingPlanRow]
    let recordingState: (MusicBrainzTaggingPlanRow) -> MusicBrainzTaggingWorkbenchStore.RecordingLookupState?

    func makeNSView(context: Context) -> MusicBrainzWorkbenchContainerView {
        MusicBrainzWorkbenchContainerView()
    }

    func updateNSView(_ nsView: MusicBrainzWorkbenchContainerView, context: Context) {
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            views.append(MusicBrainzWorkbenchAppKitFactory.planRow(row, recordingState: recordingState(row)))
            if index < rows.count - 1 {
                views.append(MusicBrainzWorkbenchAppKitFactory.divider())
            }
        }
        nsView.replaceArrangedSubviews(with: views)
    }
}

private final class MusicBrainzWorkbenchContainerView: NSView {
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: stackView.fittingSize.height)
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    func replaceArrangedSubviews(with views: [NSView]) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for view in views {
            stackView.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        invalidateIntrinsicContentSize()
    }
}

private final class MusicBrainzAssignmentPopUpButton: NSPopUpButton {
    let assignmentID: String
    let selectionValues: [String?]

    init(assignmentID: String, selectionValues: [String?]) {
        self.assignmentID = assignmentID
        self.selectionValues = selectionValues
        super.init(frame: .zero, pullsDown: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private enum MusicBrainzWorkbenchAppKitFactory {
    static func assignmentRow(
        assignment: MusicBrainzTaggingWorkbenchStore.AssignmentDraft,
        tracks: [MusicBrainzReleaseMatchTrack],
        isDuplicate: Bool,
        selectedTrackID: String?,
        selectedTrack: MusicBrainzReleaseMatchTrack?,
        isApplying: Bool,
        target: AnyObject,
        action: Selector
    ) -> NSView {
        let titleStack = verticalStack(spacing: 4, views: [
            label(assignment.fileInput.preferredDisplayTitle, font: .systemFont(ofSize: 13, weight: .medium), color: .labelColor),
            fileSubtitle(for: assignment).isEmpty ? nil : label(fileSubtitle(for: assignment), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        ].compactMap { $0 })

        let popUp = assignmentPopUp(
            assignmentID: assignment.id,
            tracks: tracks,
            selectedTrackID: selectedTrackID,
            isEnabled: !isApplying,
            target: target,
            action: action
        )
        popUp.widthAnchor.constraint(equalToConstant: 380).isActive = true

        let group = verticalStack(spacing: 10)
        addFullWidthArrangedSubview(horizontalStack(spacing: 18, alignment: .top, views: [
            titleStack,
            spacer(),
            popUp
        ]), to: group)

        if let selectedTrack {
            addFullWidthArrangedSubview(label(trackDetailLine(for: selectedTrack), font: .systemFont(ofSize: 11), color: .secondaryLabelColor), to: group)
        }

        if let initialReason = assignment.initialReason, !initialReason.isEmpty {
            addFullWidthArrangedSubview(label("Auto-match: \(initialReason)", font: .systemFont(ofSize: 11), color: .secondaryLabelColor), to: group)
        }

        if isDuplicate {
            addFullWidthArrangedSubview(iconText("This MusicBrainz track is assigned to more than one file.", symbolName: "exclamationmark.triangle.fill", color: .systemOrange), to: group)
        }

        return padded(group, top: 12, left: 18, bottom: 12, right: 18)
    }

    static func planRow(
        _ row: MusicBrainzTaggingPlanRow,
        recordingState: MusicBrainzTaggingWorkbenchStore.RecordingLookupState?
    ) -> NSView {
        let group = verticalStack(spacing: 0)
        let titleViews: [NSView] = [
            label(row.file?.url.lastPathComponent ?? row.fileInput.preferredDisplayTitle, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor),
            subtitleView(for: row)
        ].compactMap { $0 }
        let titleStack = verticalStack(spacing: 4, views: titleViews)

        var headerViews: [NSView] = [titleStack, spacer()]
        if let writeEntry = row.writeEntry {
            headerViews.append(label("\(writeEntry.values.count) change\(writeEntry.values.count == 1 ? "" : "s")", font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor))
        }

        addFullWidthArrangedSubview(padded(
            horizontalStack(spacing: 18, alignment: .top, views: headerViews),
            top: 14,
            left: 18,
            bottom: row.changes.isEmpty ? 14 : 12,
            right: 18
        ), to: group)

        if !row.changes.isEmpty {
            addFullWidthArrangedSubview(divider(), to: group)
            for (index, change) in row.changes.enumerated() {
                addFullWidthArrangedSubview(planChangeRow(
                    change,
                    recordingState: change.field.requiresRecordingDetail ? recordingState : nil
                ), to: group)
                if index < row.changes.count - 1 {
                    addFullWidthArrangedSubview(divider(), to: group)
                }
            }
        }

        return group
    }

    static func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            box.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            box.topAnchor.constraint(equalTo: container.topAnchor),
            box.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static func planChangeRow(
        _ change: MusicBrainzTaggingFieldChange,
        recordingState: MusicBrainzTaggingWorkbenchStore.RecordingLookupState?
    ) -> NSView {
        let remoteValue = remoteDisplayValue(for: change, recordingState: recordingState)
        let localLabel = valueLabel(change.localValue.isEmpty ? "—" : change.localValue, color: change.localValue.isEmpty ? .secondaryLabelColor.withAlphaComponent(0.55) : .labelColor)
        let remoteLabel = valueLabel(remoteValue, color: remoteColor(for: change, displayedValue: remoteValue, recordingState: recordingState))

        var rowViews: [NSView] = [
            label(change.field.displayName, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, width: 118),
            localLabel,
            symbol(change.status.symbolName, color: change.status.nsColor, width: 18),
            remoteLabel
        ]

        if change.willWrite {
            rowViews.append(writeBadge())
        }

        let content = horizontalStack(spacing: 14, alignment: .top, views: rowViews)
        localLabel.widthAnchor.constraint(equalTo: remoteLabel.widthAnchor).isActive = true

        return padded(content, top: 10, left: 18, bottom: 10, right: 18)
    }

    private static func subtitleView(for row: MusicBrainzTaggingPlanRow) -> NSView? {
        if let issueMessage = row.issueMessage {
            return label(issueMessage, font: .systemFont(ofSize: 11), color: .systemOrange)
        }

        guard let track = row.track else { return nil }
        let number = track.number.isEmpty ? "" : "\(track.number) "
        return label("MusicBrainz: \(number)\(track.title)", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
    }

    private static func assignmentPopUp(
        assignmentID: String,
        tracks: [MusicBrainzReleaseMatchTrack],
        selectedTrackID: String?,
        isEnabled: Bool,
        target: AnyObject,
        action: Selector
    ) -> MusicBrainzAssignmentPopUpButton {
        let values = OnlineMetadataWorkbenchPopUpMapping.selectionValues(for: tracks.map(\.id))
        let popUp = MusicBrainzAssignmentPopUpButton(assignmentID: assignmentID, selectionValues: values)
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.controlSize = .regular
        popUp.isEnabled = isEnabled
        popUp.addItem(withTitle: L10n.string("Unassigned"))
        popUp.menu?.addItem(.separator())
        for track in tracks {
            popUp.addItem(withTitle: trackOptionTitle(track))
        }
        if let selectedTrackID, let index = values.firstIndex(of: selectedTrackID) {
            popUp.selectItem(at: index)
        } else {
            popUp.selectItem(at: 0)
        }
        popUp.target = target
        popUp.action = action
        return popUp
    }

    private static func trackOptionTitle(_ track: MusicBrainzReleaseMatchTrack) -> String {
        let number = track.number.isEmpty ? "" : "\(track.number) "
        let discPrefix = track.releaseMediumCount > 1 ? "Disc \(track.mediumPosition) • " : ""
        return discPrefix + number + track.title
    }

    private static func trackDetailLine(for track: MusicBrainzReleaseMatchTrack) -> String {
        [
            track.artistCredit,
            track.mediumFormat.isEmpty ? track.mediumTitle : track.mediumFormat
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private static func fileSubtitle(for assignment: MusicBrainzTaggingWorkbenchStore.AssignmentDraft) -> String {
        [assignment.fileInput.artist, assignment.fileInput.album]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private static func remoteDisplayValue(
        for change: MusicBrainzTaggingFieldChange,
        recordingState: MusicBrainzTaggingWorkbenchStore.RecordingLookupState?
    ) -> String {
        if change.field.requiresRecordingDetail, let recordingState {
            switch recordingState {
            case .loading, .idle:
                return "Loading recording details..."
            case .failed:
                return "Recording lookup failed."
            case .loaded:
                return change.remoteValue.isEmpty ? "—" : change.remoteValue
            }
        }

        return change.remoteValue.isEmpty ? "—" : change.remoteValue
    }

    private static func remoteColor(
        for change: MusicBrainzTaggingFieldChange,
        displayedValue: String,
        recordingState: MusicBrainzTaggingWorkbenchStore.RecordingLookupState?
    ) -> NSColor {
        if displayedValue == "—" {
            if change.field.requiresRecordingDetail, recordingState != nil {
                return .secondaryLabelColor
            }
            return .secondaryLabelColor.withAlphaComponent(0.55)
        }
        return .labelColor
    }

    private static func valueLabel(_ text: String, color: NSColor) -> NSTextField {
        let textField = label(text, font: .systemFont(ofSize: 12), color: color)
        textField.isSelectable = true
        return textField
    }

    private static func label(
        _ text: String,
        font: NSFont,
        color: NSColor,
        width: CGFloat? = nil
    ) -> NSTextField {
        let textField = NSTextField(labelWithString: text)
        textField.font = font
        textField.textColor = color
        textField.backgroundColor = .clear
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.translatesAutoresizingMaskIntoConstraints = false
        if let width {
            textField.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return textField
    }

    private static func symbol(_ name: String, color: NSColor, width: CGFloat) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        imageView.contentTintColor = color
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: width).isActive = true
        imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 13).isActive = true
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return imageView
    }

    private static func iconText(_ text: String, symbolName: String, color: NSColor) -> NSView {
        horizontalStack(spacing: 5, alignment: .centerY, views: [
            symbol(symbolName, color: color, width: 12),
            label(text, font: .systemFont(ofSize: 11), color: color)
        ])
    }

    private static func writeBadge() -> NSView {
        let badge = padded(
            label("Write", font: .systemFont(ofSize: 10, weight: .semibold), color: .controlAccentColor),
            top: 4,
            left: 8,
            bottom: 4,
            right: 8
        )
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        badge.layer?.cornerRadius = 9
        return badge
    }

    private static func padded(
        _ content: NSView,
        top: CGFloat,
        left: CGFloat,
        bottom: CGFloat,
        right: CGFloat
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: left),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -right),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: top),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottom)
        ])
        return container
    }

    private static func horizontalStack(
        spacing: CGFloat,
        alignment: NSLayoutConstraint.Attribute,
        views: [NSView]
    ) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = alignment
        stack.distribution = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func verticalStack(spacing: CGFloat, views: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func addFullWidthArrangedSubview(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private static func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
}

private extension MusicBrainzTaggingFieldChange.Status {
    var symbolName: String {
        switch self {
        case .same:
            return "checkmark.circle.fill"
        case .different:
            return "arrow.left.arrow.right.circle.fill"
        case .missingLocal:
            return "square.and.arrow.down.fill"
        case .missingRemote:
            return "questionmark.circle.fill"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .same:
            return .systemGreen
        case .different:
            return .systemOrange
        case .missingLocal:
            return .controlAccentColor
        case .missingRemote:
            return .secondaryLabelColor
        }
    }
}
#endif

private struct AssignmentEditorRow: View {
    let assignment: MusicBrainzTaggingWorkbenchStore.AssignmentDraft
    let tracks: [MusicBrainzReleaseMatchTrack]
    let isDuplicate: Bool
    let selection: Binding<String?>
    let selectedTrack: MusicBrainzReleaseMatchTrack?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assignment.fileInput.preferredDisplayTitle)
                        .font(.system(size: 13, weight: .medium))

                    if !fileSubtitle.isEmpty {
                        Text(fileSubtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                DeferredSelectionMenu(
                    options: tracks,
                    selection: selection,
                    selectionValue: \.id,
                    optionTitle: trackOptionTitle
                )
                .frame(width: 380, alignment: .trailing)
            }

            if let selectedTrack {
                Text(trackDetailLine(for: selectedTrack))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let initialReason = assignment.initialReason, !initialReason.isEmpty {
                Text("Auto-match: \(initialReason)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if isDuplicate {
                Label("This MusicBrainz track is assigned to more than one file.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var fileSubtitle: String {
        [assignment.fileInput.artist, assignment.fileInput.album]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func trackOptionTitle(_ track: MusicBrainzReleaseMatchTrack) -> String {
        let number = track.number.isEmpty ? "" : "\(track.number) "
        let discPrefix = track.releaseMediumCount > 1 ? "Disc \(track.mediumPosition) • " : ""
        return discPrefix + number + track.title
    }

    private func trackDetailLine(for track: MusicBrainzReleaseMatchTrack) -> String {
        [
            track.artistCredit,
            track.mediumFormat.isEmpty ? track.mediumTitle : track.mediumFormat
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }
}

private struct PlanRowView: View {
    let row: MusicBrainzTaggingPlanRow
    let recordingState: MusicBrainzTaggingWorkbenchStore.RecordingLookupState?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.file?.url.lastPathComponent ?? row.fileInput.preferredDisplayTitle)
                        .font(.system(size: 13, weight: .semibold))

                    if let issueMessage = row.issueMessage {
                        Text(issueMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    } else if let track = row.track {
                        Text(trackHeading(for: track))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                if let writeEntry = row.writeEntry {
                    Text("\(writeEntry.values.count) change\(writeEntry.values.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, row.changes.isEmpty ? 14 : 12)

            if !row.changes.isEmpty {
                Divider()
                    .padding(.leading, 18)

                ForEach(Array(row.changes.enumerated()), id: \.element.id) { index, change in
                    PlanChangeRow(
                        change: change,
                        recordingState: change.field.requiresRecordingDetail ? recordingState : nil
                    )

                    if index < row.changes.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func trackHeading(for track: MusicBrainzReleaseMatchTrack) -> String {
        let number = track.number.isEmpty ? "" : "\(track.number) "
        return "MusicBrainz: \(number)\(track.title)"
    }
}

private struct PlanChangeRow: View {
    let change: MusicBrainzTaggingFieldChange
    let recordingState: MusicBrainzTaggingWorkbenchStore.RecordingLookupState?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(change.field.displayName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            valueView(change.localValue)

            Image(systemName: statusSymbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 18)
                .padding(.top, 1)

            valueView(remoteDisplayValue, isRemote: true)

            if change.willWrite {
                Text("Write")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var remoteDisplayValue: String {
        if change.field.requiresRecordingDetail, let recordingState {
            switch recordingState {
            case .loading:
                return "Loading recording details..."
            case .failed(let message):
                return message.isEmpty ? "Recording lookup failed." : "Recording lookup failed."
            case .idle:
                return "Loading recording details..."
            case .loaded:
                return change.remoteValue
            }
        }

        return change.remoteValue
    }

    private var statusSymbolName: String {
        switch change.status {
        case .same:
            return "checkmark.circle.fill"
        case .different:
            return "arrow.left.arrow.right.circle.fill"
        case .missingLocal:
            return "square.and.arrow.down.fill"
        case .missingRemote:
            return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch change.status {
        case .same:
            return .green
        case .different:
            return .orange
        case .missingLocal:
            return .accentColor
        case .missingRemote:
            return .secondary
        }
    }

    @ViewBuilder
    private func valueView(_ value: String, isRemote: Bool = false) -> some View {
        Text(displayText(for: value, isRemote: isRemote))
            .font(.system(size: 12))
            .foregroundStyle(displayColor(for: value, isRemote: isRemote))
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayText(for value: String, isRemote: Bool) -> String {
        if !value.isEmpty {
            return value
        }

        if isRemote, change.field.requiresRecordingDetail, recordingState != nil {
            return remoteDisplayValue
        }

        return "—"
    }

    private func displayColor(for value: String, isRemote: Bool) -> Color {
        if value.isEmpty {
            if isRemote, change.field.requiresRecordingDetail, recordingState != nil {
                return .secondary
            }
            return .secondary.opacity(0.55)
        }

        return .primary
    }
}
