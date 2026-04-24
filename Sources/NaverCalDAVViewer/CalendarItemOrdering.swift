import Foundation

/// Shared ordering rules for month grid, day agenda, and sync output.
///
/// Keeping the ordering here prevents UI views and `CalendarStore` from drifting:
/// incomplete items sort before completed items, then by date/all-day/title.
enum CalendarItemOrdering {
    static func compareItems(_ lhs: CalendarItem, _ rhs: CalendarItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return rhs.isCompleted
        }

        let left = lhs.startDate ?? .distantFuture
        let right = rhs.startDate ?? .distantFuture
        if left == right {
            if lhs.isAllDay != rhs.isAllDay {
                return lhs.isAllDay
            }
            return lhs.summary < rhs.summary
        }
        return left < right
    }

    static func compareDayItems(_ lhs: CalendarItem, _ rhs: CalendarItem, on day: Date) -> Bool {
        if lhs.isCompleted != rhs.isCompleted {
            return !lhs.isCompleted
        }

        let leftEnd = daySortEndDate(lhs, on: day)
        let rightEnd = daySortEndDate(rhs, on: day)
        if leftEnd != rightEnd {
            return leftEnd < rightEnd
        }

        let leftStart = lhs.startDate ?? .distantFuture
        let rightStart = rhs.startDate ?? .distantFuture
        if leftStart != rightStart {
            return leftStart < rightStart
        }

        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay
        }

        return lhs.summary < rhs.summary
    }

    private static func daySortEndDate(_ item: CalendarItem, on day: Date) -> Date {
        if let endDate = item.endDate {
            return endDate
        }
        if let displayEndDay = item.displayEndDay {
            return displayEndDay
        }
        if let startDate = item.startDate {
            return startDate
        }
        return Calendar.current.startOfDay(for: day)
    }
}
