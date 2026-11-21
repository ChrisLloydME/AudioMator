import AppKit
import SwiftUI

/// Native macOS date controls share the same Gregorian date and system locale.
struct NativeMacDatePicker: NSViewRepresentable {
    let year: Int
    let month: Int
    let day: Int
    let includesDay: Bool
    let style: NSDatePicker.Style
    let accessibilityLabel: String
    let onDateSelected: (Int, Int, Int) -> Void

    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!
    private static var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.firstWeekday = Calendar.autoupdatingCurrent.firstWeekday
        calendar.timeZone = utcTimeZone
        return calendar
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDateSelected: onDateSelected)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = style
        picker.datePickerMode = .single
        picker.datePickerElements = includesDay ? .yearMonthDay : .yearMonth
        picker.presentsCalendarOverlay = false
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .default
        picker.controlSize = .regular
        picker.calendar = Self.utcGregorianCalendar
        picker.timeZone = Self.utcTimeZone
        picker.locale = .autoupdatingCurrent
        picker.minDate = Self.utcDate(year: 1, month: 1, day: 1)
        picker.maxDate = Self.utcDate(year: 9999, month: 12, day: 31)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.setAccessibilityLabel(accessibilityLabel)
        picker.dateValue = Self.utcDate(year: year, month: month, day: day)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.onDateSelected = onDateSelected
        picker.locale = .autoupdatingCurrent
        picker.setAccessibilityLabel(accessibilityLabel)

        let elements: NSDatePicker.ElementFlags = includesDay ? .yearMonthDay : .yearMonth
        if picker.datePickerElements != elements {
            picker.datePickerElements = elements
            picker.invalidateIntrinsicContentSize()
        }
        let desiredDate = Self.utcDate(year: year, month: month, day: day)
        let currentParts = Self.utcGregorianCalendar.dateComponents([.year, .month, .day], from: picker.dateValue)
        if currentParts.year != year || currentParts.month != month || currentParts.day != day {
            context.coordinator.isUpdatingFromSwiftUI = true
            picker.dateValue = desiredDate
            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        nsView.fittingSize
    }

    private static func utcDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = utcGregorianCalendar
        components.timeZone = utcTimeZone
        components.year = min(max(year, 1), 9999)
        components.month = min(max(month, 1), 12)
        components.day = min(max(day, 1), MetadataLocalDateTimeComponents.daysInMonth(year: year, month: month))
        components.hour = 12
        components.minute = 0
        components.second = 0
        return utcGregorianCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    final class Coordinator: NSObject {
        var onDateSelected: (Int, Int, Int) -> Void
        var isUpdatingFromSwiftUI = false

        init(onDateSelected: @escaping (Int, Int, Int) -> Void) {
            self.onDateSelected = onDateSelected
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            guard !isUpdatingFromSwiftUI else { return }
            let parts = NativeMacDatePicker.utcGregorianCalendar.dateComponents(
                [.year, .month, .day],
                from: sender.dateValue
            )
            guard let year = parts.year, let month = parts.month, let day = parts.day else {
                return
            }
            onDateSelected(year, month, day)
        }
    }
}

/// Native macOS textual time picker (`NSDatePicker` `.textField`)
/// operating on wall-clock hour/minute/second in UTC space so users can enter
/// any wall-clock time (including DST spring-forward gaps) while respecting the
/// system locale's 12-hour or 24-hour presentation.
struct NativeMacTimePicker: NSViewRepresentable {
    let hour: Int
    let minute: Int
    let second: Int
    let includesSeconds: Bool
    let accessibilityLabel: String
    let onTimeSelected: (Int, Int, Int) -> Void

    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!
    private static var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTimeSelected: onTimeSelected)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerMode = .single
        picker.datePickerElements = includesSeconds ? .hourMinuteSecond : .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .default
        picker.controlSize = .regular
        picker.calendar = Self.utcGregorianCalendar
        picker.timeZone = Self.utcTimeZone
        picker.locale = .autoupdatingCurrent
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.timeChanged(_:))
        picker.setAccessibilityLabel(accessibilityLabel)
        picker.dateValue = Self.utcTime(hour: hour, minute: minute, second: second)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.onTimeSelected = onTimeSelected
        picker.locale = .autoupdatingCurrent
        picker.setAccessibilityLabel(accessibilityLabel)

        let expectedElements: NSDatePicker.ElementFlags = includesSeconds ? .hourMinuteSecond : .hourMinute
        if picker.datePickerElements != expectedElements {
            picker.datePickerElements = expectedElements
            picker.invalidateIntrinsicContentSize()
        }

        let currentParts = Self.utcGregorianCalendar.dateComponents([.hour, .minute, .second], from: picker.dateValue)
        let desiredSecond = includesSeconds ? second : 0
        if currentParts.hour != hour
            || currentParts.minute != minute
            || (includesSeconds && currentParts.second != desiredSecond) {
            context.coordinator.isUpdatingFromSwiftUI = true
            picker.dateValue = Self.utcTime(hour: hour, minute: minute, second: desiredSecond)
            context.coordinator.isUpdatingFromSwiftUI = false
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        nsView.fittingSize
    }

    private static func utcTime(hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.calendar = utcGregorianCalendar
        components.timeZone = utcTimeZone
        components.year = 2000
        components.month = 1
        components.day = 1
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = min(max(second, 0), 59)
        return utcGregorianCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    final class Coordinator: NSObject {
        var onTimeSelected: (Int, Int, Int) -> Void
        var isUpdatingFromSwiftUI = false

        init(onTimeSelected: @escaping (Int, Int, Int) -> Void) {
            self.onTimeSelected = onTimeSelected
        }

        @objc func timeChanged(_ sender: NSDatePicker) {
            guard !isUpdatingFromSwiftUI else { return }
            let parts = NativeMacTimePicker.utcGregorianCalendar.dateComponents(
                [.hour, .minute, .second],
                from: sender.dateValue
            )
            guard let hour = parts.hour, let minute = parts.minute else {
                return
            }
            onTimeSelected(hour, minute, parts.second ?? 0)
        }
    }
}
