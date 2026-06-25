import SwiftUI

struct ITunesTaggingWorkbenchView: View {
    @ObservedObject var store: ITunesTaggingWorkbenchStore
    @ObservedObject var viewModel: AudioViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false

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
        .modifier(ITunesWorkbenchFrameModifier())
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

    private func summarySection(plan: ITunesTaggingPlan) -> some View {
        MetadataSectionCard(title: "Summary", symbolName: "text.badge.checkmark") {
            ITunesSummaryRow(title: "Release", value: summaryAlbumLine)
            MetadataCardDivider()
            ITunesSummaryRow(title: "Selected Fields", value: "\(store.selectedAvailableFields.count)")
            MetadataCardDivider()
            ITunesSummaryRow(title: "Files With Changes", value: "\(plan.filesWithChangesCount)")
            MetadataCardDivider()
            ITunesSummaryRow(title: "Pending Writes", value: "\(plan.changeCount)")

            if plan.unresolvedIssueCount > 0 || store.hasDuplicateTrackAssignments {
                MetadataCardDivider()
                VStack(alignment: .leading, spacing: 8) {
                    if store.hasDuplicateTrackAssignments {
                        ITunesWarningLabel(
                            text: "Some iTunes tracks are assigned to more than one file."
                        )
                    }
                    if plan.unresolvedIssueCount > 0 {
                        ITunesWarningLabel(
                            text: "\(plan.unresolvedIssueCount) file(s) cannot be written until they are assigned to an iTunes track and remain loaded."
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
                Text("Choose exactly which iTunes values should overwrite the current file tags.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var assignmentSection: some View {
        MetadataSectionCard(title: "Assignments", symbolName: "link", lazyContent: true) {
            ForEach(Array(store.assignments.enumerated()), id: \.element.id) { index, assignment in
                ITunesAssignmentRow(
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

    private func diffSection(plan: ITunesTaggingPlan) -> some View {
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
                    ITunesPlanRow(row: row)

                    if index < plan.rows.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }

    private func actionBar(plan: ITunesTaggingPlan) -> some View {
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

    private var summaryAlbumLine: String {
        [store.detail.album.collectionName, store.detail.album.artistName, store.detail.album.releaseDate]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func fieldBinding(_ field: ITunesTagWriteField) -> Binding<Bool> {
        Binding(
            get: { store.isFieldSelected(field) },
            set: { store.setFieldSelected($0, for: field) }
        )
    }

    private func trackSelectionBinding(for assignment: ITunesTaggingWorkbenchStore.AssignmentDraft) -> Binding<Int?> {
        Binding(
            get: { store.selectedTrackID(for: assignment.id) },
            set: { store.updateSelectedTrack($0, for: assignment.id) }
        )
    }

    private func applyTags(plan: ITunesTaggingPlan) {
        let entries = plan.writeEntries
        guard !entries.isEmpty, viewModel.metadataSaveProgress == nil else { return }

        Task {
            isApplying = true
            await viewModel.applyITunesTaggingPlan(entries)
            store.refreshLoadedFiles(viewModel.files)
            isApplying = false
        }
    }
}

private struct ITunesSummaryRow: View {
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

private struct ITunesWarningLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

private struct ITunesWorkbenchFrameModifier: ViewModifier {
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

private struct ITunesAssignmentRow: View {
    let assignment: ITunesTaggingWorkbenchStore.AssignmentDraft
    let tracks: [ITunesTrackResult]
    let isDuplicate: Bool
    let selection: Binding<Int?>
    let selectedTrack: ITunesTrackResult?

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
                    selectionValue: \.trackID,
                    optionTitle: trackOptionTitle
                )
                .frame(width: 380, alignment: .trailing)
            }

            if let selectedTrack {
                Text(trackDetailLine(for: selectedTrack))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let reason = assignment.initialReason, !reason.isEmpty {
                Text("Auto-match: \(reason)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if isDuplicate {
                Label("This iTunes track is assigned to more than one file.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var fileSubtitle: String {
        [assignment.fileInput.artist, assignment.fileInput.album].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private func trackOptionTitle(_ track: ITunesTrackResult) -> String {
        let number = track.trackNumber > 0 ? "\(track.trackNumber) " : ""
        let discPrefix = track.discCount > 1 ? "Disc \(track.discNumber) • " : ""
        return discPrefix + number + track.trackName
    }

    private func trackDetailLine(for track: ITunesTrackResult) -> String {
        [track.artistName, track.primaryGenreName, track.releaseDate].filter { !$0.isEmpty }.joined(separator: " • ")
    }
}

private struct ITunesPlanRow: View {
    let row: ITunesTaggingPlanRow

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.file?.url.lastPathComponent ?? row.fileInput.preferredDisplayTitle)
                        .font(.system(size: 13, weight: .semibold))

                    if let issue = row.issueMessage {
                        Text(issue)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    } else if let track = row.track {
                        Text("iTunes: \(track.trackNumber > 0 ? "\(track.trackNumber) " : "")\(track.trackName)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                if let entry = row.writeEntry {
                    Text("\(entry.values.count) change\(entry.values.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, row.changes.isEmpty ? 14 : 12)

            if !row.changes.isEmpty {
                Divider().padding(.leading, 18)
                ForEach(Array(row.changes.enumerated()), id: \.element.id) { index, change in
                    ITunesPlanChangeRow(change: change)
                    if index < row.changes.count - 1 {
                        Divider().padding(.leading, 18)
                    }
                }
            }
        }
    }
}

private struct ITunesPlanChangeRow: View {
    let change: ITunesTaggingFieldChange

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

            valueView(change.remoteValue)

            if change.willWrite {
                Text("Write")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var statusSymbolName: String {
        switch change.status {
        case .same: return "checkmark.circle.fill"
        case .different: return "arrow.left.arrow.right.circle.fill"
        case .missingLocal: return "square.and.arrow.down.fill"
        case .missingRemote: return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch change.status {
        case .same: return .green
        case .different: return .orange
        case .missingLocal: return .accentColor
        case .missingRemote: return .secondary
        }
    }

    private func valueView(_ value: String) -> some View {
        Text(value.isEmpty ? "-" : value)
            .font(.system(size: 12))
            .foregroundStyle(value.isEmpty ? Color.secondary.opacity(0.55) : Color.primary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
