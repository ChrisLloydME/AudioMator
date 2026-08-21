import SwiftUI
#if os(macOS)
import AppKit
#endif

struct iTunesTaggingWorkbenchView: View {
    @ObservedObject var store: iTunesTaggingWorkbenchStore
    @ObservedObject var viewModel: AudioViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false
    @State private var applyTask: Task<Void, Never>?

    var body: some View {
        let plan = store.plan

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
        .modifier(iTunesWorkbenchFrameModifier())
        .background(Color(platformColor: .audiomatorWindowBackground))
        .navigationTitle("Review & Apply Tags")
        .task {
            store.refreshLoadedFiles(viewModel.files)
        }
        .onChange(of: viewModel.files.map(\.middleListContentFingerprint)) { _, _ in
            store.refreshLoadedFiles(viewModel.files)
        }
        .interactiveDismissDisabled(isApplying || viewModel.metadataSaveProgress != nil)
        .overlay {
            if let progress = viewModel.metadataSaveProgress {
                MetadataSaveProgressOverlay(progress: progress)
            }
        }
    }

    private func summarySection(plan: iTunesTaggingPlan) -> some View {
        MetadataSectionCard(title: "Summary", symbolName: "text.badge.checkmark") {
            iTunesSummaryRow(title: "Release", value: summaryAlbumLine)
            MetadataCardDivider()
            iTunesSummaryRow(title: "Selected Fields", value: "\(store.selectedAvailableFields.count)")
            MetadataCardDivider()
            iTunesSummaryRow(title: "Files With Changes", value: "\(plan.filesWithChangesCount)")
            MetadataCardDivider()
            iTunesSummaryRow(title: "Pending Writes", value: "\(plan.changeCount)")

            if plan.unresolvedIssueCount > 0 || store.hasDuplicateTrackAssignments {
                MetadataCardDivider()
                VStack(alignment: .leading, spacing: 8) {
                    if store.hasDuplicateTrackAssignments {
                        iTunesWarningLabel(
                            text: "Some iTunes tracks are assigned to more than one file."
                        )
                    }
                    if plan.unresolvedIssueCount > 0 {
                        iTunesWarningLabel(
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
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Choose exactly which iTunes values should overwrite the current file tags.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    fieldSelectionActions
                }

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

    private var fieldSelectionActions: some View {
        HStack(spacing: 8) {
            Button("Select All") {
                store.selectAllAvailableFields()
            }
            .disabled(isApplying || store.availableFields.isEmpty || store.selectedAvailableFields.count == store.availableFields.count)

            Button("Deselect All") {
                store.deselectAllFields()
            }
            .disabled(isApplying || store.selectedAvailableFields.isEmpty)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    var assignmentSection: some View {
        iTunesAssignmentSection(
            storeID: store.id,
            assignments: store.assignments,
            tracks: store.availableTracks,
            duplicateTrackIDs: store.duplicateTrackIDs,
            isApplying: isApplying,
            onSelectTrack: { trackID, assignmentID in
                store.updateSelectedTrack(trackID, for: assignmentID)
            }
        )
        .equatable()
    }

    private func diffSection(plan: iTunesTaggingPlan) -> some View {
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
                    iTunesPlanRow(row: row)

                    if index < plan.rows.count - 1 {
                        MetadataCardDivider()
                    }
                }
            }
        }
    }

    private func actionBar(plan: iTunesTaggingPlan) -> some View {
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
            .disabled(isApplying || viewModel.metadataSaveProgress != nil)

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

    private func fieldBinding(_ field: iTunesTagWriteField) -> Binding<Bool> {
        Binding(
            get: { store.isFieldSelected(field) },
            set: { store.setFieldSelected($0, for: field) }
        )
    }

    private func applyTags(plan: iTunesTaggingPlan) {
        let entries = plan.writeEntries
        guard !entries.isEmpty, viewModel.metadataSaveProgress == nil else { return }
        guard applyTask == nil else { return }
        isApplying = true

        applyTask = Task {
            defer {
                isApplying = false
                applyTask = nil
            }
            await viewModel.applyiTunesTaggingPlan(entries)
            guard !Task.isCancelled else { return }
            store.refreshLoadedFiles(viewModel.files)
        }
    }
}

struct iTunesAssignmentSection: View, Equatable {
    let storeID: UUID
    let assignments: [iTunesTaggingWorkbenchStore.AssignmentDraft]
    let tracks: [iTunesTrackResult]
    let duplicateTrackIDs: Set<Int>
    let isApplying: Bool
    let onSelectTrack: (Int?, String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storeID == rhs.storeID &&
            lhs.assignments == rhs.assignments &&
            lhs.tracks == rhs.tracks &&
            lhs.duplicateTrackIDs == rhs.duplicateTrackIDs &&
            lhs.isApplying == rhs.isApplying
    }

    var body: some View {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.trackID, $0) })

        MetadataSectionCard(
            title: "Assignments",
            symbolName: "link",
            lazyContent: {
                #if os(macOS)
                false
                #else
                true
                #endif
            }()
        ) {
            #if os(macOS)
            iTunesAssignmentsAppKitList(
                assignments: assignments,
                tracks: tracks,
                isApplying: isApplying,
                selectedTrackID: { $0.selectedTrackID },
                selectedTrack: { assignment in
                    assignment.selectedTrackID.flatMap { tracksByID[$0] }
                },
                isDuplicate: { assignment in
                    assignment.selectedTrackID.map(duplicateTrackIDs.contains) ?? false
                },
                onSelectTrack: onSelectTrack
            )
            #else
            ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                iTunesAssignmentRow(
                    assignment: assignment,
                    tracks: tracks,
                    isDuplicate: assignment.selectedTrackID.map(duplicateTrackIDs.contains) ?? false,
                    selection: Binding(
                        get: { assignment.selectedTrackID },
                        set: { onSelectTrack($0, assignment.id) }
                    ),
                    selectedTrack: assignment.selectedTrackID.flatMap { tracksByID[$0] }
                )
                .disabled(isApplying)

                if index < assignments.count - 1 {
                    MetadataCardDivider()
                }
            }
            #endif
        }
    }
}

private struct iTunesSummaryRow: View {
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

private struct iTunesWarningLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

private struct iTunesWorkbenchFrameModifier: ViewModifier {
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
private struct iTunesAssignmentsAppKitList: View {
    let assignments: [iTunesTaggingWorkbenchStore.AssignmentDraft]
    let tracks: [iTunesTrackResult]
    let isApplying: Bool
    let selectedTrackID: (iTunesTaggingWorkbenchStore.AssignmentDraft) -> Int?
    let selectedTrack: (iTunesTaggingWorkbenchStore.AssignmentDraft) -> iTunesTrackResult?
    let isDuplicate: (iTunesTaggingWorkbenchStore.AssignmentDraft) -> Bool
    let onSelectTrack: (Int?, String) -> Void

    var body: some View {
        let rows = assignments.map { assignment in
            AssignmentSnapshot(
                assignment: assignment,
                selectedTrackID: selectedTrackID(assignment),
                selectedTrack: selectedTrack(assignment),
                isDuplicate: isDuplicate(assignment)
            )
        }

        OnlineMetadataVirtualizedList(
            rows: rows,
            contentVersion: contentVersion,
            rowID: { AnyHashable($0.id) },
            estimatedRowHeight: { row in
                iTunesWorkbenchAppKitFactory.assignmentRowEstimatedHeight(
                    assignment: row.assignment,
                    selectedTrack: row.selectedTrack,
                    isDuplicate: row.isDuplicate
                )
            },
            rowHeight: { row, width, textHeightCache in
                iTunesWorkbenchAppKitFactory.assignmentRowHeight(
                    assignment: row.assignment,
                    selectedTrack: row.selectedTrack,
                    isDuplicate: row.isDuplicate,
                    width: width,
                    textHeightCache: textHeightCache
                )
            },
            makeRowView: { row in
                iTunesWorkbenchAppKitFactory.assignmentRow(
                    assignment: row.assignment,
                    tracks: tracks,
                    isDuplicate: row.isDuplicate,
                    selectedTrackID: row.selectedTrackID,
                    selectedTrack: row.selectedTrack,
                    isApplying: isApplying,
                    onSelectTrack: { trackID in
                        onSelectTrack(trackID, row.id)
                    }
                )
            }
        )
    }

    private var contentVersion: String {
        ([isApplying ? "applying" : "editing"] + tracks.map {
            [
                String($0.trackID),
                String($0.trackNumber),
                $0.trackName,
                $0.artistName,
                $0.primaryGenreName,
                $0.releaseDate
            ].joined(separator: "\u{1f}")
        }).joined(separator: "\u{1e}")
    }

    private struct AssignmentSnapshot: Identifiable, Equatable {
        let assignment: iTunesTaggingWorkbenchStore.AssignmentDraft
        let selectedTrackID: Int?
        let selectedTrack: iTunesTrackResult?
        let isDuplicate: Bool

        var id: String { assignment.id }
    }
}

private struct iTunesDiffPreviewAppKitList: NSViewRepresentable {
    let rows: [iTunesTaggingPlanRow]

    func makeNSView(context: Context) -> iTunesWorkbenchContainerView {
        iTunesWorkbenchContainerView()
    }

    func updateNSView(_ nsView: iTunesWorkbenchContainerView, context: Context) {
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            views.append(iTunesWorkbenchAppKitFactory.planRow(row))
            if index < rows.count - 1 {
                views.append(iTunesWorkbenchAppKitFactory.divider())
            }
        }
        nsView.replaceArrangedSubviews(with: views)
    }
}

private final class iTunesWorkbenchContainerView: NSView {
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

private enum iTunesWorkbenchAppKitFactory {
    static func assignmentRow(
        assignment: iTunesTaggingWorkbenchStore.AssignmentDraft,
        tracks: [iTunesTrackResult],
        isDuplicate: Bool,
        selectedTrackID: Int?,
        selectedTrack: iTunesTrackResult?,
        isApplying: Bool,
        onSelectTrack: @escaping (Int?) -> Void
    ) -> NSView {
        let selectedOptionIndex = selectedTrackID.flatMap { selectedID in
            tracks.firstIndex { $0.trackID == selectedID }
        }
        let values = OnlineMetadataWorkbenchPopUpMapping.selectionValues(for: tracks.map(\.trackID))
        return OnlineMetadataAssignmentRowView(
            rowID: AnyHashable(assignment.id),
            title: assignment.fileInput.preferredDisplayTitle,
            subtitle: fileSubtitle(for: assignment),
            detailLines: [
                selectedTrack.map(trackDetailLine),
                assignment.initialReason.flatMap { $0.isEmpty ? nil : "Auto-match: \($0)" }
            ].compactMap { $0 },
            warning: isDuplicate ? "This iTunes track is assigned to more than one file." : nil,
            optionTitles: tracks.map(trackOptionTitle),
            selectedOptionIndex: selectedOptionIndex,
            isEnabled: !isApplying
        ) { index in
            guard values.indices.contains(index) else { return }
            onSelectTrack(values[index])
        }
    }

    static func assignmentRowHeight(
        assignment: iTunesTaggingWorkbenchStore.AssignmentDraft,
        selectedTrack: iTunesTrackResult?,
        isDuplicate: Bool,
        width: CGFloat,
        textHeightCache: OnlineMetadataTextHeightCache
    ) -> CGFloat {
        let selectedTrackDetail: String?
        if let selectedTrack {
            selectedTrackDetail = trackDetailLine(for: selectedTrack)
        } else {
            selectedTrackDetail = nil
        }
        return OnlineMetadataAssignmentRowLayout.height(
            width: width,
            title: assignment.fileInput.preferredDisplayTitle,
            subtitle: fileSubtitle(for: assignment),
            detailLines: [
                selectedTrackDetail,
                assignment.initialReason.flatMap { $0.isEmpty ? nil : "Auto-match: \($0)" },
                isDuplicate ? "This iTunes track is assigned to more than one file." : nil
            ].compactMap { $0 },
            textHeightCache: textHeightCache
        )
    }

    static func assignmentRowEstimatedHeight(
        assignment: iTunesTaggingWorkbenchStore.AssignmentDraft,
        selectedTrack: iTunesTrackResult?,
        isDuplicate: Bool
    ) -> CGFloat {
        let detailLineCount = (selectedTrack == nil ? 0 : 1)
            + ((assignment.initialReason?.isEmpty == false) ? 1 : 0)
            + (isDuplicate ? 1 : 0)
        return OnlineMetadataAssignmentRowLayout.estimatedHeight(
            hasSubtitle: !fileSubtitle(for: assignment).isEmpty,
            detailLineCount: detailLineCount
        )
    }

    static func planRow(_ row: iTunesTaggingPlanRow) -> NSView {
        let group = verticalStack(spacing: 0)
        let titleViews: [NSView] = [
            label(row.file?.url.lastPathComponent ?? row.fileInput.preferredDisplayTitle, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor),
            subtitleView(for: row)
        ].compactMap { $0 }
        let titleStack = verticalStack(spacing: 4, views: titleViews)

        var headerViews: [NSView] = [titleStack, spacer()]
        if let entry = row.writeEntry {
            headerViews.append(label("\(entry.values.count) change\(entry.values.count == 1 ? "" : "s")", font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor))
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
                addFullWidthArrangedSubview(planChangeRow(change), to: group)
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

    private static func planChangeRow(_ change: iTunesTaggingFieldChange) -> NSView {
        let localLabel = valueLabel(change.localValue.isEmpty ? "-" : change.localValue, color: change.localValue.isEmpty ? .secondaryLabelColor.withAlphaComponent(0.55) : .labelColor)
        let remoteLabel = valueLabel(change.remoteValue.isEmpty ? "-" : change.remoteValue, color: change.remoteValue.isEmpty ? .secondaryLabelColor.withAlphaComponent(0.55) : .labelColor)

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

    private static func subtitleView(for row: iTunesTaggingPlanRow) -> NSView? {
        if let issue = row.issueMessage {
            return label(issue, font: .systemFont(ofSize: 11), color: .systemOrange)
        }

        guard let track = row.track else { return nil }
        return label("iTunes: \(track.trackNumber > 0 ? "\(track.trackNumber) " : "")\(track.trackName)", font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
    }

    nonisolated private static func trackOptionTitle(_ track: iTunesTrackResult) -> String {
        let number = track.trackNumber > 0 ? "\(track.trackNumber) " : ""
        let discPrefix = track.discCount > 1 ? "Disc \(track.discNumber) • " : ""
        return discPrefix + number + track.trackName
    }

    nonisolated private static func trackDetailLine(for track: iTunesTrackResult) -> String {
        [track.artistName, track.primaryGenreName, track.releaseDate].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private static func fileSubtitle(for assignment: iTunesTaggingWorkbenchStore.AssignmentDraft) -> String {
        [assignment.fileInput.artist, assignment.fileInput.album].filter { !$0.isEmpty }.joined(separator: " • ")
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

private extension iTunesTaggingFieldChange.Status {
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

private struct iTunesAssignmentRow: View {
    let assignment: iTunesTaggingWorkbenchStore.AssignmentDraft
    let tracks: [iTunesTrackResult]
    let isDuplicate: Bool
    let selection: Binding<Int?>
    let selectedTrack: iTunesTrackResult?

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

    private func trackOptionTitle(_ track: iTunesTrackResult) -> String {
        let number = track.trackNumber > 0 ? "\(track.trackNumber) " : ""
        let discPrefix = track.discCount > 1 ? "Disc \(track.discNumber) • " : ""
        return discPrefix + number + track.trackName
    }

    private func trackDetailLine(for track: iTunesTrackResult) -> String {
        [track.artistName, track.primaryGenreName, track.releaseDate].filter { !$0.isEmpty }.joined(separator: " • ")
    }
}

private struct iTunesPlanRow: View {
    let row: iTunesTaggingPlanRow

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
                    iTunesPlanChangeRow(change: change)
                    if index < row.changes.count - 1 {
                        Divider().padding(.leading, 18)
                    }
                }
            }
        }
    }
}

private struct iTunesPlanChangeRow: View {
    let change: iTunesTaggingFieldChange

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
