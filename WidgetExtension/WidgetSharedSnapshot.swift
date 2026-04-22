import Foundation
import SwiftUI

// Widget-safe snapshot loading and color conversion. This file must remain free of
// credentialed network calls to avoid WidgetKit refresh and Keychain prompt issues.
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
        )
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
    private static let customColorPrefix = "custom:"

    static func color(for code: String) -> Color {
        if code.hasPrefix(customColorPrefix) {
            return color(hex: String(code.dropFirst(customColorPrefix.count)))
        }

        switch code {
        case "0":
            return Color(red: 0.15, green: 0.56, blue: 0.96)
        case "1":
            return Color(red: 0.11, green: 0.72, blue: 0.41)
        case "2":
            return Color(red: 0.96, green: 0.49, blue: 0.18)
        case "3":
            return Color(red: 0.93, green: 0.28, blue: 0.43)
        case "4":
            return Color(red: 0.47, green: 0.35, blue: 0.93)
        case "5":
            return Color(red: 0.94, green: 0.73, blue: 0.16)
        case "6":
            return Color(red: 0.0, green: 0.65, blue: 0.72)
        case "7":
            return Color(red: 0.18, green: 0.74, blue: 0.64)
        case "8":
            return Color(red: 0.93, green: 0.20, blue: 0.20)
        case "9":
            return Color(red: 0.28, green: 0.39, blue: 0.95)
        default:
            return Color(red: 0.15, green: 0.56, blue: 0.96)
        }
    }

    private static func color(hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return Color(red: 0.15, green: 0.56, blue: 0.96)
        }

        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}
