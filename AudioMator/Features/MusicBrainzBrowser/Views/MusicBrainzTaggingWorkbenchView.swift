import SwiftUI

struct MusicBrainzTaggingWorkbenchView: View {
    @ObservedObject var store: MusicBrainzTaggingWorkbenchStore
    @ObservedObject var viewModel: AudioViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    summarySection
                    fieldSelectionSection
                    assignmentSection
                    diffSection
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .audiomatorScrollEdgeEffect(.soft, for: .vertical)

            Divider()

            actionBar
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
        .overlay {
            if let progress = viewModel.metadataSaveProgress {
                MetadataSaveProgressOverlay(progress: progress)
            }
        }
    }

    private var summarySection: some View {
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
                value: "\(store.plan.filesWithChangesCount)"
            )
            MetadataCardDivider()
            SummaryRow(
                title: "Pending Writes",
                value: "\(store.plan.changeCount)"
            )

            if store.plan.unresolvedIssueCount > 0 || store.hasDuplicateTrackAssignments || store.hasPendingRecordingLoads || store.recordingFailureCount > 0 {
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

                    if store.plan.unresolvedIssueCount > 0 {
                        WarningLabel(
                            text: "\(store.plan.unresolvedIssueCount) file(s) cannot be written until they are assigned to a MusicBrainz track and remain loaded."
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
                Text("Choose exactly which MusicBrainz values should overwrite the current file tags.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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

    private var assignmentSection: some View {
        MetadataSectionCard(title: "Assignments", symbolName: "link") {
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
    private var diffSection: some View {
        MetadataSectionCard(title: "Diff Preview", symbolName: "arrow.left.arrow.right") {
            if store.plan.rows.isEmpty {
                ContentUnavailableView(
                    "Nothing to Preview",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Choose fields and assignments to generate a write plan.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ForEach(Array(store.plan.rows.enumerated()), id: \.element.id) { index, row in
                    PlanRowView(
                        row: row,
                        recordingState: recordingState(for: row)
                    )

                    if index < store.plan.rows.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(alignment: .center, spacing: 12) {
            if let reason = store.applyDisabledReason {
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
                applyTags()
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
            .disabled(isApplying || viewModel.metadataSaveProgress != nil || !store.canApply)
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

    private func applyTags() {
        let entries = store.plan.writeEntries
        guard !entries.isEmpty, viewModel.metadataSaveProgress == nil else { return }

        Task {
            isApplying = true
            await viewModel.applyMusicBrainzTaggingPlan(entries)
            store.refreshLoadedFiles(viewModel.files)
            isApplying = false
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

                Picker("Track", selection: selection) {
                    Text("Unassigned").tag(String?.none)

                    ForEach(tracks) { track in
                        Text(trackOptionTitle(track))
                            .tag(String?.some(track.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
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
        VStack(alignment: .leading, spacing: 0) {
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
