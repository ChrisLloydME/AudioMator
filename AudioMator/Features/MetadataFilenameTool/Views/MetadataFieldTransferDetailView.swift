import SwiftUI

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
            HStack(spacing: 12) {
                Text(String(localized: "\(targetCount) selected files"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if isApplying {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Picker(String(localized: "Operation"), selection: $store.operation) {
                    ForEach(MetadataFieldTransferOperation.allCases) { operation in
                        Text(operation.title).tag(operation)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
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

            Picker(title, selection: selection) {
                ForEach(MetadataFieldTransferPlanner.fields) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(Text(title))
            .frame(maxWidth: .infinity, minHeight: 24)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}
