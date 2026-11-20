import SwiftUI
import AppKit

/// Presentation mode for the shared native macOS date & time picker.
enum MetadataDateTimePickerPresentation {
    /// Compact anchored popover used by the right-hand Inspector.
    case popover
    /// Inline side panel beside the value input in Metadata Editor.
    case inlinePanel
}

/// Native macOS date and time picker supporting precision selection, optional
/// time/seconds, regional time zones with automatic UTC conversion, and
/// explicit DST transition resolution.
struct MetadataDateTimePickerView: View {
    let fieldTitle: String
    let presentation: MetadataDateTimePickerPresentation
    @Binding var session: MetadataDateTimePickerSession
    let onApply: (String) -> Void
    var onCancel: (() -> Void)? = nil

    @State private var yearInputText: String = ""

    private var destinationFormat: MetadataDateDestinationFormat {
        session.destinationFormat
    }

    private var precisionBinding: Binding<MetadataDatePrecision> {
        Binding(
            get: { session.datePrecision },
            set: { session.setDatePrecision($0) }
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

            if let formatted = session.formattedValue {
                Divider()
                previewSection(formatted)
            }

            actionButtonsSection
        }
        .padding(presentation == .popover ? 14 : 12)
        .frame(width: presentation == .popover ? 304 : 296)
        .onAppear {
            syncYearInputText()
        }
        .onChange(of: session.localComponents.year) { _, _ in
            syncYearInputText()
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(presentation == .popover ? fieldTitle : (destinationFormat.supportsTime ? String(localized: "Date & Time") : String(localized: "Date")))
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
        HStack(alignment: .center, spacing: 8) {
            Text(String(localized: "Year"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                TextField(String(localized: "Year"), text: $yearInputText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                    .accessibilityLabel(String(localized: "Year"))
                    .onChange(of: yearInputText) { _, newText in
                        let digitsOnly = newText.filter(\.isNumber)
                        if let parsed = Int(digitsOnly), (1...9999).contains(parsed) {
                            session.setYear(parsed)
                        }
                    }
                    .onSubmit {
                        syncYearInputText()
                    }

                Stepper(String(localized: "Year"), value: yearStepperBinding, in: 1...9999)
                    .labelsHidden()
                    .accessibilityLabel(String(localized: "Adjust Year"))
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
            Text(String(localized: "This tag can’t store the selected time at this precision."))
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
        let currentEntry = currentTimeZoneDisplayLabel(referenceDate: referenceDate)

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
            Text(String(localized: "System — \(catalog.systemEntry.displayLabel)"))
        }

        if let utcEntry = catalog.utcEntry, utcEntry.identifier != catalog.systemEntry.identifier {
            Button {
                session.setTimeZone(identifier: utcEntry.identifier)
            } label: {
                Text(utcEntry.displayLabel)
            }
        }

        Divider()

        ForEach(catalog.regionGroups, id: \.region) { group in
            Menu(group.region) {
                ForEach(group.entries) { entry in
                    Button {
                        session.setTimeZone(identifier: entry.identifier)
                    } label: {
                        Text("\(entry.cityName) (\(entry.gmtOffsetText))")
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

            VStack(alignment: .leading, spacing: 4) {
                ForEach(options) { option in
                    let isSelected = session.selectedDSTOptionID == option.id
                    Button {
                        session.selectDSTResolution(optionID: option.id)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(dstOptionPrimaryLabel(option))
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                if let utcDetail = dstOptionUTCDetail(option) {
                                    Text(utcDetail)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dstOptionPrimaryLabel(option))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
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
            if presentation == .popover, let onCancel {
                Button(String(localized: "Cancel"), role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }

            Spacer(minLength: 0)

            if presentation == .popover {
                Button(String(localized: "Apply")) {
                    if let formatted = session.formattedValue {
                        onApply(formatted)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!session.canApply)
            } else {
                Button(String(localized: "Apply")) {
                    if let formatted = session.formattedValue {
                        onApply(formatted)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canApply)
            }
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

    private func currentTimeZoneDisplayLabel(referenceDate: Date) -> String {
        let tz = session.timeZone
        let offset = MetadataDSTResolutionOption.formatGMTOffset(seconds: tz.secondsFromGMT(for: referenceDate))
        if tz.identifier == "UTC" || tz.identifier == "GMT" {
            return "UTC (\(offset))"
        }
        let city = tz.identifier.split(separator: "/").last.map {
            String($0).replacingOccurrences(of: "_", with: " ")
        } ?? tz.identifier
        return "\(city) (\(offset))"
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
        return "UTC: \(formatted)"
    }
}

private struct RegionalTimeZoneCatalog {
    struct RegionGroup {
        let region: String
        let entries: [MetadataTimeZoneEntry]
    }

    private static let groupedIdentifiersByRegion: [(region: String, identifiers: [(id: String, city: String)])] = {
        var buckets: [String: [(id: String, city: String)]] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers where identifier != "UTC" && identifier != "GMT" {
            let parts = identifier.split(separator: "/").map {
                String($0).replacingOccurrences(of: "_", with: " ")
            }
            let topRegion = parts.count > 1 ? parts[0] : "Other"
            let city = parts.last ?? identifier
            buckets[topRegion, default: []].append((id: identifier, city: city))
        }
        return buckets.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.map { region in
            let sorted = (buckets[region] ?? []).sorted {
                $0.city.localizedStandardCompare($1.city) == .orderedAscending
            }
            return (region: region, identifiers: sorted)
        }
    }()

    let systemEntry: MetadataTimeZoneEntry
    let utcEntry: MetadataTimeZoneEntry?
    let regionGroups: [RegionGroup]

    static func grouped(referenceDate: Date) -> RegionalTimeZoneCatalog {
        let systemTZ = TimeZone.autoupdatingCurrent
        let systemParts = systemTZ.identifier.split(separator: "/").map {
            String($0).replacingOccurrences(of: "_", with: " ")
        }
        let system = MetadataTimeZoneEntry(
            identifier: systemTZ.identifier,
            cityName: systemParts.last ?? systemTZ.identifier,
            regionName: systemParts.count > 1 ? systemParts.dropLast().joined(separator: " / ") : "",
            gmtOffsetText: MetadataDSTResolutionOption.formatGMTOffset(
                seconds: systemTZ.secondsFromGMT(for: referenceDate)
            ),
            isSystemDefault: true
        )
        let utc = MetadataTimeZoneEntry(
            identifier: "UTC",
            cityName: "UTC",
            regionName: "",
            gmtOffsetText: "UTC+00:00",
            isSystemDefault: systemTZ.identifier == "UTC"
        )

        let groups = groupedIdentifiersByRegion.map { bucket in
            let entries = bucket.identifiers.compactMap { item -> MetadataTimeZoneEntry? in
                guard let tz = TimeZone(identifier: item.id) else { return nil }
                let offset = MetadataDSTResolutionOption.formatGMTOffset(
                    seconds: tz.secondsFromGMT(for: referenceDate)
                )
                return MetadataTimeZoneEntry(
                    identifier: item.id,
                    cityName: item.city,
                    regionName: bucket.region,
                    gmtOffsetText: offset,
                    isSystemDefault: item.id == systemTZ.identifier
                )
            }
            return RegionGroup(region: bucket.region, entries: entries)
        }

        return RegionalTimeZoneCatalog(
            systemEntry: system,
            utcEntry: utc,
            regionGroups: groups
        )
    }
}
