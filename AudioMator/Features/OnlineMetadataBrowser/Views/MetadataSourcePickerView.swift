import SwiftUI

struct MetadataSourcePickerView: View {
    let onSelect: (MetadataBrowserSource) -> Void

    private let rowRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(MetadataBrowserSource.allCases) { source in
                    Button {
                        onSelect(source)
                    } label: {
                        MetadataSourceRow(source: source)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: rowRadius)
                            .fill(Color.secondary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: rowRadius)
                            .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MetadataSourceRow: View {
    let source: MetadataBrowserSource

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: source.symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(source.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(source.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
