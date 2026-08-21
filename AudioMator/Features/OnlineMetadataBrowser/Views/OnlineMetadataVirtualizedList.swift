#if os(macOS)
import AppKit
import SwiftUI

struct OnlineMetadataVirtualizedList<Row: Equatable>: NSViewRepresentable {
    let rows: [Row]
    let contentVersion: String
    let rowID: (Row) -> AnyHashable
    let estimatedRowHeight: (Row) -> CGFloat
    let rowHeight: (Row, CGFloat, OnlineMetadataTextHeightCache) -> CGFloat
    let makeRowView: (Row) -> NSView

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> OnlineMetadataVirtualizedListContainer {
        let container = OnlineMetadataVirtualizedListContainer()
        container.listDelegate = context.coordinator
        context.coordinator.update(parent: self, container: container)
        return container
    }

    func updateNSView(_ nsView: OnlineMetadataVirtualizedListContainer, context: Context) {
        context.coordinator.update(parent: self, container: nsView)
    }

    final class Coordinator: NSObject, OnlineMetadataVirtualizedListContainerDelegate {
        private var parent: OnlineMetadataVirtualizedList
        private var renderedRows: [Row] = []
        private var renderedContentVersion = ""
        private var rowFrames: [CGRect] = []
        private var rowViews: [Int: OnlineMetadataVirtualizedRowView] = [:]
        private var layoutWidth: CGFloat = 0
        private var exactRowHeightsByWidth: [CGFloat: [Int: CGFloat]] = [:]
        private let textHeightCache = OnlineMetadataTextHeightCache()

        init(parent: OnlineMetadataVirtualizedList) {
            self.parent = parent
        }

        func update(parent: OnlineMetadataVirtualizedList, container: OnlineMetadataVirtualizedListContainer) {
            container.totalConfigurationUpdateCount += 1
            let previousRows = renderedRows
            let previousIDs = previousRows.map(self.parent.rowID)
            let nextIDs = parent.rows.map(parent.rowID)
            let contentChanged = renderedContentVersion != parent.contentVersion
            self.parent = parent
            renderedRows = parent.rows
            renderedContentVersion = parent.contentVersion
            container.totalRowCount = parent.rows.count

            if previousIDs != nextIDs || contentChanged {
                removeAllRows()
                layoutWidth = 0
                exactRowHeightsByWidth.removeAll(keepingCapacity: true)
            } else {
                for index in parent.rows.indices where previousRows[index] != parent.rows[index] {
                    removeRow(at: index)
                }
                if previousRows != parent.rows {
                    exactRowHeightsByWidth.removeAll(keepingCapacity: true)
                }
            }
            let measurementWidth = container.bounds.width > 1 ? container.bounds.width : 900
            container.setIntrinsicContentHeight(contentHeight(for: measurementWidth))
            layoutVisibleRows(in: container)
        }

        func visibleRectDidChange(in container: OnlineMetadataVirtualizedListContainer) {
            layoutVisibleRows(in: container)
        }

        func contentHeight(for width: CGFloat) -> CGFloat {
            ceil(rowHeights(for: width).reduce(0, +))
        }

        private func layoutVisibleRows(in container: OnlineMetadataVirtualizedListContainer) {
            guard container.bounds.width > 1 else { return }
            let width = container.bounds.width
            prepareRowFrames(for: width)
            container.setIntrinsicContentHeight(contentHeight(for: width))

            let visibleRect = container.outerVisibleRect
            guard !visibleRect.isEmpty else { return }
            let bufferedRect = visibleRect.insetBy(dx: 0, dy: -max(visibleRect.height, 300))
            let estimatedVisibleIndexes = Set(
                rowFrames.indices.filter { rowFrames[$0].intersects(bufferedRect) }
            )
            if measureExactHeights(
                at: estimatedVisibleIndexes,
                width: width,
                container: container
            ) {
                rebuildRowFrames(for: width)
                container.setIntrinsicContentHeight(contentHeight(for: width))
            }
            let visibleIndexes = Set(
                rowFrames.indices.filter { rowFrames[$0].intersects(bufferedRect) }
            )

            for index in rowViews.keys.filter({ !visibleIndexes.contains($0) }) {
                removeRow(at: index)
            }

            for index in visibleIndexes.sorted() {
                let rowView: OnlineMetadataVirtualizedRowView
                if let existing = rowViews[index] {
                    rowView = existing
                } else {
                    rowView = OnlineMetadataVirtualizedRowView()
                    rowView.setContent(
                        parent.makeRowView(parent.rows[index]),
                        showsDivider: index < parent.rows.count - 1
                    )
                    container.totalMaterializedRowBuildCount += 1
                    rowViews[index] = rowView
                    container.addSubview(rowView)
                }
                rowView.frame = rowFrames[index]
            }
        }

        private func prepareRowFrames(for width: CGFloat) {
            guard abs(width - layoutWidth) > 0.5 || rowFrames.count != parent.rows.count else { return }
            layoutWidth = width
            removeAllRows()
            rebuildRowFrames(for: width)
        }

        private func rebuildRowFrames(for width: CGFloat) {
            var nextY: CGFloat = 0
            rowFrames = rowHeights(for: width).map { height in
                defer { nextY += height }
                return CGRect(x: 0, y: nextY, width: width, height: height)
            }
        }

        private func rowHeights(for width: CGFloat) -> [CGFloat] {
            let exactHeights = exactRowHeightsByWidth[width] ?? [:]
            return parent.rows.indices.map { index in
                exactHeights[index] ?? parent.estimatedRowHeight(parent.rows[index])
            }
        }

        private func measureExactHeights(
            at indexes: Set<Int>,
            width: CGFloat,
            container: OnlineMetadataVirtualizedListContainer
        ) -> Bool {
            if exactRowHeightsByWidth.count >= 8, exactRowHeightsByWidth[width] == nil {
                exactRowHeightsByWidth.removeAll(keepingCapacity: true)
            }
            var exactHeights = exactRowHeightsByWidth[width] ?? [:]
            let missingIndexes = indexes.filter { exactHeights[$0] == nil }
            guard !missingIndexes.isEmpty else { return false }
            container.totalRowHeightMeasurementCount += missingIndexes.count
            for index in missingIndexes {
                exactHeights[index] = parent.rowHeight(parent.rows[index], width, textHeightCache)
            }
            exactRowHeightsByWidth[width] = exactHeights
            return true
        }

        private func removeAllRows() {
            for rowView in rowViews.values {
                rowView.removeFromSuperview()
            }
            rowViews.removeAll(keepingCapacity: true)
        }

        private func removeRow(at index: Int) {
            rowViews.removeValue(forKey: index)?.removeFromSuperview()
        }
    }
}

enum OnlineMetadataAssignmentRowLayout {
    static func height(
        width: CGFloat,
        title: String,
        subtitle: String,
        detailLines: [String],
        textHeightCache: OnlineMetadataTextHeightCache? = nil
    ) -> CGFloat {
        let innerWidth = max(width - 36, 1)
        let titleWidth = max(innerWidth - 410, 80)
        let titleHeight = textHeight(
            title,
            font: .systemFont(ofSize: 13, weight: .medium),
            width: titleWidth,
            cache: textHeightCache
        )
        let subtitleHeight = subtitle.isEmpty
            ? 0
            : 4 + textHeight(
                subtitle,
                font: .systemFont(ofSize: 11),
                width: titleWidth,
                cache: textHeightCache
            )
        let headerHeight = max(26, titleHeight + subtitleHeight)
        let detailsHeight = detailLines.reduce(CGFloat.zero) { result, line in
            result + 10 + textHeight(
                line,
                font: .systemFont(ofSize: 11),
                width: innerWidth,
                cache: textHeightCache
            )
        }
        return 24 + headerHeight + detailsHeight
    }

    static func estimatedHeight(hasSubtitle: Bool, detailLineCount: Int) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let detailFont = NSFont.systemFont(ofSize: 11)
        let titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
        let detailHeight = ceil(detailFont.ascender - detailFont.descender + detailFont.leading)
        let headerHeight = max(26, titleHeight + (hasSubtitle ? 4 + detailHeight : 0))
        return 24 + headerHeight + CGFloat(detailLineCount) * (10 + detailHeight)
    }

    static func textHeight(
        _ text: String,
        font: NSFont,
        width: CGFloat,
        cache: OnlineMetadataTextHeightCache? = nil
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        if let cache {
            return cache.height(for: text, font: font, width: width)
        }
        return measuredTextHeight(text, font: font, width: width)
    }

    static func measuredTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(max(bounds.height, font.ascender - font.descender + font.leading))
    }
}

final class OnlineMetadataTextHeightCache {
    private struct Key: Hashable {
        let text: String
        let fontName: String
        let pointSize: CGFloat
        let width: CGFloat
    }

    private var heights: [Key: CGFloat] = [:]

    func height(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let key = Key(text: text, fontName: font.fontName, pointSize: font.pointSize, width: width)
        if let height = heights[key] {
            return height
        }
        if heights.count >= 2_048 {
            heights.removeAll(keepingCapacity: true)
        }
        let height = OnlineMetadataAssignmentRowLayout.measuredTextHeight(
            text,
            font: font,
            width: width
        )
        heights[key] = height
        return height
    }
}

final class OnlineMetadataAssignmentRowView: NSView {
    let popUp: OnlineMetadataVirtualizedPopUpButton

    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField?
    private let detailLabels: [NSTextField]
    private let warningLabel: NSTextField?
    private let warningImageView: NSImageView?

    override var isFlipped: Bool { true }

    init(
        rowID: AnyHashable,
        title: String,
        subtitle: String,
        detailLines: [String],
        warning: String?,
        optionTitles: [String],
        selectedOptionIndex: Int?,
        isEnabled: Bool,
        onSelectionChange: @escaping (Int) -> Void
    ) {
        titleLabel = Self.label(
            title,
            font: .systemFont(ofSize: 13, weight: .medium),
            color: .labelColor
        )
        subtitleLabel = subtitle.isEmpty
            ? nil
            : Self.label(subtitle, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        detailLabels = detailLines.map {
            Self.label($0, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        }

        if let warning {
            warningLabel = Self.label(warning, font: .systemFont(ofSize: 11), color: .systemOrange)
            let imageView = NSImageView()
            imageView.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            imageView.contentTintColor = .systemOrange
            warningImageView = imageView
        } else {
            warningLabel = nil
            warningImageView = nil
        }

        popUp = OnlineMetadataVirtualizedPopUpButton(frame: .zero, pullsDown: false)
        super.init(frame: .zero)

        addSubview(titleLabel)
        if let subtitleLabel { addSubview(subtitleLabel) }
        for detailLabel in detailLabels { addSubview(detailLabel) }
        if let warningImageView { addSubview(warningImageView) }
        if let warningLabel { addSubview(warningLabel) }

        popUp.rowID = rowID
        popUp.controlSize = .regular
        popUp.setAccessibilityLabel(L10n.string("Track"))
        popUp.isEnabled = isEnabled
        popUp.configure(
            unassignedTitle: L10n.string("Unassigned"),
            optionTitles: optionTitles,
            selectedOptionIndex: selectedOptionIndex,
            onSelectionChange: onSelectionChange
        )
        addSubview(popUp)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        let horizontalPadding: CGFloat = 18
        let topPadding: CGFloat = 12
        let innerWidth = max(bounds.width - horizontalPadding * 2, 1)
        let popUpWidth = min(380, innerWidth)
        let titleWidth = max(innerWidth - 410, 80)
        let titleHeight = OnlineMetadataAssignmentRowLayout.textHeight(
            titleLabel.stringValue,
            font: titleLabel.font ?? .systemFont(ofSize: 13),
            width: titleWidth
        )
        titleLabel.frame = NSRect(
            x: horizontalPadding,
            y: topPadding,
            width: titleWidth,
            height: titleHeight
        )

        var titleStackHeight = titleHeight
        if let subtitleLabel {
            let subtitleHeight = OnlineMetadataAssignmentRowLayout.textHeight(
                subtitleLabel.stringValue,
                font: subtitleLabel.font ?? .systemFont(ofSize: 11),
                width: titleWidth
            )
            subtitleLabel.frame = NSRect(
                x: horizontalPadding,
                y: topPadding + titleHeight + 4,
                width: titleWidth,
                height: subtitleHeight
            )
            titleStackHeight += 4 + subtitleHeight
        }

        popUp.frame = NSRect(
            x: bounds.width - horizontalPadding - popUpWidth,
            y: topPadding,
            width: popUpWidth,
            height: 26
        )

        var nextY = topPadding + max(26, titleStackHeight)
        for detailLabel in detailLabels {
            nextY += 10
            let height = OnlineMetadataAssignmentRowLayout.textHeight(
                detailLabel.stringValue,
                font: detailLabel.font ?? .systemFont(ofSize: 11),
                width: innerWidth
            )
            detailLabel.frame = NSRect(
                x: horizontalPadding,
                y: nextY,
                width: innerWidth,
                height: height
            )
            nextY += height
        }

        if let warningLabel, let warningImageView {
            nextY += 10
            let iconWidth: CGFloat = 12
            let spacing: CGFloat = 5
            let labelWidth = max(innerWidth - iconWidth - spacing, 1)
            let height = OnlineMetadataAssignmentRowLayout.textHeight(
                warningLabel.stringValue,
                font: warningLabel.font ?? .systemFont(ofSize: 11),
                width: labelWidth
            )
            warningImageView.frame = NSRect(
                x: horizontalPadding,
                y: nextY,
                width: iconWidth,
                height: max(height, 13)
            )
            warningLabel.frame = NSRect(
                x: horizontalPadding + iconWidth + spacing,
                y: nextY,
                width: labelWidth,
                height: height
            )
        }
    }

    private static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let textField = NSTextField(labelWithString: text)
        textField.font = font
        textField.textColor = color
        textField.backgroundColor = .clear
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        return textField
    }
}

final class OnlineMetadataVirtualizedPopUpButton: NSPopUpButton, NSMenuDelegate {
    var rowID: AnyHashable?
    var onSelectionChange: ((Int) -> Void)?
    private var unassignedTitle = ""
    private var optionTitles: [String] = []
    private var selectedFullIndex = 0
    private var selectedDisplayTitle = ""
    private var isExpanded = false

    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        target = self
        action = #selector(selectionChanged)
        menu?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        unassignedTitle: String,
        optionTitles: [String],
        selectedOptionIndex: Int?,
        onSelectionChange: @escaping (Int) -> Void
    ) {
        self.unassignedTitle = unassignedTitle
        self.optionTitles = optionTitles
        selectedFullIndex = selectedOptionIndex.map { $0 + 2 } ?? 0
        selectedDisplayTitle = selectedOptionIndex.map { optionTitles[$0] } ?? unassignedTitle
        self.onSelectionChange = onSelectionChange
        collapseMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isExpanded else { return }
        isExpanded = true
        removeAllItems()
        addItem(withTitle: unassignedTitle)
        self.menu?.addItem(.separator())
        for title in optionTitles {
            addItem(withTitle: title)
        }
        selectItem(at: selectedFullIndex)
    }

    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in
            self?.collapseMenu()
        }
    }

    @objc
    private func selectionChanged() {
        let fullIndex = isExpanded ? indexOfSelectedItem : 0
        guard fullIndex != 1 else { return }
        selectedFullIndex = fullIndex
        if fullIndex >= 2, optionTitles.indices.contains(fullIndex - 2) {
            selectedDisplayTitle = optionTitles[fullIndex - 2]
        } else {
            selectedDisplayTitle = unassignedTitle
        }
        onSelectionChange?(fullIndex)
    }

    private func collapseMenu() {
        isExpanded = false
        removeAllItems()
        addItem(withTitle: selectedDisplayTitle)
        selectItem(at: 0)
        menu?.delegate = self
    }
}

@MainActor
protocol OnlineMetadataVirtualizedListContainerDelegate: AnyObject {
    func visibleRectDidChange(in container: OnlineMetadataVirtualizedListContainer)
}

final class OnlineMetadataVirtualizedListContainer: NSView {
    weak var listDelegate: OnlineMetadataVirtualizedListContainerDelegate?
    fileprivate(set) var totalRowCount = 0
    fileprivate(set) var totalConfigurationUpdateCount = 0
    fileprivate(set) var totalMaterializedRowBuildCount = 0
    fileprivate(set) var totalRowHeightMeasurementCount = 0
    private weak var observedClipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?
    private var intrinsicHeight: CGFloat = 0

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: intrinsicHeight)
    }

    var materializedRowCount: Int {
        subviews.lazy.filter { $0 is OnlineMetadataVirtualizedRowView }.count
    }

    var outerVisibleRect: CGRect {
        guard let observedClipView else { return visibleRect.intersection(bounds) }
        return convert(observedClipView.bounds, from: observedClipView).intersection(bounds)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        connectToOuterClipView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        connectToOuterClipView()
    }

    override func layout() {
        super.layout()
        connectToOuterClipView()
        listDelegate?.visibleRectDidChange(in: self)
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    fileprivate func setIntrinsicContentHeight(_ height: CGFloat) {
        guard abs(height - intrinsicHeight) > 0.5 else { return }
        intrinsicHeight = height
        invalidateIntrinsicContentSize()
    }

    private func connectToOuterClipView() {
        guard let clipView = enclosingScrollView?.contentView, clipView !== observedClipView else { return }
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.listDelegate?.visibleRectDidChange(in: self)
            }
        }
    }
}

private final class OnlineMetadataVirtualizedRowView: NSView {
    private var contentView: NSView?
    private let divider = NSBox()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        divider.boxType = .separator
        addSubview(divider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setContent(_ view: NSView, showsDivider: Bool) {
        contentView?.removeFromSuperview()
        contentView = view
        addSubview(view, positioned: .below, relativeTo: divider)
        divider.isHidden = !showsDivider
        needsLayout = true
    }

    override func layout() {
        super.layout()
        contentView?.frame = bounds
        divider.frame = NSRect(x: 18, y: bounds.height - 1, width: max(bounds.width - 18, 0), height: 1)
    }
}
#endif
