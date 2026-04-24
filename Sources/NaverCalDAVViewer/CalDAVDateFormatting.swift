import Foundation

/// CalDAV wire-format date helpers.
///
/// REPORT time-range filters require UTC stamps in `yyyyMMdd'T'HHmmss'Z'` form.
enum CalDAVDateFormatting {
    static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
