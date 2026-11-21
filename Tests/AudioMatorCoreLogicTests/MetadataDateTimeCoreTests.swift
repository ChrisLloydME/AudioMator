import Foundation
import XCTest
@testable import AudioMatorCoreLogic

final class MetadataDateTimeCoreTests: XCTestCase {
    func testSheetViewportUsesSmallerInsetsToFitNarrowWindow() {
        let viewport = MetadataDatePickerViewport(
            window: CGSize(width: 200, height: 225),
            screen: CGSize(width: 1440, height: 864)
        )
        XCTAssertEqual(viewport.size.width, 176)
        XCTAssertEqual(viewport.size.height, 225)
        XCTAssertEqual(viewport.horizontalInset, 12)
        XCTAssertEqual(viewport.bodyWidth, 152)
    }

    func testSheetViewportRespectsSmallScreenAndCapsRoomyWindow() {
        let smallScreen = MetadataDatePickerViewport(
            window: CGSize(width: 900, height: 750),
            screen: CGSize(width: 292, height: 280)
        )
        XCTAssertEqual(smallScreen.size.width, 268)
        XCTAssertEqual(smallScreen.size.height, 256)
        XCTAssertEqual(smallScreen.bodyWidth + 2 * MetadataDatePickerViewport.contentInset, smallScreen.size.width)

        let roomy = MetadataDatePickerViewport(
            window: CGSize(width: 900, height: 750),
            screen: CGSize(width: 1440, height: 864)
        )
        XCTAssertEqual(roomy.size.width, 420)
        XCTAssertEqual(roomy.size.height, 640)
        let standard = MetadataDatePickerViewport(
            window: CGSize(width: 860, height: 600),
            screen: CGSize(width: 1440, height: 900)
        )
        XCTAssertEqual(standard.size.height, 600)
    }

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
                destinationFormat: .utcTextTimestamp,
                systemTimeZone: tz
            )
            session.setDate(year: 2024, month: 6, day: 2)
            XCTAssertEqual(session.formattedValue, "2024-06-02")

            session.setDatePrecision(.yearMonth)
            XCTAssertEqual(session.formattedValue, "2024-06")

            session.setDatePrecision(.year)
            XCTAssertEqual(session.formattedValue, "2024")

            XCTAssertFalse(session.isTimeEnabled)
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

    func testDestinationFormatIntersectionKeepsAllPrecisionsAndUsesCommonUTCSyntax() {
        let id3AndID3 = MetadataDateDestinationFormat.intersect([.id3v24Timestamp, .id3v24Timestamp])
        XCTAssertEqual(id3AndID3, .id3v24Timestamp)
        XCTAssertEqual(MetadataDateDestinationFormat.intersect([.utcTextTimestamp, .id3v24Timestamp]), .id3v24Timestamp)
        XCTAssertEqual(MetadataDateDestinationFormat.intersect([.utcTextTimestamp, .utcTextTimestamp]), .utcTextTimestamp)

        XCTAssertNil(MetadataDateDestinationFormat.intersect([]))
    }

    func testTextDatePickerSupportsEveryPrecisionAndRoundTripsExplicitUTC() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        var session = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14:18:45Z", destinationFormat: .utcTextTimestamp, systemTimeZone: zone
        )
        XCTAssertEqual(session.localComponents.hour, 20)
        XCTAssertEqual(session.localComponents.minute, 3)
        XCTAssertEqual(session.formattedValue, "2024-06-02T14:18:45Z")
        session.setTimePrecision(.minute)
        XCTAssertEqual(session.formattedValue, "2024-06-02T14:18Z")
        session.setTimePrecision(.hour)
        XCTAssertEqual(session.formattedValue, "2024-06-02T14Z")
        XCTAssertEqual(session.localComponents.minute, 45)
        session.setTime(hour: 20, minute: 45)
        XCTAssertEqual(session.timePrecision, .hour)
        XCTAssertEqual(session.formattedValue, "2024-06-02T15Z")
        session.setDatePrecision(.yearMonth)
        XCTAssertEqual(session.formattedValue, "2024-06")
        session.setDatePrecision(.year)
        XCTAssertEqual(session.formattedValue, "2024")
    }

    func testOpeningMixedOrBlankFieldPositionsAtTodayWithoutParsing() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_732_060_800) // 2024-11-20T00:00:00Z

        let mixed = MetadataDateTimePickerSession(
            initialText: "2020-01-01",
            isMixed: true,
            destinationFormat: .utcTextTimestamp,
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

    func testTimeZoneSwitchRejectionAtYearBoundsPreservesAcceptedZoneAndPreview() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var lowerBound = MetadataDateTimePickerSession(
            initialText: "0001-01-01T00:00",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: losAngeles
        )
        XCTAssertEqual(lowerBound.timeZone.secondsFromGMT(), 0)
        XCTAssertEqual(lowerBound.formattedValue, "0001-01-01T00:00")
        XCTAssertFalse(lowerBound.setTimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(lowerBound.timeZone.secondsFromGMT(), 0)
        XCTAssertEqual(lowerBound.formattedValue, "0001-01-01T00:00")
        XCTAssertTrue(lowerBound.setTimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(lowerBound.timeZoneIdentifier, "Asia/Tokyo")
        XCTAssertEqual(lowerBound.formattedValue, "0001-01-01T00:00")

        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var upperBound = MetadataDateTimePickerSession(
            initialText: "9999-12-31T23:00",
            destinationFormat: .id3v24Timestamp,
            systemTimeZone: shanghai
        )
        XCTAssertEqual(upperBound.timeZone.secondsFromGMT(), 0)
        XCTAssertEqual(upperBound.formattedValue, "9999-12-31T23:00")
        XCTAssertFalse(upperBound.setTimeZone(identifier: "Asia/Shanghai"))
        XCTAssertEqual(upperBound.timeZone.secondsFromGMT(), 0)
        XCTAssertEqual(upperBound.formattedValue, "9999-12-31T23:00")
        XCTAssertTrue(upperBound.setTimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(upperBound.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(upperBound.formattedValue, "9999-12-31T23:00")
    }

    func testFractionalSecondsPreservedOnNoOpApplyAndZoneSwitchAndDroppedOnExplicitReduction() throws {
        let shanghai = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let expectedEpoch = 1_717_338_645.123 // 2024-06-02T14:30:45.123Z

        var session = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14:30:45.123Z",
            destinationFormat: .utcTextTimestamp,
            systemTimeZone: shanghai
        )
        XCTAssertTrue(session.didParseExistingValue)
        XCTAssertEqual(session.timePrecision, .second)
        XCTAssertEqual(session.fractionalSecondsDigits, "123")
        XCTAssertEqual(session.formattedValue, "2024-06-02T14:30:45.123Z")
        XCTAssertEqual(try XCTUnwrap(session.resolvedInstant).timeIntervalSince1970, expectedEpoch, accuracy: 0.0005)

        // Switching display time zones preserves the full instant including .123.
        XCTAssertTrue(session.setTimeZone(identifier: "America/New_York"))
        XCTAssertEqual(session.localComponents.hour, 10)
        XCTAssertEqual(session.localComponents.minute, 30)
        XCTAssertEqual(session.localComponents.second, 45)
        XCTAssertEqual(try XCTUnwrap(session.resolvedInstant).timeIntervalSince1970, expectedEpoch, accuracy: 0.0005)
        XCTAssertEqual(session.formattedValue, "2024-06-02T14:30:45.123Z")

        XCTAssertTrue(session.setTimeZone(identifier: "UTC"))
        XCTAssertEqual(session.formattedValue, "2024-06-02T14:30:45.123Z")

        // No-op setTime preserves fractional seconds; date-only edit preserves them too.
        session.setTime(hour: 14, minute: 30, second: 45)
        XCTAssertEqual(session.formattedValue, "2024-06-02T14:30:45.123Z")
        session.setDate(year: 2024, month: 6, day: 5)
        XCTAssertEqual(session.formattedValue, "2024-06-05T14:30:45.123Z")

        // Explicit time edit reduces to edited whole seconds and updates preview clearly.
        session.setTime(hour: 15, minute: 0, second: 0)
        XCTAssertNil(session.fractionalSecondsDigits)
        XCTAssertEqual(session.formattedValue, "2024-06-05T15:00:00Z")

        // Explicit precision reduction to minute or hour updates preview clearly.
        var toMinute = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14:30:00.123Z",
            destinationFormat: .utcTextTimestamp,
            systemTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        XCTAssertEqual(toMinute.formattedValue, "2024-06-02T14:30:00.123Z")
        toMinute.setTimePrecision(.minute)
        XCTAssertNil(toMinute.fractionalSecondsDigits)
        XCTAssertEqual(toMinute.formattedValue, "2024-06-02T14:30Z")

        var toHour = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14:30:45.123Z",
            destinationFormat: .utcTextTimestamp,
            systemTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        toHour.setTimePrecision(.hour)
        XCTAssertNil(toHour.fractionalSecondsDigits)
        XCTAssertEqual(toHour.formattedValue, "2024-06-02T14Z")

        // Explicit offset with fractional seconds preserves .123 in UTC.
        let offsetSession = MetadataDateTimePickerSession(
            initialText: "2024-06-02T14:30:45.123+08:00",
            destinationFormat: .utcTextTimestamp,
            systemTimeZone: shanghai
        )
        XCTAssertEqual(offsetSession.formattedValue, "2024-06-02T06:30:45.123Z")

        // Ambiguous DST timestamp with fractional seconds keeps occurrence and .123 across zone switches.
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var dstFractional = MetadataDateTimePickerSession(
            initialText: "2024-11-03T05:30:45.123Z",
            destinationFormat: .utcTextTimestamp,
            systemTimeZone: newYork
        )
        XCTAssertEqual(dstFractional.selectedDSTOptionID, "earlier")
        XCTAssertEqual(dstFractional.formattedValue, "2024-11-03T05:30:45.123Z")
        XCTAssertTrue(dstFractional.setTimeZone(identifier: "UTC"))
        XCTAssertTrue(dstFractional.setTimeZone(identifier: "America/New_York"))
        XCTAssertEqual(dstFractional.selectedDSTOptionID, "earlier")
        XCTAssertEqual(dstFractional.formattedValue, "2024-11-03T05:30:45.123Z")
    }

    func testWriteFailureFieldAnnotationDistinguishesDateFromUpdateAndCompoundDateLabels() {
        let compounds = ["Release Date", "Original Release Date", "Purchase Date", "iTunes Purchase Date"]

        // "update" must not satisfy "Date".
        XCTAssertFalse(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Date"],
                in: "Failed to update tag metadata.",
                compoundLabels: compounds
            )
        )

        // "Release Date" and "Original Release Date" must not satisfy standalone "Date".
        XCTAssertFalse(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Date"],
                in: "Release Date could not be saved.",
                compoundLabels: compounds
            )
        )
        XCTAssertFalse(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Date", "Release Date"],
                in: "Release Date could not be saved.",
                compoundLabels: compounds
            )
        )
        XCTAssertFalse(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Date"],
                in: "Original Release Date is not supported.",
                compoundLabels: compounds
            )
        )
        XCTAssertFalse(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Release Date"],
                in: "Original Release Date is not supported.",
                compoundLabels: compounds
            )
        )

        // Independent mentions still count as already named.
        XCTAssertTrue(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Date"],
                in: "Date cannot be written in this container.",
                compoundLabels: compounds
            )
        )
        XCTAssertTrue(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Date", "Release Date"],
                in: "Release Date and Date could not be saved.",
                compoundLabels: compounds
            )
        )
        XCTAssertTrue(
            MetadataWriteFailureFieldAnnotation.namesEveryField(
                ["Original Release Date"],
                in: "Original Release Date is not supported.",
                compoundLabels: compounds
            )
        )
    }
}
