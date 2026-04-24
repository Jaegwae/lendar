import Foundation

/// Static date formatters used by widget rows.
///
/// DateFormatter creation is relatively expensive and WidgetKit can recreate
/// views frequently. Static formatters keep rendering cheap and consistent.
enum WidgetDateFormatting {
    static let headerDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter
    }()

    static let dayRange: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func headerText(for date: Date) -> String {
        headerDate.string(from: date)
    }

    static func timeRangeText(_ item: WidgetEventSnapshot) -> String {
        if item.isAllDay {
            return "하루 종일"
        }
        let start = Date(timeIntervalSince1970: item.startTimestamp)
        guard let endTimestamp = item.endTimestamp else {
            return timeOnly.string(from: start)
        }
        let end = Date(timeIntervalSince1970: endTimestamp)
        return "\(timeOnly.string(from: start)) - \(timeOnly.string(from: end))"
    }

    static func dateRangeText(_ item: WidgetEventSnapshot) -> String {
        let start = Date(timeIntervalSince1970: item.startTimestamp)
        guard let endTimestamp = item.endTimestamp else {
            return dayRange.string(from: start)
        }
        let end = Date(timeIntervalSince1970: endTimestamp)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return dayRange.string(from: start)
        }
        return "\(dayRange.string(from: start)) - \(dayRange.string(from: end))"
    }
}
