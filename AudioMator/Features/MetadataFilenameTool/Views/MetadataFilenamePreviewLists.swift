import SwiftUI

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
                    .fill(Color(nsColor: .audiomatorControlBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: innerCardRadius, style: .continuous)
                    .stroke(Color(nsColor: .audiomatorSeparator).opacity(0.35), lineWidth: 1)
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
}

private extension FilenameMetadataPreviewStatus {
    var nsTint: NSColor {
        switch self {
        case .ready:
            return .systemGreen
        case .unchanged, .noWritableFields:
            return .secondaryLabelColor
        case .noMatch, .sourceUnavailable, .unsupported:
            return .systemOrange
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "minus.circle.fill"
        case .noMatch, .sourceUnavailable, .unsupported:
            return "exclamationmark.triangle.fill"
        case .noWritableFields:
            return "questionmark.circle.fill"
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
}

private extension FileRenameMetadataField {
    var usesMonospacedComparisonValue: Bool {
        switch self {
        case .year, .date, .originalReleaseDate, .trackNumberText, .discNumberText, .releaseDate:
            return true
        case .title, .artist, .album, .albumArtist, .composer, .genre,
                .comment, .publisher, .copyright, .credits, .ignore:
            return false
        }
    }
}
