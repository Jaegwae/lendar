import Foundation

struct CalendarCollection: Identifiable {
    let id = UUID()
    let href: String
    let displayName: String
    let supportedComponents: Set<String>
}

enum CalendarItemType: String, Codable {
    case event = "VEVENT"
    case todo = "VTODO"
}

struct CalendarItem: Identifiable {
    let id: UUID
    let type: CalendarItemType
    let uid: String
    let summary: String
    let startOrDue: String
    let endOrCompleted: String
    let location: String
    let note: String
    let status: String
    let sourceCalendar: String
    let sourceColorCode: String
    let rawFields: [String: String]

    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool

    init(
        id: UUID = UUID(),
        type: CalendarItemType,
        uid: String,
        summary: String,
        startOrDue: String,
        endOrCompleted: String,
        location: String,
        note: String,
        status: String,
        sourceCalendar: String,
        sourceColorCode: String,
        rawFields: [String: String],
        startDate: Date?,
        endDate: Date?,
        isAllDay: Bool
    ) {
        self.id = id
        self.type = type
        self.uid = uid
        self.summary = summary
        self.startOrDue = startOrDue
        self.endOrCompleted = endOrCompleted
        self.location = location
        self.note = note
        self.status = status
        self.sourceCalendar = sourceCalendar
        self.sourceColorCode = sourceColorCode
        self.rawFields = rawFields
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }

    func withSourceColorCode(_ colorCode: String) -> CalendarItem {
        CalendarItem(
            id: id,
            type: type,
            uid: uid,
            summary: summary,
            startOrDue: startOrDue,
            endOrCompleted: endOrCompleted,
            location: location,
            note: note,
            status: status,
            sourceCalendar: sourceCalendar,
            sourceColorCode: colorCode,
            rawFields: rawFields,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    func withSourceCalendar(_ calendarName: String) -> CalendarItem {
        CalendarItem(
            id: id,
            type: type,
            uid: uid,
            summary: summary,
            startOrDue: startOrDue,
            endOrCompleted: endOrCompleted,
            location: location,
            note: note,
            status: status,
            sourceCalendar: calendarName,
            sourceColorCode: sourceColorCode,
            rawFields: rawFields,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    var derivedStatus: String {
        if !status.isEmpty {
            return status
        }
        if let completed = rawFields["COMPLETED"], !completed.isEmpty {
            return "COMPLETED"
        }
        if rawFields["PERCENT-COMPLETE"] == "100" {
            return "COMPLETED"
        }
        if let xComplete = rawFields["X-NAVER-COMPLETED"], !xComplete.isEmpty {
            let normalized = xComplete.lowercased()
            if normalized == "true" || normalized == "yes" || normalized == "y" || normalized == "1" {
                return "COMPLETED"
            }
            if normalized == "false" || normalized == "no" || normalized == "n" || normalized == "0" {
                return "NEEDS-ACTION"
            }
        }
        return ""
    }

    var isCompleted: Bool {
        derivedStatus.uppercased() == "COMPLETED"
    }

    var hasNote: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasLocation: Bool {
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayStartDay: Date? {
        startDate.map { Calendar.current.startOfDay(for: $0) }
    }

    var displayEndDay: Date? {
        guard let endDate else {
            return displayStartDay
        }

        let calendar = Calendar.current
        if isAllDay, let startDate, endDate > startDate {
            let adjusted = endDate.addingTimeInterval(-1)
            return calendar.startOfDay(for: adjusted)
        }
        return calendar.startOfDay(for: endDate)
    }

    func occurs(on day: Date) -> Bool {
        guard let startDay = displayStartDay else {
            return false
        }

        let normalizedDay = Calendar.current.startOfDay(for: day)
        let endDay = displayEndDay ?? startDay
        return normalizedDay >= startDay && normalizedDay <= endDay
    }

    func spanPosition(on day: Date) -> CalendarSpanPosition {
        guard let startDay = displayStartDay else {
            return .single
        }

        let normalizedDay = Calendar.current.startOfDay(for: day)
        let endDay = displayEndDay ?? startDay

        if startDay == endDay {
            return .single
        }
        if normalizedDay == startDay {
            return .start
        }
        if normalizedDay == endDay {
            return .end
        }
        return .middle
    }
}

struct FetchResult {
    let items: [CalendarItem]
    let diagnostics: [String]
}

struct WidgetEventSnapshot: Codable, Identifiable {
    let id: String
    let title: String
    let calendarName: String
    let startTimestamp: TimeInterval
    let endTimestamp: TimeInterval?
    let isAllDay: Bool
    let location: String
    let note: String
    let status: String
    let colorCode: String
}

enum CalendarSpanPosition {
    case single
    case start
    case middle
    case end
}
