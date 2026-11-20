import Foundation

/// Calendar precision offered by the native date and time picker.
nonisolated enum MetadataDatePrecision: String, CaseIterable, Hashable, Sendable {
    case year
    case yearMonth
    case date

    static let ordered: [MetadataDatePrecision] = [.year, .yearMonth, .date]
}

/// Time-of-day precision tracked by the picker.
///
/// `.hour` is preserved when reopening an existing ID3v2.4 `YYYY-MM-DDTHH`
/// timestamp so editing its date alone preserves the stored precision.
nonisolated enum MetadataTimePrecision: String, CaseIterable, Hashable, Sendable {
    case none
    case hour
    case minute
    case second

    var includesTime: Bool {
        self != .none
    }
}

/// Exact serialization capabilities of a concrete writable metadata tag target.
nonisolated struct MetadataDateDestinationFormat: Equatable, Hashable, Sendable {
    let supportedDatePrecisions: Set<MetadataDatePrecision>
    let supportsTime: Bool
    let supportsHourOnlyTime: Bool
    let supportsMinuteTime: Bool
    let supportsSeconds: Bool
    let requiresUTC: Bool

    /// ID3v2.4 native timestamp frames (`TDRC`, `TDRL`, `TDOR`).
    /// ID3v2.4.0 Section 4 defines `yyyy`, `yyyy-MM`, `yyyy-MM-dd`,
    /// `yyyy-MM-ddTHH`, `yyyy-MM-ddTHH:mm`, and `yyyy-MM-ddTHH:mm:ss` in UTC
    /// without a trailing `Z`.
    static let id3v24Timestamp = MetadataDateDestinationFormat(
        supportedDatePrecisions: [.year, .yearMonth, .date],
        supportsTime: true,
        supportsHourOnlyTime: true,
        supportsMinuteTime: true,
        supportsSeconds: true,
        requiresUTC: true
    )

    /// ISO-8601 date-only text fields (`DATE`, `RELEASEDATE`, `ORIGINALDATE`
    /// in Vorbis/APE/MP4 freeform, `TXXX(DATE)` in ID3v2.4, `DATE` in ASF).
    static let isoDateOnly = MetadataDateDestinationFormat(
        supportedDatePrecisions: [.year, .yearMonth, .date],
        supportsTime: false,
        supportsHourOnlyTime: false,
        supportsMinuteTime: false,
        supportsSeconds: false,
        requiresUTC: false
    )

    /// Year-only targets such as ASF `WM/OriginalReleaseYear`.
    static let yearOnly = MetadataDateDestinationFormat(
        supportedDatePrecisions: [.year],
        supportsTime: false,
        supportsHourOnlyTime: false,
        supportsMinuteTime: false,
        supportsSeconds: false,
        requiresUTC: false
    )

    var orderedDatePrecisions: [MetadataDatePrecision] {
        MetadataDatePrecision.ordered.filter { supportedDatePrecisions.contains($0) }
    }

    var defaultDatePrecision: MetadataDatePrecision {
        if supportedDatePrecisions.contains(.date) { return .date }
        if supportedDatePrecisions.contains(.yearMonth) { return .yearMonth }
        return .year
    }

    var defaultEnabledTimePrecision: MetadataTimePrecision {
        if supportsMinuteTime { return .minute }
        if supportsSeconds { return .second }
        if supportsHourOnlyTime { return .hour }
        return .none
    }

    /// Computes the intersection of picker capabilities that every target in a
    /// selection can represent identically.
    static func intersect(_ formats: [MetadataDateDestinationFormat]) -> MetadataDateDestinationFormat? {
        guard let first = formats.first else { return nil }

        let commonDatePrecisions = formats.dropFirst().reduce(first.supportedDatePrecisions) {
            $0.intersection($1.supportedDatePrecisions)
        }
        guard !commonDatePrecisions.isEmpty else { return nil }

        let allSupportTime = formats.allSatisfy(\.supportsTime)
        let compatibleTimestampSyntax = formats.dropFirst().allSatisfy {
            $0.requiresUTC == first.requiresUTC
        }

        let supportsHourOnly = allSupportTime && compatibleTimestampSyntax && formats.allSatisfy(\.supportsHourOnlyTime)
        let supportsMinute = allSupportTime && compatibleTimestampSyntax && formats.allSatisfy(\.supportsMinuteTime)
        let supportsSeconds = allSupportTime && compatibleTimestampSyntax && formats.allSatisfy(\.supportsSeconds)
        let supportsTime = allSupportTime
            && compatibleTimestampSyntax
            && commonDatePrecisions.contains(.date)
            && (supportsHourOnly || supportsMinute || supportsSeconds)

        return MetadataDateDestinationFormat(
            supportedDatePrecisions: commonDatePrecisions,
            supportsTime: supportsTime,
            supportsHourOnlyTime: supportsTime && supportsHourOnly,
            supportsMinuteTime: supportsTime && supportsMinute,
            supportsSeconds: supportsTime && supportsSeconds,
            requiresUTC: supportsTime && first.requiresUTC
        )
    }
}

/// Gregorian wall-clock components edited in the picker.
nonisolated struct MetadataLocalDateTimeComponents: Equatable, Hashable, Sendable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int

    init(
        year: Int,
        month: Int = 1,
        day: Int = 1,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) {
        self.year = min(max(year, 1), 9999)
        self.month = min(max(month, 1), 12)
        self.day = max(day, 1)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.second = min(max(second, 0), 59)
        clampDayToValidMonthLength()
    }

    mutating func clampDayToValidMonthLength() {
        let maxDay = Self.daysInMonth(year: year, month: month)
        day = min(max(day, 1), maxDay)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = min(max(year, 1), 9999)
        components.month = min(max(month, 1), 12)
        components.day = 1
        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 28
        }
        return range.count
    }

    static func today(now: Date = Date(), in timeZone: TimeZone) -> MetadataLocalDateTimeComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        return MetadataLocalDateTimeComponents(
            year: parts.year ?? 2000,
            month: parts.month ?? 1,
            day: parts.day ?? 1,
            hour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: parts.second ?? 0
        )
    }

    /// Converts these wall-clock components to a `Date` anchored in UTC for
    /// date-only calendar display without time-zone day shifts.
    func calendarAnchorDate(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

/// One concrete instant choice for resolving an ambiguous or nonexistent DST
/// local time.
nonisolated struct MetadataDSTResolutionOption: Equatable, Hashable, Identifiable, Sendable {
    enum Role: String, Equatable, Hashable, Sendable {
        case earlierOccurrence
        case laterOccurrence
        case shiftForward
        case transitionStart
        case shiftBackward
    }

    let id: String
    let role: Role
    let date: Date
    let secondsFromGMT: Int
    let abbreviation: String
    let isDaylightSavingTime: Bool
    let localComponents: MetadataLocalDateTimeComponents

    var formattedGMTOffset: String {
        Self.formatGMTOffset(seconds: secondsFromGMT)
    }

    static func formatGMTOffset(seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "−"
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }
}

/// Resolution result for a Gregorian wall-clock time in a given time zone.
nonisolated enum MetadataLocalTimeResolution: Equatable, Sendable {
    case unique(Date)
    case ambiguous(earlier: MetadataDSTResolutionOption, later: MetadataDSTResolutionOption)
    case nonexistent(options: [MetadataDSTResolutionOption])

    var options: [MetadataDSTResolutionOption] {
        switch self {
        case .unique:
            return []
        case .ambiguous(let earlier, let later):
            return [earlier, later]
        case .nonexistent(let options):
            return options
        }
    }
}

/// Parsed representation of an existing metadata date/time string.
nonisolated struct MetadataParsedDateTimeValue: Equatable, Sendable {
    let datePrecision: MetadataDatePrecision
    let timePrecision: MetadataTimePrecision
    let localComponents: MetadataLocalDateTimeComponents
    let resolvedInstant: Date?
    let matchedDSTOptionID: String?
}

/// Pure Foundation parser, DST resolver, and formatter for metadata dates and
/// timestamps.
nonisolated enum MetadataDateTimeCodec {
    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    private static func gregorianCalendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Resolves local Gregorian wall-clock components in `timeZone`,
    /// distinguishing unique, DST fall-back ambiguous, and DST spring-forward
    /// nonexistent times.
    static func resolveLocalTime(
        _ components: MetadataLocalDateTimeComponents,
        in timeZone: TimeZone
    ) -> MetadataLocalTimeResolution {
        guard let naiveUTC = utcDate(from: components) else {
            return .nonexistent(options: [])
        }

        let localCalendar = gregorianCalendar(in: timeZone)
        let candidateOffsets = nearbyGMTOffsets(around: naiveUTC, in: timeZone)

        var matchingDates: [Date] = []
        for offset in candidateOffsets {
            let candidate = Date(timeIntervalSince1970: naiveUTC.timeIntervalSince1970 - Double(offset))
            let actual = localCalendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: candidate
            )
            if actual.year == components.year,
               actual.month == components.month,
               actual.day == components.day,
               actual.hour == components.hour,
               actual.minute == components.minute,
               actual.second == components.second {
                if !matchingDates.contains(where: { abs($0.timeIntervalSince(candidate)) < 0.5 }) {
                    matchingDates.append(candidate)
                }
            }
        }

        matchingDates.sort()

        if matchingDates.count == 1 {
            return .unique(matchingDates[0])
        }

        if matchingDates.count >= 2 {
            let earlier = makeDSTOption(
                id: "earlier",
                role: .earlierOccurrence,
                date: matchingDates.first!,
                in: timeZone
            )
            let later = makeDSTOption(
                id: "later",
                role: .laterOccurrence,
                date: matchingDates.last!,
                in: timeZone
            )
            return .ambiguous(earlier: earlier, later: later)
        }

        // Nonexistent local wall-clock time (spring-forward gap).
        let options = nonexistentResolutionOptions(
            for: naiveUTC,
            candidateOffsets: candidateOffsets,
            in: timeZone
        )
        return .nonexistent(options: options)
    }

    /// Parses a single-line tag value for reopening in the picker.
    ///
    /// Returns `nil` when the string is blank, multiline, malformed, or uses a
    /// precision that `destinationFormat` cannot represent.
    static func parse(
        _ rawText: String,
        destinationFormat: MetadataDateDestinationFormat,
        displayTimeZone: TimeZone = .autoupdatingCurrent
    ) -> MetadataParsedDateTimeValue? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n"), !trimmed.contains("\r") else {
            return nil
        }

        // Pure date: YYYY, YYYY-MM, YYYY-MM-DD
        if let dateMatch = parseDateOnly(trimmed) {
            guard destinationFormat.supportedDatePrecisions.contains(dateMatch.precision) else {
                return nil
            }
            return MetadataParsedDateTimeValue(
                datePrecision: dateMatch.precision,
                timePrecision: .none,
                localComponents: dateMatch.components,
                resolvedInstant: nil,
                matchedDSTOptionID: nil
            )
        }

        // Timestamp: YYYY-MM-DD[T ]HH[:mm[:ss[.fff]]][Z|±HH[:mm]]
        guard destinationFormat.supportsTime,
              destinationFormat.supportedDatePrecisions.contains(.date),
              let timestamp = parseTimestamp(trimmed) else {
            return nil
        }

        let effectiveTimePrecision: MetadataTimePrecision
        switch timestamp.timePrecision {
        case .hour:
            if destinationFormat.supportsHourOnlyTime {
                effectiveTimePrecision = .hour
            } else if destinationFormat.supportsMinuteTime {
                effectiveTimePrecision = .minute
            } else if destinationFormat.supportsSeconds {
                effectiveTimePrecision = .second
            } else {
                return nil
            }
        case .minute:
            if destinationFormat.supportsMinuteTime {
                effectiveTimePrecision = .minute
            } else if destinationFormat.supportsSeconds {
                effectiveTimePrecision = .second
            } else {
                return nil
            }
        case .second:
            if destinationFormat.supportsSeconds {
                effectiveTimePrecision = .second
            } else if destinationFormat.supportsMinuteTime {
                effectiveTimePrecision = .minute
            } else {
                return nil
            }
        case .none:
            return nil
        }

        let instant: Date
        if let explicitOffsetSeconds = timestamp.explicitOffsetSeconds {
            guard let utcNaive = utcDate(from: timestamp.components) else { return nil }
            instant = Date(timeIntervalSince1970: utcNaive.timeIntervalSince1970 - Double(explicitOffsetSeconds))
        } else if destinationFormat.requiresUTC {
            guard let utcInstant = utcDate(from: timestamp.components) else { return nil }
            instant = utcInstant
        } else {
            switch resolveLocalTime(timestamp.components, in: displayTimeZone) {
            case .unique(let date):
                instant = date
            case .ambiguous(let earlier, _):
                instant = earlier.date
            case .nonexistent:
                return nil
            }
        }

        guard let localComponents = components(for: instant, in: displayTimeZone) else {
            return nil
        }

        var matchedOptionID: String?
        if case .ambiguous(let earlier, let later) = resolveLocalTime(localComponents, in: displayTimeZone) {
            if abs(earlier.date.timeIntervalSince(instant)) < 1 {
                matchedOptionID = earlier.id
            } else if abs(later.date.timeIntervalSince(instant)) < 1 {
                matchedOptionID = later.id
            }
        }

        return MetadataParsedDateTimeValue(
            datePrecision: .date,
            timePrecision: effectiveTimePrecision,
            localComponents: localComponents,
            resolvedInstant: instant,
            matchedDSTOptionID: matchedOptionID
        )
    }

    /// Formats picker selections into the destination tag's exact string syntax.
    static func format(
        localComponents: MetadataLocalDateTimeComponents,
        datePrecision: MetadataDatePrecision,
        timePrecision: MetadataTimePrecision,
        timeZone: TimeZone,
        resolvedDate: Date?,
        destinationFormat: MetadataDateDestinationFormat
    ) -> String? {
        if timePrecision == .none {
            guard destinationFormat.supportedDatePrecisions.contains(datePrecision) else {
                return nil
            }
            switch datePrecision {
            case .year:
                return String(format: "%04d", localComponents.year)
            case .yearMonth:
                return String(format: "%04d-%02d", localComponents.year, localComponents.month)
            case .date:
                return String(
                    format: "%04d-%02d-%02d",
                    localComponents.year,
                    localComponents.month,
                    localComponents.day
                )
            }
        }

        guard destinationFormat.supportsTime,
              destinationFormat.supportedDatePrecisions.contains(.date) else {
            return nil
        }

        let outputComponents: MetadataLocalDateTimeComponents

        if destinationFormat.requiresUTC {
            let instant: Date
            if let resolvedDate {
                instant = resolvedDate
            } else if case .unique(let uniqueDate) = resolveLocalTime(localComponents, in: timeZone) {
                instant = uniqueDate
            } else {
                return nil
            }

            guard let utcComponents = components(for: instant, in: utcCalendar.timeZone) else {
                return nil
            }
            outputComponents = utcComponents
        } else {
            outputComponents = localComponents
        }

        let datePrefix = String(
            format: "%04d-%02d-%02d",
            outputComponents.year,
            outputComponents.month,
            outputComponents.day
        )

        switch timePrecision {
        case .none:
            return datePrefix
        case .hour:
            guard destinationFormat.supportsHourOnlyTime,
                  outputComponents.minute == 0,
                  outputComponents.second == 0 else {
                return nil
            }
            return "\(datePrefix)T\(String(format: "%02d", outputComponents.hour))"
        case .minute:
            guard destinationFormat.supportsMinuteTime, outputComponents.second == 0 else { return nil }
            return "\(datePrefix)T\(String(format: "%02d:%02d", outputComponents.hour, outputComponents.minute))"
        case .second:
            guard destinationFormat.supportsSeconds else { return nil }
            return "\(datePrefix)T\(String(format: "%02d:%02d:%02d", outputComponents.hour, outputComponents.minute, outputComponents.second))"
        }
    }

    /// Parse the year field in the picker without discarding invalid input.
    static func pickerYear(from text: String) -> Int? {
        guard (1...4).contains(text.count),
              text.unicodeScalars.allSatisfy({ $0.properties.numericType == .decimal }) else {
            return nil
        }
        let digits = text.compactMap(\.wholeNumberValue)
        guard digits.count == text.count else { return nil }
        let year = digits.reduce(0) { $0 * 10 + $1 }
        return year > 0 ? year : nil
    }

    static func isSupportedUTCYear(for instant: Date) -> Bool {
        components(for: instant, in: utcCalendar.timeZone) != nil
    }

    static func components(for instant: Date, in timeZone: TimeZone) -> MetadataLocalDateTimeComponents? {
        let parts = gregorianCalendar(in: timeZone).dateComponents(
            [.era, .year, .month, .day, .hour, .minute, .second],
            from: instant
        )
        guard parts.era == 1, let year = parts.year, (1...9999).contains(year),
              let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute, let second = parts.second else {
            return nil
        }
        return MetadataLocalDateTimeComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        )
    }

    // MARK: - Private Parsing & DST Helpers

    private static func utcDate(from components: MetadataLocalDateTimeComponents) -> Date? {
        var dateComponents = DateComponents()
        dateComponents.calendar = utcCalendar
        dateComponents.timeZone = utcTimeZone
        dateComponents.year = components.year
        dateComponents.month = components.month
        dateComponents.day = components.day
        dateComponents.hour = components.hour
        dateComponents.minute = components.minute
        dateComponents.second = components.second
        guard let date = utcCalendar.date(from: dateComponents) else { return nil }

        let verified = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard verified.year == components.year,
              verified.month == components.month,
              verified.day == components.day,
              verified.hour == components.hour,
              verified.minute == components.minute,
              verified.second == components.second else {
            return nil
        }
        return date
    }

    private static func nearbyGMTOffsets(around naiveUTC: Date, in timeZone: TimeZone) -> [Int] {
        var offsets: [Int] = []
        func appendUnique(_ offset: Int) {
            if !offsets.contains(offset) {
                offsets.append(offset)
            }
        }

        let probeWindowStart = naiveUTC.addingTimeInterval(-48 * 3600)
        let probeWindowEnd = naiveUTC.addingTimeInterval(48 * 3600)
        appendUnique(timeZone.secondsFromGMT(for: probeWindowStart))
        appendUnique(timeZone.secondsFromGMT(for: naiveUTC.addingTimeInterval(-24 * 3600)))
        appendUnique(timeZone.secondsFromGMT(for: naiveUTC))
        appendUnique(timeZone.secondsFromGMT(for: naiveUTC.addingTimeInterval(24 * 3600)))
        appendUnique(timeZone.secondsFromGMT(for: probeWindowEnd))

        var cursor = probeWindowStart
        var iterations = 0
        while iterations < 4,
              let transition = timeZone.nextDaylightSavingTimeTransition(after: cursor),
              transition <= probeWindowEnd {
            appendUnique(timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1)))
            appendUnique(timeZone.secondsFromGMT(for: transition))
            appendUnique(timeZone.secondsFromGMT(for: transition.addingTimeInterval(1)))
            cursor = transition.addingTimeInterval(1)
            iterations += 1
        }

        return offsets
    }

    private static func nonexistentResolutionOptions(
        for naiveUTC: Date,
        candidateOffsets: [Int],
        in timeZone: TimeZone
    ) -> [MetadataDSTResolutionOption] {
        let probeStart = naiveUTC.addingTimeInterval(-48 * 3600)
        let probeEnd = naiveUTC.addingTimeInterval(48 * 3600)

        var nearestTransition: Date?
        var cursor = probeStart
        var iterations = 0
        while iterations < 4,
              let transition = timeZone.nextDaylightSavingTimeTransition(after: cursor),
              transition <= probeEnd {
            let beforeOffset = timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            let afterOffset = timeZone.secondsFromGMT(for: transition)
            if afterOffset > beforeOffset {
                if nearestTransition == nil
                    || abs(transition.timeIntervalSince(naiveUTC)) < abs(nearestTransition!.timeIntervalSince(naiveUTC)) {
                    nearestTransition = transition
                }
            }
            cursor = transition.addingTimeInterval(1)
            iterations += 1
        }

        var options: [MetadataDSTResolutionOption] = []
        func appendOption(id: String, role: MetadataDSTResolutionOption.Role, date: Date) {
            guard !options.contains(where: { abs($0.date.timeIntervalSince(date)) < 0.5 }) else { return }
            options.append(makeDSTOption(id: id, role: role, date: date, in: timeZone))
        }

        if let transition = nearestTransition {
            let beforeOffset = timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            let afterOffset = timeZone.secondsFromGMT(for: transition)

            // 1. Shift forward by the gap duration (preserving the pre-transition offset).
            let shiftedForward = Date(timeIntervalSince1970: naiveUTC.timeIntervalSince1970 - Double(beforeOffset))
            appendOption(id: "shiftForward", role: .shiftForward, date: shiftedForward)

            // 2. Start of DST immediately after the gap.
            appendOption(id: "transitionStart", role: .transitionStart, date: transition)

            // 3. Shift backward before the transition (preserving the post-transition offset).
            let shiftedBackward = Date(timeIntervalSince1970: naiveUTC.timeIntervalSince1970 - Double(afterOffset))
            appendOption(id: "shiftBackward", role: .shiftBackward, date: shiftedBackward)
        } else if let minOffset = candidateOffsets.min(), let maxOffset = candidateOffsets.max() {
            let shiftedForward = Date(timeIntervalSince1970: naiveUTC.timeIntervalSince1970 - Double(minOffset))
            let shiftedBackward = Date(timeIntervalSince1970: naiveUTC.timeIntervalSince1970 - Double(maxOffset))
            appendOption(id: "shiftForward", role: .shiftForward, date: shiftedForward)
            appendOption(id: "shiftBackward", role: .shiftBackward, date: shiftedBackward)
        }

        return options
    }

    private static func makeDSTOption(
        id: String,
        role: MetadataDSTResolutionOption.Role,
        date: Date,
        in timeZone: TimeZone
    ) -> MetadataDSTResolutionOption {
        let localCalendar = gregorianCalendar(in: timeZone)
        let parts = localCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let secondsFromGMT = timeZone.secondsFromGMT(for: date)
        let abbreviation = timeZone.abbreviation(for: date)
            ?? MetadataDSTResolutionOption.formatGMTOffset(seconds: secondsFromGMT)
        return MetadataDSTResolutionOption(
            id: id,
            role: role,
            date: date,
            secondsFromGMT: secondsFromGMT,
            abbreviation: abbreviation,
            isDaylightSavingTime: timeZone.isDaylightSavingTime(for: date),
            localComponents: MetadataLocalDateTimeComponents(
                year: parts.year ?? 2000,
                month: parts.month ?? 1,
                day: parts.day ?? 1,
                hour: parts.hour ?? 0,
                minute: parts.minute ?? 0,
                second: parts.second ?? 0
            )
        )
    }

    private static func parseDateOnly(_ text: String) -> (precision: MetadataDatePrecision, components: MetadataLocalDateTimeComponents)? {
        let chars = Array(text)
        switch chars.count {
        case 4:
            guard let year = parseFixedDigits(chars, start: 0, count: 4), (1...9999).contains(year) else {
                return nil
            }
            return (.year, MetadataLocalDateTimeComponents(year: year))
        case 7:
            guard chars[4] == "-",
                  let year = parseFixedDigits(chars, start: 0, count: 4), (1...9999).contains(year),
                  let month = parseFixedDigits(chars, start: 5, count: 2), (1...12).contains(month) else {
                return nil
            }
            return (.yearMonth, MetadataLocalDateTimeComponents(year: year, month: month))
        case 10:
            guard chars[4] == "-", chars[7] == "-",
                  let year = parseFixedDigits(chars, start: 0, count: 4), (1...9999).contains(year),
                  let month = parseFixedDigits(chars, start: 5, count: 2), (1...12).contains(month),
                  let day = parseFixedDigits(chars, start: 8, count: 2),
                  (1...MetadataLocalDateTimeComponents.daysInMonth(year: year, month: month)).contains(day) else {
                return nil
            }
            return (.date, MetadataLocalDateTimeComponents(year: year, month: month, day: day))
        default:
            return nil
        }
    }

    private struct ParsedTimestamp {
        let components: MetadataLocalDateTimeComponents
        let timePrecision: MetadataTimePrecision
        let explicitOffsetSeconds: Int?
    }

    private static func parseTimestamp(_ text: String) -> ParsedTimestamp? {
        let chars = Array(text)
        guard chars.count >= 13,
              chars[4] == "-", chars[7] == "-",
              (chars[10] == "T" || chars[10] == "t" || chars[10] == " "),
              let year = parseFixedDigits(chars, start: 0, count: 4), (1...9999).contains(year),
              let month = parseFixedDigits(chars, start: 5, count: 2), (1...12).contains(month),
              let day = parseFixedDigits(chars, start: 8, count: 2),
              (1...MetadataLocalDateTimeComponents.daysInMonth(year: year, month: month)).contains(day),
              let hour = parseFixedDigits(chars, start: 11, count: 2), (0...23).contains(hour) else {
            return nil
        }

        var index = 13
        var minute = 0
        var second = 0
        var precision: MetadataTimePrecision = .hour

        if index < chars.count, chars[index] == ":" {
            guard index + 3 <= chars.count,
                  let parsedMinute = parseFixedDigits(chars, start: index + 1, count: 2),
                  (0...59).contains(parsedMinute) else {
                return nil
            }
            minute = parsedMinute
            precision = .minute
            index += 3

            if index < chars.count, chars[index] == ":" {
                guard index + 3 <= chars.count,
                      let parsedSecond = parseFixedDigits(chars, start: index + 1, count: 2),
                      (0...59).contains(parsedSecond) else {
                    return nil
                }
                second = parsedSecond
                precision = .second
                index += 3

                // Optional fractional seconds (e.g. .000)
                if index < chars.count, chars[index] == "." {
                    index += 1
                    let fractionStart = index
                    while index < chars.count, chars[index].isASCII, chars[index].isNumber {
                        index += 1
                    }
                    guard index > fractionStart else { return nil }
                }
            }
        }

        var explicitOffsetSeconds: Int?
        if index < chars.count {
            let suffix = Array(chars[index...])
            if suffix.count == 1, suffix[0] == "Z" || suffix[0] == "z" {
                explicitOffsetSeconds = 0
            } else if let offset = parseTimezoneOffset(suffix) {
                explicitOffsetSeconds = offset
            } else {
                return nil
            }
        }

        let components = MetadataLocalDateTimeComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return ParsedTimestamp(
            components: components,
            timePrecision: precision,
            explicitOffsetSeconds: explicitOffsetSeconds
        )
    }

    private static func parseTimezoneOffset(_ chars: [Character]) -> Int? {
        guard let signChar = chars.first, signChar == "+" || signChar == "-" else {
            return nil
        }
        let sign = signChar == "+" ? 1 : -1

        switch chars.count {
        case 3: // ±HH
            guard let hours = parseFixedDigits(chars, start: 1, count: 2), (0...23).contains(hours) else {
                return nil
            }
            return sign * hours * 3600
        case 5: // ±HHMM
            guard let hours = parseFixedDigits(chars, start: 1, count: 2), (0...23).contains(hours),
                  let minutes = parseFixedDigits(chars, start: 3, count: 2), (0...59).contains(minutes) else {
                return nil
            }
            return sign * (hours * 3600 + minutes * 60)
        case 6: // ±HH:MM
            guard chars[3] == ":",
                  let hours = parseFixedDigits(chars, start: 1, count: 2), (0...23).contains(hours),
                  let minutes = parseFixedDigits(chars, start: 4, count: 2), (0...59).contains(minutes) else {
                return nil
            }
            return sign * (hours * 3600 + minutes * 60)
        default:
            return nil
        }
    }

    private static func parseFixedDigits(_ chars: [Character], start: Int, count: Int) -> Int? {
        guard start >= 0, start + count <= chars.count else { return nil }
        var value = 0
        for offset in 0..<count {
            guard let ascii = chars[start + offset].asciiValue, ascii >= 48, ascii <= 57 else {
                return nil
            }
            value = value * 10 + Int(ascii - 48)
        }
        return value
    }
}

/// Pure, testable editing session for a single date/time picker interaction.
///
/// Opening a blank or mixed field positions the calendar at `now` while
/// leaving the external field untouched until the user explicitly applies.
nonisolated struct MetadataDateTimePickerSession: Equatable, Sendable {
    let destinationFormat: MetadataDateDestinationFormat
    let didParseExistingValue: Bool
    private(set) var datePrecision: MetadataDatePrecision
    private(set) var timePrecision: MetadataTimePrecision
    private(set) var localComponents: MetadataLocalDateTimeComponents
    private(set) var timeZoneIdentifier: String
    private(set) var selectedDSTOptionID: String?
    private var preservesInstantOnTimeZoneChange: Bool

    init(
        initialText: String?,
        isMixed: Bool = false,
        destinationFormat: MetadataDateDestinationFormat,
        systemTimeZone: TimeZone = .autoupdatingCurrent,
        now: Date = Date()
    ) {
        self.destinationFormat = destinationFormat
        var displayTimeZone = systemTimeZone
        var parsed: MetadataParsedDateTimeValue?
        if !isMixed, let initialText {
            parsed = MetadataDateTimeCodec.parse(
                initialText, destinationFormat: destinationFormat, displayTimeZone: displayTimeZone
            )
            // A timestamp near the calendar's year limits may not have a
            // displayable local date. Keep it editable in UTC.
            if parsed == nil, destinationFormat.requiresUTC, let utc = TimeZone(identifier: "UTC"),
               let utcParsed = MetadataDateTimeCodec.parse(
                   initialText, destinationFormat: destinationFormat, displayTimeZone: utc
               ) {
                displayTimeZone = utc
                parsed = utcParsed
            }
        }
        self.timeZoneIdentifier = displayTimeZone.identifier

        if let parsed {
            self.didParseExistingValue = true
            self.datePrecision = parsed.datePrecision
            self.timePrecision = parsed.timePrecision
            self.localComponents = parsed.localComponents
            self.selectedDSTOptionID = parsed.matchedDSTOptionID
            self.preservesInstantOnTimeZoneChange = parsed.timePrecision.includesTime
        } else {
            self.didParseExistingValue = false
            self.datePrecision = destinationFormat.defaultDatePrecision
            self.timePrecision = .none
            self.localComponents = MetadataLocalDateTimeComponents.today(now: now, in: systemTimeZone)
            self.selectedDSTOptionID = nil
            self.preservesInstantOnTimeZoneChange = false
        }
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
    }

    var isTimeEnabled: Bool {
        timePrecision.includesTime
    }

    var isSecondsEnabled: Bool {
        timePrecision == .second
    }

    var localTimeResolution: MetadataLocalTimeResolution? {
        guard timePrecision.includesTime else { return nil }
        return MetadataDateTimeCodec.resolveLocalTime(localComponents, in: timeZone)
    }

    var dstResolutionOptions: [MetadataDSTResolutionOption] {
        localTimeResolution?.options ?? []
    }

    var selectedDSTOption: MetadataDSTResolutionOption? {
        guard let selectedDSTOptionID else { return nil }
        return dstResolutionOptions.first { $0.id == selectedDSTOptionID }
    }

    var requiresDSTResolution: Bool {
        guard let resolution = localTimeResolution else { return false }
        switch resolution {
        case .unique:
            return false
        case .ambiguous, .nonexistent:
            return selectedDSTOption == nil
        }
    }

    var resolvedInstant: Date? {
        guard let resolution = localTimeResolution else { return nil }
        switch resolution {
        case .unique(let date):
            return date
        case .ambiguous, .nonexistent:
            return selectedDSTOption?.date
        }
    }

    var formattedValue: String? {
        if requiresDSTResolution {
            return nil
        }
        return formattedValue(at: timePrecision)
    }

    private func formattedValue(at precision: MetadataTimePrecision) -> String? {
        MetadataDateTimeCodec.format(
            localComponents: localComponents,
            datePrecision: datePrecision,
            timePrecision: precision,
            timeZone: timeZone,
            resolvedDate: resolvedInstant,
            destinationFormat: destinationFormat
        )
    }

    var isUTCYearOutOfRange: Bool {
        guard destinationFormat.requiresUTC, let resolvedInstant else { return false }
        return !MetadataDateTimeCodec.isSupportedUTCYear(for: resolvedInstant)
    }

    var finerTimePrecision: MetadataTimePrecision? {
        guard timePrecision.includesTime, !requiresDSTResolution, formattedValue == nil else { return nil }
        if timePrecision == .hour, formattedValue(at: .minute) != nil { return .minute }
        if timePrecision != .second, formattedValue(at: .second) != nil { return .second }
        return nil
    }

    mutating func useFinerTimePrecision() {
        guard let finerTimePrecision else { return }
        timePrecision = finerTimePrecision
    }

    var canApply: Bool {
        formattedValue != nil
    }

    /// Updates only the calendar date, preserving any active time and its precision.
    mutating func setDate(year: Int, month: Int, day: Int) {
        localComponents.year = min(max(year, 1), 9999)
        localComponents.month = min(max(month, 1), 12)
        localComponents.day = max(day, 1)
        localComponents.clampDayToValidMonthLength()
        revalidateDSTSelection()
    }

    mutating func setYear(_ year: Int) {
        localComponents.year = min(max(year, 1), 9999)
        localComponents.clampDayToValidMonthLength()
        revalidateDSTSelection()
    }

    mutating func setMonth(_ month: Int) {
        localComponents.month = min(max(month, 1), 12)
        localComponents.clampDayToValidMonthLength()
        revalidateDSTSelection()
    }

    mutating func setDatePrecision(_ precision: MetadataDatePrecision) {
        guard destinationFormat.supportedDatePrecisions.contains(precision) else { return }
        datePrecision = precision
        if precision != .date {
            timePrecision = .none
            selectedDSTOptionID = nil
            preservesInstantOnTimeZoneChange = false
        }
    }

    mutating func setTimeEnabled(_ enabled: Bool) {
        if enabled {
            guard destinationFormat.supportsTime,
                  destinationFormat.supportedDatePrecisions.contains(.date) else {
                return
            }
            datePrecision = .date
            if timePrecision == .none {
                timePrecision = destinationFormat.defaultEnabledTimePrecision
                if timePrecision != .second {
                    localComponents.second = 0
                }
                preservesInstantOnTimeZoneChange = false
            }
            revalidateDSTSelection()
        } else {
            timePrecision = .none
            selectedDSTOptionID = nil
            preservesInstantOnTimeZoneChange = false
        }
    }

    mutating func setSecondsEnabled(_ enabled: Bool) {
        guard destinationFormat.supportsTime, destinationFormat.supportsSeconds,
              timePrecision.includesTime, enabled != isSecondsEnabled else {
            return
        }
        if enabled {
            timePrecision = .second
        } else if destinationFormat.supportsMinuteTime {
            // Changing precision is explicit. Keep an already exact minute
            // (including historical offsets with local seconds); otherwise
            // discard the seconds the user chose to hide.
            if formattedValue(at: .minute) == nil {
                localComponents.second = 0
            }
            timePrecision = .minute
        }
        if selectedDSTOption == nil {
            selectedDSTOptionID = nil
        }
    }

    mutating func setTime(hour: Int, minute: Int, second: Int? = nil) {
        guard timePrecision.includesTime else { return }
        let clampedHour = min(max(hour, 0), 23)
        let clampedMinute = min(max(minute, 0), 59)
        let clampedSecond = second.map { min(max($0, 0), 59) }

        let didChange = clampedHour != localComponents.hour
            || clampedMinute != localComponents.minute
            || (clampedSecond != nil && clampedSecond != localComponents.second)
        guard didChange else { return }

        localComponents.hour = clampedHour
        localComponents.minute = clampedMinute
        if let clampedSecond {
            localComponents.second = clampedSecond
        }
        if timePrecision == .hour, destinationFormat.supportsMinuteTime {
            timePrecision = .minute
        }
        preservesInstantOnTimeZoneChange = false
        revalidateDSTSelection()
    }

    mutating func setTimeZone(identifier: String) {
        guard let targetTimeZone = TimeZone(identifier: identifier) else { return }
        guard identifier != timeZoneIdentifier else { return }

        if timePrecision.includesTime,
           preservesInstantOnTimeZoneChange,
           let instant = resolvedInstant {
            guard let components = MetadataDateTimeCodec.components(for: instant, in: targetTimeZone) else {
                return
            }
            localComponents = components
            timeZoneIdentifier = identifier

            if case .ambiguous(let earlier, let later) = MetadataDateTimeCodec.resolveLocalTime(
                components,
                in: targetTimeZone
            ) {
                if abs(earlier.date.timeIntervalSince(instant)) < 1 {
                    selectedDSTOptionID = earlier.id
                } else if abs(later.date.timeIntervalSince(instant)) < 1 {
                    selectedDSTOptionID = later.id
                } else {
                    selectedDSTOptionID = nil
                }
            } else {
                selectedDSTOptionID = nil
            }
            return
        }

        timeZoneIdentifier = identifier
        selectedDSTOptionID = nil
    }

    mutating func selectDSTResolution(optionID: String) {
        guard dstResolutionOptions.contains(where: { $0.id == optionID }) else { return }
        selectedDSTOptionID = optionID
    }

    private mutating func revalidateDSTSelection() {
        guard let resolution = localTimeResolution else {
            selectedDSTOptionID = nil
            return
        }
        switch resolution {
        case .unique:
            selectedDSTOptionID = nil
        case .ambiguous, .nonexistent:
            // Any edit to date/time while in a DST transition requires fresh confirmation.
            selectedDSTOptionID = nil
        }
    }
}
