import SwiftUI

#if os(macOS)
struct MetadataConverterModePickerView: View {
    let onSelect: (MetadataConverterMode) -> Void

    private let rowRadius: CGFloat = 12
    private let rowMaxWidth: CGFloat = 690

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                ForEach(MetadataConverterMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 38)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(mode.title)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    if mode.showsBetaBadge {
                                        MetadataConverterModeBetaBadge()
                                    }
                                }

                                Text(mode.subtitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: rowRadius)
                            .fill(Color.secondary.opacity(0.075))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: rowRadius)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                }
            }
            .frame(maxWidth: rowMaxWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MetadataConverterModeBetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.8)
            )
    }
}

private extension MetadataConverterMode {
    var showsBetaBadge: Bool {
        switch self {
        case .metadataToText, .textToMetadata, .metadataToCSV, .csvToMetadata:
            return true
        case .metadataToFilename, .filenameToMetadata:
            return false
        }
    }
}
#endif
