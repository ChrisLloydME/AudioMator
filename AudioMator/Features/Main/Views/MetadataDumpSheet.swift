import SwiftUI

struct MetadataDumpSheet: View {
    let metadataDumpText: String
    let onClose: () -> Void

    private var displayText: String {
        metadataDumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(No metadata details)"
            : metadataDumpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Metadata Details")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Copy") {
                    PlatformPasteboard.copy(metadataDumpText)
                }
            }

            Text("Review raw tags and file properties for the selected files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ReadOnlyMonospacedTextView(text: displayText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                .iPadRoundedGroupedSurface()
                #else
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )
                #endif

            HStack {
                Spacer()
                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(width: 760, height: 560)
        #endif
    }
}
