import SwiftUI

struct MetadataSourcePickerView: View {
    let onSelect: (MetadataBrowserSource) -> Void

    private let rowRadius: CGFloat = 12
    private let rowMaxWidth: CGFloat = 690

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                ForEach(MetadataBrowserSource.allCases) { source in
                    Button {
                        onSelect(source)
                    } label: {
                        MetadataSourceRow(source: source)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MetadataSourceRow: View {
    let source: MetadataBrowserSource

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: source.symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(source.subtitle)
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
}
