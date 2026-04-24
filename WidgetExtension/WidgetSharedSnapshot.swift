import Foundation
import SwiftUI

/// Widget-safe snapshot loading and color conversion. This file must remain free of
/// credentialed network calls to avoid WidgetKit refresh and Keychain prompt issues.
extension WidgetEventSnapshot {
    static let samples: [WidgetEventSnapshot] = [
        WidgetEventSnapshot(
            id: "sample-1",
            title: "디자인 리뷰",
            calendarName: "내 캘린더",
            startTimestamp: Date().addingTimeInterval(3600).timeIntervalSince1970,
            endTimestamp: Date().addingTimeInterval(7200).timeIntervalSince1970,
            isAllDay: false,
            location: "회의실 A",
            note: "",
            status: "CONFIRMED",
            colorCode: "0"
        ),
        WidgetEventSnapshot(
            id: "sample-2",
            title: "프로젝트 제출",
            calendarName: "내 할 일",
            startTimestamp: Date().addingTimeInterval(86400).timeIntervalSince1970,
            endTimestamp: nil,
            isAllDay: true,
            location: "",
            note: "",
            status: "COMPLETED",
            colorCode: "2"
        ),
    ]
}

enum WidgetCalendarLoader {
    static func load() async -> [WidgetEventSnapshot] {
        // The widget intentionally does no OAuth, Keychain credential reads, or network
        // requests. It only consumes the latest flattened snapshot written by the app.
        // This keeps WidgetKit refreshes stable and avoids repeated macOS Keychain prompts.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return ConnectionStore.loadWidgetEventSnapshots()
            .filter { occurs($0, on: today, calendar: calendar) }
            .map(cleanedSnapshot)
            .sorted(by: compareItems)
    }

    private static func compareItems(_ lhs: WidgetEventSnapshot, _ rhs: WidgetEventSnapshot) -> Bool {
        let leftCompleted = isCompleted(lhs)
        let rightCompleted = isCompleted(rhs)
        if leftCompleted != rightCompleted {
            return !leftCompleted
        }

        let leftDue = lhs.endTimestamp ?? lhs.startTimestamp
        let rightDue = rhs.endTimestamp ?? rhs.startTimestamp
        if leftDue != rightDue {
            return leftDue < rightDue
        }

        if lhs.startTimestamp != rhs.startTimestamp {
            return lhs.startTimestamp < rhs.startTimestamp
        }

        return lhs.title < rhs.title
    }

    private static func isCompleted(_ item: WidgetEventSnapshot) -> Bool {
        item.status.uppercased() == "COMPLETED"
    }

    private static func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedSnapshot(_ item: WidgetEventSnapshot) -> WidgetEventSnapshot {
        WidgetEventSnapshot(
            id: item.id,
            title: cleanText(item.title),
            calendarName: cleanText(item.calendarName),
            startTimestamp: item.startTimestamp,
            endTimestamp: item.endTimestamp,
            isAllDay: item.isAllDay,
            location: cleanText(item.location),
            note: cleanText(item.note),
            status: item.status,
            colorCode: item.colorCode
        )
    }

    private static func occurs(_ item: WidgetEventSnapshot, on day: Date, calendar: Calendar) -> Bool {
        // Widget rows show today's agenda only. For all-day events, Google and CalDAV
        // commonly store the end as the exclusive next day, so subtract one day for
        // display-day inclusion checks.
        let start = Date(timeIntervalSince1970: item.startTimestamp)
        let end = item.endTimestamp.map { Date(timeIntervalSince1970: $0) } ?? start
        let dayStart = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)

        if item.isAllDay {
            let displayEnd = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: end)) ?? end
            return calendar.startOfDay(for: start) <= dayStart && calendar.startOfDay(for: displayEnd) >= dayStart
        }

        return start < nextDay && end >= dayStart
    }
}

enum WidgetPalette {
    static func color(for code: String) -> Color {
        let rgb = CalendarColorCatalog.rgb(for: code)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
