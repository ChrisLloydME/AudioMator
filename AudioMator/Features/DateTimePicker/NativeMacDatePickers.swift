import AppKit
import SwiftUI

/// Native macOS graphical month calendar (`NSDatePicker` `.clockAndCalendar`)
/// operating in UTC Gregorian calendar space so pure calendar dates never shift
/// days across local time zones or DST boundaries.
struct NativeMacGraphicalCalendarPicker: NSViewRepresentable {
    let year: Int
    let month: Int
    let day: Int
    let accessibilityLabel: String
    let onDateSelected: (Int, Int, Int) -> Void

    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!
    private static var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDateSelected: onDateSelected)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerMode = .single
        picker.datePickerElements = .yearMonthDay
        picker.isBezeled = true
        picker.isBordered = true
        picker.focusRingType = .default
        picker.calendar = Self.utcGregorianCalendar
        picker.timeZone = Self.utcTimeZone
        picker.locale = .autoupdatingCurrent
        picker.minDate = Self.utcDate(year: 1, month: 1, day: 1)
        picker.maxDate = Self.utcDate(year: 9999, month: 12, day: 31)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.setAccessibilityLabel(accessibilityLabel)
        picker.dateValue = Self.utcDate(year: year, month: month, day: day)
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentHuggingPriority(.required, for: .vertical)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.onDateSelected = onDateSelected
        picker.locale = .autoupdatingCurrent
        picker.setAccessibilityLabel(accessibilityLabel)

        let desiredDate = Self.utcDate(year: year, month: month, day: day)
        let currentParts = Self.utcGregorianCalendar.dateComponents([.year, .month, .day], from: picker.dateValue)
        if currentParts.year != year || currentParts.month != month || currentParts.day != day {
            context.coordinator.isUpdatingFromSwiftUI = true
            picker.dateValue = desiredDate
            context.coordinator.isUpdatingFromSwiftUI = false
        }
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
            let parts = NativeMacGraphicalCalendarPicker.utcGregorianCalendar.dateComponents(
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

/// Native macOS textual + stepper date field (`NSDatePicker` `.textFieldAndStepper`)
/// with locale-aware date order, keyboard segment navigation, and visible focus ring.
struct NativeMacTextualDatePicker: NSViewRepresentable {
    let year: Int
    let month: Int
    let day: Int
    let accessibilityLabel: String
    let onDateSelected: (Int, Int, Int) -> Void

    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!
    private static var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDateSelected: onDateSelected)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerMode = .single
        picker.datePickerElements = .yearMonthDay
        picker.isBezeled = true
        picker.isBordered = true
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

        let desiredDate = Self.utcDate(year: year, month: month, day: day)
        let currentParts = Self.utcGregorianCalendar.dateComponents([.year, .month, .day], from: picker.dateValue)
        if currentParts.year != year || currentParts.month != month || currentParts.day != day {
            context.coordinator.isUpdatingFromSwiftUI = true
            picker.dateValue = desiredDate
            context.coordinator.isUpdatingFromSwiftUI = false
        }
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
            let parts = NativeMacTextualDatePicker.utcGregorianCalendar.dateComponents(
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

/// Native macOS textual + stepper time picker (`NSDatePicker` `.textFieldAndStepper`)
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
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerMode = .single
        picker.datePickerElements = includesSeconds ? .hourMinuteSecond : .hourMinute
        picker.isBezeled = true
        picker.isBordered = true
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
