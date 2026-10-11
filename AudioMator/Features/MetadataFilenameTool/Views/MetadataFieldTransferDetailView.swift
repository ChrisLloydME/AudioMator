import SwiftUI
import AppKit

struct MetadataFieldTransferDetailView: View {
    @ObservedObject var store: MetadataFieldTransferStore
    let plan: MetadataExchangeImportPlan
    let targetCount: Int
    let selectionSummaryText: String
    let isApplying: Bool

    private let sectionInset: CGFloat = 12
    private let sectionRadius: CGFloat = 18
    private let contentInset: CGFloat = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                setupSection
                previewSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(contentInset)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(MetadataConverterMode.metadataFieldTransfer.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                if isApplying {
                    ProgressView().controlSize(.small)
                }
            }

            Text(MetadataConverterMode.metadataFieldTransfer.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(selectionSummaryText, systemImage: "checkmark.circle")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Setup"), systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.secondary)

            transferControls
                .padding(sectionInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: sectionRadius)
                        .fill(Color.secondary.opacity(0.06))
                }
        }
    }

    private var transferControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.operation == .copy
                ? String(localized: "Replaces the destination and keeps the source. Empty sources are skipped.")
                : String(localized: "Replaces the destination and clears the source. Empty sources are skipped."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Operation"))
                    .font(.headline)

                Picker(String(localized: "Operation"), selection: $store.operation) {
                    ForEach(MetadataFieldTransferOperation.allCases) { operation in
                        Text(operation.title).tag(operation)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            HStack(alignment: .bottom, spacing: 16) {
                fieldPicker(title: String(localized: "Source Field"), selection: $store.source)

                Image(systemName: "arrow.right")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                fieldPicker(title: String(localized: "Destination Field"), selection: $store.destination)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isApplying)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Preview"), systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Label(
                    MetadataFilenameStatusPresentation.importMessage(targetCount: targetCount, plan: plan),
                    systemImage: previewStatusSymbol
                )
                .font(.subheadline)
                .foregroundStyle(previewStatusTint)

                MetadataExchangeImportPreviewList(plan: plan, isFieldTransfer: true)
                    .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(sectionInset)
            .background {
                RoundedRectangle(cornerRadius: sectionRadius)
                    .fill(Color.secondary.opacity(0.06))
            }
        }
    }

    private var previewStatusSymbol: String {
        if plan.issueCount > 0 { return "exclamationmark.triangle.fill" }
        return plan.readyCount > 0 ? "checkmark.circle.fill" : "info.circle.fill"
    }

    private var previewStatusTint: Color {
        if plan.issueCount > 0 { return .orange }
        return plan.readyCount > 0 ? .green : .secondary
    }

    private func fieldPicker(title: String, selection: Binding<MetadataExchangeField>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            MetadataFieldTransferPopUpButton(title: title, selection: selection)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetadataFieldTransferPopUpButton: NSViewRepresentable {
    let title: String
    @Binding var selection: MetadataExchangeField

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.addItems(withTitles: MetadataFieldTransferPlanner.fields.map(\.displayName))
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectField(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        if let index = MetadataFieldTransferPlanner.fields.firstIndex(of: selection) {
            button.selectItem(at: index)
        }
        button.isEnabled = context.environment.isEnabled
        button.setAccessibilityLabel(title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 260, height: nsView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject {
        var selection: Binding<MetadataExchangeField>

        init(selection: Binding<MetadataExchangeField>) {
            self.selection = selection
        }

        @objc func selectField(_ sender: NSPopUpButton) {
            let fields = MetadataFieldTransferPlanner.fields
            guard fields.indices.contains(sender.indexOfSelectedItem) else { return }
            selection.wrappedValue = fields[sender.indexOfSelectedItem]
        }
    }
}
