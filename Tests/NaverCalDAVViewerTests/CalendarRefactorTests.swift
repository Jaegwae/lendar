@testable import NaverCalDAVViewer
import XCTest

final class CalendarRefactorTests: XCTestCase {
    func testICSParserParsesAllDayEventAndUnfoldedText() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:event-1
        SUMMARY:Design\\, review
        DESCRIPTION:Line one
         line two
        DTSTART;VALUE=DATE:20260422
        DTEND;VALUE=DATE:20260424
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].uid, "event-1")
        XCTAssertEqual(items[0].summary, "Design, review")
        XCTAssertEqual(items[0].note, "Line oneline two")
        XCTAssertTrue(items[0].isAllDay)
        XCTAssertTrue(items[0].occurs(on: date(2026, 4, 23)))
        XCTAssertFalse(items[0].occurs(on: date(2026, 4, 24)))
    }

    func testICSParserPreservesRepeatedFieldsTimezoneParametersAndDailyRecurrence() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:recurring-1
        SUMMARY:Daily standup
        DESCRIPTION:First note
        DESCRIPTION:Second note
        DTSTART;TZID=Asia/Seoul:20260422T090000
        DTEND;TZID=Asia/Seoul:20260422T093000
        RRULE:FREQ=DAILY;COUNT=3
        EXDATE;TZID=Asia/Seoul:20260423T090000
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")

        XCTAssertEqual(items.map(\.summary), ["Daily standup", "Daily standup"])
        XCTAssertEqual(items.map(\.uid), ["recurring-1", "recurring-1#r1"])
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertEqual(items[0].note, "First note\n\nSecond note")
        XCTAssertEqual(items[0].rawFields["DESCRIPTION"], "First note")
        XCTAssertEqual(items[0].rawFields["DESCRIPTION#2"], "Second note")
        XCTAssertEqual(items[0].rawFields["DTSTART;PARAMS"], "TZID=Asia/Seoul")
        XCTAssertTrue(Calendar.current.isDate(items[0].startDate ?? .distantPast, inSameDayAs: date(2026, 4, 22)))
        XCTAssertTrue(Calendar.current.isDate(items[1].startDate ?? .distantPast, inSameDayAs: date(2026, 4, 24)))
    }

    func testICSParserExpandsWeeklyRecurrenceByDayCountAndUntil() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:weekly-1
        SUMMARY:Practice
        DTSTART;TZID=Asia/Seoul:20260420T090000
        DTEND;TZID=Asia/Seoul:20260420T100000
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4
        END:VEVENT
        BEGIN:VEVENT
        UID:weekly-2
        SUMMARY:Review
        DTSTART;TZID=Asia/Seoul:20260420T140000
        DTEND;TZID=Asia/Seoul:20260420T150000
        RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO;UNTIL=20260520T235959
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")
        let practiceDates = items
            .filter { $0.uid.hasPrefix("weekly-1") }
            .compactMap(\.startDate)
        let reviewDates = items
            .filter { $0.uid.hasPrefix("weekly-2") }
            .compactMap(\.startDate)

        XCTAssertEqual(practiceDates.map(dayNumber), [20, 22, 27, 29])
        XCTAssertEqual(practiceDates.map(hourNumber), [9, 9, 9, 9])
        XCTAssertEqual(Set(items.filter { $0.uid.hasPrefix("weekly-1") }.map(\.id)).count, 4)

        XCTAssertEqual(reviewDates.map { fixedCalendar.component(.month, from: $0) }, [4, 5, 5])
        XCTAssertEqual(reviewDates.map(dayNumber), [20, 4, 18])
        XCTAssertEqual(reviewDates.map(hourNumber), [14, 14, 14])
    }

    func testICSParserExpandsMonthlyAndYearlyRecurrenceRules() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:monthly-1
        SUMMARY:Last Friday
        DTSTART;TZID=Asia/Seoul:20260424T100000
        DTEND;TZID=Asia/Seoul:20260424T110000
        RRULE:FREQ=MONTHLY;BYDAY=FR;BYSETPOS=-1;COUNT=3
        END:VEVENT
        BEGIN:VEVENT
        UID:yearly-1
        SUMMARY:Anniversary
        DTSTART;VALUE=DATE:20260422
        DTEND;VALUE=DATE:20260423
        RRULE:FREQ=YEARLY;COUNT=2
        END:VEVENT
        BEGIN:VEVENT
        UID:payday-1
        SUMMARY:Payday
        DTSTART;VALUE=DATE:20260430
        DTEND;VALUE=DATE:20260501
        RRULE:FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")
        let monthlyDates = items.filter { $0.uid.hasPrefix("monthly-1") }.compactMap(\.startDate)
        let yearlyDates = items.filter { $0.uid.hasPrefix("yearly-1") }.compactMap(\.startDate)
        let paydayDates = items.filter { $0.uid.hasPrefix("payday-1") }.compactMap(\.startDate)

        XCTAssertEqual(monthlyDates.map { fixedCalendar.component(.month, from: $0) }, [4, 5, 6])
        XCTAssertEqual(monthlyDates.map(dayNumber), [24, 29, 26])
        XCTAssertEqual(yearlyDates.map { Calendar.current.component(.year, from: $0) }, [2026, 2027])
        XCTAssertEqual(yearlyDates.map(localDayNumber), [22, 22])
        XCTAssertEqual(paydayDates.map(localDayNumber), [30, 31, 30])
    }

    func testICSParserLimitsOpenEndedRecurrenceToRequestedRange() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:open-yearly
        SUMMARY:Holiday
        DTSTART;VALUE=DATE:20200101
        DTEND;VALUE=DATE:20200102
        RRULE:FREQ=YEARLY
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(
            from: ics,
            calendarName: "Work",
            rangeStart: date(2025, 12, 31),
            rangeEnd: date(2027, 12, 30)
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.compactMap(\.startDate).map { Calendar.current.component(.year, from: $0) }, [2026, 2027])
    }

    func testICSParserExpandsAdvancedYearlyRecurrenceFilters() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:year-day-1
        SUMMARY:Hundredth day
        DTSTART;VALUE=DATE:20260101
        DTEND;VALUE=DATE:20260102
        RRULE:FREQ=YEARLY;BYYEARDAY=100;COUNT=2
        END:VEVENT
        BEGIN:VEVENT
        UID:week-no-1
        SUMMARY:Second ISO week Monday
        DTSTART;TZID=Asia/Seoul:20260101T090000
        DTEND;TZID=Asia/Seoul:20260101T100000
        RRULE:FREQ=YEARLY;BYWEEKNO=2;BYDAY=MO;COUNT=2
        END:VEVENT
        BEGIN:VEVENT
        UID:year-setpos-1
        SUMMARY:First Monday across Jan Feb
        DTSTART;TZID=Asia/Seoul:20260101T090000
        DTEND;TZID=Asia/Seoul:20260101T100000
        RRULE:FREQ=YEARLY;BYMONTH=1,2;BYDAY=MO;BYSETPOS=1;COUNT=2
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")
        let yearDayDates = items.filter { $0.uid.hasPrefix("year-day-1") }.compactMap(\.startDate)
        let weekNoDates = items.filter { $0.uid.hasPrefix("week-no-1") }.compactMap(\.startDate)
        let setPositionDates = items.filter { $0.uid.hasPrefix("year-setpos-1") }.compactMap(\.startDate)

        XCTAssertEqual(yearDayDates.map { Calendar.current.component(.month, from: $0) }, [4, 4])
        XCTAssertEqual(yearDayDates.map(localDayNumber), [10, 10])
        XCTAssertEqual(weekNoDates.map { Calendar.current.component(.year, from: $0) }, [2026, 2027])
        XCTAssertEqual(weekNoDates.map { Calendar.current.component(.month, from: $0) }, [1, 1])
        XCTAssertEqual(weekNoDates.map(localDayNumber), [5, 11])
        XCTAssertEqual(setPositionDates.map { Calendar.current.component(.year, from: $0) }, [2026, 2027])
        XCTAssertEqual(setPositionDates.map(localDayNumber), [5, 4])
    }

    func testICSParserIncludesExplicitRDatesAndHonorsWeekStart() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:rdate-1
        SUMMARY:Extra sessions
        DTSTART;TZID=Asia/Seoul:20260420T090000
        DTEND;TZID=Asia/Seoul:20260420T100000
        RDATE;TZID=Asia/Seoul:20260422T090000,20260424T090000
        EXDATE;TZID=Asia/Seoul:20260422T090000
        END:VEVENT
        BEGIN:VEVENT
        UID:wkst-1
        SUMMARY:Week starts Sunday
        DTSTART;TZID=Asia/Seoul:20260419T090000
        DTEND;TZID=Asia/Seoul:20260419T100000
        RRULE:FREQ=WEEKLY;INTERVAL=2;WKST=SU;BYDAY=SU;COUNT=3
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")
        let rdates = items.filter { $0.uid.hasPrefix("rdate-1") }.compactMap(\.startDate)
        let weekStartDates = items.filter { $0.uid.hasPrefix("wkst-1") }.compactMap(\.startDate)

        XCTAssertEqual(rdates.map(dayNumber), [20, 24])
        XCTAssertEqual(weekStartDates.map(dayNumber), [19, 3, 17])
    }

    func testICSParserAppliesRecurrenceOverridesAndCancelledInstances() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:override-1
        SUMMARY:Team sync
        DTSTART;TZID=Asia/Seoul:20260420T090000
        DTEND;TZID=Asia/Seoul:20260420T100000
        RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3
        END:VEVENT
        BEGIN:VEVENT
        UID:override-1
        RECURRENCE-ID;TZID=Asia/Seoul:20260427T090000
        SUMMARY:Moved team sync
        DTSTART;TZID=Asia/Seoul:20260427T110000
        DTEND;TZID=Asia/Seoul:20260427T120000
        END:VEVENT
        BEGIN:VEVENT
        UID:override-1
        RECURRENCE-ID;TZID=Asia/Seoul:20260504T090000
        STATUS:CANCELLED
        SUMMARY:Cancelled team sync
        DTSTART;TZID=Asia/Seoul:20260504T090000
        DTEND;TZID=Asia/Seoul:20260504T100000
        END:VEVENT
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")

        XCTAssertEqual(items.map(\.summary), ["Team sync", "Moved team sync"])
        XCTAssertEqual(items.map(\.uid), ["override-1", "override-1#r1"])
        XCTAssertEqual(items.compactMap(\.startDate).map(dayNumber), [20, 27])
        XCTAssertEqual(items.compactMap(\.startDate).map(hourNumber), [9, 11])
    }

    func testICSParserUsesFallbackTodoStartParameters() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VTODO
        UID:todo-1
        SUMMARY:Submit report
        DTSTART;VALUE=DATE:20260422
        END:VTODO
        END:VCALENDAR
        """

        let items = ICSParser.parseItems(from: ics, calendarName: "Work")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .todo)
        XCTAssertTrue(items[0].isAllDay)
        XCTAssertTrue(Calendar.current.isDate(items[0].startDate ?? .distantPast, inSameDayAs: date(2026, 4, 22)))
        XCTAssertEqual(items[0].rawFields["DTSTART;PARAMS"], "VALUE=DATE")
    }

    func testScheduleSearchRanksExactPrefixContainsAndFuzzyMatches() {
        XCTAssertEqual(ScheduleSearchMatcher.score(query: "Design Review", target: "Design Review"), 0)
        XCTAssertEqual(ScheduleSearchMatcher.score(query: "Design", target: "Design Review"), 1)
        XCTAssertEqual(ScheduleSearchMatcher.score(query: "Review", target: "Design Review"), 2)
        XCTAssertEqual(ScheduleSearchMatcher.score(query: "dr", target: "Design Review"), 4)
        XCTAssertEqual(ScheduleSearchMatcher.score(query: "Desugn", target: "Design"), 11)
        XCTAssertNil(ScheduleSearchMatcher.score(query: "Payroll", target: "Design Review"))
    }

    func testScheduleDateRangeIncludesMultiDayOverlaps() {
        let range = ScheduleDateRange(start: date(2026, 4, 22), end: date(2026, 4, 22), calendar: fixedCalendar)
        let spanning = item(uid: "1", summary: "Trip", start: date(2026, 4, 21), end: date(2026, 4, 24), allDay: true)
        let outside = item(uid: "2", summary: "Later", start: date(2026, 4, 23), end: date(2026, 4, 23), allDay: false)

        XCTAssertTrue(range.contains(spanning))
        XCTAssertFalse(range.contains(outside))
    }

    func testMonthLayoutBuilderAssignsLanesAndHiddenCounts() {
        let builder = MonthLayoutBuilder(calendar: fixedCalendar, visibleLaneCount: 2)
        let week = (20 ... 26).map { date(2026, 4, $0) as Date? }
        let items = [
            item(uid: "1", summary: "A", start: date(2026, 4, 20), end: date(2026, 4, 22), allDay: false),
            item(uid: "2", summary: "B", start: date(2026, 4, 21), end: date(2026, 4, 23), allDay: false),
            item(uid: "3", summary: "C", start: date(2026, 4, 22), end: date(2026, 4, 24), allDay: false),
        ]

        let segments = builder.buildSegments(week: week, monthStart: date(2026, 4, 1), items: items)
        let hiddenCounts = builder.hiddenCountsByColumn(segments: segments)

        XCTAssertEqual(segments.map(\.lane), [0, 1, 2])
        XCTAssertEqual(hiddenCounts[2], 1)
        XCTAssertEqual(hiddenCounts[3], 1)
        XCTAssertEqual(hiddenCounts[4], 1)
    }

    func testSharedColorCatalogHandlesStandardAndCustomCodes() {
        XCTAssertEqual(CalendarColorCatalog.rgb(for: "0"), CalendarRGB(red: 0.15, green: 0.56, blue: 0.96))
        XCTAssertEqual(CalendarColorCatalog.rgb(for: "custom:FF8000"), CalendarRGB(red: 1.0, green: 128.0 / 255.0, blue: 0.0))
        XCTAssertEqual(CalendarColorCatalog.rgb(for: "custom:nope"), CalendarColorCatalog.fallback)
    }

    func testCalDAVPathNormalizesGoogleCalendarURLsAndFallbacks() {
        let googleURL = CalDAVPath.normalizedBaseURL("https://www.google.com/calendar/dav/user@gmail.com/events")
        XCTAssertEqual(googleURL.absoluteString, "https://apidata.googleusercontent.com/caldav/v2")

        XCTAssertEqual(CalDAVPath.normalize("https://example.com/a%20b/events/"), "/a b/events")
        XCTAssertEqual(CalDAVPath.normalize("calendars/users/demo/events"), "/calendars/users/demo/events")
        XCTAssertEqual(CalDAVPath.parentPath(of: "/calendars/users/demo/events/item.ics"), "/calendars/users/demo/events/")
        XCTAssertEqual(CalDAVPath.fallbackPrincipalPath(username: "demo@naver.com"), "/principals/users/demo")
        XCTAssertEqual(CalDAVPath.fallbackCalendarHomePath(username: "demo@naver.com"), "/calendars/users/demo/")
    }

    func testCalDAVXMLExtractsDecodedCalendarDataAndResponseFields() {
        let xml = """
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>/calendar/item.ics</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>Work</d:displayname>
                <d:getcontenttype>text/calendar</d:getcontenttype>
                <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
                <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
                <c:calendar-data>BEGIN:VCALENDAR
        SUMMARY:Design &amp; Review
        END:VCALENDAR</c:calendar-data>
              </d:prop>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """

        let responses = CalDAVXML.responses(from: xml)

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses[0].hrefs, ["/calendar/item.ics"])
        XCTAssertEqual(responses[0].displayName, "Work")
        XCTAssertEqual(responses[0].contentType, "text/calendar")
        XCTAssertEqual(responses[0].componentNames, ["VEVENT"])
        XCTAssertTrue(responses[0].isCollection)
        XCTAssertTrue(responses[0].isCalendar)
        XCTAssertEqual(CalDAVXML.extractCalendarData(from: xml), ["BEGIN:VCALENDAR\nSUMMARY:Design & Review\nEND:VCALENDAR"])
    }

    func testCalDAVXMLExtractsPrincipalAndCalendarHomeHrefs() {
        let xml = """
        <D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
          <D:response>
            <D:propstat>
              <D:prop>
                <D:current-user-principal><D:href>/principals/demo/</D:href></D:current-user-principal>
                <C:calendar-home-set><D:href>/calendars/demo/</D:href></C:calendar-home-set>
              </D:prop>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """

        XCTAssertEqual(CalDAVXML.firstCurrentUserPrincipalHref(from: xml), "/principals/demo/")
        XCTAssertEqual(CalDAVXML.firstCalendarHomeSetHref(from: xml), "/calendars/demo/")
    }

    func testConnectionNormalizerPreservesProviderAndServerRules() {
        XCTAssertEqual(ConnectionNormalizer.username("demo"), "demo@naver.com")
        XCTAssertEqual(ConnectionNormalizer.username("Demo@Example.COM"), "demo@example.com")
        XCTAssertEqual(ConnectionNormalizer.serverURL("calendar.google.com/calendar/dav/demo/events"), "https://apidata.googleusercontent.com/caldav/v2")
        XCTAssertEqual(ConnectionNormalizer.serverURL("caldav.calendar.naver.com/"), "https://caldav.calendar.naver.com")
        XCTAssertEqual(ConnectionNormalizer.provider(for: "https://www.googleapis.com/calendar/v3"), "google")
        XCTAssertEqual(ConnectionNormalizer.provider(for: "https://caldav.calendar.naver.com"), "caldav")
        XCTAssertEqual(ConnectionNormalizer.provider(for: "https://caldav.example.com", explicit: "google"), "google")
    }

    func testCalendarItemOrderingKeepsIncompleteItemsBeforeCompletedItems() {
        let incomplete = item(uid: "1", summary: "B", start: date(2026, 4, 22), end: date(2026, 4, 22), allDay: false)
        let completed = item(
            uid: "2",
            summary: "A",
            start: date(2026, 4, 21),
            end: date(2026, 4, 21),
            allDay: false,
            status: "COMPLETED"
        )

        let sorted = [completed, incomplete].sorted(by: CalendarItemOrdering.compareItems)

        XCTAssertEqual(sorted.map(\.uid), ["1", "2"])
        XCTAssertTrue(CalendarItemOrdering.compareDayItems(incomplete, completed, on: date(2026, 4, 22)))
    }

    func testWidgetSnapshotMapperCopiesDisplayFieldsAndColors() {
        let event = item(
            uid: "snapshot-1",
            summary: "Planning",
            start: date(2026, 4, 22),
            end: date(2026, 4, 22),
            allDay: false,
            location: "Room 1",
            note: "Bring notes",
            status: "CONFIRMED",
            sourceColorCode: "3"
        )

        let snapshots = WidgetSnapshotMapper.snapshots(from: [event]) { item in
            item.sourceColorCode
        }

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].id, "snapshot-1")
        XCTAssertEqual(snapshots[0].title, "Planning")
        XCTAssertEqual(snapshots[0].location, "Room 1")
        XCTAssertEqual(snapshots[0].note, "Bring notes")
        XCTAssertEqual(snapshots[0].status, "CONFIRMED")
        XCTAssertEqual(snapshots[0].colorCode, "3")
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        fixedCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dayNumber(_ date: Date) -> Int {
        fixedCalendar.component(.day, from: date)
    }

    private func localDayNumber(_ date: Date) -> Int {
        Calendar.current.component(.day, from: date)
    }

    private func hourNumber(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    private func item(
        uid: String,
        summary: String,
        start: Date,
        end: Date,
        allDay: Bool,
        location: String = "",
        note: String = "",
        status: String = "",
        sourceColorCode: String = "0"
    ) -> CalendarItem {
        CalendarItem(
            type: .event,
            uid: uid,
            summary: summary,
            startOrDue: "",
            endOrCompleted: "",
            location: location,
            note: note,
            status: status,
            sourceCalendar: "Work",
            sourceColorCode: sourceColorCode,
            rawFields: [:],
            startDate: start,
            endDate: end,
            isAllDay: allDay
        )
    }
}
