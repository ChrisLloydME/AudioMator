import SwiftUI

#if os(macOS)
import AppKit

struct MetadataConverterPreviewCard<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    private let innerCardRadius: CGFloat = 12

    init(
        title: String,
        symbolName: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbolName = symbolName
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 10, weight: .semibold))

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: innerCardRadius, style: .continuous)
                    .fill(Color(platformColor: .audiomatorControlBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: innerCardRadius, style: .continuous)
                    .stroke(Color(platformColor: .audiomatorSeparator).opacity(0.35), lineWidth: 1)
            )
        }
    }
}

struct MetadataFilenameRenamePreviewList: View {
    let rows: [FileRenamePreviewRow]

    var body: some View {
        MetadataConverterPreviewCard(title: "Filename Comparison", symbolName: "arrow.left.arrow.right") {
            MetadataFilenameRenameComparisonAppKitList(rows: rows)
        }
    }
}

private struct MetadataFilenameRenameComparisonHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Status")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("Current Name")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("Preview")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct MetadataFilenameRenameComparisonRowView: View {
    let row: FileRenamePreviewRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.status.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(row.status.tint)
                    .multilineTextAlignment(.leading)

                if row.status != .ready {
                    Text(row.status.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(width: 118, alignment: .leading)

            MetadataFilenameRenameComparisonValue(
                row.currentName,
                foregroundColor: .primary
            )

            Image(systemName: row.status.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(row.status.tint)
                .help(row.status.message)
                .frame(width: 18)
                .padding(.top, 1)

            MetadataFilenameRenameComparisonValue(
                row.previewName,
                foregroundColor: row.status.isError ? .orange : .primary
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct MetadataFilenameRenameComparisonValue: View {
    let value: String
    let foregroundColor: Color

    init(_ value: String, foregroundColor: Color) {
        self.value = value
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        Text(value.isEmpty ? "—" : value)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(value.isEmpty ? Color(nsColor: .tertiaryLabelColor) : foregroundColor)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FilenameMetadataPreviewList: View {
    let plan: FilenameMetadataPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            MetadataConverterPreviewCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                ContentUnavailableView(
                    "Template Needs More Structure",
                    systemImage: "exclamationmark.triangle",
                    description: Text(validationMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        } else if plan.rows.isEmpty {
            MetadataConverterPreviewCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                ContentUnavailableView(
                    "No Files Selected",
                    systemImage: "music.note.list",
                    description: Text("Select one or more files to preview metadata extraction from filenames.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        } else {
            MetadataConverterPreviewCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                FilenameMetadataComparisonAppKitList(rows: plan.rows)
            }
        }
    }
}

private struct MetadataFilenameRenameComparisonAppKitList: NSViewRepresentable {
    let rows: [FileRenamePreviewRow]

    func makeNSView(context: Context) -> MetadataFilenamePreviewContainerView {
        MetadataFilenamePreviewContainerView()
    }

    func updateNSView(_ nsView: MetadataFilenamePreviewContainerView, context: Context) {
        var views: [NSView] = [MetadataFilenameAppKitRowFactory.renameHeader()]
        for (index, row) in rows.enumerated() {
            views.append(MetadataFilenameAppKitRowFactory.renameRow(row))
            if index < rows.count - 1 {
                views.append(MetadataFilenameAppKitRowFactory.divider())
            }
        }
        nsView.replaceArrangedSubviews(with: views)
    }
}

private struct FilenameMetadataComparisonAppKitList: NSViewRepresentable {
    let rows: [FilenameMetadataPreviewRow]

    func makeNSView(context: Context) -> MetadataFilenamePreviewContainerView {
        MetadataFilenamePreviewContainerView()
    }

    func updateNSView(_ nsView: MetadataFilenamePreviewContainerView, context: Context) {
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            views.append(MetadataFilenameAppKitRowFactory.metadataGroup(row))
            if index < rows.count - 1 {
                views.append(MetadataFilenameAppKitRowFactory.divider())
            }
        }
        nsView.replaceArrangedSubviews(with: views)
    }
}

private final class MetadataFilenamePreviewContainerView: NSView {
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: stackView.fittingSize.height)
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    func replaceArrangedSubviews(with views: [NSView]) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for view in views {
            stackView.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }

        invalidateIntrinsicContentSize()
    }
}

private enum MetadataFilenameAppKitRowFactory {
    static func renameHeader() -> NSView {
        let currentName = label("Current Name", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        let previewName = label("Preview", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        let content = horizontalStack(spacing: 14, alignment: .centerY, views: [
            label("Status", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor, width: 118),
            currentName,
            symbol("arrow.left.arrow.right", color: .tertiaryLabelColor, width: 18),
            previewName
        ])
        currentName.widthAnchor.constraint(equalTo: previewName.widthAnchor).isActive = true

        return padded(
            content,
            top: 9,
            left: 18,
            bottom: 9,
            right: 18
        )
    }

    static func renameRow(_ row: FileRenamePreviewRow) -> NSView {
        let status = verticalStack(spacing: 4, views: [
            label(row.status.title, font: .systemFont(ofSize: 12, weight: .semibold), color: row.status.nsTint),
            row.status == .ready ? nil : label(row.status.message, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        ].compactMap { $0 })
        status.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let icon = symbol(row.status.symbolName, color: row.status.nsTint, width: 18)
        icon.toolTip = row.status.message
        let currentName = valueLabel(row.currentName, monospaced: true, emptyText: "—", color: .labelColor, emptyColor: .tertiaryLabelColor)
        let previewName = valueLabel(row.previewName, monospaced: true, emptyText: "—", color: row.status.isError ? .systemOrange : .labelColor, emptyColor: .tertiaryLabelColor)
        let content = horizontalStack(spacing: 12, alignment: .top, views: [
            status,
            currentName,
            icon,
            previewName
        ])
        currentName.widthAnchor.constraint(equalTo: previewName.widthAnchor).isActive = true

        return padded(
            content,
            top: 10,
            left: 18,
            bottom: 10,
            right: 18
        )
    }

    static func metadataGroup(_ row: FilenameMetadataPreviewRow) -> NSView {
        let group = verticalStack(spacing: 0)

        let titleStack = verticalStack(spacing: 4, views: [
            label(row.currentName, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor),
            valueLabel("Filename stem: \(row.sourceBaseName)", monospaced: true, fontSize: 11, emptyText: "", color: .secondaryLabelColor, emptyColor: .secondaryLabelColor)
        ])

        let heading = horizontalStack(spacing: 18, alignment: .top, views: [
            titleStack,
            spacer(),
            badge(title: row.status.title, symbolName: row.status.symbolName, tint: row.status.nsTint)
        ])

        addFullWidthArrangedSubview(padded(
            heading,
            top: 14,
            left: 18,
            bottom: row.changes.isEmpty ? 8 : 12,
            right: 18
        ), to: group)

        if let issueMessage = row.issueMessage {
            addFullWidthArrangedSubview(padded(
                label(issueMessage, font: .systemFont(ofSize: 11), color: row.status.nsTint),
                top: 0,
                left: 18,
                bottom: row.changes.isEmpty ? 14 : 12,
                right: 18
            ), to: group)
        }

        if row.changes.isEmpty {
            addFullWidthArrangedSubview(padded(
                label(row.status.message, font: .systemFont(ofSize: 12), color: .secondaryLabelColor),
                top: 14,
                left: 18,
                bottom: 14,
                right: 18
            ), to: group)
        } else {
            addFullWidthArrangedSubview(divider(), to: group)
            addFullWidthArrangedSubview(metadataHeader(), to: group)

            for (index, change) in row.changes.enumerated() {
                addFullWidthArrangedSubview(metadataChangeRow(change), to: group)
                if index < row.changes.count - 1 {
                    addFullWidthArrangedSubview(divider(), to: group)
                }
            }
        }

        return group
    }

    static func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            box.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            box.topAnchor.constraint(equalTo: container.topAnchor),
            box.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static func metadataHeader() -> NSView {
        let metadata = label("Metadata", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        let filename = label("Filename", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        let content = horizontalStack(spacing: 14, alignment: .centerY, views: [
            label("Field", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor, width: 118),
            metadata,
            symbol("arrow.left.arrow.right", color: .tertiaryLabelColor, width: 18),
            filename
        ])
        metadata.widthAnchor.constraint(equalTo: filename.widthAnchor).isActive = true

        return padded(
            content,
            top: 9,
            left: 18,
            bottom: 9,
            right: 18
        )
    }

    private static func metadataChangeRow(_ change: FilenameMetadataFieldChange) -> NSView {
        let icon = symbol(change.status.symbolName, color: change.status.nsTint, width: 18)
        icon.toolTip = change.willWrite ? "This value will be written to metadata." : "This field already matches."
        let currentValue = valueLabel(change.currentValue, monospaced: change.field.usesMonospacedComparisonValue, emptyText: "—", color: .labelColor, emptyColor: .tertiaryLabelColor)
        let extractedValue = valueLabel(change.extractedValue, monospaced: change.field.usesMonospacedComparisonValue, emptyText: "—", color: change.willWrite ? change.status.nsTint : .labelColor, emptyColor: .tertiaryLabelColor)
        let content = horizontalStack(spacing: 14, alignment: .top, views: [
            label(change.field.displayName, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, width: 118),
            currentValue,
            icon,
            extractedValue
        ])
        currentValue.widthAnchor.constraint(equalTo: extractedValue.widthAnchor).isActive = true

        return padded(
            content,
            top: 10,
            left: 18,
            bottom: 10,
            right: 18
        )
    }

    private static func label(
        _ text: String,
        font: NSFont,
        color: NSColor,
        width: CGFloat? = nil
    ) -> NSTextField {
        let textField = NSTextField(labelWithString: text)
        textField.font = font
        textField.textColor = color
        textField.backgroundColor = .clear
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.translatesAutoresizingMaskIntoConstraints = false
        if let width {
            textField.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return textField
    }

    private static func valueLabel(
        _ value: String,
        monospaced: Bool,
        fontSize: CGFloat = 12,
        emptyText: String,
        color: NSColor,
        emptyColor: NSColor
    ) -> NSTextField {
        let displayValue = value.isEmpty ? emptyText : value
        let textField = label(
            displayValue,
            font: monospaced ? .monospacedSystemFont(ofSize: fontSize, weight: .regular) : .systemFont(ofSize: fontSize),
            color: value.isEmpty ? emptyColor : color
        )
        textField.isSelectable = true
        return textField
    }

    private static func symbol(_ name: String, color: NSColor, width: CGFloat) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        imageView.contentTintColor = color
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: width).isActive = true
        imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 13).isActive = true
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return imageView
    }

    private static func badge(title: String, symbolName: String, tint: NSColor) -> NSView {
        let content = horizontalStack(spacing: 5, alignment: .centerY, views: [
            symbol(symbolName, color: tint, width: 12),
            label(title, font: .systemFont(ofSize: 11, weight: .semibold), color: tint)
        ])

        let paddedBadge = padded(content, top: 6, left: 10, bottom: 6, right: 10)
        paddedBadge.wantsLayer = true
        paddedBadge.layer?.backgroundColor = tint.withAlphaComponent(0.12).cgColor
        paddedBadge.layer?.cornerRadius = 12
        return paddedBadge
    }

    private static func padded(
        _ content: NSView,
        top: CGFloat,
        left: CGFloat,
        bottom: CGFloat,
        right: CGFloat
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: left),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -right),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: top),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottom)
        ])
        return container
    }

    private static func horizontalStack(
        spacing: CGFloat,
        alignment: NSLayoutConstraint.Attribute,
        views: [NSView]
    ) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = alignment
        stack.distribution = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func verticalStack(spacing: CGFloat, views: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func addFullWidthArrangedSubview(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private static func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
}

private struct FilenameMetadataComparisonGroupView: View {
    let row: FilenameMetadataPreviewRow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.currentName)
                        .font(.system(size: 13, weight: .semibold))

                    Text("Filename stem: \(row.sourceBaseName)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                FilenameMetadataStatusBadge(status: row.status)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, row.changes.isEmpty ? 8 : 12)

            if let issueMessage = row.issueMessage {
                Text(issueMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(row.status.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, row.changes.isEmpty ? 14 : 12)
            }

            if !row.changes.isEmpty {
                Divider()
                    .padding(.leading, 18)

                FilenameMetadataComparisonHeader()

                ForEach(Array(row.changes.enumerated()), id: \.element.id) { index, change in
                    FilenameMetadataComparisonRowView(change: change)

                    if index < row.changes.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            } else {
                FilenameMetadataComparisonEmptyStateRow(message: row.status.message)
            }
        }
    }
}

private struct FilenameMetadataStatusBadge: View {
    let status: FilenameMetadataPreviewStatus

    var body: some View {
        Label(status.title, systemImage: status.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(status.tint.opacity(0.12))
            )
    }
}

private struct FilenameMetadataComparisonHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Field")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("Metadata")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("Filename")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct FilenameMetadataComparisonRowView: View {
    let change: FilenameMetadataFieldChange

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(change.field.displayName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            FilenameMetadataComparisonValue(
                value: change.currentValue,
                monospaced: change.field.usesMonospacedComparisonValue,
                foregroundColor: .primary
            )

            Image(systemName: change.status.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(change.status.tint)
                .help(change.willWrite ? "This value will be written to metadata." : "This field already matches.")
                .frame(width: 18)
                .padding(.top, 1)

            FilenameMetadataComparisonValue(
                value: change.extractedValue,
                monospaced: change.field.usesMonospacedComparisonValue,
                foregroundColor: change.willWrite ? change.status.tint : .primary
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct FilenameMetadataComparisonValue: View {
    let value: String
    let monospaced: Bool
    let foregroundColor: Color

    var body: some View {
        Text(value.isEmpty ? "—" : value)
            .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
            .foregroundStyle(value.isEmpty ? Color(nsColor: .tertiaryLabelColor) : foregroundColor)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FilenameMetadataComparisonEmptyStateRow: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }
}

private extension FileRenamePreviewStatus {
    var nsTint: NSColor {
        switch self {
        case .ready:
            return .systemGreen
        case .unchanged:
            return .secondaryLabelColor
        case .emptyName, .nameTooLong, .sourceUnavailable, .duplicateTarget, .existingFile:
            return .systemOrange
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "minus.circle.fill"
        case .emptyName, .nameTooLong, .sourceUnavailable, .duplicateTarget, .existingFile:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unchanged:
            return .secondary
        case .emptyName, .nameTooLong, .sourceUnavailable, .duplicateTarget, .existingFile:
            return .orange
        }
    }
}

private extension FilenameMetadataPreviewStatus {
    var nsTint: NSColor {
        switch self {
        case .ready:
            return .systemGreen
        case .unchanged, .noWritableFields:
            return .secondaryLabelColor
        case .noMatch:
            return .systemOrange
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "minus.circle.fill"
        case .noMatch:
            return "exclamationmark.triangle.fill"
        case .noWritableFields:
            return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unchanged, .noWritableFields:
            return .secondary
        case .noMatch:
            return .orange
        }
    }
}

private extension FilenameMetadataFieldChangeStatus {
    var nsTint: NSColor {
        switch self {
        case .same:
            return .systemGreen
        case .different:
            return .systemOrange
        }
    }

    var symbolName: String {
        switch self {
        case .same:
            return "checkmark.circle.fill"
        case .different:
            return "arrow.left.arrow.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .same:
            return .green
        case .different:
            return .orange
        }
    }
}

private extension FileRenameMetadataField {
    var usesMonospacedComparisonValue: Bool {
        switch self {
        case .year, .trackNumberText, .discNumberText, .releaseDate:
            return true
        case .title, .artist, .album, .albumArtist, .composer, .genre,
                .comment, .publisher, .copyright, .credits, .ignore:
            return false
        }
    }
}
#endif
