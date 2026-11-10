import SwiftUI
import TagLibAudioMetadata

/// Focused number recovery/cleanup preview. The plan shown here is captured by
/// the pipeline; Apply executes that exact plan and never regenerates it.
struct NumberNormalizationSheet: View {
    @ObservedObject var viewModel: AudioViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            policyControls

            if let preview = viewModel.numberNormalizationPreview {
                previewContent(preview)
            } else {
                ContentUnavailableView(
                    "Build a Preview",
                    systemImage: "number",
                    description: Text("Choose how numbering should be resolved, then build the preview before applying it.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Restore or Clean Up Numbers")
                .font(.title3)
                .fontWeight(.semibold)
            Text(viewModel.numberNormalizationTargetFile?.url.lastPathComponent ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Track and disc numbers and totals stay independent. Cleanup changes only the groups and alias identities shown in this preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: NumberNormalizationPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "Planned native values"))
                    .font(.headline)
                if preview.plan.groups.contains(.track) {
                    Text("Track: \(preview.plan.trackNumber.map(String.init) ?? "—") / \(preview.plan.trackTotal.map(String.init) ?? "—")")
                }
                if preview.plan.groups.contains(.disc) {
                    Text("Disc: \(preview.plan.discNumber.map(String.init) ?? "—") / \(preview.plan.discTotal.map(String.init) ?? "—")")
                }
                groupSection(title: "Track", group: preview.track)
                groupSection(title: "Disc", group: preview.disc)

                if !preview.removalIdentities.isEmpty {
                    labelledList("Aliases selected for removal", values: preview.removalIdentities)
                }
                if !preview.warnings.isEmpty {
                    labelledList("Warnings", values: preview.warnings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var policyControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Resolution", selection: $viewModel.numberNormalizationChoice) {
                ForEach(NumberNormalizationChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.numberNormalizationChoice) { _, _ in
                viewModel.numberNormalizationPreview = nil
            }

            if viewModel.numberNormalizationChoice == .replace {
                HStack(spacing: 12) {
                    TextField("Number", text: $viewModel.numberNormalizationReplaceNumber)
                        .frame(maxWidth: 120)
                    TextField("Total", text: $viewModel.numberNormalizationReplaceTotal)
                        .frame(maxWidth: 120)
                    Text("The replacement pair applies to every selected group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Toggle("Track", isOn: groupBinding(.track))
                Toggle("Disc", isOn: groupBinding(.disc))
            }
            .toggleStyle(.checkbox)
        }
    }

    private func groupBinding(_ group: MetadataNumberGroup) -> Binding<Bool> {
        Binding(
            get: { viewModel.numberNormalizationGroups.contains(group) },
            set: { isOn in
                if isOn {
                    viewModel.numberNormalizationGroups.insert(group)
                } else {
                    viewModel.numberNormalizationGroups.remove(group)
                }
                viewModel.numberNormalizationPreview = nil
            }
        )
    }

    @ViewBuilder
    private func groupSection(title: String, group: MetadataNumberGroupInventory) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 6) {
                if !group.nativeIdentities.isEmpty {
                    labelledList("Native identities", values: group.nativeIdentities)
                }
                if !group.legacyAliasIdentities.isEmpty {
                    labelledList("Legacy alias identities", values: group.legacyAliasIdentities)
                }
                componentRow("Number", component: group.number)
                componentRow("Total", component: group.total)
                ForEach(group.privateTexts, id: \.identity) { privateText in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private formatting provenance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(privateText.identity) = \(privateText.values.joined(separator: ", "))")
                            .font(.caption.monospaced())
                    }
                }
                if !group.warnings.isEmpty {
                    labelledList("Warnings", values: group.warnings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func componentRow(_ label: String, component: MetadataNumberComponentInventory) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.headline)
                Text(component.state.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(component.resolvedValue.map(String.init) ?? "—")
                    .font(.body.monospacedDigit())
            }
            if !component.candidates.isEmpty {
                Text("Candidates: " + component.candidates.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !component.identities.isEmpty {
                Text("Sources: " + component.identities.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func labelledList(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.monospaced())
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh Preview") {
                viewModel.refreshNumberNormalizationPreview()
            }
            .disabled(viewModel.numberNormalizationTargetFile == nil)

            Spacer()

            Button("Cancel") {
                viewModel.numberNormalizationPreview = nil
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply Cleanup") {
                Task {
                    if await viewModel.applyNumberNormalization() {
                        dismiss()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.numberNormalizationPreview == nil || viewModel.metadataSaveProgress != nil)
        }
    }
}

extension MetadataNumberComponentState {
    var displayName: String {
        switch self {
        case .absent: L10n.string("Absent")
        case .native: L10n.string("Native")
        case .recoveredLegacy: L10n.string("Recovered from legacy data")
        case .ambiguous: L10n.string("Ambiguous")
        case .invalid: L10n.string("Invalid")
        }
    }
}
