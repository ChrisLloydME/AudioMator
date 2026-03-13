import SwiftUI
import AppKit

struct MetadataDumpSheet: View {
    let metadataDumpText: String
    let onClose: () -> Void

    private var displayText: String {
        metadataDumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(No metadata details available)"
            : metadataDumpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tag Inspector")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(metadataDumpText, forType: .string)
                }
            }

            Text("Shows detailed metadata for the selected file(s), including file properties and tag entries.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ReadOnlyMonospacedTextView(text: displayText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )

            HStack {
                Spacer()
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 760, height: 560)
    }
}
