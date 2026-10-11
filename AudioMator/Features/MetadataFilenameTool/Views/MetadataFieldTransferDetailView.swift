import SwiftUI
import AppKit

struct MetadataFieldTransferDetailView: View {
    @ObservedObject var store: MetadataFieldTransferStore
    let plan: MetadataExchangeImportPlan
    let targetCount: Int
    let isApplying: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                transferControls

                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Preview"))
                        .font(.headline)
                    Text(MetadataFilenameStatusPresentation.importMessage(targetCount: targetCount, plan: plan))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MetadataExchangeImportPreviewList(plan: plan, isFieldTransfer: true)
                        .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transferControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Operation"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(String(localized: "Operation"), selection: $store.operation) {
                        ForEach(MetadataFieldTransferOperation.allCases) { operation in
                            Text(operation.title).tag(operation)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                if isApplying {
                    ProgressView().controlSize(.small)
                }
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

            Text(store.operation == .copy
                ? String(localized: "Replaces the destination and keeps the source. Empty sources are skipped.")
                : String(localized: "Replaces the destination and clears the source. Empty sources are skipped."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .audiomatorControlBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .audiomatorSeparator).opacity(0.35), lineWidth: 1)
        }
        .disabled(isApplying)
    }

    private func fieldPicker(title: String, selection: Binding<MetadataExchangeField>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

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
