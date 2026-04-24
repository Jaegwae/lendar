import Foundation

enum CalendarValueParser {
    static func parseDateValue(_ raw: String) -> (date: Date?, isAllDay: Bool) {
        parseDateValue(raw, parameters: [:])
    }

    /// Parses iCalendar date/date-time values.
    ///
    /// `parameters` carries property metadata such as `VALUE=DATE` and `TZID`.
    /// Floating and Naver-style `Z` values are treated as calendar wall-clock times
    /// unless an explicit timezone is provided.
    static func parseDateValue(_ raw: String, parameters: [String: String]) -> (date: Date?, isAllDay: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (nil, false)
        }

        let normalized = trimmed.uppercased()
        let calendarTimeZone = parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        let allDayFormats = ["yyyyMMdd"]
        for format in allDayFormats {
            let formatter = formatter(format: format, timeZone: calendarTimeZone)
            if let date = formatter.date(from: normalized) {
                return (date, parameters["VALUE"] == "DATE" || !normalized.contains("T"))
            }
        }

        // Naver CalDAV values are consumed as calendar wall-clock times in this app.
        // Some timed values arrive with a trailing "Z" even when they represent the
        // local Naver Calendar time, so keep them in the calendar timezone instead
        // of shifting them as UTC instants.
        let timedFormats = [
            ("yyyyMMdd'T'HHmmss'Z'", calendarTimeZone),
            ("yyyyMMdd'T'HHmm'Z'", calendarTimeZone),
            ("yyyyMMdd'T'HHmmss", calendarTimeZone),
            ("yyyyMMdd'T'HHmm", calendarTimeZone),
        ]

        for (format, timeZone) in timedFormats {
            let formatter = formatter(format: format, timeZone: timeZone)
            if let date = formatter.date(from: normalized) {
                return (date, false)
            }
        }

        return (nil, false)
    }

    private static func formatter(format: String, timeZone: TimeZone?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
