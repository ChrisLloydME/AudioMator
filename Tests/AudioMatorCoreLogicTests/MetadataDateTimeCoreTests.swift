import Foundation
import XCTest
@testable import AudioMatorCoreLogic

final class MetadataDateTimeCoreTests: XCTestCase {
    func testShanghaiLocalTimeConvertsToID3v24UTCTimestampAndRoundTrips() throws {
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let reference = Date(timeIntervalSince1970: 1_717_288_200) // 2024-06-02T00:30:00Z

        var session = MetadataDateTimePickerSession(
            initialText: "",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: shanghai,
            now: reference
        )
        XCTAssertFalse(session.didParseExistingValue)
        XCTAssertEqual(session.datePrecision, .date)
        XCTAssertFalse(session.isTimeEnabled)

        session.setDate(year: 2024, month: 6, day: 2)
        session.setTimeEnabled(true)
        session.setTime(hour: 0, minute: 30)

        XCTAssertEqual(session.timePrecision, .minute)
        XCTAssertFalse(session.isSecondsEnabled)
        XCTAssertTrue(session.canApply)
        XCTAssertEqual(session.formattedValue, "2024-06-01T16:30")

        // Reopen existing ID3v2.4 UTC timestamp in Shanghai: shows local 00:30 and minute precision.
        var reopened = MetadataDateTimePickerSession(
            initialText: "2024-06-01T16:30",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: shanghai,
            now: reference
        )
        XCTAssertTrue(reopened.didParseExistingValue)
        XCTAssertEqual(reopened.datePrecision, .date)
        XCTAssertEqual(reopened.timePrecision, .minute)
        XCTAssertEqual(reopened.localComponents.year, 2024)
        XCTAssertEqual(reopened.localComponents.month, 6)
        XCTAssertEqual(reopened.localComponents.day, 2)
        XCTAssertEqual(reopened.localComponents.hour, 0)
        XCTAssertEqual(reopened.localComponents.minute, 30)
        XCTAssertEqual(reopened.formattedValue, "2024-06-01T16:30")

        // Editing the date alone preserves both time and precision.
        reopened.setDate(year: 2024, month: 6, day: 5)
        XCTAssertEqual(reopened.timePrecision, .minute)
        XCTAssertEqual(reopened.localComponents.hour, 0)
        XCTAssertEqual(reopened.localComponents.minute, 30)
        XCTAssertEqual(reopened.formattedValue, "2024-06-04T16:30")
    }

    func testReopeningTimestampWithSecondsAndHourOnlyPreservesPrecisionWhenEditingDateAlone() throws {
        let utc = TimeZone(secondsFromGMT: 0)!

        var secondsSession = MetadataDateTimePickerSession(
            initialText: "2024-06-01T16:30:45",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: utc
        )
        XCTAssertEqual(secondsSession.timePrecision, .second)
        XCTAssertTrue(secondsSession.isSecondsEnabled)
        XCTAssertEqual(secondsSession.localComponents.second, 45)
        secondsSession.setDate(year: 2025, month: 1, day: 15)
        XCTAssertEqual(secondsSession.timePrecision, .second)
        XCTAssertEqual(secondsSession.formattedValue, "2025-01-15T16:30:45")

        var hourOnlySession = MetadataDateTimePickerSession(
            initialText: "2024-06-01T16",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: utc
        )
        XCTAssertEqual(hourOnlySession.timePrecision, .hour)
        hourOnlySession.setDate(year: 2025, month: 2, day: 10)
        XCTAssertEqual(hourOnlySession.timePrecision, .hour)
        XCTAssertEqual(hourOnlySession.formattedValue, "2025-02-10T16")
    }

    func testPureDatesKeepCalendarDayAndPrecisionWithoutUTCConversion() throws {
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        for tz in [tokyo, losAngeles] {
            var session = MetadataDateTimePickerSession(
                initialText: nil,
                destinationFormat: .isoDateOnly,
                systemTimeZone: tz
            )
            XCTAssertFalse(session.destinationFormat.supportsTime)
            session.setDate(year: 2024, month: 6, day: 2)
            XCTAssertEqual(session.formattedValue, "2024-06-02")

            session.setDatePrecision(.yearMonth)
            XCTAssertEqual(session.formattedValue, "2024-06")

            session.setDatePrecision(.year)
            XCTAssertEqual(session.formattedValue, "2024")

            // Attempting to enable time on a date-only destination is ignored.
            session.setTimeEnabled(true)
            XCTAssertFalse(session.isTimeEnabled)
            XCTAssertEqual(session.formattedValue, "2024")
        }
    }

    func testDSTAmbiguousFallBackTimeRequiresExplicitResolutionAndRoundTrips() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var session = MetadataDateTimePickerSession(
            initialText: nil,
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: newYork
        )
        session.setDate(year: 2024, month: 11, day: 3)
        session.setTimeEnabled(true)
        session.setTime(hour: 1, minute: 30)

        guard case .ambiguous(let earlier, let later) = session.localTimeResolution else {
            return XCTFail("Expected ambiguous DST fall-back resolution for 2024-11-03 01:30 in America/New_York")
        }
        XCTAssertTrue(session.requiresDSTResolution)
        XCTAssertFalse(session.canApply)
        XCTAssertNil(session.formattedValue)
        XCTAssertEqual(earlier.secondsFromGMT, -4 * 3600)
        XCTAssertEqual(later.secondsFromGMT, -5 * 3600)

        // Choose first occurrence (EDT, UTC-4 -> 05:30 UTC).
        session.selectDSTResolution(optionID: earlier.id)
        XCTAssertFalse(session.requiresDSTResolution)
        XCTAssertTrue(session.canApply)
        XCTAssertEqual(session.formattedValue, "2024-11-03T05:30")

        // Choose second occurrence (EST, UTC-5 -> 06:30 UTC).
        session.selectDSTResolution(optionID: later.id)
        XCTAssertEqual(session.formattedValue, "2024-11-03T06:30")

        // Reopening either UTC timestamp pre-selects the matching occurrence.
        let reopenedEarlier = MetadataDateTimePickerSession(
            initialText: "2024-11-03T05:30",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: newYork
        )
        XCTAssertEqual(reopenedEarlier.selectedDSTOptionID, earlier.id)
        XCTAssertEqual(reopenedEarlier.formattedValue, "2024-11-03T05:30")

        let reopenedLater = MetadataDateTimePickerSession(
            initialText: "2024-11-03T06:30",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: newYork
        )
        XCTAssertEqual(reopenedLater.selectedDSTOptionID, later.id)
        XCTAssertEqual(reopenedLater.formattedValue, "2024-11-03T06:30")
    }

    func testDSTNonexistentSpringForwardTimeRequiresExplicitResolution() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var session = MetadataDateTimePickerSession(
            initialText: nil,
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: newYork
        )
        session.setDate(year: 2024, month: 3, day: 10)
        session.setTimeEnabled(true)
        session.setTime(hour: 2, minute: 30)

        guard case .nonexistent(let options) = session.localTimeResolution else {
            return XCTFail("Expected nonexistent DST spring-forward resolution for 2024-03-10 02:30 in America/New_York")
        }
        XCTAssertFalse(options.isEmpty)
        XCTAssertTrue(session.requiresDSTResolution)
        XCTAssertFalse(session.canApply)
        XCTAssertNil(session.formattedValue)

        let shiftForward = try XCTUnwrap(options.first { $0.role == .shiftForward })
        XCTAssertEqual(shiftForward.localComponents.hour, 3)
        XCTAssertEqual(shiftForward.localComponents.minute, 30)
        session.selectDSTResolution(optionID: shiftForward.id)
        XCTAssertTrue(session.canApply)
        XCTAssertEqual(session.formattedValue, "2024-03-10T07:30")

        // Pure dates on DST transition days never prompt for DST.
        session.setTimeEnabled(false)
        XCTAssertNil(session.localTimeResolution)
        XCTAssertFalse(session.requiresDSTResolution)
        XCTAssertEqual(session.formattedValue, "2024-03-10")
    }

    func testRegionalTimeZoneSelectionOverridesSystemTimeZoneForUTCConversion() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var session = MetadataDateTimePickerSession(
            initialText: nil,
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: newYork
        )
        session.setDate(year: 2024, month: 6, day: 2)
        session.setTimeEnabled(true)
        session.setTime(hour: 0, minute: 30)
        XCTAssertEqual(session.formattedValue, "2024-06-02T04:30")

        // Switch regional time zone to Asia/Shanghai -> same local 00:30 now converts to 2024-06-01T16:30 UTC.
        session.setTimeZone(identifier: "Asia/Shanghai")
        XCTAssertEqual(session.formattedValue, "2024-06-01T16:30")
    }

    func testDisablingSecondsAllowsMinuteEditsAndKeepsExactlyRepresentableHistoricalInstants() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var session = MetadataDateTimePickerSession(
            initialText: "2024-06-01T16:30:45",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: utc
        )
        session.setSecondsEnabled(false)
        XCTAssertEqual(session.formattedValue, "2024-06-01T16:30")
        session.setTime(hour: 12, minute: 0)
        XCTAssertEqual(session.formattedValue, "2024-06-01T12:00")

        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        var historical = MetadataDateTimePickerSession(
            initialText: "1900-06-02T14:30:00",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: kolkata
        )
        historical.setSecondsEnabled(false)
        XCTAssertEqual(historical.localComponents.second, 10)
        XCTAssertEqual(historical.formattedValue, "1900-06-02T14:30")
    }

    func testPrecisionToggleRetainsSelectedDSTOccurrence() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var session = MetadataDateTimePickerSession(
            initialText: "2024-11-03T05:30:00",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: newYork
        )
        let selectedOption = try XCTUnwrap(session.selectedDSTOptionID)
        session.setSecondsEnabled(false)
        XCTAssertEqual(session.selectedDSTOptionID, selectedOption)
        XCTAssertEqual(session.formattedValue, "2024-11-03T05:30")
        session.setSecondsEnabled(true)
        XCTAssertEqual(session.selectedDSTOptionID, selectedOption)
        XCTAssertEqual(session.formattedValue, "2024-11-03T05:30:00")
    }

    func testPickerYearAcceptsEditingPrefixesAndRejectsInvalidText() {
        for (text, year) in [("1", 1), ("98", 98), ("1998", 1998), ("9999", 9999), ("٢٠٢٤", 2024)] {
            XCTAssertEqual(MetadataDateTimeCodec.pickerYear(from: text), year)
        }
        for text in ["", "0", "0000", "10000", "01998", "19x98", " 1998", "⑴"] {
            XCTAssertNil(MetadataDateTimeCodec.pickerYear(from: text), text)
        }
    }

    func testHistoricalSubMinuteOffsetsPreserveExistingUTCTimestamp() throws {
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        for value in ["1900-06-02T14", "1900-06-02T14:30"] {
            var session = MetadataDateTimePickerSession(
                initialText: value,
                destinationFormat: .id3v24Timestamp,
                systemTimeZone: kolkata
            )
            XCTAssertEqual(session.localComponents.second, 10)
            XCTAssertEqual(session.formattedValue, value)
            session.setTimeZone(identifier: "UTC")
            XCTAssertEqual(session.localComponents.second, 0)
            XCTAssertEqual(session.formattedValue, value)
            session.setTimeZone(identifier: kolkata.identifier)
            XCTAssertEqual(session.localComponents.second, 10)
            XCTAssertEqual(session.formattedValue, value)
        }
    }

    func testDateChangeAcrossSubHourDSTTransitionRequiresExplicitFinerPrecision() throws {
        let lordHowe = try XCTUnwrap(TimeZone(identifier: "Australia/Lord_Howe"))
        var session = MetadataDateTimePickerSession(
            initialText: "2024-04-06T14",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: lordHowe
        )
        XCTAssertEqual(session.formattedValue, "2024-04-06T14")
        session.setDate(year: 2024, month: 4, day: 10)
        XCTAssertFalse(session.canApply)
        XCTAssertEqual(session.finerTimePrecision, .minute)
        session.useFinerTimePrecision()
        XCTAssertEqual(session.localComponents.hour, 1)
        XCTAssertEqual(session.formattedValue, "2024-04-09T14:30")
    }

    func testUTCConversionRejectsOutOfRangeYearAndExistingValueCanOpenInUTC() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var session = MetadataDateTimePickerSession(
            initialText: "9999-12-31",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: losAngeles
        )
        session.setTimeEnabled(true)
        session.setTime(hour: 23, minute: 0)
        XCTAssertFalse(session.canApply)
        XCTAssertTrue(session.isUTCYearOutOfRange)
        XCTAssertNil(session.finerTimePrecision)

        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let existing = MetadataDateTimePickerSession(
            initialText: "9999-12-31T23:00",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: shanghai
        )
        XCTAssertEqual(existing.timeZone.secondsFromGMT(), 0)
        XCTAssertEqual(existing.formattedValue, "9999-12-31T23:00")
    }

    func testDestinationFormatIntersectionRestrictsToCommonRepresentableChoices() {
        let id3AndISO = MetadataDateDestinationFormat.intersect([.id3v24Timestamp, .isoDateOnly])
        XCTAssertEqual(id3AndISO?.supportedDatePrecisions, [.year, .yearMonth, .date])
        XCTAssertEqual(id3AndISO?.supportsTime, false)

        let id3AndID3 = MetadataDateDestinationFormat.intersect([.id3v24Timestamp, .id3v24Timestamp])
        XCTAssertEqual(id3AndID3, .id3v24Timestamp)

        let yearOnlyAndISO = MetadataDateDestinationFormat.intersect([.yearOnly, .isoDateOnly])
        XCTAssertEqual(yearOnlyAndISO?.supportedDatePrecisions, [.year])
        XCTAssertEqual(yearOnlyAndISO?.supportsTime, false)
    }

    func testOpeningMixedOrBlankFieldPositionsAtTodayWithoutParsing() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_732_060_800) // 2024-11-20T00:00:00Z

        let mixed = MetadataDateTimePickerSession(
            initialText: "2020-01-01",
            isMixed: true,
            destinationFormat: .isoDateOnly,
            systemTimeZone: utc,
            now: now
        )
        XCTAssertFalse(mixed.didParseExistingValue)
        XCTAssertEqual(mixed.localComponents.year, 2024)
        XCTAssertEqual(mixed.localComponents.month, 11)
        XCTAssertEqual(mixed.localComponents.day, 20)
    }

    func testHourPrecisionTimestampInHalfHourAndQuarterHourZonesPreservesUTCHourOnApplyAndDateOnlyEdit() throws {
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        var session = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: kolkata
        )

        XCTAssertTrue(session.didParseExistingValue)
        XCTAssertEqual(session.datePrecision, .date)
        XCTAssertEqual(session.timePrecision, .hour)
        XCTAssertEqual(session.localComponents.year, 2024)
        XCTAssertEqual(session.localComponents.month, 6)
        XCTAssertEqual(session.localComponents.day, 2)
        XCTAssertEqual(session.localComponents.hour, 19)
        XCTAssertEqual(session.localComponents.minute, 30)
        // Applying without edits must preserve 2024-06-02T14 (not 2024-06-02T13).
        XCTAssertEqual(session.formattedValue, "2024-06-02T14")

        // No-op setTime matching displayed 19:30 must not degrade precision or value.
        session.setTime(hour: 19, minute: 30)
        XCTAssertEqual(session.timePrecision, .hour)
        XCTAssertEqual(session.formattedValue, "2024-06-02T14")

        // Changing only the date keeps UTC hour 14 and hour-only precision.
        session.setDate(year: 2024, month: 6, day: 10)
        XCTAssertEqual(session.timePrecision, .hour)
        XCTAssertEqual(session.localComponents.hour, 19)
        XCTAssertEqual(session.localComponents.minute, 30)
        XCTAssertEqual(session.formattedValue, "2024-06-10T14")

        // Same check in a +05:45 zone (Asia/Kathmandu): 2024-06-02T14 UTC -> 19:45 local.
        let kathmandu = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        var nepal = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: kathmandu
        )
        XCTAssertEqual(nepal.timePrecision, .hour)
        XCTAssertEqual(nepal.localComponents.hour, 19)
        XCTAssertEqual(nepal.localComponents.minute, 45)
        XCTAssertEqual(nepal.formattedValue, "2024-06-02T14")
        nepal.setDate(year: 2024, month: 6, day: 15)
        XCTAssertEqual(nepal.timePrecision, .hour)
        XCTAssertEqual(nepal.formattedValue, "2024-06-15T14")
    }

    func testChangingDisplayTimeZonePreservesStoredInstantWhileNewLocalTimeUsesSelectedRegion() throws {
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var reopened = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14:30",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: shanghai
        )
        XCTAssertEqual(reopened.localComponents.year, 2024)
        XCTAssertEqual(reopened.localComponents.month, 6)
        XCTAssertEqual(reopened.localComponents.day, 2)
        XCTAssertEqual(reopened.localComponents.hour, 22)
        XCTAssertEqual(reopened.localComponents.minute, 30)
        XCTAssertEqual(reopened.formattedValue, "2024-06-02T14:30")

        // Switching display time zone to UTC updates displayed clock to 14:30 and preserves stored instant.
        reopened.setTimeZone(identifier: "UTC")
        XCTAssertEqual(reopened.localComponents.year, 2024)
        XCTAssertEqual(reopened.localComponents.month, 6)
        XCTAssertEqual(reopened.localComponents.day, 2)
        XCTAssertEqual(reopened.localComponents.hour, 14)
        XCTAssertEqual(reopened.localComponents.minute, 30)
        XCTAssertEqual(reopened.formattedValue, "2024-06-02T14:30")

        // Further switches keep the same stored instant, including half-hour zones.
        reopened.setTimeZone(identifier: "Asia/Kolkata")
        XCTAssertEqual(reopened.localComponents.hour, 20)
        XCTAssertEqual(reopened.localComponents.minute, 0)
        XCTAssertEqual(reopened.formattedValue, "2024-06-02T14:30")

        // Switching into a fall-back ambiguous instant selects the exact matching DST occurrence.
        var fallBack = MetadataDateTimePickerSession(
            initialText: "2024-11-03T06:30",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        fallBack.setTimeZone(identifier: "America/New_York")
        XCTAssertEqual(fallBack.localComponents.hour, 1)
        XCTAssertEqual(fallBack.localComponents.minute, 30)
        XCTAssertFalse(fallBack.requiresDSTResolution)
        XCTAssertEqual(fallBack.formattedValue, "2024-11-03T06:30")

        // Newly entered local time (whether zone chosen before or after time entry) uses the selected region.
        let utc = TimeZone(secondsFromGMT: 0)!
        var freshZoneFirst = MetadataDateTimePickerSession(
            initialText: nil,
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: utc
        )
        freshZoneFirst.setDate(year: 2024, month: 6, day: 2)
        freshZoneFirst.setTimeEnabled(true)
        freshZoneFirst.setTimeZone(identifier: "Asia/Shanghai")
        freshZoneFirst.setTime(hour: 0, minute: 30)
        XCTAssertEqual(freshZoneFirst.formattedValue, "2024-06-01T16:30")

        var freshTimeFirst = MetadataDateTimePickerSession(
            initialText: "2024-06-02",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: utc
        )
        freshTimeFirst.setTimeEnabled(true)
        freshTimeFirst.setTime(hour: 0, minute: 30)
        freshTimeFirst.setTimeZone(identifier: "Asia/Shanghai")
        XCTAssertEqual(freshTimeFirst.localComponents.hour, 0)
        XCTAssertEqual(freshTimeFirst.localComponents.minute, 30)
        XCTAssertEqual(freshTimeFirst.formattedValue, "2024-06-01T16:30")
    }
}
