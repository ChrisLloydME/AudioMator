import SwiftUI

#if os(macOS)
import AppKit

struct MetadataTextExportPreviewList: View {
    let plan: MetadataTextExportPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            ContentUnavailableView(
                "Template Needs More Structure",
                systemImage: "text.cursor",
                description: Text(validationMessage)
            )
        } else if plan.rows.isEmpty {
            ContentUnavailableView(
                "No Files Selected",
                systemImage: "music.note.list",
                description: Text("Select one or more files to preview text export.")
            )
        } else {
            MetadataConverterPreviewCard(title: "Text Lines", symbolName: "text.alignleft") {
                MetadataTextExportPreviewAppKitList(rows: plan.rows)
            }
        }
    }
}

struct MetadataCSVExportPreviewList: View {
    let plan: MetadataCSVExportPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            ContentUnavailableView(
                "Column Template Needs Work",
                systemImage: "tablecells",
                description: Text(validationMessage)
            )
        } else if plan.rows.isEmpty {
            ContentUnavailableView(
                "No Files Selected",
                systemImage: "music.note.list",
                description: Text("Select one or more files to preview CSV export.")
            )
        } else {
            MetadataConverterPreviewCard(title: "CSV Rows", symbolName: "tablecells") {
                MetadataCSVExportPreviewAppKitList(
                    columns: plan.columns,
                    rows: Array(plan.rows.prefix(24))
                )
                .frame(height: MetadataCSVExportPreviewAppKitList.height(forRowCount: min(plan.rows.count, 24)))
            }
        }
    }

    private func csvCell(_ value: String, isHeader: Bool) -> some View {
        Text(value)
            .font(isHeader ? .system(size: 11, weight: .semibold) : .system(size: 12, design: .monospaced))
            .foregroundStyle(value == "Empty" ? Color.secondary : Color.primary)
            .lineLimit(2)
            .frame(width: 150, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}

struct MetadataExchangeImportPreviewList: View {
    let plan: MetadataExchangeImportPlan

    var body: some View {
        if let validationMessage = plan.validationMessage {
            ContentUnavailableView(
                "Template Needs More Structure",
                systemImage: "exclamationmark.triangle",
                description: Text(validationMessage)
            )
        } else if plan.rows.isEmpty {
            ContentUnavailableView(
                "Add Source Records",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Choose or paste text to preview imported metadata.")
            )
        } else {
            MetadataConverterPreviewCard(title: "Metadata Comparison", symbolName: "arrow.left.arrow.right") {
                MetadataExchangeImportPreviewAppKitList(rows: plan.rows)
            }
        }
    }
}

private struct MetadataTextExportPreviewAppKitList: NSViewRepresentable {
    let rows: [MetadataTextExportRow]

    func makeNSView(context: Context) -> MetadataExchangePreviewContainerView {
        MetadataExchangePreviewContainerView()
    }

    func updateNSView(_ nsView: MetadataExchangePreviewContainerView, context: Context) {
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            views.append(MetadataExchangeAppKitRowFactory.textExportRow(row))
            if index < rows.count - 1 {
                views.append(MetadataExchangeAppKitRowFactory.divider())
            }
        }
        nsView.replaceArrangedSubviews(with: views)
    }
}

private struct MetadataCSVExportPreviewAppKitList: NSViewRepresentable {
    let columns: [MetadataExchangeField]
    let rows: [[String]]

    static func height(forRowCount rowCount: Int) -> CGFloat {
        CGFloat(rowCount + 1) * 32 + CGFloat(rowCount)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0

        stack.addArrangedSubview(MetadataExchangeAppKitRowFactory.csvRow(columns.map(\.displayName), isHeader: true))
        stack.addArrangedSubview(MetadataExchangeAppKitRowFactory.divider())
        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(MetadataExchangeAppKitRowFactory.csvRow(row.map { $0.isEmpty ? "Empty" : $0 }, isHeader: false))
            if index < rows.count - 1 {
                stack.addArrangedSubview(MetadataExchangeAppKitRowFactory.divider())
            }
        }

        scrollView.documentView = stack
    }
}

private struct MetadataExchangeImportPreviewAppKitList: NSViewRepresentable {
    let rows: [MetadataExchangeImportPreviewRow]

    func makeNSView(context: Context) -> MetadataExchangePreviewContainerView {
        MetadataExchangePreviewContainerView()
    }

    func updateNSView(_ nsView: MetadataExchangePreviewContainerView, context: Context) {
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            views.append(MetadataExchangeAppKitRowFactory.importGroup(row))
            if index < rows.count - 1 {
                views.append(MetadataExchangeAppKitRowFactory.divider())
            }
        }
        nsView.replaceArrangedSubviews(with: views)
    }
}

private final class MetadataExchangePreviewContainerView: NSView {
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

private enum MetadataExchangeAppKitRowFactory {
    static func textExportRow(_ row: MetadataTextExportRow) -> NSView {
        return padded(
            horizontalStack(spacing: 14, alignment: .top, views: [
                label(row.fileName, font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor, width: 180, maximumLines: 2),
                valueLabel(row.output, emptyText: "Empty", monospaced: true, color: row.output.isEmpty ? .secondaryLabelColor : .labelColor)
            ]),
            top: 10,
            left: 18,
            bottom: 10,
            right: 18
        )
    }

    static func csvRow(_ values: [String], isHeader: Bool) -> NSView {
        let cells = values.map { value in
            padded(
                label(
                    value,
                    font: isHeader ? .systemFont(ofSize: 11, weight: .semibold) : .monospacedSystemFont(ofSize: 12, weight: .regular),
                    color: value == "Empty" ? .secondaryLabelColor : .labelColor,
                    width: 130,
                    maximumLines: 2
                ),
                top: 8,
                left: 10,
                bottom: 8,
                right: 10
            )
        }

        let row = horizontalStack(spacing: 0, alignment: .top, views: cells)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    static func importGroup(_ row: MetadataExchangeImportPreviewRow) -> NSView {
        let group = verticalStack(spacing: 0)
        let titleStack = verticalStack(spacing: 4, views: [
            label(row.fileName, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor, maximumLines: 1),
            valueLabel(row.externalRecord, emptyText: "No external record", monospaced: true, fontSize: 11, color: .secondaryLabelColor, maximumLines: 2)
        ])

        let heading = horizontalStack(spacing: 14, alignment: .top, views: [
            titleStack,
            spacer(),
            badge(title: row.status.title, symbolName: row.status.symbolName, tint: row.status.nsTint)
        ])

        addFullWidthArrangedSubview(padded(heading, top: 12, left: 18, bottom: 12, right: 18), to: group)

        if let issueMessage = row.issueMessage {
            addFullWidthArrangedSubview(padded(
                label(issueMessage, font: .systemFont(ofSize: 11), color: row.status.isIssue ? row.status.nsTint : .secondaryLabelColor),
                top: 0,
                left: 18,
                bottom: 10,
                right: 18
            ), to: group)
        }

        if !row.changes.isEmpty {
            addFullWidthArrangedSubview(divider(), to: group)
            addFullWidthArrangedSubview(importHeader(), to: group)
            for (index, change) in row.changes.enumerated() {
                addFullWidthArrangedSubview(importChangeRow(change), to: group)
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

    private static func importHeader() -> NSView {
        let current = label("Current", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        let imported = label("Imported", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
        let content = horizontalStack(spacing: 14, alignment: .centerY, views: [
            label("Field", font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor, width: 118),
            current,
            symbol("arrow.left.arrow.right", color: .tertiaryLabelColor, width: 18),
            imported
        ])
        current.widthAnchor.constraint(equalTo: imported.widthAnchor).isActive = true

        return padded(
            content,
            top: 9,
            left: 18,
            bottom: 9,
            right: 18
        )
    }

    private static func importChangeRow(_ change: MetadataExchangeFieldChange) -> NSView {
        let currentValue = valueLabel(change.currentValue, emptyText: "Empty", monospaced: false, color: change.currentValue.isEmpty ? .secondaryLabelColor : .labelColor)
        let importedValue = valueLabel(change.importedValue, emptyText: "Empty", monospaced: false, color: change.importedValue.isEmpty ? .secondaryLabelColor : (change.willWrite ? .systemGreen : .labelColor))
        let content = horizontalStack(spacing: 14, alignment: .top, views: [
            label(change.field.displayName, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, width: 118),
            currentValue,
            symbol(change.willWrite ? "pencil.circle.fill" : "equal.circle.fill", color: change.willWrite ? .systemGreen : .secondaryLabelColor, width: 18),
            importedValue
        ])
        currentValue.widthAnchor.constraint(equalTo: importedValue.widthAnchor).isActive = true

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
        width: CGFloat? = nil,
        maximumLines: Int = 0
    ) -> NSTextField {
        let textField = NSTextField(labelWithString: text)
        textField.font = font
        textField.textColor = color
        textField.backgroundColor = .clear
        textField.lineBreakMode = maximumLines == 1 ? .byTruncatingTail : .byWordWrapping
        textField.maximumNumberOfLines = maximumLines
        textField.cell?.wraps = maximumLines != 1
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
        emptyText: String,
        monospaced: Bool,
        fontSize: CGFloat = 12,
        color: NSColor,
        maximumLines: Int = 0
    ) -> NSTextField {
        let textField = label(
            value.isEmpty ? emptyText : value,
            font: monospaced ? .monospacedSystemFont(ofSize: fontSize, weight: .regular) : .systemFont(ofSize: fontSize),
            color: color,
            maximumLines: maximumLines
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

private struct MetadataExchangeImportRowView: View {
    let row: MetadataExchangeImportPreviewRow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Text(row.externalRecord.isEmpty ? "No external record" : row.externalRecord)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Label(row.status.title, systemImage: row.status.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(row.status.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(row.status.tint.opacity(0.12)))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if let issueMessage = row.issueMessage {
                Text(issueMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(row.status.isIssue ? row.status.tint : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }

            if !row.changes.isEmpty {
                Divider()
                    .padding(.leading, 18)

                MetadataExchangeImportHeader()

                ForEach(Array(row.changes.enumerated()), id: \.element.id) { index, change in
                    MetadataExchangeImportChangeRow(change: change)

                    if index < row.changes.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
        }
    }
}

private struct MetadataExchangeImportHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Field")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            Text("Current")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 18)

            Text("Imported")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}

private struct MetadataExchangeImportChangeRow: View {
    let change: MetadataExchangeFieldChange

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(change.field.displayName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)

            metadataValue(change.currentValue)

            Image(systemName: change.willWrite ? "pencil.circle.fill" : "equal.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(change.willWrite ? Color.green : Color.secondary)
                .frame(width: 18)
                .padding(.top, 1)

            metadataValue(change.importedValue, highlight: change.willWrite)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func metadataValue(_ value: String, highlight: Bool = false) -> some View {
        Text(value.isEmpty ? "Empty" : value)
            .font(.system(size: 12))
            .foregroundStyle(value.isEmpty ? Color.secondary : (highlight ? Color.green : Color.primary))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension MetadataExchangePreviewStatus {
    var nsTint: NSColor {
        switch self {
        case .ready:
            return .systemGreen
        case .unchanged, .extraExternalRecord, .noWritableFields:
            return .secondaryLabelColor
        case .noMatch, .ambiguousMatch, .parseError, .sourceUnavailable, .missingExternalRecord:
            return .systemOrange
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unchanged:
            return "equal.circle.fill"
        case .noMatch, .ambiguousMatch, .parseError, .sourceUnavailable, .missingExternalRecord:
            return "exclamationmark.triangle.fill"
        case .extraExternalRecord, .noWritableFields:
            return "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready:
            return .green
        case .unchanged, .extraExternalRecord, .noWritableFields:
            return .secondary
        case .noMatch, .ambiguousMatch, .parseError, .sourceUnavailable, .missingExternalRecord:
            return .orange
        }
    }
}
#endif
