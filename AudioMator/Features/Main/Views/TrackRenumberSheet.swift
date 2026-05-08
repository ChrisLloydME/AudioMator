import SwiftUI

struct TrackRenumberSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    @ObservedObject var state: SharedState

    @Binding var isPresented: Bool
    @Binding var trackRenumberOptions: TrackRenumberOptions
    @Binding var trackRenumberStartText: String
    @Binding var isTrackRenumberRunning: Bool
    @Binding var trackRenumberResult: TrackRenumberResult

    private let cardInset: CGFloat = 16
    private let previewInnerRadius: CGFloat = 12
    private let setupSectionInset: CGFloat = 10
    private let contentInset: CGFloat = 20

    private var setupSectionRadius: CGFloat {
        previewInnerRadius + setupSectionInset
    }

    private var orderedIDs: [AudioFile.ID] {
        state.orderedMiddleListIDs(from: viewModel.files)
    }

    private var targetIDs: [AudioFile.ID] {
        if state.selectedAudioIDs.isEmpty {
            return orderedIDs
        }
        return orderedIDs.filter { state.selectedAudioIDs.contains($0) }
    }

    private var targetCount: Int {
        targetIDs.count
    }

    private var sanitizedStartNumber: Int {
        let parsed = Int(trackRenumberStartText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        return max(0, parsed)
    }

    private var startNumberBinding: Binding<Int> {
        Binding(
            get: { sanitizedStartNumber },
            set: { newValue in
                let value = max(0, newValue)
                trackRenumberStartText = String(value)
            }
        )
    }

    private var previewNumbers: [Int] {
        guard targetCount > 0 else { return [] }

        let start = sanitizedStartNumber
        switch trackRenumberOptions.direction {
        case .ascending:
            return (0..<targetCount).map { start + $0 }
        case .descending:
            return (0..<targetCount).map { start + (targetCount - 1 - $0) }
        }
    }

    private var previewPadWidth: Int {
        let maxValue = previewNumbers.max() ?? sanitizedStartNumber
        return trackRenumberPadWidth(maxNumber: maxValue, padWithZeros: trackRenumberOptions.padWithZeros)
    }

    private var previewSequenceText: String {
        guard !previewNumbers.isEmpty else { return L10n.string("No tracks selected") }

        let visibleNumbers = previewNumbers.prefix(3).map(formattedNumber)
        if previewNumbers.count <= 3 {
            return visibleNumbers.joined(separator: ", ")
        }

        return "\(visibleNumbers.joined(separator: ", "))..."
    }

    private var previewRangeText: String {
        guard let first = previewNumbers.first, let last = previewNumbers.last else {
            return L10n.string("Add files to preview the new numbers.")
        }

        let scope = state.selectedAudioIDs.isEmpty ? "current list" : "selection"
        return "\(targetCount) tracks in the \(scope) will be renumbered from \(formattedNumber(first)) to \(formattedNumber(last))."
    }

    private var selectionSummaryText: String {
        if state.selectedAudioIDs.isEmpty {
            return L10n.string("Current list")
        }

        return "\(targetCount) selected tracks"
    }

    private var selectionDetailText: String {
        state.selectedAudioIDs.isEmpty
            ? "Uses the order shown in the center list."
            : "Uses the selected rows in center-list order."
    }

    private var hasResult: Bool {
        trackRenumberResult.totalTargets > 0 ||
            trackRenumberResult.failed > 0 ||
            trackRenumberResult.skippedUnsupported > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                configurationSection

                if hasResult {
                    resultSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentInset)
            .padding(.top, contentInset)
            .padding(.bottom, contentInset)
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            footer
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(width: 640, height: 560)
        #endif
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

            Label(selectionSummaryText, systemImage: state.selectedAudioIDs.isEmpty ? "music.note.list" : "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                #if os(iOS)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        configurationControls
                            .frame(maxWidth: .infinity, alignment: .leading)

                        previewCard
                            .frame(width: 176)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        configurationControls
                        previewCard
                    }
                }
                #else
                HStack(alignment: .top, spacing: 16) {
                    configurationControls
                        .frame(maxWidth: .infinity, alignment: .leading)

                    previewCard
                        .frame(width: 176)
                }
                #endif
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
                #if os(macOS)
                .frame(width: 220)
                #else
                .frame(maxWidth: 260)
                #endif
                .disabled(isTrackRenumberRunning)
            }

            Divider()

            configurationRow(
                title: "Start number",
                caption: "Set the first number in the sequence."
            ) {
                HStack(spacing: 8) {
                    TextField("1", text: $trackRenumberStartText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .disabled(isTrackRenumberRunning)

                    Stepper("", value: startNumberBinding, in: 0...9999)
                        .labelsHidden()
                        .disabled(isTrackRenumberRunning)
                }
            }

            Divider()

            Toggle(isOn: $trackRenumberOptions.padWithZeros) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pad with leading zeros")
                    Text("Keeps the same width as numbers grow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
            .disabled(isTrackRenumberRunning)
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

            Text(trackRenumberOptions.direction == .ascending ? "First row gets the lowest number." : "First row gets the highest number.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        .padding(cardInset)
        #if os(iOS)
        .iPadRoundedGroupedSurface()
        #else
        .background(
            RoundedRectangle(cornerRadius: previewInnerRadius)
                .fill(Color.secondary.opacity(0.08))
        )
        #endif
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Results", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    resultMetric(title: "Targets", value: trackRenumberResult.totalTargets, tint: .primary)
                    resultMetric(title: "Succeeded", value: trackRenumberResult.succeeded, tint: .green)
                    resultMetric(title: "Skipped", value: trackRenumberResult.skippedUnsupported, tint: .orange)
                    resultMetric(title: "Failed", value: trackRenumberResult.failed, tint: .red)
                }

                if !trackRenumberResult.failures.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Failed Files", systemImage: "exclamationmark.triangle.fill")
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
                                    #if os(iOS)
                                    .iPadRoundedGroupedSurface()
                                    #else
                                    .background(
                                        RoundedRectangle(cornerRadius: previewInnerRadius)
                                            .fill(Color.secondary.opacity(0.08))
                                    )
                                    #endif
                                }
                            }
                        }
                        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
                        .frame(maxHeight: 150)
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
        HStack {
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
            .disabled(isTrackRenumberRunning || targetCount == 0)
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
        #if os(iOS)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                configurationLabel(title: title, caption: caption)
                    .frame(width: 144, alignment: .leading)

                Spacer(minLength: 12)

                content()
            }

            VStack(alignment: .leading, spacing: 10) {
                configurationLabel(title: title, caption: caption)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #else
        HStack(alignment: .top, spacing: 16) {
            configurationLabel(title: title, caption: caption)
            .frame(width: 144, alignment: .leading)

            Spacer(minLength: 12)

            content()
        }
        #endif
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
        #if os(iOS)
        .iPadRoundedGroupedSurface()
        #else
        .background(
            RoundedRectangle(cornerRadius: previewInnerRadius)
                .fill(Color.secondary.opacity(0.08))
        )
        #endif
    }

    private func resultMetricSymbol(for title: String) -> String {
        switch title {
        case "Succeeded":
            return "checkmark.circle.fill"
        case "Skipped":
            return "arrowshape.turn.up.right.circle.fill"
        case "Failed":
            return "xmark.octagon.fill"
        default:
            return "number.circle.fill"
        }
    }

    private func formattedNumber(_ number: Int) -> String {
        guard previewPadWidth > 0 else { return String(number) }
        return String(format: "%0*d", previewPadWidth, number)
    }

    private func applyTrackRenumber() {
        let parsed = Int(trackRenumberStartText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        trackRenumberOptions.startNumber = max(0, parsed)
        trackRenumberStartText = String(trackRenumberOptions.startNumber)

        let selected = state.selectedAudioIDs

        isTrackRenumberRunning = true
        trackRenumberResult = .empty

        Task {
            let result = await viewModel.renumberTrackNumbers(
                orderedIDs: state.orderedMiddleListIDs(from: viewModel.files),
                selectedIDs: selected,
                options: trackRenumberOptions
            )

            await MainActor.run {
                trackRenumberResult = result
                isTrackRenumberRunning = false
            }
        }
    }
}
