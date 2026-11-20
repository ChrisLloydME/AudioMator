import SwiftUI
import AppKit

/// Native macOS date and time picker supporting precision selection, optional
/// time/seconds, regional time zones with automatic UTC conversion, and
/// explicit DST transition resolution.
struct MetadataDateTimePickerView: View {
    let fieldTitle: String
    @Binding var session: MetadataDateTimePickerSession
    let onApply: (String) -> Void
    let onCancel: () -> Void

    @State private var yearInputText: String = ""

    private var destinationFormat: MetadataDateDestinationFormat {
        session.destinationFormat
    }

    private var precisionBinding: Binding<MetadataDatePrecision> {
        Binding(
            get: { session.datePrecision },
            set: { precision in
                if session.datePrecision == .date {
                    syncYearInputText()
                }
                session.setDatePrecision(precision)
            }
        )
    }

    private var timeEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.isTimeEnabled },
            set: { session.setTimeEnabled($0) }
        )
    }

    private var secondsEnabledBinding: Binding<Bool> {
        Binding(
            get: { session.isSecondsEnabled },
            set: { session.setSecondsEnabled($0) }
        )
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { session.localComponents.month },
            set: { session.setMonth($0) }
        )
    }

    private var yearInputBinding: Binding<String> {
        Binding(
            get: { yearInputText },
            set: { text in
                yearInputText = text
                if let year = MetadataDateTimeCodec.pickerYear(from: text) {
                    session.setYear(year)
                }
            }
        )
    }

    private var formattedValue: String? {
        guard session.datePrecision == .date ||
                MetadataDateTimeCodec.pickerYear(from: yearInputText) == session.localComponents.year else {
            return nil
        }
        return session.formattedValue
    }

    private var yearStepperBinding: Binding<Int> {
        Binding(
            get: { session.localComponents.year },
            set: { newYear in
                session.setYear(newYear)
                yearInputText = String(format: "%04d", session.localComponents.year)
            }
        )
    }

    private var localizedMonthSymbols: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        let symbols = calendar.standaloneMonthSymbols
        return symbols.count == 12 ? symbols : (1...12).map { String($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            if destinationFormat.orderedDatePrecisions.count > 1 {
                precisionPicker
            }

            dateInputSection

            if destinationFormat.supportsTime {
                Divider()
                timeInputSection
            }

            if let formatted = formattedValue {
                Divider()
                previewSection(formatted)
            }

            actionButtonsSection
        }
        .padding(14)
        .frame(width: 304)
        .onAppear {
            syncYearInputText()
        }
        .onChange(of: session.localComponents.year) { _, year in
            if MetadataDateTimeCodec.pickerYear(from: yearInputText) != year {
                syncYearInputText()
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(fieldTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 0)

            if destinationFormat.orderedDatePrecisions == [.year] {
                Text(String(localized: "Year Only"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var precisionPicker: some View {
        Picker(String(localized: "Date Precision"), selection: precisionBinding) {
            ForEach(destinationFormat.orderedDatePrecisions, id: \.self) { precision in
                Text(precisionLabel(for: precision))
                    .tag(precision)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(String(localized: "Date Precision"))
    }

    @ViewBuilder
    private var dateInputSection: some View {
        switch session.datePrecision {
        case .date:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(String(localized: "Date"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    NativeMacTextualDatePicker(
                        year: session.localComponents.year,
                        month: session.localComponents.month,
                        day: session.localComponents.day,
                        accessibilityLabel: String(localized: "Date"),
                        onDateSelected: { year, month, day in
                            session.setDate(year: year, month: month, day: day)
                        }
                    )
                    .fixedSize()
                }

                HStack {
                    Spacer(minLength: 0)
                    NativeMacGraphicalCalendarPicker(
                        year: session.localComponents.year,
                        month: session.localComponents.month,
                        day: session.localComponents.day,
                        accessibilityLabel: String(localized: "Calendar"),
                        onDateSelected: { year, month, day in
                            session.setDate(year: year, month: month, day: day)
                        }
                    )
                    .fixedSize()
                    Spacer(minLength: 0)
                }
            }

        case .yearMonth:
            VStack(alignment: .leading, spacing: 10) {
                yearRow
                HStack(alignment: .center, spacing: 8) {
                    Text(String(localized: "Month"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Picker(String(localized: "Month"), selection: monthBinding) {
                        ForEach(1...12, id: \.self) { monthIndex in
                            Text(localizedMonthSymbols[monthIndex - 1])
                                .tag(monthIndex)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 136, alignment: .trailing)
                    .accessibilityLabel(String(localized: "Month"))
                }
            }

        case .year:
            yearRow
        }
    }

    private var yearRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(String(localized: "Year"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                TextField(String(localized: "Year"), text: yearInputBinding)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                    .accessibilityLabel(String(localized: "Year"))

                Stepper(String(localized: "Year"), value: yearStepperBinding, in: 1...9999)
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "Adjust Year"))
            }

            if MetadataDateTimeCodec.pickerYear(from: yearInputText) == nil {
                Text(String(localized: "Enter a year from 1 to 9999."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var timeInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(String(localized: "Add Time"), isOn: timeEnabledBinding)

            if session.isTimeEnabled {
                HStack(alignment: .center, spacing: 8) {
                    Text(String(localized: "Time"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    NativeMacTimePicker(
                        hour: session.localComponents.hour,
                        minute: session.localComponents.minute,
                        second: session.localComponents.second,
                        includesSeconds: session.isSecondsEnabled,
                        accessibilityLabel: String(localized: "Time"),
                        onTimeSelected: { hour, minute, second in
                            session.setTime(
                                hour: hour, minute: minute,
                                second: session.isSecondsEnabled ? second : nil
                            )
                        }
                    )
                    .fixedSize()
                }

                if destinationFormat.supportsSeconds && destinationFormat.supportsMinuteTime {
                    Toggle(String(localized: "Include Seconds"), isOn: secondsEnabledBinding)
                }

                timeZonePickerRow

                if let resolution = session.localTimeResolution {
                    dstResolutionSection(for: resolution)
                }

                if !session.requiresDSTResolution && !session.canApply {
                    precisionWarning
                }
            }
        }
    }

    private var precisionWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.isUTCYearOutOfRange
                ? String(localized: "The converted UTC year must be from 1 to 9999.")
                : String(localized: "This tag can’t store the selected time at this precision."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let precision = session.finerTimePrecision {
                Button(precision == .minute
                    ? String(localized: "Use Minute Precision")
                    : String(localized: "Use Second Precision")) {
                    session.useFinerTimePrecision()
                }
            }
        }
    }

    private var timeZonePickerRow: some View {
        let referenceDate = session.resolvedInstant
            ?? session.localComponents.calendarAnchorDate(in: session.timeZone)
        let currentEntry = RegionalTimeZoneCatalog.entry(for: session.timeZone, at: referenceDate).title

        return HStack(alignment: .center, spacing: 8) {
            Text(String(localized: "Time Zone"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Menu {
                timeZoneMenuContent(referenceDate: referenceDate)
            } label: {
                Text(currentEntry)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 184, alignment: .trailing)
            .accessibilityLabel(String(localized: "Time Zone"))
            .accessibilityValue(currentEntry)
        }
    }

    @ViewBuilder
    private func timeZoneMenuContent(referenceDate: Date) -> some View {
        let catalog = RegionalTimeZoneCatalog.grouped(referenceDate: referenceDate)

        Button {
            session.setTimeZone(identifier: catalog.systemEntry.identifier)
        } label: {
            Text(String(localized: "System — \(catalog.systemEntry.title)"))
        }

        if catalog.utcEntry.identifier != catalog.systemEntry.identifier {
            Button {
                session.setTimeZone(identifier: catalog.utcEntry.identifier)
            } label: {
                Text(catalog.utcEntry.title)
            }
        }

        Divider()

        ForEach(catalog.regionGroups, id: \.id) { group in
            Menu(group.title) {
                ForEach(group.entries) { entry in
                    Button {
                        session.setTimeZone(identifier: entry.identifier)
                    } label: {
                        Text(entry.title)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dstResolutionSection(for resolution: MetadataLocalTimeResolution) -> some View {
        switch resolution {
        case .unique:
            EmptyView()

        case .ambiguous(let earlier, let later):
            dstCallout(
                message: String(localized: "This local time occurs twice due to daylight saving time. Choose which occurrence to use:"),
                options: [earlier, later]
            )

        case .nonexistent(let options):
            dstCallout(
                message: String(localized: "This local time doesn’t exist in \(session.timeZone.identifier) due to daylight saving time. Choose a valid time:"),
                options: options
            )
        }
    }

    private func dstCallout(
        message: String,
        options: [MetadataDSTResolutionOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(
                String(localized: "Local Time"),
                selection: Binding(
                    get: { session.selectedDSTOptionID },
                    set: { optionID in
                        if let optionID {
                            session.selectDSTResolution(optionID: optionID)
                        }
                    }
                )
            ) {
                ForEach(options) { option in
                    let primary = dstOptionPrimaryLabel(option)
                    let label = dstOptionUTCDetail(option).map { "\(primary)\n\($0)" } ?? primary
                    Text(label)
                        .tag(Optional(option.id))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func previewSection(_ formatted: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(localized: "Tag Value"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(formatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            if destinationFormat.requiresUTC && session.isTimeEnabled {
                Text(String(localized: "Converted automatically to UTC for this tag."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 8) {
            Button(String(localized: "Cancel"), role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer(minLength: 0)

            Button(String(localized: "Apply")) {
                if let formattedValue {
                    onApply(formattedValue)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(formattedValue == nil)
        }
    }

    private func syncYearInputText() {
        let expected = String(format: "%04d", session.localComponents.year)
        if yearInputText != expected {
            yearInputText = expected
        }
    }

    private func precisionLabel(for precision: MetadataDatePrecision) -> String {
        switch precision {
        case .year:
            return String(localized: "Year")
        case .yearMonth:
            return String(localized: "Year & Month")
        case .date:
            return String(localized: "Full Date")
        }
    }

    private func dstOptionPrimaryLabel(_ option: MetadataDSTResolutionOption) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = session.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = session.isSecondsEnabled ? .medium : .short
        let localizedTime = formatter.string(from: option.date)

        let roleNote: String
        switch option.role {
        case .earlierOccurrence:
            roleNote = String(localized: "First occurrence")
        case .laterOccurrence:
            roleNote = String(localized: "Second occurrence")
        case .shiftForward:
            roleNote = String(localized: "After spring-forward")
        case .transitionStart:
            roleNote = String(localized: "Start of daylight saving time")
        case .shiftBackward:
            roleNote = String(localized: "Before spring-forward")
        }

        return "\(localizedTime) \(option.abbreviation) (\(option.formattedGMTOffset)) — \(roleNote)"
    }

    private func dstOptionUTCDetail(_ option: MetadataDSTResolutionOption) -> String? {
        guard destinationFormat.requiresUTC else { return nil }
        guard let formatted = MetadataDateTimeCodec.format(
            localComponents: option.localComponents,
            datePrecision: .date,
            timePrecision: session.timePrecision,
            timeZone: session.timeZone,
            resolvedDate: option.date,
            destinationFormat: destinationFormat
        ) else {
            return nil
        }
        return String(localized: "UTC: \(formatted)")
    }
}

private struct RegionalTimeZoneCatalog {
    struct Entry: Identifiable {
        let identifier: String
        let title: String

        var id: String { identifier }
    }

    struct RegionGroup {
        let id: String
        let title: String
        let entries: [Entry]
    }

    private static let regionalZones = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers.compactMap {
        TimeZone(identifier: $0)
    }.filter { !["UTC", "GMT"].contains($0.identifier) }) { zone in
        if zone.identifier.contains("/"), !zone.identifier.hasPrefix("Etc/") {
            return String(zone.identifier.prefix { $0 != "/" })
        }
        return "Other"
    }

    let systemEntry: Entry
    let utcEntry: Entry
    let regionGroups: [RegionGroup]

    static func grouped(referenceDate: Date) -> RegionalTimeZoneCatalog {
        let formatter = cityFormatter()
        let groups = regionalZones.map { region, zones in
            let entries = zones.map { entry(for: $0, at: referenceDate, formatter: formatter) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return RegionGroup(id: region, title: regionTitle(region), entries: entries)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return RegionalTimeZoneCatalog(
            systemEntry: entry(for: .autoupdatingCurrent, at: referenceDate, formatter: formatter),
            utcEntry: Entry(identifier: "UTC", title: "UTC"),
            regionGroups: groups
        )
    }

    static func entry(for zone: TimeZone, at date: Date) -> Entry {
        entry(for: zone, at: date, formatter: cityFormatter())
    }

    private static func cityFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        // Unicode date pattern VVV requests the localized exemplar city.
        formatter.dateFormat = "VVV"
        return formatter
    }

    private static func entry(for zone: TimeZone, at date: Date, formatter: DateFormatter) -> Entry {
        if ["UTC", "GMT"].contains(zone.identifier) {
            return Entry(identifier: zone.identifier, title: "UTC")
        }
        let offset = MetadataDSTResolutionOption.formatGMTOffset(seconds: zone.secondsFromGMT(for: date))
        guard zone.identifier.contains("/"), !zone.identifier.hasPrefix("Etc/") else {
            let label = zone.localizedName(for: .generic, locale: .autoupdatingCurrent) ?? zone.identifier
            return Entry(identifier: zone.identifier, title: "\(label) (\(offset))")
        }
        formatter.timeZone = zone
        let city = formatter.string(from: date)
        return Entry(identifier: zone.identifier, title: "\(city) (\(offset))")
    }

    private static func regionTitle(_ region: String) -> String {
        switch region {
        case "Africa": return String(localized: "Africa")
        case "America": return String(localized: "Americas")
        case "Antarctica": return String(localized: "Antarctica")
        case "Arctic": return String(localized: "Arctic")
        case "Asia": return String(localized: "Asia")
        case "Atlantic": return String(localized: "Atlantic")
        case "Australia": return String(localized: "Australia")
        case "Europe": return String(localized: "Europe")
        case "Indian": return String(localized: "Indian Ocean")
        case "Pacific": return String(localized: "Pacific")
        case "Other": return String(localized: "Other")
        default: return region
        }
    }
}
