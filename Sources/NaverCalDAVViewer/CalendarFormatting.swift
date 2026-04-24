import Foundation

enum CalendarFormatting {
    static let toolbarToday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter
    }()

    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter
    }()

    static let dayHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "d"
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd a h:mm"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    static let filterDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. MM. dd"
        return formatter
    }()

    static let compactMonthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M"
        return formatter
    }()

    static func eventTimeText(for item: CalendarItem) -> String {
        guard let startDate = item.startDate else {
            return item.startOrDue
        }
        if item.isAllDay {
            if let endDate = item.endDate,
               !Calendar.current.isDate(startDate, inSameDayAs: endDate)
            {
                return "\(monthDay.string(from: startDate)) - \(monthDay.string(from: endDate))"
            }
            return "종일"
        }
        if let endDate = item.endDate {
            return "\(timeOnly.string(from: startDate)) - \(timeOnly.string(from: endDate))"
        }
        return timeOnly.string(from: startDate)
    }

    static func detailedEventRangeText(for item: CalendarItem) -> String {
        guard let startDate = item.startDate else {
            return item.startOrDue
        }

        if item.isAllDay {
            if let endDate = item.displayEndDay, endDate != Calendar.current.startOfDay(for: startDate) {
                return "\(fullDate.string(from: startDate)) ~ \(fullDate.string(from: endDate))"
            }
            return "\(fullDate.string(from: startDate)) 종일"
        }

        if let endDate = item.endDate {
            return "\(fullDateTime.string(from: startDate)) ~ \(fullDateTime.string(from: endDate))"
        }

        return fullDateTime.string(from: startDate)
    }
}
