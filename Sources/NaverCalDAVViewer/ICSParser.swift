import Foundation

/// Converts raw iCalendar VEVENT/VTODO text from CalDAV servers into CalendarItem.
///
/// The parser intentionally remains small, but it now keeps enough iCalendar
/// structure for common CalDAV cases:
/// - folded lines are unfolded before parsing
/// - property parameters such as `TZID` and `VALUE=DATE` are preserved
/// - duplicate fields are stored in `rawFields` using `#2`, `#3`, ... suffixes
/// - daily, weekly, monthly, and yearly recurrence rules are expanded into items
/// - `RECURRENCE-ID` override events replace the generated occurrence they target
/// Google Calendar API responses bypass this parser and are mapped in
/// `GoogleCalendarClient`.
enum ICSParser {
    static func parseItems(
        from ics: String,
        calendarName: String,
        rangeStart: Date? = nil,
        rangeEnd: Date? = nil
    ) -> [CalendarItem] {
        let unfolded = unfold(ics)
        let lines = unfolded.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var components: [ICSComponent] = []
        var currentType: CalendarItemType?
        var fields = ICSFields()
        var nestedComponentDepth = 0

        for raw in lines {
            let line = raw.trimmingCharacters(in: .newlines)

            if line == "BEGIN:VEVENT" {
                currentType = .event
                fields = ICSFields()
                continue
            }
            if line == "BEGIN:VTODO" {
                currentType = .todo
                fields = ICSFields()
                continue
            }

            if line.hasPrefix("BEGIN:") {
                if currentType != nil {
                    nestedComponentDepth += 1
                }
                continue
            }

            if line == "END:VEVENT" || line == "END:VTODO" {
                if let type = currentType {
                    components.append(ICSComponent(type: type, fields: fields))
                }
                currentType = nil
                fields = ICSFields()
                nestedComponentDepth = 0
                continue
            }

            if line.hasPrefix("END:") {
                if nestedComponentDepth > 0 {
                    nestedComponentDepth -= 1
                }
                continue
            }

            guard currentType != nil else { continue }
            guard nestedComponentDepth == 0 else { continue }
            guard let property = ICSProperty(line: line) else { continue }

            fields.append(property)
        }

        return makeItems(from: components, calendarName: calendarName, rangeStart: rangeStart, rangeEnd: rangeEnd)
    }

    private static func makeItems(
        from components: [ICSComponent],
        calendarName: String,
        rangeStart: Date?,
        rangeEnd: Date?
    ) -> [CalendarItem] {
        let recurringUIDs = Set(components.compactMap { component in
            component.fields.first("RRULE") == nil ? nil : component.fields.first("UID")
        })
        let overridesByUID = Dictionary(grouping: components.filter(\.isRecurrenceOverride)) { component in
            component.fields.first("UID") ?? ""
        }
        let range = (start: rangeStart, end: rangeEnd)

        return components.flatMap { component -> [CalendarItem] in
            guard !component.isRecurrenceOverride || !recurringUIDs.contains(component.fields.first("UID") ?? "") else {
                return []
            }
            return makeItems(
                type: component.type,
                fields: component.fields,
                calendarName: calendarName,
                range: range,
                overrides: overridesByUID[component.fields.first("UID") ?? ""] ?? []
            )
        }
    }

    private static func makeItems(
        type: CalendarItemType,
        fields: ICSFields,
        calendarName: String,
        range: (start: Date?, end: Date?),
        overrides: [ICSComponent]
    ) -> [CalendarItem] {
        let base = makeItem(type: type, fields: fields, calendarName: calendarName)
        guard type == .event,
              let startDate = base.startDate
        else {
            return item(base, overlapsRangeStart: range.start, rangeEnd: range.end) ? [base] : []
        }

        let rule = RecurrenceRule(raw: fields.first("RRULE"))
        let rdates = recurrenceDates(from: fields)
        guard rule != nil || !rdates.isEmpty else {
            return item(base, overlapsRangeStart: range.start, rangeEnd: range.end) ? [base] : []
        }

        let duration = base.endDate.map { $0.timeIntervalSince(startDate) }
        let exceptionDates = fields.properties("EXDATE").flatMap { property in
            property.value
                .split(separator: ",")
                .compactMap { value in
                    CalendarValueParser.parseDateValue(String(value), parameters: property.parameters).date
                }
        }
        let occurrences = uniqueOccurrences(
            (rule?.occurrences(startingAt: startDate, rangeStart: range.start, rangeEnd: range.end) ?? [startDate]) + rdates
        )

        return occurrences
            .filter { occurrence in
                date(occurrence, overlapsRangeStart: range.start, rangeEnd: range.end)
            }
            .filter { occurrence in
                !exceptionDates.contains { isExceptionDate($0, matching: occurrence) }
            }
            .enumerated()
            .map { index, occurrence in
                let endDate = duration.map { occurrence.addingTimeInterval($0) } ?? base.endDate
                let item = overrideItem(
                    for: occurrence,
                    baseIsAllDay: base.isAllDay,
                    overrides: overrides,
                    calendarName: calendarName
                ) ?? base.withDates(startDate: occurrence, endDate: endDate)

                return item
                    .withIdentifierSuffix(index == 0 ? nil : "r\(index)")
            }
            .filter { $0.status.uppercased() != "CANCELLED" }
    }

    private static func recurrenceDates(from fields: ICSFields) -> [Date] {
        fields.properties("RDATE").flatMap { property in
            property.value
                .split(separator: ",")
                .compactMap { value in
                    CalendarValueParser.parseDateValue(String(value), parameters: property.parameters).date
                }
        }
    }

    private static func item(_ item: CalendarItem, overlapsRangeStart rangeStart: Date?, rangeEnd: Date?) -> Bool {
        guard let start = item.startDate else {
            return true
        }
        let end = item.endDate ?? start
        if let rangeEnd, start > rangeEnd {
            return false
        }
        if let rangeStart, end < rangeStart {
            return false
        }
        return true
    }

    private static func date(_ date: Date, overlapsRangeStart rangeStart: Date?, rangeEnd: Date?) -> Bool {
        if let rangeStart, date < rangeStart {
            return false
        }
        if let rangeEnd, date > rangeEnd {
            return false
        }
        return true
    }

    private static func uniqueOccurrences(_ dates: [Date]) -> [Date] {
        dates.reduce(into: [Date]()) { result, date in
            if !result.contains(date) {
                result.append(date)
            }
        }
        .sorted()
    }

    private static func overrideItem(
        for occurrence: Date,
        baseIsAllDay: Bool,
        overrides: [ICSComponent],
        calendarName: String
    ) -> CalendarItem? {
        guard let override = overrides.first(where: { component in
            guard let recurrenceDate = component.fields.recurrenceDate else { return false }
            return isSameOccurrence(recurrenceDate, occurrence, isAllDay: baseIsAllDay)
        }) else {
            return nil
        }

        return makeItem(type: override.type, fields: override.fields, calendarName: calendarName)
    }

    private static func makeItem(type: CalendarItemType, fields: ICSFields, calendarName: String) -> CalendarItem {
        let uid = fields.first("UID") ?? "(no uid)"
        let summary = fields.first("SUMMARY") ?? "(no title)"

        let startOrDue: String
        let endOrCompleted: String
        let startParse: (date: Date?, isAllDay: Bool)
        let endParse: (date: Date?, isAllDay: Bool)

        if type == .event {
            startOrDue = fields.first("DTSTART") ?? ""
            endOrCompleted = fields.first("DTEND") ?? ""
            startParse = CalendarValueParser.parseDateValue(startOrDue, parameters: fields.parameters(for: "DTSTART"))
            endParse = CalendarValueParser.parseDateValue(endOrCompleted, parameters: fields.parameters(for: "DTEND"))
        } else {
            let startFieldName = fields.first("DUE") == nil ? "DTSTART" : "DUE"
            startOrDue = fields.first(startFieldName) ?? ""
            endOrCompleted = fields.first("COMPLETED") ?? ""
            startParse = CalendarValueParser.parseDateValue(startOrDue, parameters: fields.parameters(for: startFieldName))
            endParse = CalendarValueParser.parseDateValue(endOrCompleted)
        }

        let location = fields.first("LOCATION") ?? ""
        let note = fields.values("DESCRIPTION").joined(separator: "\n\n")
        let status = fields.first("STATUS") ?? ""
        let colorCode = fields.first("X-NAVER-CATEGORY-COLOR") ?? "0"

        return CalendarItem(
            type: type,
            uid: uid,
            summary: summary,
            startOrDue: startOrDue,
            endOrCompleted: endOrCompleted,
            location: location,
            note: note,
            status: status,
            sourceCalendar: calendarName,
            sourceColorCode: colorCode,
            rawFields: fields.rawFields,
            startDate: startParse.date,
            endDate: endParse.date,
            isAllDay: startParse.isAllDay
        )
    }

    private static func unfold(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")

        var result: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            if let last = result.last, lineText.hasPrefix(" ") || lineText.hasPrefix("\t") {
                result[result.count - 1] = last + lineText.dropFirst()
            } else {
                result.append(lineText)
            }
        }
        return result.joined(separator: "\n")
    }

    private struct ICSComponent {
        let type: CalendarItemType
        let fields: ICSFields

        var isRecurrenceOverride: Bool {
            fields.first("RECURRENCE-ID") != nil
        }
    }

    private struct ICSFields {
        private var ordered: [String: [ICSProperty]] = [:]

        var recurrenceDate: Date? {
            guard let property = properties("RECURRENCE-ID").first else {
                return nil
            }
            return CalendarValueParser.parseDateValue(property.value, parameters: property.parameters).date
        }

        var rawFields: [String: String] {
            var result: [String: String] = [:]
            for (name, properties) in ordered {
                for (index, property) in properties.enumerated() {
                    let key = index == 0 ? name : "\(name)#\(index + 1)"
                    result[key] = property.value
                    if !property.parameters.isEmpty {
                        result["\(key);PARAMS"] = property.parameters
                            .map { "\($0.key)=\($0.value)" }
                            .sorted()
                            .joined(separator: ";")
                    }
                }
            }
            return result
        }

        mutating func append(_ property: ICSProperty) {
            ordered[property.name, default: []].append(property)
        }

        func first(_ name: String) -> String? {
            ordered[name.uppercased()]?.first?.value
        }

        func values(_ name: String) -> [String] {
            ordered[name.uppercased()]?.map(\.value) ?? []
        }

        func properties(_ name: String) -> [ICSProperty] {
            ordered[name.uppercased()] ?? []
        }

        func parameters(for name: String) -> [String: String] {
            ordered[name.uppercased()]?.first?.parameters ?? [:]
        }
    }

    private struct ICSProperty {
        let name: String
        let parameters: [String: String]
        let value: String

        init?(line: String) {
            guard let colon = line.firstIndex(of: ":") else {
                return nil
            }
            let left = String(line[..<colon])
            let right = String(line[line.index(after: colon)...])
            let parts = left.split(separator: ";", omittingEmptySubsequences: true).map(String.init)
            guard let rawName = parts.first, !rawName.isEmpty else {
                return nil
            }

            name = rawName.uppercased()
            value = decodeText(right)
            parameters = Dictionary(
                uniqueKeysWithValues: parts.dropFirst().compactMap { parameter in
                    guard let equals = parameter.firstIndex(of: "=") else {
                        return nil
                    }
                    let key = String(parameter[..<equals]).uppercased()
                    let value = String(parameter[parameter.index(after: equals)...])
                    return (key, value)
                }
            )
        }
    }

    private static func isExceptionDate(_ exceptionDate: Date, matching occurrence: Date) -> Bool {
        exceptionDate == occurrence || Calendar.current.isDate(exceptionDate, inSameDayAs: occurrence)
    }

    private static func isSameOccurrence(_ recurrenceDate: Date, _ occurrence: Date, isAllDay: Bool) -> Bool {
        if isAllDay {
            return Calendar.current.isDate(recurrenceDate, inSameDayAs: occurrence)
        }
        return recurrenceDate == occurrence
    }

    private static func decodeText(_ value: String) -> String {
        var out = value
        out = out.replacingOccurrences(of: "\\n", with: "\n")
        out = out.replacingOccurrences(of: "\\N", with: "\n")
        out = out.replacingOccurrences(of: "\\,", with: ",")
        out = out.replacingOccurrences(of: "\\;", with: ";")
        out = out.replacingOccurrences(of: "\\\\", with: "\\")
        return out
    }
}

private extension CalendarItem {
    func withIdentifierSuffix(_ suffix: String?) -> CalendarItem {
        CalendarItem(
            id: suffix == nil ? id : UUID(),
            type: type,
            uid: suffix.map { "\(uid)#\($0)" } ?? uid,
            summary: summary,
            startOrDue: startOrDue,
            endOrCompleted: endOrCompleted,
            location: location,
            note: note,
            status: status,
            sourceCalendar: sourceCalendar,
            sourceColorCode: sourceColorCode,
            rawFields: rawFields,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }

    func withDates(startDate: Date?, endDate: Date?) -> CalendarItem {
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
            sourceColorCode: sourceColorCode,
            rawFields: rawFields,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay
        )
    }
}
