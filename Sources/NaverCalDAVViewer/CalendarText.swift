import Foundation

enum CalendarText {
    static let calendarSourceDelimiter = "||"

    static func cleanName(_ value: String) -> String {
        value.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
    }

    static func calendarKey(source: String, calendar: String) -> String {
        "\(source)\(calendarSourceDelimiter)\(calendar)"
    }

    static func calendarSourceName(_ key: String) -> String {
        let parts = key.components(separatedBy: calendarSourceDelimiter)
        return cleanName(parts.count > 1 ? parts[0] : "caldav.calendar.naver.com")
    }

    static func calendarDisplayName(_ key: String) -> String {
        let parts = key.components(separatedBy: calendarSourceDelimiter)
        return cleanName(parts.count > 1 ? parts.dropFirst().joined(separator: calendarSourceDelimiter) : key)
    }
}

extension Notification.Name {
    static let openSyncSettings = Notification.Name("openSyncSettings")
}
