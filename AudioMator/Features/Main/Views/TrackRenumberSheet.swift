import SwiftUI

struct TrackRenumberSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    @Binding var isPresented: Bool
    @Binding var trackRenumberOptions: TrackRenumberOptions
    @Binding var trackRenumberStartText: String
    @Binding var isTrackRenumberRunning: Bool
    @Binding var trackRenumberResult: TrackRenumberResult

    /// The exact reviewed plan the preview displays and Apply submits. It is
    /// rebuilt when the resolved order, selection, direction or start entry
    /// changes; Apply never reconstructs a sequence from the live file collection.
    @State private var plan: TrackRenumberPlan = .empty
    @State private var planNotice: String?

    private let cardInset: CGFloat = 16
    private let previewInnerRadius: CGFloat = 12
    private let setupSectionInset: CGFloat = 10
    private let contentInset: CGFloat = 20

    private var setupSectionRadius: CGFloat {
        previewInnerRadius + setupSectionInset
    }

    /// Middle-list order resolved exactly as the center list displays it.
    private var currentOrderedFiles: [AudioFile] {
        state.orderedMiddleListFiles(from: viewModel.files)
    }

    private var executableNumbers: [Int] {
        plan.executableRows.compactMap(\.assignedNumber)
    }

    private var startNumberBinding: Binding<Int> {
        Binding(
            get: { plan.startNumber ?? defaultTrackRenumberStartNumber },
            set: { newValue in
                let value = min(max(newValue, minimumTrackRenumberStartNumber), maximumTrackRenumberStartNumber)
                trackRenumberStartText = String(value)
            }
        )
    }

    private var previewSequenceText: String {
        guard !plan.rows.isEmpty else { return L10n.string("No tracks selected") }
        guard !executableNumbers.isEmpty else {
            return plan.unchangedCount > 0
                ? L10n.string("Already numbered")
                : L10n.string("No changes")
        }

        let visibleNumbers = executableNumbers.prefix(3).map(String.init)
        if executableNumbers.count <= 3 {
            return visibleNumbers.joined(separator: ", ")
        }
        return "\(visibleNumbers.joined(separator: ", "))..."
    }

    private var previewRangeText: String {
        if let validationMessage = plan.validationMessage {
            return validationMessage
        }
        guard let first = executableNumbers.first, let last = executableNumbers.last else {
            if plan.unchangedCount > 0, plan.executableCount == 0 {
                return L10n.string("Every numbered track already has the previewed number.")
            }
            return L10n.string("Add files to preview the new numbers.")
        }
        let scope = viewModel.selectedAudioIDs.isEmpty ? "current list" : "selection"
        return "\(plan.executableCount) tracks in the \(scope) will be renumbered from \(first) to \(last)."
    }

    private var planSummaryText: String {
        var parts: [String] = []
        if plan.executableCount > 0 {
            parts.append(String(localized: "\(plan.executableCount) to update"))
        }
        if plan.unchangedCount > 0 {
            parts.append(String(localized: "\(plan.unchangedCount) already correct"))
        }
        if plan.skippedUnsupportedCount > 0 {
            parts.append(String(localized: "\(plan.skippedUnsupportedCount) skipped"))
        }
        if plan.skippedDuplicateCount > 0 {
            parts.append(String(localized: "\(plan.skippedDuplicateCount) duplicate"))
        }
        if plan.failedRowCount > 0 {
            parts.append(String(localized: "\(plan.failedRowCount) blocked"))
        }
        return parts.isEmpty ? L10n.string("No tracks selected") : parts.joined(separator: " · ")
    }

    private var selectionSummaryText: String {
        if viewModel.selectedAudioIDs.isEmpty {
            return L10n.string("Current list")
        }

        return "\(plan.totalTargets) selected tracks"
    }

    private var selectionDetailText: String {
        viewModel.selectedAudioIDs.isEmpty
            ? "Uses the order shown in the center list."
            : "Uses the selected rows in center-list order."
    }

    private var canApply: Bool {
        !isTrackRenumberRunning && plan.isStartValid && plan.executableCount > 0
    }

    private var footerStatusText: String? {
        if plan.isStartValid == false {
            return plan.validationMessage
        }
        guard plan.executableCount == 0 else { return nil }
        if plan.totalTargets == 0 {
            return L10n.string("Add files to renumber track numbers.")
        }
        if plan.unchangedCount > 0 {
            return L10n.string("Every numbered track already has the previewed number.")
        }
        return L10n.string("No selected track can be renumbered.")
    }

    private var hasResult: Bool {
        trackRenumberResult.totalTargets > 0 ||
            trackRenumberResult.failed > 0 ||
            trackRenumberResult.unchanged > 0 ||
            trackRenumberResult.skippedUnsupported > 0 ||
            trackRenumberResult.skippedDuplicate > 0 ||
            trackRenumberResult.validationMessage != nil ||
            !trackRenumberResult.warnings.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                configurationSection

                if !plan.isStartValid {
                    invalidStartNotice
                }

                if !plan.issueRows.isEmpty {
                    planIssuesSection
                }

                if let planNotice, !isTrackRenumberRunning {
                    Text(planNotice)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                if hasResult {
                    resultSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentInset)
            .padding(.top, contentInset)
            .padding(.bottom, contentInset)
        }
        .onAppear { rebuildPlan() }
        .onChange(of: trackRenumberOptions.direction) { _, _ in rebuildPlan() }
        .onChange(of: trackRenumberStartText) { _, _ in rebuildPlan() }
        .onChange(of: viewModel.selectedAudioIDs) { _, _ in rebuildPlan() }
        .onChange(of: viewModel.files.map(\.snapshotID)) { _, _ in rebuildPlan() }
        .audiomatorSafeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 640, height: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Renumber Track Numbers")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if isTrackRenumberRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Renumber tracks using the order shown in the center list. Select rows first to renumber only those tracks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label(selectionSummaryText, systemImage: viewModel.selectedAudioIDs.isEmpty ? "music.note.list" : "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
                Text(planSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                HStack(alignment: .top, spacing: 16) {
                    configurationControls
                        .frame(maxWidth: .infinity, alignment: .leading)

                    previewCard
                        .frame(width: 176)
                }
            }
            .padding(setupSectionInset)
            .background(
                RoundedRectangle(cornerRadius: setupSectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var configurationControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            configurationRow(
                title: "Scope",
                caption: selectionDetailText
            ) {
                Text(selectionSummaryText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            configurationRow(
                title: "Direction",
                caption: "Choose whether the first row gets the lowest or highest number."
            ) {
                Picker("", selection: $trackRenumberOptions.direction) {
                    Text("Ascending").tag(TrackRenumberDirection.ascending)
                    Text("Descending").tag(TrackRenumberDirection.descending)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(isTrackRenumberRunning)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                configurationRow(
                    title: "Start number",
                    caption: "A whole number from 1 to 9,999. Numbers are stored as shown."
                ) {
                    HStack(spacing: 8) {
                        TextField(String(defaultTrackRenumberStartNumber), text: $trackRenumberStartText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .disabled(isTrackRenumberRunning)

                        Stepper(
                            "",
                            value: startNumberBinding,
                            in: minimumTrackRenumberStartNumber...maximumTrackRenumberStartNumber
                        )
                        .labelsHidden()
                        .disabled(isTrackRenumberRunning)
                    }
                }

                if let issue = plan.startInput.issue {
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 160)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Preview")
                    .font(.headline)

                Spacer()

                Image(systemName: "number.square.fill")
                    .foregroundStyle(.secondary)
            }

            Text(previewSequenceText)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(2)

            Text(previewRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(plan.direction == .ascending ? "First row gets the lowest number." : "First row gets the highest number.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        .padding(cardInset)
        .background(
            RoundedRectangle(cornerRadius: previewInnerRadius)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var invalidStartNotice: some View {
        Label(
            plan.validationMessage ?? String(localized: "Enter a start number from 1 to 9,999."),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
    }

    private var planIssuesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not Written", systemImage: "arrowshape.turn.up.right.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plan.issueRows.prefix(8).enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.fileName)
                            .font(.system(.body, design: .monospaced))
                        if let message = row.issueMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if plan.issueRows.count > 8 {
                    Text("\(plan.issueRows.count - 8) more rows won’t be written.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(setupSectionInset)
            .background(
                RoundedRectangle(cornerRadius: setupSectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Results", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                if let validationMessage = trackRenumberResult.validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    resultMetric(title: "Targets", value: trackRenumberResult.totalTargets, tint: .primary)
                    resultMetric(title: "Succeeded", value: trackRenumberResult.succeeded, tint: .green)
                    resultMetric(title: "Unchanged", value: trackRenumberResult.unchanged, tint: .blue)
                    resultMetric(title: "Skipped", value: trackRenumberResult.skippedUnsupported, tint: .orange)
                    if trackRenumberResult.skippedDuplicate > 0 {
                        resultMetric(title: "Duplicates", value: trackRenumberResult.skippedDuplicate, tint: .orange)
                    }
                    resultMetric(title: "Failed", value: trackRenumberResult.failed, tint: .red)
                    if !trackRenumberResult.cancelled.isEmpty {
                        resultMetric(title: "Cancelled", value: trackRenumberResult.cancelled.count, tint: .secondary)
                    }
                }

                if !trackRenumberResult.failures.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Files That Couldn't Be Updated"), systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(trackRenumberResult.failures) { failure in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(failure.fileName)
                                            .font(.system(.body, design: .monospaced))
                                        Text(failure.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(cardInset)
                                    .background(
                                        RoundedRectangle(cornerRadius: previewInnerRadius)
                                            .fill(Color.secondary.opacity(0.08))
                                    )
                                }
                            }
                        }
                        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
                        .frame(maxHeight: 150)
                    }
                }

                if !trackRenumberResult.cancelled.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Files Not Processed").font(.headline)
                        ForEach(trackRenumberResult.cancelled) { item in
                            Text(item.fileName).font(.body)
                            Text(item.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if !trackRenumberResult.warnings.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Warnings", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(trackRenumberResult.warnings) { warning in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(warning.fileName)
                                    .font(.system(.body, design: .monospaced))
                                ForEach(warning.messages, id: \.self) { message in
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(cardInset)
                            .background(
                                RoundedRectangle(cornerRadius: previewInnerRadius)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(setupSectionInset)
            .background(
                RoundedRectangle(cornerRadius: setupSectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            if let footerStatusText {
                Text(footerStatusText)
                    .font(.caption)
                    .foregroundStyle(plan.isStartValid ? Color.secondary : Color.red)
                    .lineLimit(2)
            }

            Spacer()

            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isTrackRenumberRunning)

            Button("Renumber") {
                applyTrackRenumber()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, contentInset)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func configurationRow<Content: View>(
        title: String,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            configurationLabel(title: title, caption: caption)
            .frame(width: 144, alignment: .leading)

            Spacer(minLength: 12)

            content()
        }
    }

    private func configurationLabel(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultMetric(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text("\(value)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()

                Spacer()

                Image(systemName: resultMetricSymbol(for: title))
                    .foregroundStyle(tint.opacity(0.85))
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardInset)
        .background(
            RoundedRectangle(cornerRadius: previewInnerRadius)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func resultMetricSymbol(for title: String) -> String {
        switch title {
        case "Succeeded":
            return "checkmark.circle.fill"
        case "Unchanged":
            return "equal.circle.fill"
        case "Skipped", "Duplicates":
            return "arrowshape.turn.up.right.circle.fill"
        case "Failed":
            return "xmark.octagon.fill"
        default:
            return "number.circle.fill"
        }
    }

    // MARK: - Reviewed plan and Apply

    private func rebuildPlan() {
        plan = viewModel.makeTrackRenumberPlan(
            orderedFiles: currentOrderedFiles,
            selectedIDs: viewModel.selectedAudioIDs,
            direction: trackRenumberOptions.direction,
            startNumberText: trackRenumberStartText
        )
    }

    private func resolvedTargetIDs() -> [AudioFile.ID] {
        let orderedFiles = currentOrderedFiles
        if viewModel.selectedAudioIDs.isEmpty {
            return orderedFiles.map(\.id)
        }
        return orderedFiles
            .filter { viewModel.selectedAudioIDs.contains($0.id) }
            .map(\.id)
    }

    private func applyTrackRenumber() {
        guard plan.isStartValid, let startNumber = plan.startNumber else { return }

        // Apply the reviewed plan the sheet showed. If the resolved scope or order
        // changed while the sheet was open, refresh the preview and require a new
        // review instead of dispatching a mismatched plan.
        guard plan.matchesOrderedTargets(resolvedTargetIDs()) else {
            rebuildPlan()
            planNotice = String(localized: "The file list order or selection changed. Review the updated preview before applying.")
            return
        }

        let appliedPlan = plan
        trackRenumberOptions.startNumber = startNumber
        trackRenumberOptions.direction = appliedPlan.direction
        planNotice = nil
        trackRenumberResult = .empty

        isTrackRenumberRunning = true
        Task {
            let result = await viewModel.renumberTrackNumbers(using: appliedPlan)

            await MainActor.run {
                trackRenumberResult = result
                isTrackRenumberRunning = false
                // Committed files now carry refreshed observations; rebuild the
                // reviewed plan so a second Apply is based on the current preview.
                rebuildPlan()
            }
        }
    }
}
