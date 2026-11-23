import AppKit
import SwiftUI

/// The button owns presentation. Its panel owns a nonoptional editing copy, so
/// closing the sheet cannot invalidate a binding held by the closing view.
struct MetadataDatePickerButton<Scope: Equatable, ButtonLabel: View>: View {
    let scope: Scope
    let title: String
    let value: String
    let format: MetadataDateDestinationFormat
    let onApply: (Scope, String) -> Void
    @ViewBuilder let label: () -> ButtonLabel

    private struct Presentation: Identifiable {
        let id = UUID()
        let scope: Scope
        let session: MetadataDateTimePickerSession
        let viewport: MetadataDatePickerViewport
    }

    private final class WeakWindowBox {
        weak var window: NSWindow?
    }

    @State private var presentation: Presentation?
    @State private var hostWindowBox = WeakWindowBox()

    var body: some View {
        Button {
            let window = hostWindowBox.window ?? NSApp.keyWindow
            let preferred = MetadataDatePickerViewport.preferredHostSize
            presentation = Presentation(
                scope: scope,
                session: MetadataDateTimePickerSession(initialText: value, destinationFormat: format),
                viewport: MetadataDatePickerViewport(
                    window: window?.contentView?.bounds.size ?? preferred,
                    screen: window?.screen?.visibleFrame.size ?? preferred
                )
            )
        } label: {
            label()
        }
        .background(HostWindowAccessor { hostWindowBox.window = $0 })
        .sheet(item: $presentation) { item in
            MetadataDatePickerPanel(title: title, session: item.session, viewport: item.viewport) { value in
                guard presentation?.id == item.id else { return }
                presentation = nil
                if let value {
                    onApply(item.scope, value)
                }
            }
            .id(item.id)
        }
        .onChange(of: scope) { _, _ in presentation = nil }
        .onChange(of: format) { _, _ in presentation = nil }
    }
}

private struct HostWindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.onWindowChange = onWindowChange
        onWindowChange(nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowObserverView, coordinator: ()) {
        nsView.onWindowChange = nil
    }

    final class WindowObserverView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}

private struct MetadataDatePickerPanel: View {
    let title: String
    @State var session: MetadataDateTimePickerSession
    let viewport: MetadataDatePickerViewport
    let onClose: (String?) -> Void
    @State private var yearText: String?
    @State private var contentHeight: CGFloat?
    @State private var actionBarHeight: CGFloat?

    private var canAddTime: Bool {
        session.datePrecision == .date && session.destinationFormat.supportsTime
    }

    private var yearBinding: Binding<String> {
        Binding {
            yearText ?? String(format: "%04d", session.localComponents.year)
        } set: { text in
            yearText = text
            if let year = MetadataDateTimeCodec.pickerYear(from: text) {
                session.setYear(year)
            }
        }
    }

    private var valueToApply: String? {
        if session.datePrecision == .year, let yearText,
           MetadataDateTimeCodec.pickerYear(from: yearText) == nil {
            return nil
        }
        return session.formattedValue
    }

    private var timeZoneReference: Date {
        session.resolvedInstant ?? session.localComponents.calendarAnchorDate(in: session.timeZone)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title3.weight(.semibold))
                fields
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, viewport.horizontalInset)
            .padding(.top, MetadataDatePickerViewport.contentInset)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .audiomatorSafeAreaBar(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, viewport.horizontalInset)
                .padding(.top, 12)
                .padding(.bottom, MetadataDatePickerViewport.contentInset)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { actionBarHeight = $0 }
        }
        .audiomatorScrollEdgeEffect(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: viewport.size.width, height: sheetHeight)
    }

    private var sheetHeight: CGFloat {
        guard let contentHeight, let actionBarHeight else { return viewport.size.height }
        return min(ceil(contentHeight + actionBarHeight), viewport.size.height)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            dateSection
            if canAddTime {
                timeSection
            }
        }
    }

    private var dateSection: some View {
        MacSettingsSection(title: nil) {
            if session.destinationFormat.orderedDatePrecisions.count > 1 {
                settingsRow("Date Precision") { datePrecisionInput }
                settingsDivider
            }
            settingsRow(session.datePrecision == .year ? "Year" : "Date") { dateInput }
            if session.datePrecision == .date {
                settingsDivider
                dateControl(style: .clockAndCalendar, label: String(localized: "Calendar"))
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            if !canAddTime {
                settingsDivider
                tagValuePreview
            }
        }
    }

    private var timeSection: some View {
        MacSettingsSection(title: nil) {
            settingsRow("Add Time") {
                Toggle("Add Time", isOn: Binding(
                    get: { session.isTimeEnabled },
                    set: { session.setTimeEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            if session.isTimeEnabled {
                settingsDivider
                settingsRow("Time") { timeInput }
                if session.destinationFormat.orderedTimePrecisions.count > 1 {
                    settingsDivider
                    settingsRow("Time Precision") {
                        Picker("Time Precision", selection: Binding(
                            get: { session.timePrecision },
                            set: { session.setTimePrecision($0) }
                        )) {
                            ForEach(session.destinationFormat.orderedTimePrecisions, id: \.self) { precision in
                                Text(timePrecisionTitle(precision)).tag(precision)
                            }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                settingsDivider
                settingsRow("Time Zone") {
                    MetadataTimeZonePicker(
                        current: session.timeZone,
                        reference: timeZoneReference,
                        onSelection: { session.setTimeZone(identifier: $0) }
                    )
                    .frame(idealWidth: 190, maxWidth: 210)
                }
                if !session.dstResolutionOptions.isEmpty || !session.canApply {
                    settingsDivider
                    VStack(alignment: .leading, spacing: 6) { timeIssues }
                        .padding(.horizontal, rowInset)
                        .padding(.vertical, 10)
                }
            }
            settingsDivider
            tagValuePreview
        }
    }

    private func settingsRow<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        let label = Text(title).accessibilityHidden(true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                label.fixedSize()
                Spacer(minLength: 0)
                content()
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                content()
            }
        }
        .padding(.horizontal, rowInset)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsDivider: some View {
        Divider().padding(.horizontal, rowInset)
    }

    private var rowInset: CGFloat {
        viewport.bodyWidth < 240 ? 10 : 18
    }

    private var datePrecisionInput: some View {
        Picker("Date Precision", selection: Binding(
            get: { session.datePrecision },
            set: {
                yearText = nil
                session.setDatePrecision($0)
            }
        )) {
            ForEach(session.destinationFormat.orderedDatePrecisions, id: \.self) { precision in
                Text(precisionTitle(precision)).tag(precision)
            }
        }
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(alignment: .trailing, spacing: 8) { actionButtons }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var tagValuePreview: some View {
        let label: LocalizedStringKey = session.isTimeEnabled && session.destinationFormat.requiresUTC
            ? "Tag Value Preview (UTC)" : "Tag Value Preview"
        let value = valueToApply ?? "—"
        return settingsRow(label) {
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(value))
        }
    }

    private var actionButtons: some View {
        Group {
            Button("Cancel", role: .cancel) { onClose(nil) }
                .keyboardShortcut(.cancelAction)
            Button("Apply") {
                if let valueToApply { onClose(valueToApply) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(valueToApply == nil)
        }
    }

    @ViewBuilder
    private var dateInput: some View {
        if session.datePrecision == .year {
            VStack(alignment: .trailing, spacing: 6) {
                TextField("Year", text: yearBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                if valueToApply == nil {
                    Text("Enter a year from 1 to 9999.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            segmentedInput {
                dateControl(style: .textField, label: String(localized: "Date"))
            }
        }
    }

    private func dateControl(style: NSDatePicker.Style, label: String) -> some View {
        NativeMacDatePicker(
            year: session.localComponents.year,
            month: session.localComponents.month,
            day: session.localComponents.day,
            includesDay: session.datePrecision == .date,
            style: style,
            accessibilityLabel: label,
            onDateSelected: { year, month, day in
                let current = session.localComponents
                guard (year, month, day) != (current.year, current.month, current.day) else { return }
                session.setDate(year: year, month: month, day: day)
            }
        )
    }

    private var timeInput: some View {
        segmentedInput {
            NativeMacTimePicker(
                hour: session.localComponents.hour,
                minute: session.localComponents.minute,
                second: session.localComponents.second,
                includesSeconds: session.isSecondsEnabled,
                accessibilityLabel: String(localized: "Time"),
                onTimeSelected: {
                    session.setTime(hour: $0, minute: $1, second: session.isSecondsEnabled ? $2 : nil)
                }
            )
        }
    }

    private func segmentedInput<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 6))
    }

    @ViewBuilder
    private var timeIssues: some View {
        if !session.dstResolutionOptions.isEmpty {
            dstOptions
        }
        if session.isUTCYearOutOfRange {
            Text("The converted UTC year must be from 1 to 9999.").font(.caption)
        } else if !session.requiresDSTResolution && !session.canApply {
            VStack(alignment: .leading, spacing: 6) {
                if session.timePrecision == .hour, session.selectedDSTOption != nil {
                    Text("Hour precision can’t preserve the selected daylight saving time choice.").font(.caption)
                } else {
                    Text("This tag can’t store the selected time at this precision.").font(.caption)
                }
                if let precision = session.finerTimePrecision {
                    Button(precision == .minute ? "Use Minute Precision" : "Use Second Precision") {
                        session.useFinerTimePrecision()
                    }
                }
            }
        }
    }

    private var dstOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .nonexistent = session.localTimeResolution {
                Text("This local time doesn’t exist. Choose a valid time.")
            } else {
                Text("This local time occurs twice. Choose an occurrence.")
            }
            Picker("Local Time", selection: Binding(
                get: { session.selectedDSTOptionID },
                set: { if let id = $0 { session.selectDSTResolution(optionID: id) } }
            )) {
                ForEach(session.dstResolutionOptions) { option in
                    Text(dstOptionTitle(option)).tag(Optional(option.id))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .font(.caption)
    }

    private func dstOptionTitle(_ option: MetadataDSTResolutionOption) -> String {
        let staged = session.valueToStage(for: option)
        let local = (staged?.instant ?? option.date).formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: session.timePrecision == .second ? .standard : .shortened,
                timeZone: session.timeZone
            )
        )
        let label = "\(local) (\(option.formattedGMTOffset))"
        guard session.destinationFormat.requiresUTC, let stored = staged?.value else {
            return label
        }
        return String(localized: "\(label), UTC: \(stored)")
    }

    private func precisionTitle(_ precision: MetadataDatePrecision) -> LocalizedStringKey {
        switch precision {
        case .year: return "Year"
        case .yearMonth: return "Year & Month"
        case .date: return "Full Date"
        }
    }

    private func timePrecisionTitle(_ precision: MetadataTimePrecision) -> LocalizedStringKey {
        switch precision {
        case .none: return "Date Only"
        case .hour: return "Hour"
        case .minute: return "Minute"
        case .second: return "Second"
        }
    }
}

#if DEBUG
#Preview("Release Date · Calendar", traits: .sizeThatFitsLayout) {
    MetadataDatePickerPanel(
        title: "Release Date",
        session: MetadataDateTimePickerSession(initialText: "2017-11-03", destinationFormat: .id3v24Timestamp),
        viewport: MetadataDatePickerViewport(
            window: CGSize(width: 860, height: 540),
            screen: CGSize(width: 1440, height: 900)
        ),
        onClose: { _ in }
    )
}

#Preview("Release Date · Date and Time", traits: .sizeThatFitsLayout) {
    MetadataDatePickerPanel(
        title: "Release Date",
        session: MetadataDateTimePickerSession(
            initialText: "2017-11-03T04:00",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        ),
        viewport: MetadataDatePickerViewport(
            window: CGSize(width: 860, height: 600),
            screen: CGSize(width: 1440, height: 900)
        ),
        onClose: { _ in }
    )
}

#Preview("Purchase Date · Time Zone Dropdown", traits: .sizeThatFitsLayout) {
    MetadataDatePickerPanel(
        title: "Purchase Date",
        session: MetadataDateTimePickerSession(
            initialText: "2017-11-03T04:00Z",
            destinationFormat: .utcTextTimestamp,
            systemTimeZone: TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        ),
        viewport: MetadataDatePickerViewport(
            window: CGSize(width: 860, height: 600),
            screen: CGSize(width: 1440, height: 900)
        ),
        onClose: { _ in }
    )
}

#Preview("Release Date · Narrow Window", traits: .sizeThatFitsLayout) {
    MetadataDatePickerPanel(
        title: "Release Date",
        session: MetadataDateTimePickerSession(initialText: "2017-11-03T12:30", destinationFormat: .id3v24Timestamp),
        viewport: MetadataDatePickerViewport(
            window: CGSize(width: 244, height: 230),
            screen: CGSize(width: 1440, height: 900)
        ),
        onClose: { _ in }
    )
}

#Preview("Release Date · Time and DST Choice", traits: .sizeThatFitsLayout) {
    var session = MetadataDateTimePickerSession(
        initialText: "2024-11-03",
        destinationFormat: .id3v24Timestamp,
        systemTimeZone: TimeZone(identifier: "America/New_York") ?? .gmt
    )
    session.setTimeEnabled(true)
    session.setTime(hour: 1, minute: 30)
    return MetadataDatePickerPanel(
        title: "Release Date",
        session: session,
        viewport: MetadataDatePickerViewport(
            window: CGSize(width: 860, height: 600),
            screen: CGSize(width: 1440, height: 900)
        ),
        onClose: { _ in }
    )
}
#endif
