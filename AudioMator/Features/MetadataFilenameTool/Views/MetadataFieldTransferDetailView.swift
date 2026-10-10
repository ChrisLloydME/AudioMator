import SwiftUI

struct MetadataFieldTransferDetailView: View {
    @ObservedObject var store: MetadataFieldTransferStore
    let plan: MetadataExchangeImportPlan
    let targetCount: Int
    let isApplying: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(String(localized: "\(targetCount) selected files"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isApplying {
                        ProgressView().controlSize(.small)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker(String(localized: "Operation"), selection: $store.operation) {
                            ForEach(MetadataFieldTransferOperation.allCases) { operation in
                                Text(operation.title).tag(operation)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)

                        HStack(spacing: 20) {
                            Picker(String(localized: "Source Field"), selection: $store.source) {
                                ForEach(MetadataFieldTransferPlanner.fields) { field in
                                    Text(field.displayName).tag(field)
                                }
                            }
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Picker(String(localized: "Destination Field"), selection: $store.destination) {
                                ForEach(MetadataFieldTransferPlanner.fields) { field in
                                    Text(field.displayName).tag(field)
                                }
                            }
                        }

                        Text(store.operation == .copy
                            ? String(localized: "Replace the destination with each file’s source value, keeping the source. Files with an empty source are skipped.")
                            : String(localized: "Replace the destination with each file’s source value and clear the source in the same save. Files with an empty source are skipped."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(isApplying)
                } label: {
                    Text(String(localized: "Setup"))
                }

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
}
